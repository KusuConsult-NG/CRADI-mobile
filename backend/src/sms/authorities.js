// SMS to local authorities when a report is approved (restores the Firebase
// behaviour). Called from the outbox report_status_changed handler on a
// transition into 'approved'.
//
// Guards, persisted in public.sms_deliveries so a restart (or a second
// replica) never re-texts anyone:
//   - dedupe per (report, phone): a 'claimed' row is inserted before each
//     send; a conflict means that number was already texted (or is being
//     texted) for this report and it is skipped. A retryable failure deletes
//     the claim so the outbox retry sends it; a number the provider rejects
//     stays recorded as 'rejected' and is not retried;
//   - per-event cap (app_settings.max_sms_per_alert_event, default 20):
//     texts per report, counted across retries;
//   - daily cap per LGA (app_settings.max_sms_per_lga_per_day, default 50),
//     counted from rows created since midnight Africa/Lagos (UTC+1), keyed by
//     (state, lga) since LGA names repeat across states.
// A crash between claiming and sending leaves the claim in place, so that
// number is skipped rather than risk texting it twice.
import { errMessage, log as defaultLog } from '../log.js';
import { normalizeNigerianPhone } from './phone.js';
import { isPermanentSmsError, isSmsAccountError } from './providers.js';

export const SMS_MAX_CHARS = 320;
export const DEFAULT_MAX_SMS_PER_ALERT_EVENT = 20;
export const DEFAULT_MAX_SMS_PER_LGA_PER_DAY = 50;
const WAT_OFFSET_MS = 60 * 60_000; // Nigeria: UTC+1, no DST

const oneLine = (s) => String(s ?? '').replace(/\s+/g, ' ').trim();
/** lga / state as stored in sms_deliveries (trimmed, lower-case). */
export const smsArea = (v) => oneLine(v).toLowerCase();

/** "EWER ALERT: {SEVERITY} {hazard} reported in {ward}, {lga}. {description} - verified by community monitors." (<= 320 chars) */
export function authoritySmsText(report, maxChars = SMS_MAX_CHARS) {
  const severity = oneLine(report.severity || 'high').toUpperCase();
  const hazard = oneLine(report.hazard_type) || 'hazard';
  const where = [oneLine(report.ward), oneLine(report.lga)].filter(Boolean).join(', ');
  const head = `EWER ALERT: ${severity} ${hazard} reported${where ? ` in ${where}` : ''}.`;
  const tail = ' - verified by community monitors.';
  let desc = oneLine(report.description);
  const room = maxChars - head.length - tail.length - 1; // 1 = space before description
  if (desc && room < 4) desc = '';
  else if (desc.length > room) desc = `${desc.slice(0, room - 3).trimEnd()}...`;
  const text = `${head}${desc ? ` ${desc}` : ''}${tail}`;
  return text.length > maxChars ? text.slice(0, maxChars) : text;
}

function positiveInt(value, fallback) {
  const n = Number.parseInt(value ?? '', 10);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

export function lagosDay(ms) {
  return new Date(ms + WAT_OFFSET_MS).toISOString().slice(0, 10);
}

/** ISO instant of the most recent midnight in Lagos at time `ms`. */
export function lagosDayStart(ms) {
  return new Date(Date.parse(`${lagosDay(ms)}T00:00:00Z`) - WAT_OFFSET_MS).toISOString();
}

export function createAuthoritySms({ repo, sms, logger = defaultLog, now = Date.now }) {
  async function notifyApproved(report) {
    if (!report?.id || !report.lga) return { sent: 0, note: 'report has no lga' };
    if (!sms.configured) {
      logger.warn('sms.skipped_not_configured', { report_id: report.id });
      return { sent: 0, note: 'sms not configured' };
    }
    const t = now();
    const settings = await repo.getSettings(['max_sms_per_alert_event', 'max_sms_per_lga_per_day']);
    const perEvent = positiveInt(settings.max_sms_per_alert_event, DEFAULT_MAX_SMS_PER_ALERT_EVENT);
    const perDay = positiveInt(settings.max_sms_per_lga_per_day, DEFAULT_MAX_SMS_PER_LGA_PER_DAY);
    if (!oneLine(report.state)) {
      // No state on the report: nobody is texted. Every authority has a
      // coverage_state since migration 20260927090000 (NOT NULL + a foreign
      // key into public.nigeria_lgas), and findAuthorities() can only match
      // state-less rows when the report has no state, so this finds nothing.
      // That is deliberate: an LGA name alone can mean two states (Obi is in
      // Benue and in Nasarawa), and texting the wrong state's emergency desk
      // is worse than texting no one. reports.lga/state come from the app's
      // fixed location list, so a report without a state is a data fault to
      // fix at the source, not something to guess around.
      logger.warn('sms.report_without_state', {
        report_id: report.id,
        lga: report.lga,
        hint: 'No SMS is sent: an LGA name without a state can mean two different states. Set reports.state for this report.',
      });
    }
    const authorities = await repo.findAuthorities(report.lga, report.state, perEvent);

    const text = authoritySmsText(report);
    const area = { lga: smsArea(report.lga), state: smsArea(report.state) };
    let dailyCount = await repo.countSmsDeliveries({ ...area, since: lagosDayStart(t) });
    let reportCount = await repo.countReportSmsDeliveries(report.id);
    const seen = new Set();
    const summary = { sent: 0, failed: 0, rejected: 0, invalid: 0, capped: 0, skipped: 0 };

    for (const a of authorities) {
      const phone = normalizeNigerianPhone(a.phone);
      if (!phone) {
        summary.invalid++;
        logger.warn('sms.invalid_phone', { report_id: report.id, authority_id: a.id });
        continue;
      }
      if (seen.has(phone)) continue;
      seen.add(phone);
      if (dailyCount >= perDay || reportCount >= perEvent) {
        summary.capped++;
        continue;
      }
      if (!(await repo.claimSmsDelivery({ reportId: report.id, phone, ...area }))) {
        summary.skipped++; // already sent (or being sent) for this report
        continue;
      }
      dailyCount++;
      reportCount++;
      try {
        await sms.send(phone, text);
        summary.sent++;
        await bestEffort(() => repo.setSmsDeliveryStatus(report.id, phone, 'sent'), report.id);
      } catch (err) {
        if (isPermanentSmsError(err)) {
          // The provider refuses this number: retrying would fail the same
          // way forever. Keep the row (as 'rejected') so it isn't retried.
          summary.rejected++;
          dailyCount--;
          reportCount--;
          await bestEffort(() => repo.setSmsDeliveryStatus(report.id, phone, 'rejected'), report.id);
          logger.error('sms.recipient_rejected', { report_id: report.id, authority_id: a.id, provider: sms.name, error: errMessage(err) });
          continue;
        }
        summary.failed++;
        dailyCount--;
        reportCount--;
        // Free the claim so the outbox retry texts this number again.
        await bestEffort(() => repo.releaseSmsDelivery(report.id, phone), report.id);
        if (isSmsAccountError(err)) {
          logger.error('sms.provider_account_error', {
            report_id: report.id,
            provider: sms.name,
            status: err.status,
            error: errMessage(err),
            hint: 'Check the SMS provider credentials, balance and account status; the event is retried.',
          });
        } else {
          logger.error('sms.send_failed', { report_id: report.id, authority_id: a.id, provider: sms.name, error: errMessage(err) });
        }
      }
    }

    logger.info('sms.authorities', { report_id: report.id, lga: report.lga, state: report.state ?? null, authorities: authorities.length, ...summary });
    // Any failed send: throw so the outbox retries the event. Numbers already
    // texted keep their rows and are skipped on the retry, so only the failed
    // ones are attempted again.
    if (summary.failed > 0) {
      throw new Error(
        `SMS to authorities failed for ${summary.failed} of ${summary.failed + summary.sent} recipients (report ${report.id})`,
      );
    }
    return summary;
  }

  async function bestEffort(fn, reportId) {
    try {
      await fn();
    } catch (err) {
      logger.error('sms.delivery_bookkeeping_failed', { report_id: reportId, error: errMessage(err) });
    }
  }

  return {
    notifyApproved,
    /** Texts counted toward today's cap for (lga, state). */
    dailyCount: (lga, t = now(), state = '') =>
      repo.countSmsDeliveries({ lga: smsArea(lga), state: smsArea(state), since: lagosDayStart(t) }),
  };
}
