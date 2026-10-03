/**
 * The five outbox handlers, ported from `backend/src/outbox.js`.
 *
 * They were already written against a `repo` and a `push` interface, so
 * what changes is the field names and the delivery calls, not the logic.
 * Each returns a note (or null) on success and throws to retry.
 */
import { Query, getRow, listRowsOrThrow, updateRow } from './appwrite.js';
import { sendPush } from './messaging.js';
import { PermanentEventError } from './outbox.js';
import {
  DISPUTE_REASON,
  adminAlertNotification,
  alertTopics,
  disputeEscalationNotification,
  disputeReasonFor,
  escalationQueries,
  reporterStatusNotification,
  selectRecipientIds,
  shouldBroadcastApproval,
  validatedAlertNotification,
  verificationRequestNotification,
  verifierQuery,
} from './notifications.js';

/** Profiles matching one of the recipient filters. */
export async function findProfiles({ roles, lga, ward, limit }) {
  const queries = [Query.equal('role', roles), Query.limit(limit ?? 50)];
  if (lga) queries.push(Query.equal('lga', lga));
  if (ward) queries.push(Query.equal('ward', ward));
  // `isApproved`/`isDisabled` are filtered by selectRecipientIds rather
  // than here, so one query serves every caller and the eligibility rule
  // stays in one place.
  return listRowsOrThrow('profiles', queries);
}

async function notifyEscalationRecipients(report, notification, key) {
  const lists = [];
  for (const q of escalationQueries(report)) lists.push(await findProfiles(q));
  const users = selectRecipientIds(lists, { excludeId: report.userId });
  await sendPush({ key, users, notification });
  return users.length;
}

/** `deps`: `{ settings, sms, log }` — `sms` is optional (no SMS without it). */
export function createHandlers({ settings = {}, sms = null, log = () => {} } = {}) {
  return {
    async report_created(event, payload) {
      const reportId = payload.reportId;
      if (!reportId) throw new PermanentEventError('payload: reportId missing');
      const report = await readRow('reports', reportId);
      if (!report) return 'report not found';
      if (report.status !== 'pending') {
        return `report no longer pending (${report.status})`;
      }

      const query = verifierQuery(report);
      if (!query) return 'report has no ward/lga; skipped';
      const users = selectRecipientIds([await findProfiles(query)], {
        excludeId: report.userId,
      });
      await sendPush({
        key: `outbox:${event.$id}:verifiers`,
        users,
        notification: verificationRequestNotification(report),
      });
      log(`report_created ${reportId} -> ${users.length} verifiers`);
      return null;
    },

    async report_status_changed(event, payload) {
      const { reportId, oldStatus, newStatus } = payload;
      if (!reportId || !newStatus) {
        throw new PermanentEventError('payload: reportId/newStatus missing');
      }
      const report = await readRow('reports', reportId);
      if (!report) return 'report not found';
      // The event may be minutes old — retries back off — so never
      // announce a decision that has since been changed.
      if (report.status !== newStatus) return `stale: report now ${report.status}`;

      // Every delivery is attempted even when an earlier one fails: a
      // push outage must not hold back the authority SMS. Failures are
      // rethrown at the end so the event retries, and a retry only
      // repeats what did not land — pushes are idempotent by message id
      // and the SMS claims are per (report, phone).
      const errors = [];
      const attempt = async (what, fn) => {
        try {
          await fn();
        } catch (e) {
          errors.push(`${what}: ${e?.message ?? e}`);
        }
      };

      if (report.userId) {
        await attempt('reporter push', () =>
          sendPush({
            key: `outbox:${event.$id}:reporter`,
            users: [report.userId],
            notification: reporterStatusNotification(report, newStatus),
          }),
        );
      }

      let broadcast = null;
      let smsSummary = null;
      if (shouldBroadcastApproval(oldStatus, newStatus)) {
        const target = alertTopics({
          targetState: report.state,
          targetLga: report.lga,
        });
        await attempt('broadcast push', async () => {
          broadcast = await sendPush({
            key: `outbox:${event.$id}:broadcast`,
            topics: target.all ? [] : target.topics,
            users: [],
            notification: validatedAlertNotification(report),
          });
        });
        if (sms) {
          await attempt('authority sms', async () => {
            smsSummary = await sms(report, settings);
          });
        }
      }

      if (errors.length) {
        throw new Error(`report_status_changed ${reportId}: ${errors.join('; ')}`);
      }
      log(
        `report_status_changed ${reportId} ${oldStatus}->${newStatus} ` +
          `broadcast=${broadcast} sms=${JSON.stringify(smsSummary)}`,
      );
      return null;
    },

    async report_disputed(event, payload) {
      const { reportId, verificationId } = payload;
      if (!reportId) throw new PermanentEventError('payload: reportId missing');
      const report = await readRow('reports', reportId);
      if (!report) return 'report not found';
      if (report.status !== 'pending') {
        return `report no longer pending (${report.status})`;
      }

      // A retry finds the report already escalated by this very event
      // (its id is in escalationReason); carry on, so the idempotent push
      // is re-attempted. Any other escalation has already notified.
      const ownReason = disputeReasonFor(event.$id);
      const resuming = report.escalated && report.escalationReason === ownReason;
      if (report.escalated && !resuming) return 'report already escalated';
      if (!report.escalated) {
        // Postgres made this conditional (`where escalated = false`) and
        // Appwrite cannot. Two racing disputes could both mark it; the
        // push key is per event, so the second would notify again. The
        // window is the few milliseconds between read and write, and a
        // duplicate escalation notice is the mildest failure in this
        // file — unlike the SMS, which is claimed properly.
        await updateRow('reports', report.$id, {
          escalated: true,
          escalationReason: ownReason,
        });
      }
      await finishEscalationsFor(report.$id, 'processed', DISPUTE_REASON);

      const recipients = await notifyEscalationRecipients(
        report,
        disputeEscalationNotification(report),
        `outbox:${event.$id}:dispute`,
      );
      log(`report_disputed ${reportId} (${verificationId}) -> ${recipients}`);
      return null;
    },

    async user_access_changed(event, payload) {
      const userId = payload.userId;
      if (!userId) throw new PermanentEventError('payload: userId missing');
      const profile = await readRow('profiles', userId);
      if (!profile) return 'user not found';
      const disabled = profile.isDisabled === true;
      // Acts on the profile's current value, so a late or repeated event
      // is safe. Appwrite's `status` is true for active.
      const updated = await api_patch(`/users/${userId}/status`, { status: !disabled });
      if (!updated) return 'auth user not found';
      log(`user_access_changed ${userId} disabled=${disabled}`);
      return null;
    },

    async alert_created(event, payload) {
      const alertId = payload.alertId;
      if (!alertId) throw new PermanentEventError('payload: alertId missing');
      const alert = await readRow('alerts', alertId);
      if (!alert) return 'alert not found';
      if (alert.isActive === false) return 'alert inactive; skipped';

      const target = alertTopics(alert);
      await sendPush({
        key: `outbox:${event.$id}:alert`,
        topics: target.all ? [ALL_USERS_TOPIC] : target.topics,
        users: [],
        notification: adminAlertNotification(alert),
      });
      log(`alert_created ${alertId} -> ${JSON.stringify(target)}`);
      return null;
    },
  };
}

/**
 * OneSignal could address "everyone" directly; Appwrite addresses topics,
 * so "everyone" is a topic every account is subscribed to at
 * registration. Phase 3 counted it among the ~650.
 */
export const ALL_USERS_TOPIC = 'all-users';

async function readRow(table, id) {
  const row = await getRow(table, id);
  if (row.status === 404) return null;
  if (!row.ok) throw new Error(`${table}/${id} read failed: ${row.status}`);
  return row.body;
}

/** Closes any pending escalation rows for a report that escalated another way. */
async function finishEscalationsFor(reportId, status, reason) {
  const pending = await listRowsOrThrow('scheduled_escalations', [
    Query.equal('reportId', reportId),
    Query.equal('status', 'pending'),
    Query.limit(10),
  ]);
  for (const esc of pending) {
    await updateRow('scheduled_escalations', esc.$id, {
      status,
      reason,
      processedAt: new Date().toISOString(),
    });
  }
}

// Imported lazily to keep this module free of a circular import with
// appwrite.js's default export shape.
async function api_patch(path, body) {
  const { api } = await import('./appwrite.js');
  const result = await api(path, { method: 'PATCH', body });
  if (result.status === 404) return false;
  if (!result.ok) throw new Error(`${path} failed: ${result.status}`);
  return true;
}
