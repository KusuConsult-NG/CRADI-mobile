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

  await repo.markReportEscalated(report.id, ESCALATION_REASON);

  const lists = [];
  for (const q of escalationQueries(report)) lists.push(await repo.findProfiles(q));
  const ids = selectRecipientIds(lists, { excludeId: report.user_id });
  await push.sendToUsers(ids, escalationNotification(report), { key: `escalation:${esc.id}` });

  const won = await repo.finishEscalation(esc.id, 'processed', ESCALATION_REASON);
  logger.info('escalation.processed', { escalation_id: esc.id, report_id: report.id, recipients: ids.length, won });
  return 'processed';
}

export async function runEscalations({ repo, push, logger = defaultLog, limit = ESCALATION_BATCH }) {
  const due = await repo.dueEscalations(limit);
  const summary = { processed: 0, skipped: 0, failed: 0 };
  for (const esc of due) {
    try {
      summary[await processEscalation(esc, { repo, push, logger })]++;
    } catch (err) {
      summary.failed++;
      logger.error('escalation.failed', { escalation_id: esc.id, report_id: esc.report_id, error: errMessage(err) });
      try {
        await repo.noteEscalationError(esc.id, `Last error: ${errMessage(err)}`);
      } catch {
        /* best effort; retried next tick */
      }
    }
  }
  if (due.length) logger.info('escalation.run', { due: due.length, ...summary });
  return summary;
}
