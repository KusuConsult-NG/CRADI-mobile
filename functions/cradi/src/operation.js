/**
 * `operation` — the named server-side operations.
 *
 * Contract: docs/APPWRITE-FUNCTION-CONTRACTS.md.
 * Client: `DataBackend.callOperation`, which is the one call in the data
 * interface that is neither a document nor a file.
 *
 * These are the Postgres RPCs. Each was a `SECURITY DEFINER` function —
 * which means it ran with the database owner's rights and did its own
 * authorisation check inside. That check has to come with it, so every
 * operation here states who may run it.
 */
import { getRow, listRows, updateRow, deleteRow, Query } from './lib/appwrite.js';
import {
  callerId,
  forbidden,
  handler,
  invalid,
  notFound,
  readJson,
  ErrorType,
} from './lib/http.js';
import { isAdmin } from './lib/policy.js';
import {
  COLLECTION as OUTBOX,
  enqueue,
  markProcessed,
  payloadOf,
} from './lib/outbox.js';

/** The event types the original superseded on reopen. */
const SUPERSEDED_BY_REOPEN = [
  'report_disputed',
  'report_created',
  'report_status_changed',
];
import { escalationTimeoutMinutes, getSettings } from './lib/settings.js';

const OPERATIONS = { reopen_report: reopenReport };

export default handler(async (context) => {
  const payload = readJson(context.req);
  const run = OPERATIONS[payload.operation];
  if (!run) {
    throw invalid(`Unknown operation: ${payload.operation}`, ErrorType.argument);
  }

  const userId = callerId(context.req);
  const profile = await getRow('profiles', userId);
  if (!profile.ok) throw forbidden('Your account is not set up yet');
  if (profile.body.isDisabled === true) {
    throw forbidden('Your account has been disabled. Please contact support.');
  }

  return run(payload.params ?? {}, {
    ...context,
    userId,
    role: profile.body.role ?? 'user',
  });
});

/**
 * Reopens a report: clears its peer votes, sets it back to pending and
 * reschedules escalation.
 *
 * Senior staff and admin only — `ewr` is the Early Warning Reviewer, the
 * role the original function gated on.
 */
async function reopenReport(params, { userId, role, log }) {
  // The Postgres function's own list, carried over verbatim. An earlier
  // port had only `ewr` and admin, which silently refused the three
  // roles that do most of the reviewing.
  const MAY_REOPEN = ['ewv', 'ewr', 'ldp_coordinator', 'project_staff'];
  if (!MAY_REOPEN.includes(role) && !isAdmin(role)) {
    throw forbidden('Your role cannot reopen reports');
  }

  const reportId = params.p_report_id ?? params.reportId;
  if (!reportId) throw invalid('p_report_id is required', ErrorType.argument);

  const report = await getRow('reports', reportId);
  if (report.status === 404) throw notFound('That report no longer exists');
  if (!report.ok) throw new Error(`report read failed: ${report.status}`);

  // Both guards are the original's. Reopening an already-pending report
  // would wipe live votes; reopening your own is how a reporter would
  // clear a rejection.
  if (report.body.status === 'pending') {
    throw invalid('That report is already pending', ErrorType.argument);
  }
  if (!isAdmin(role) && report.body.userId === userId) {
    throw forbidden('You cannot reopen your own report');
  }

  // Postgres did all of this in one transaction and Appwrite has none, so
  // the order matters: votes first, then the status. Interrupted halfway,
  // the report is still closed with some votes cleared — recoverable by
  // running it again. The other order would leave a reopened report
  // carrying stale votes, which would re-escalate it immediately on a
  // count that is no longer true.
  const votes = await listRows('verifications', [
    Query.equal('reportId', reportId),
    Query.limit(200),
  ]);
  if (!votes.ok) throw new Error(`vote read failed: ${votes.status}`);
  for (const vote of votes.body?.rows ?? []) {
    const removed = await deleteRow('verifications', vote.$id);
    if (!removed.ok && removed.status !== 404) {
      throw new Error(`vote delete failed: ${removed.status}`);
    }
  }

  // Every field the decision left behind. Clearing only `status` and the
  // vote count leaves `verifiedAt`, `rejectionReason` and the rest of the
  // old decision on a report that is supposedly undecided again.
  const settings = await getSettings();
  const escalateAt = new Date(
    Date.now() + escalationTimeoutMinutes(settings) * 60_000,
  ).toISOString();
  const updated = await updateRow('reports', reportId, {
    status: 'pending',
    verificationCount: 0,
    verifiedAt: null,
    autoValidated: false,
    approvedAt: null,
    rejectedAt: null,
    rejectionReason: null,
    escalated: false,
    escalatedAt: null,
    escalationReason: null,
    escalationScheduledAt: escalateAt,
    escalationStatus: 'pending',
    updatedBy: userId,
  });
  if (!updated.ok) throw new Error(`report update failed: ${updated.status}`);

  // Postgres skipped the old deadline row and inserted a fresh one. Here
  // there is exactly one row per report — `scheduleEscalation` keys it by
  // the report id — so the same intent is an update in place: a new
  // deadline, back to `pending`, with the previous outcome cleared.
  const rescheduled = await updateRow('scheduled_escalations', reportId, {
    escalateAt,
    status: 'pending',
    reason: 'Report reopened',
    processedAt: null,
  });
  if (!rescheduled.ok && rescheduled.status !== 404) {
    throw new Error(`escalation reschedule failed: ${rescheduled.status}`);
  }

  // Events queued before the reopen describe the old votes and the old
  // decision, and would otherwise be delivered after it — telling the
  // ward a report was disputed or decided when it has just gone back to
  // pending. Postgres superseded them by sequence id; the outbox here
  // has no sequence, so the cut is "still unprocessed at this moment",
  // which is the same set.
  const stale = await listRows(OUTBOX, [
    Query.isNull('processedAt'),
    Query.equal('eventType', SUPERSEDED_BY_REOPEN),
    Query.limit(200),
  ]);
  if (!stale.ok) throw new Error(`outbox read failed: ${stale.status}`);
  for (const event of stale.body?.rows ?? []) {
    // `reportId`, which is the key every outbox payload uses. Written
    // `report_id` this compared `undefined` against the id, matched
    // nothing, and superseded nothing — so the ward was still told the
    // report had been disputed or decided after it went back to
    // pending, which is the one thing this loop exists to prevent.
    if (payloadOf(event).reportId !== reportId) continue;
    await markProcessed(event.$id, 'superseded by reopen');
  }

  // The reopen is itself an event, so the ward hears that the report is
  // live again. `enqueue` is keyed on the report, so a retried reopen
  // collides rather than notifying twice.
  await enqueue({
    eventType: 'report_created',
    key: `${reportId}-reopen`,
    // Also `reportId`: the `report_created` handler reads that key and
    // raises `PermanentEventError` without it, so written `report_id`
    // this event was dropped and nobody was told the report was live
    // again.
    payload: { reportId, reopened: true },
  });

  log(`report ${reportId} reopened by ${userId}, ${votes.body?.rows?.length ?? 0} votes cleared`);
  return { document: updated.body };
}
