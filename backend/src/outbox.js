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
      const { report_id: reportId, old_status: oldStatus, new_status: newStatus, reason } = event.payload ?? {};
      if (!reportId || !newStatus) throw new PermanentEventError('invalid payload: report_id/new_status missing');
      const report = await repo.getReport(reportId);
      if (!report) return 'report not found';
      // The event may be minutes old (retries back off); never announce a
      // decision that has since been changed, e.g. approved then rejected.
      if (report.status !== newStatus) return `stale: report now ${report.status}`;

      if (report.user_id) {
        await push.sendToUsers([report.user_id], reporterStatusNotification(report, newStatus, reason), {
          key: `outbox:${event.id}:reporter`,
        });
      }

      let broadcast = false;
      let sms = null;
      if (shouldBroadcastApproval(oldStatus, newStatus)) {
        const lgaTag = sanitizeTag(report.lga);
        if (lgaTag) {
          await push.sendToTag('lga', lgaTag, validatedAlertNotification(report), {
            key: `outbox:${event.id}:broadcast`,
          });
          broadcast = true;
        }
        // Pushes above are idempotent on retry; the SMS module dedupes per report itself.
        if (authoritySms) sms = await authoritySms.notifyApproved(report);
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

      // A retry of this handler finds the report already escalated by it; carry
      // on so the (idempotent) push is re-attempted. Any other escalated report
      // (timeout, or an earlier dispute) has already been notified.
      const resuming = (event.attempts ?? 1) > 1 && report.escalated && report.escalation_reason === DISPUTE_REASON;
      if (report.escalated && !resuming) return 'report already escalated';
      if (!report.escalated && !(await repo.markReportEscalated(report.id, DISPUTE_REASON))) {
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
      else await push.sendToTag(target.tagKey, target.tagValue, notification, { key });
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
export async function runOutboxBatch({ repo, handlers, logger = defaultLog, limit = BATCH_SIZE }) {
  const events = await repo.claimOutboxEvents(limit);
  for (const event of events) {
    await processEvent(event, { repo, handlers, logger });
  }
  return events.length;
}
