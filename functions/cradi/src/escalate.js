/**
 * The escalation cron: reports still pending at `escalateAt` are flagged
 * escalated (the status stays `pending`) and coordinators and staff are
 * notified.
 *
 *   schedule: * * * * *
 *   scopes:   documents.read, documents.write, messages.write
 *
 * Ported from `backend/src/escalations.js`. The logic survives; the
 * concurrency story changes, and not for the better.
 *
 * Postgres made this safe with conditional updates: the report update
 * only applied `where escalated = false`, and the escalation row was
 * finished `where status = 'pending'`. Appwrite has no conditional
 * update, so both become read-then-write with a window in between.
 *
 * What covers the window is idempotency, as everywhere else here: the
 * push carries `escalation:<id>` as its message id and Appwrite refuses
 * the duplicate with a 409. Two overlapping runs therefore cost a wasted
 * read, not a second notification. Marking a report escalated twice is
 * already idempotent.
 */
import { Query, getRow, listRowsOrThrow, updateRow } from './lib/appwrite.js';
import { getSettings } from './lib/settings.js';
import { handler } from './lib/http.js';
import { findProfiles } from './lib/handlers.js';
import { sendPush } from './lib/messaging.js';
import {
  ESCALATION_REASON,
  escalationNotification,
  escalationQueries,
  selectRecipientIds,
} from './lib/notifications.js';

export const COLLECTION = 'scheduled_escalations';
export const BATCH = 100;
export const MAX_ATTEMPTS = 5;
export const RETRY_BASE_MS = 60_000;
export const RETRY_MAX_MS = 60 * 60_000;

// `scheduled_escalations` has no attempts column — it did not have one in
// Postgres either — so failures are counted in `reason` as "attempt N:".
const ATTEMPT_RE = /^attempt (\d+):/;

export const failedAttempts = (reason) => {
  const m = ATTEMPT_RE.exec(reason ?? '');
  return m ? Number(m[1]) : 0;
};

/** 1m, 2m, 4m … capped at an hour. */
export const retryDelayMs = (attempt) =>
  Math.min(RETRY_BASE_MS * 2 ** (attempt - 1), RETRY_MAX_MS);

/**
 * The body of this Function, exported so `worker.js` can run it beside
 * the others. The plan allows two Functions and this design has seven,
 * so the three scheduled ones share one entrypoint — see `worker.js`.
 */
export async function runEscalate({ log, error }) {
  await getSettings(); // read once; the timeout itself is set at write time
  const due = await listRowsOrThrow(COLLECTION, [
    Query.equal('status', 'pending'),
    Query.lessThanEqual('escalateAt', new Date().toISOString()),
    Query.orderAsc('escalateAt'),
    Query.limit(BATCH),
  ]);

  const summary = { due: due.length, processed: 0, skipped: 0, failed: 0 };
  for (const esc of due) {
    try {
      summary[await processEscalation(esc, { log })] += 1;
    } catch (e) {
      summary.failed += 1;
      const message = e?.message ?? String(e);
      try {
        await recordFailure(esc, message);
      } catch {
        // Best effort: the row stays pending and is picked up next tick.
      }
      error(`escalation ${esc.$id} (report ${esc.reportId}): ${message}`);
    }
  }
  if (due.length) log(`escalations ${JSON.stringify(summary)}`);
  return summary;
}

export default handler(runEscalate);

export async function processEscalation(esc, { log = () => {} } = {}) {
  const found = await getRow('reports', esc.reportId);
  if (found.status === 404) {
    await finish(esc.$id, 'skipped', 'Report not found');
    return 'skipped';
  }
  if (!found.ok) throw new Error(`report read failed: ${found.status}`);
  const report = found.body;

  if (report.status !== 'pending') {
    await finish(esc.$id, 'skipped', `Status: ${report.status}`);
    return 'skipped';
  }

  // Escalated by another path — a peer dispute — which already notified.
  // A report this cron escalated on an earlier, failed attempt carries
  // ESCALATION_REASON and goes on to retry the push, which is idempotent.
  if (
    report.escalated &&
    report.escalationReason &&
    report.escalationReason !== ESCALATION_REASON
  ) {
    await finish(esc.$id, 'skipped', `Already escalated: ${report.escalationReason}`);
    return 'skipped';
  }

  if (!report.escalated) {
    await updateRow('reports', report.$id, {
      escalated: true,
      escalationReason: ESCALATION_REASON,
    });
  }

  const lists = [];
  for (const q of escalationQueries(report)) lists.push(await findProfiles(q));
  const users = selectRecipientIds(lists, { excludeId: report.userId });
  await sendPush({
    key: `escalation:${esc.$id}`,
    users,
    notification: escalationNotification(report),
  });

  await finish(esc.$id, 'processed', ESCALATION_REASON);
  log(`escalation ${esc.$id} report ${report.$id} -> ${users.length} recipients`);
  return 'processed';
}

const finish = (id, status, reason) =>
  updateRow(COLLECTION, id, {
    status,
    reason: String(reason).slice(0, 500),
    processedAt: new Date().toISOString(),
  });

/**
 * Records a failure and pushes `escalateAt` forward, so a row that keeps
 * failing stops holding the head of the (escalateAt-ordered) queue — and
 * gives up after [MAX_ATTEMPTS] rather than retrying forever.
 */
export async function recordFailure(esc, message, now = Date.now) {
  const attempt = failedAttempts(esc.reason) + 1;
  if (attempt >= MAX_ATTEMPTS) {
    await finish(esc.$id, 'skipped', `Gave up after ${attempt} attempts: ${message}`);
    return { attempt, gaveUp: true };
  }
  await updateRow(COLLECTION, esc.$id, {
    reason: `attempt ${attempt}: ${message}`.slice(0, 500),
    escalateAt: new Date(now() + retryDelayMs(attempt)).toISOString(),
  });
  return { attempt, gaveUp: false };
}
