// Escalation cron: reports still pending at escalate_at are flagged as
// escalated (status stays 'pending') and coordinators/staff are notified.
//
// Safe with several instances: the report update only applies while
// escalated=false, the escalation row is finished with a conditional
// status='pending' update, and pushes carry an idempotency key per
// escalation id so OneSignal drops duplicates.
import { errMessage, log as defaultLog } from './log.js';
import {
  ESCALATION_REASON,
  escalationNotification,
  escalationQueries,
  selectRecipientIds,
} from './notifications.js';

export const ESCALATION_BATCH = 100;
export const MAX_ESCALATION_ATTEMPTS = 5;
export const RETRY_BASE_MS = 60_000;
export const RETRY_MAX_MS = 60 * 60_000;

// scheduled_escalations has no attempts column, so failures are counted in
// `reason` as "attempt N: <error>".
const ATTEMPT_RE = /^attempt (\d+):/;

export function failedAttempts(reason) {
  const m = ATTEMPT_RE.exec(reason ?? '');
  return m ? Number(m[1]) : 0;
}

/** Exponential backoff for the Nth failure (1-based): 1m, 2m, 4m, ... capped at 1h. */
export function retryDelayMs(attempt) {
  return Math.min(RETRY_BASE_MS * 2 ** (attempt - 1), RETRY_MAX_MS);
}

/**
 * Records a failure. Pushes escalate_at forward so a persistently failing row
 * does not keep the head of the (escalate_at-ordered) queue, and gives up
 * (status 'skipped') after MAX_ESCALATION_ATTEMPTS.
 */
async function recordFailure(esc, message, { repo, now }) {
  const attempt = failedAttempts(esc.reason) + 1;
  if (attempt >= MAX_ESCALATION_ATTEMPTS) {
    await repo.finishEscalation(esc.id, 'skipped', `Gave up after ${attempt} attempts: ${message}`.slice(0, 500));
    return { attempt, gaveUp: true };
  }
  const retryAt = new Date(now() + retryDelayMs(attempt)).toISOString();
  await repo.noteEscalationError(esc.id, `attempt ${attempt}: ${message}`, retryAt);
  return { attempt, gaveUp: false };
}

/**
 * Pushes an escalation to LGA coordinators/EWRs + project staff/EWVs anywhere
 * (shared by the timeout cron and the dispute handler). Returns the recipient count.
 */
export async function notifyEscalationRecipients(report, notification, { repo, push, key }) {
  const lists = [];
  for (const q of escalationQueries(report)) lists.push(await repo.findProfiles(q));
  const ids = selectRecipientIds(lists, { excludeId: report.user_id });
  await push.sendToUsers(ids, notification, { key });
  return ids.length;
}

export async function processEscalation(esc, { repo, push, logger = defaultLog }) {
  const report = await repo.getReport(esc.report_id);
  if (!report) {
    await repo.finishEscalation(esc.id, 'skipped', 'Report not found');
    return 'skipped';
  }
  if (report.status !== 'pending') {
    await repo.finishEscalation(esc.id, 'skipped', `Status: ${report.status}`);
    return 'skipped';
  }

  // Escalated by another path (e.g. a peer dispute) that already notified.
  // A report escalated by this cron on an earlier, failed attempt carries
  // ESCALATION_REASON and goes on to (idempotently) retry the push.
  if (report.escalated && report.escalation_reason && report.escalation_reason !== ESCALATION_REASON) {
    await repo.finishEscalation(esc.id, 'skipped', `Already escalated: ${report.escalation_reason}`.slice(0, 500));
    return 'skipped';
  }

  // The conditional update only matches a pending, not-yet-escalated report.
  // If it matched nothing, something changed since the read above (e.g. a
  // dispute escalated it and notified): re-read and only continue when the
  // report carries this cron's own reason (an earlier attempt that failed
  // after marking, whose push is retried idempotently).
  if (!(await repo.markReportEscalated(report.id, ESCALATION_REASON))) {
    const fresh = await repo.getReport(report.id);
    let skipReason = null;
    if (!fresh) skipReason = 'Report not found';
    else if (fresh.status !== 'pending') skipReason = `Status: ${fresh.status}`;
    else if (!fresh.escalated || fresh.escalation_reason !== ESCALATION_REASON) {
      skipReason = `Already escalated: ${fresh.escalation_reason || 'unknown reason'}`;
    }
    if (skipReason) {
      await repo.finishEscalation(esc.id, 'skipped', skipReason.slice(0, 500));
      logger.info('escalation.skipped_race', { escalation_id: esc.id, report_id: report.id, reason: skipReason });
      return 'skipped';
    }
  }

  const recipients = await notifyEscalationRecipients(report, escalationNotification(report), {
    repo,
    push,
    key: `escalation:${esc.id}`,
  });

  const won = await repo.finishEscalation(esc.id, 'processed', ESCALATION_REASON);
  logger.info('escalation.processed', { escalation_id: esc.id, report_id: report.id, recipients, won });
  return 'processed';
}

export async function runEscalations({ repo, push, logger = defaultLog, limit = ESCALATION_BATCH, now = Date.now }) {
  const due = await repo.dueEscalations(limit);
  const summary = { processed: 0, skipped: 0, failed: 0 };
  for (const esc of due) {
    try {
      summary[await processEscalation(esc, { repo, push, logger })]++;
    } catch (err) {
      summary.failed++;
      const error = errMessage(err);
      let outcome = {};
      try {
        outcome = await recordFailure(esc, error, { repo, now });
      } catch {
        /* best effort; retried next tick */
      }
      logger.error('escalation.failed', { escalation_id: esc.id, report_id: esc.report_id, error, ...outcome });
    }
  }
  if (due.length) logger.info('escalation.run', { due: due.length, ...summary });
  return summary;
}
