// Outbox worker: claims rows from notification_outbox (written by DB triggers)
// and turns them into OneSignal pushes.
//
// Delivery is at-least-once: claim_outbox_events() bumps attempts and pushes
// available_at into the future (exponential backoff, max 8 attempts), so a
// crashed or failed event is retried later. Each push carries an idempotency
// key derived from the outbox id, so OneSignal drops duplicates on retry.
import { errMessage, log as defaultLog } from './log.js';
import { sanitizeTag } from './tags.js';
import { notifyEscalationRecipients } from './escalations.js';
import {
  DISPUTE_REASON,
  disputeReasonFor,
  adminAlertNotification,
  disputeEscalationNotification,
  alertTarget,
  reporterStatusNotification,
  selectRecipientIds,
  shouldBroadcastApproval,
  validatedAlertNotification,
  verificationRequestNotification,
  verifierQuery,
} from './notifications.js';

export const BATCH_SIZE = 50;

/** Thrown for events that can never succeed; they are marked processed with this note. */
export class PermanentEventError extends Error {}

/**
 * deps: repo, push (OneSignal), optional authoritySms (src/sms/authorities.js;
 * when omitted, approvals send no SMS).
 */
export function createHandlers({ repo, push, authoritySms = null, logger = defaultLog }) {
  return {
    async report_created(event) {
      const reportId = event.payload?.report_id;
      if (!reportId) throw new PermanentEventError('invalid payload: report_id missing');
      const report = await repo.getReport(reportId);
      if (!report) return 'report not found';
      if (report.status !== 'pending') return `report no longer pending (${report.status})`;

      const query = verifierQuery(report);
      if (!query) return 'report has no ward/lga; skipped';
      const ids = selectRecipientIds([await repo.findProfiles(query)], { excludeId: report.user_id });
      await push.sendToUsers(ids, verificationRequestNotification(report), {
        key: `outbox:${event.id}:verifiers`,
      });
      logger.info('outbox.report_created', { event_id: event.id, report_id: reportId, recipients: ids.length });
      return null;
    },

    async report_status_changed(event) {
      // payload.reason (rejection reason) is intentionally not pushed; see notifications.js.
      const { report_id: reportId, old_status: oldStatus, new_status: newStatus } = event.payload ?? {};
      if (!reportId || !newStatus) throw new PermanentEventError('invalid payload: report_id/new_status missing');
      const report = await repo.getReport(reportId);
      if (!report) return 'report not found';
      // The event may be minutes old (retries back off); never announce a
      // decision that has since been changed, e.g. approved then rejected.
      if (report.status !== newStatus) return `stale: report now ${report.status}`;

      // Each delivery is attempted even when an earlier one fails (a push
      // outage must not hold back the authority SMS); any failure is rethrown
      // at the end so the event retries. Pushes are idempotent via their keys
      // and the SMS module dedupes per (report, phone), so a retry only
      // repeats what failed.
      const errors = [];
      const attempt = async (what, fn) => {
        try {
          await fn();
          return true;
        } catch (err) {
          errors.push(`${what}: ${errMessage(err)}`);
          return false;
        }
      };

      if (report.user_id) {
        await attempt('reporter push', () =>
          push.sendToUsers([report.user_id], reporterStatusNotification(report, newStatus), {
            key: `outbox:${event.id}:reporter`,
          }),
        );
      }

      let broadcast = false;
      let sms = null;
      if (shouldBroadcastApproval(oldStatus, newStatus)) {
        const lgaTag = sanitizeTag(report.lga);
        if (lgaTag) {
          // LGA names repeat across states (Obi: Benue and Nasarawa), so a
          // report with a state also requires the device's state tag.
          const stateTag = sanitizeTag(String(report.state ?? '').trim());
          broadcast = await attempt('broadcast push', () =>
            push.sendToTag('lga', lgaTag, validatedAlertNotification(report), {
              key: `outbox:${event.id}:broadcast`,
              andTags: stateTag ? { state: stateTag } : undefined,
            }),
          );
        }
        if (authoritySms) {
          await attempt('authority sms', async () => {
            sms = await authoritySms.notifyApproved(report);
          });
        }
      }
      if (errors.length) {
        throw new Error(`report_status_changed ${reportId}: ${errors.join('; ')}`);
      }
      logger.info('outbox.report_status_changed', {
        event_id: event.id,
        report_id: reportId,
        old_status: oldStatus,
        new_status: newStatus,
        broadcast,
        sms,
      });
      return null;
    },

    // A peer submitted is_confirmed=false on a pending report: escalate it now
    // instead of waiting for the timeout, and notify the same recipients.
    async report_disputed(event) {
      const { report_id: reportId, verification_id: verificationId } = event.payload ?? {};
      if (!reportId) throw new PermanentEventError('invalid payload: report_id missing');
      const report = await repo.getReport(reportId);
      if (!report) return 'report not found';
      if (report.status !== 'pending') return `report no longer pending (${report.status})`;

      // A retry of this handler finds the report already escalated by this very
      // event (its id is in escalation_reason); carry on so the (idempotent)
      // push is re-attempted. Any other escalation (timeout, or another dispute
      // event) has already been notified.
      const ownReason = disputeReasonFor(event.id);
      const resuming = report.escalated && report.escalation_reason === ownReason;
      if (report.escalated && !resuming) return 'report already escalated';
      if (!report.escalated && !(await repo.markReportEscalated(report.id, ownReason))) {
        return 'report already escalated';
      }
      // Stop the timeout cron from escalating (and notifying) it a second time.
      await repo.finishPendingEscalationForReport(report.id, 'processed', DISPUTE_REASON);

      const recipients = await notifyEscalationRecipients(report, disputeEscalationNotification(report), {
        repo,
        push,
        key: `outbox:${event.id}:dispute`,
      });
      logger.info('outbox.report_disputed', {
        event_id: event.id,
        report_id: reportId,
        verification_id: verificationId ?? null,
        recipients,
      });
      return null;
    },

    // profiles.is_disabled changed (web or mobile admin): make Supabase Auth
    // agree, so a blocked user can't sign in and an unblocked one can. Acts
    // on the profile's current value, so late or repeated events are safe.
    async user_access_changed(event) {
      const userId = event.payload?.user_id;
      if (!userId) throw new PermanentEventError('invalid payload: user_id missing');
      const profile = await repo.getProfile(userId);
      if (!profile) return 'user not found';
      const disabled = profile.is_disabled === true;
      const found = await repo.setAuthBan(userId, disabled);
      if (!found) return 'auth user not found';
      logger.info('outbox.user_access_changed', { event_id: event.id, user_id: userId, disabled });
      return null;
    },

    async alert_created(event) {
      const alertId = event.payload?.alert_id;
      if (!alertId) throw new PermanentEventError('invalid payload: alert_id missing');
      const alert = await repo.getAlert(alertId);
      if (!alert) return 'alert not found';
      if (alert.is_active === false) return 'alert inactive; skipped';

      const target = alertTarget(alert);
      const notification = adminAlertNotification(alert);
      const key = `outbox:${event.id}:alert`;
      if (target.all) await push.sendToAll(notification, { key });
      else await push.sendToTags(target.tags, notification, { key });
      logger.info('outbox.alert_created', { event_id: event.id, alert_id: alertId, target });
      return null;
    },
  };
}

/** Processes one claimed event and records the outcome. Never throws. */
export async function processEvent(event, { repo, handlers, logger = defaultLog }) {
  const handler = Object.hasOwn(handlers, event.event_type) ? handlers[event.event_type] : null;
  try {
    if (!handler) {
      logger.warn('outbox.unknown_event', { event_id: event.id, event_type: event.event_type });
      await repo.markEventProcessed(event.id, 'unknown event');
      return 'unknown';
    }
    const note = await handler(event);
    await repo.markEventProcessed(event.id, note ?? null);
    return 'processed';
  } catch (err) {
    if (err instanceof PermanentEventError) {
      logger.warn('outbox.permanent_failure', { event_id: event.id, error: err.message });
      await safe(() => repo.markEventProcessed(event.id, err.message), logger, event.id);
      return 'processed';
    }
    logger.error('outbox.event_failed', {
      event_id: event.id,
      event_type: event.event_type,
      attempts: event.attempts,
      error: errMessage(err),
    });
    await safe(() => repo.markEventFailed(event.id, errMessage(err)), logger, event.id);
    return 'failed';
  }
}

async function safe(fn, logger, eventId) {
  try {
    await fn();
  } catch (err) {
    logger.error('outbox.bookkeeping_failed', { event_id: eventId, error: errMessage(err) });
  }
}

/** Claims and processes one batch. Returns the number of events claimed. */
export async function runOutboxBatch({ repo, handlers, logger = defaultLog, limit = BATCH_SIZE, shouldStop = () => false }) {
  const events = await repo.claimOutboxEvents(limit);
  for (const [i, event] of events.entries()) {
    // Shutting down: leave the rest of the batch. Claimed rows are simply
    // picked up again once their claim backoff (available_at) expires.
    if (shouldStop()) {
      logger.info('outbox.batch_interrupted', { processed: i, left: events.length - i });
      break;
    }
    await processEvent(event, { repo, handlers, logger });
  }
  return events.length;
}
