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
  if (role !== 'ewr' && !isAdmin(role)) {
    throw forbidden('Only a reviewer or administrator may reopen a report');
  }

  const reportId = params.p_report_id ?? params.reportId;
  if (!reportId) throw invalid('p_report_id is required', ErrorType.argument);

  const report = await getRow('reports', reportId);
  if (report.status === 404) throw notFound('That report no longer exists');
  if (!report.ok) throw new Error(`report read failed: ${report.status}`);

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

  const updated = await updateRow('reports', reportId, {
    status: 'pending',
    verificationCount: 0,
    escalated: false,
    reopenedAt: new Date().toISOString(),
    reopenedBy: userId,
  });
  if (!updated.ok) throw new Error(`report update failed: ${updated.status}`);

  log(`report ${reportId} reopened by ${userId}, ${votes.body?.rows?.length ?? 0} votes cleared`);
  return { document: updated.body };
}
