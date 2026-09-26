// SMS to local authorities when a report is approved (restores the Firebase
// behaviour). Called from the outbox report_status_changed handler on a
// transition into 'approved'.
//
// Guards (in memory, per instance; fine because the outbox marks events
// processed and one replica is the norm):
//   - dedupe per report: a report whose SMS round completed is never texted
//     again; within a round each (report, phone) is sent at most once, so an
//     outbox retry after a partial failure only sends the missing ones;
//   - daily cap per LGA (app_settings.max_sms_per_lga_per_day, default 50),
//     counted on successful sends, day boundary in Africa/Lagos (UTC+1).
import { errMessage, log as defaultLog } from '../log.js';
import { normalizeNigerianPhone } from './phone.js';

export const SMS_MAX_CHARS = 320;
export const DEFAULT_MAX_SMS_PER_ALERT_EVENT = 20;
export const DEFAULT_MAX_SMS_PER_LGA_PER_DAY = 50;
const WAT_OFFSET_MS = 60 * 60_000; // Nigeria: UTC+1, no DST
const DEDUPE_TTL_MS = 7 * 24 * 60 * 60_000;

const oneLine = (s) => String(s ?? '').replace(/\s+/g, ' ').trim();

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

export function createAuthoritySms({ repo, sms, logger = defaultLog, now = Date.now }) {
  const daily = new Map(); // `${day}|${lga}` -> successful sends
  const completed = new Map(); // report id -> completion time
  const delivered = new Map(); // report id -> Set(phone) (current round)

  function sweep(t) {
    const today = lagosDay(t);
    for (const key of daily.keys()) if (!key.startsWith(`${today}|`)) daily.delete(key);
    for (const [id, at] of completed) if (t - at > DEDUPE_TTL_MS) completed.delete(id);
  }

  async function notifyApproved(report) {
    if (!report?.id || !report.lga) return { sent: 0, note: 'report has no lga' };
    if (!sms.configured) {
      logger.warn('sms.skipped_not_configured', { report_id: report.id });
      return { sent: 0, note: 'sms not configured' };
    }
    const t = now();
    sweep(t);
    if (completed.has(report.id)) return { sent: 0, note: 'sms already sent for report' };

    const settings = await repo.getSettings(['max_sms_per_alert_event', 'max_sms_per_lga_per_day']);
    const perEvent = positiveInt(settings.max_sms_per_alert_event, DEFAULT_MAX_SMS_PER_ALERT_EVENT);
    const perDay = positiveInt(settings.max_sms_per_lga_per_day, DEFAULT_MAX_SMS_PER_LGA_PER_DAY);
    const authorities = await repo.findAuthorities(report.lga, perEvent);

    const text = authoritySmsText(report);
    const capKey = `${lagosDay(t)}|${oneLine(report.lga).toLowerCase()}`;
    const done = delivered.get(report.id) ?? new Set();
    delivered.set(report.id, done);
    const seen = new Set();
    const summary = { sent: 0, failed: 0, invalid: 0, capped: 0 };

    for (const a of authorities) {
      const phone = normalizeNigerianPhone(a.phone);
      if (!phone) {
        summary.invalid++;
        logger.warn('sms.invalid_phone', { report_id: report.id, authority_id: a.id });
        continue;
      }
      if (seen.has(phone)) continue;
      seen.add(phone);
      if (done.has(phone)) continue;
      if ((daily.get(capKey) ?? 0) >= perDay) {
        summary.capped++;
        continue;
      }
      try {
        await sms.send(phone, text);
        done.add(phone);
        daily.set(capKey, (daily.get(capKey) ?? 0) + 1);
        summary.sent++;
      } catch (err) {
        summary.failed++;
        logger.error('sms.send_failed', { report_id: report.id, authority_id: a.id, provider: sms.name, error: errMessage(err) });
      }
    }

    logger.info('sms.authorities', { report_id: report.id, lga: report.lga, authorities: authorities.length, ...summary });
    // Any failed send: throw so the outbox retries the event. Phones already
    // texted in this round are remembered in `done` and skipped on the retry,
    // so only the failed ones are attempted again. The report is marked
    // complete only once a round finishes with no failures.
    if (summary.failed > 0) {
      throw new Error(
        `SMS to authorities failed for ${summary.failed} of ${summary.failed + summary.sent} recipients (report ${report.id})`,
      );
    }
    completed.set(report.id, t);
    delivered.delete(report.id);
    return summary;
  }

  return { notifyApproved, dailyCount: (lga, t = now()) => daily.get(`${lagosDay(t)}|${oneLine(lga).toLowerCase()}`) ?? 0 };
}
