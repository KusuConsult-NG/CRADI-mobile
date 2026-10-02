/**
 * SMS to local authorities, over Termii.
 *
 * Termii is the one vendor the migration keeps, so this is a port of
 * `backend/src/sms/authorities.js` rather than a replacement — the text,
 * the caps and the dedupe rule are unchanged.
 *
 * ## The claim, which is the whole difficulty
 *
 * Push and email ride on Appwrite refusing a duplicate `messageId`.
 * Termii has no such protection, and a duplicate flood warning to a local
 * authority is not a harmless retry. So `sms_deliveries` is the lock, and
 * Phase 6 verified the primitive it rests on:
 *
 *   first  insert of a deterministic id -> 201
 *   second insert of the same id        -> 409   (the claim is taken)
 *
 * The claim is written **before** the send. A crash between claiming and
 * sending leaves the claim in place, so that number is skipped rather
 * than risk texting it twice — the same bias the Railway worker had, and
 * the right one: a missed SMS is recoverable by a person, a duplicate
 * flood warning is not.
 */
import { Query, createRow, deleteRow, fnv1a64, listRowsOrThrow, updateRow } from './appwrite.js';

export const COLLECTION = 'sms_deliveries';
export const SMS_MAX_CHARS = 320;
export const DEFAULT_MAX_SMS_PER_ALERT_EVENT = 20;
export const DEFAULT_MAX_SMS_PER_LGA_PER_DAY = 50;

const WAT_OFFSET_MS = 60 * 60_000; // Nigeria: UTC+1, no DST.

const oneLine = (s) => String(s ?? '').replace(/\s+/g, ' ').trim();

/** lga / state as stored in sms_deliveries: trimmed, lower-case. */
export const smsArea = (v) => oneLine(v).toLowerCase();

export const lagosDay = (ms) =>
  new Date(ms + WAT_OFFSET_MS).toISOString().slice(0, 10);

/** The most recent midnight in Lagos, as an instant. */
export const lagosDayStart = (ms) =>
  new Date(Date.parse(`${lagosDay(ms)}T00:00:00Z`) - WAT_OFFSET_MS).toISOString();

/**
 * "EWER ALERT: {SEVERITY} {hazard} reported in {ward}, {lga}. {description}
 *  - verified by community monitors." — at most [maxChars].
 */
export function authoritySmsText(report, maxChars = SMS_MAX_CHARS) {
  const severity = oneLine(report.severity || 'high').toUpperCase();
  const hazard = oneLine(report.hazardType) || 'hazard';
  const where = [oneLine(report.ward), oneLine(report.lga)].filter(Boolean).join(', ');
  const head = `EWER ALERT: ${severity} ${hazard} reported${where ? ` in ${where}` : ''}.`;
  const tail = ' - verified by community monitors.';
  let desc = oneLine(report.description);
  const room = maxChars - head.length - tail.length - 1; // the space before desc
  if (desc && room < 4) desc = '';
  else if (desc.length > room) desc = `${desc.slice(0, room - 3).trimEnd()}...`;
  const text = `${head}${desc ? ` ${desc}` : ''}${tail}`;
  return text.length > maxChars ? text.slice(0, maxChars) : text;
}

/** The claim id: deterministic per (report, phone), so a retry collides. */
export const claimId = (reportId, phone) =>
  `sms-${fnv1a64(`${reportId}|${phone}`)}`;

const positiveInt = (value, fallback) => {
  const n = Number.parseInt(value ?? '', 10);
  return Number.isFinite(n) && n > 0 ? n : fallback;
};

/**
 * How many texts one alert may send, and how many an LGA may receive in a
 * day.
 *
 * Its own function so the two stored keys are testable without sending
 * anything. They are snake_case because they are row *values* in
 * `app_settings.key`, not column names — see the note in lib/settings.js.
 */
export function smsBudget(settings = {}) {
  return {
    perEvent: positiveInt(settings.max_sms_per_alert_event, DEFAULT_MAX_SMS_PER_ALERT_EVENT),
    perLgaDay: positiveInt(settings.max_sms_per_lga_per_day, DEFAULT_MAX_SMS_PER_LGA_PER_DAY),
  };
}

/**
 * Texts the authorities covering [report]'s LGA.
 *
 * Returns a summary rather than throwing on a per-number failure: one bad
 * number must not hold back the rest, and the outbox retry re-sends only
 * what did not land because only those claims were released.
 */
export async function notifyApproved(report, { settings = {}, send, now = Date.now, log }) {
  const { perEvent, perLgaDay } = smsBudget(settings);
  const lga = smsArea(report.lga);
  const state = smsArea(report.state);

  // Coverage only. There is no `isActive` on `authorities` — there never
  // was one in Postgres either — and Appwrite refuses a query naming an
  // attribute that is not in the schema ("Attribute not found in schema:
  // isActive", 400), so this filter did not narrow the list, it failed
  // the whole send.
  const authorities = await listRowsOrThrow('authorities', [
    Query.equal('coverageLga', report.lga),
    Query.limit(perEvent * 2),
  ]);
  const numbers = [
    ...new Set(authorities.map((a) => normalisePhone(a.phone)).filter(Boolean)),
  ];
  if (numbers.length === 0) return { sent: 0, skipped: 0, reason: 'no authorities' };

  // Both caps are counted across retries, which is why they are counted
  // from the stored deliveries rather than from this run.
  const alreadyForEvent = (
    await listRowsOrThrow(COLLECTION, [
      Query.equal('reportId', report.$id),
      Query.limit(perEvent + 1),
    ])
  ).length;
  const alreadyToday = (
    await listRowsOrThrow(COLLECTION, [
      Query.equal('lga', lga),
      Query.equal('state', state),
      Query.greaterThanEqual('$createdAt', lagosDayStart(now())),
      Query.limit(perLgaDay + 1),
    ])
  ).length;

  let budget = Math.min(perEvent - alreadyForEvent, perLgaDay - alreadyToday);
  if (budget <= 0) {
    return { sent: 0, skipped: numbers.length, reason: 'cap reached' };
  }

  const summary = { sent: 0, skipped: 0, failed: 0 };
  for (const phone of numbers) {
    if (budget <= 0) {
      summary.skipped += 1;
      continue;
    }
    const id = claimId(report.$id, phone);
    const claimed = await createRow(COLLECTION, id, {
      reportId: report.$id,
      phone,
      lga,
      state,
      status: 'claimed',
      error: null,
    });
    if (claimed.status === 409) {
      // Already texted, or being texted right now by an overlapping run.
      summary.skipped += 1;
      continue;
    }
    if (!claimed.ok) throw new Error(`sms claim failed: ${claimed.status}`);

    budget -= 1;
    try {
      await send(phone, authoritySmsText(report));
      await updateRow(COLLECTION, id, { status: 'sent' });
      summary.sent += 1;
    } catch (e) {
      if (isPermanentSmsError(e)) {
        // The provider will never accept this number. Keep the claim, so
        // it is not tried again, and record why.
        await updateRow(COLLECTION, id, {
          status: 'rejected',
          error: String(e.message ?? e).slice(0, 500),
        });
        summary.failed += 1;
      } else {
        // Releasing the claim is what makes the outbox retry re-send this
        // number and only this number.
        await deleteRow(COLLECTION, id);
        summary.failed += 1;
        throw e;
      }
    }
    log?.(`sms ${summary.sent}/${numbers.length} for ${report.$id}`);
  }
  return summary;
}

/** +234… — the format Termii wants. */
export function normalisePhone(raw) {
  const digits = String(raw ?? '').replace(/[^\d+]/g, '');
  if (!digits) return null;
  if (digits.startsWith('+234')) return digits;
  if (digits.startsWith('234')) return `+${digits}`;
  if (digits.startsWith('0') && digits.length === 11) return `+234${digits.slice(1)}`;
  if (digits.length === 10) return `+234${digits}`;
  return null;
}

/**
 * A number the provider will never accept, as opposed to an outage.
 *
 * Erring toward "not permanent" costs a retry; erring the other way
 * silently stops warning an authority, so the list is deliberately short.
 */
export function isPermanentSmsError(error) {
  const message = String(error?.message ?? error).toLowerCase();
  return (
    message.includes('invalid phone') ||
    message.includes('invalid number') ||
    message.includes('number blacklisted') ||
    message.includes('dnd')
  );
}

/** Sends one message through Termii. */
export async function termiiSender({ apiKey, senderId, fetchImpl = fetch }) {
  return async (to, sms) => {
    const response = await fetchImpl('https://api.ng.termii.com/api/sms/send', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        to,
        from: senderId,
        sms,
        type: 'plain',
        channel: 'generic',
        api_key: apiKey,
      }),
    });
    const body = await response.json().catch(() => ({}));
    // Termii answers 200 with an error message in the body as often as it
    // answers a 4xx, so the body is checked too — a 200 that did not send
    // must not read as sent.
    if (!response.ok || body?.code === 'error' || body?.message_id === undefined) {
      throw new Error(`termii: ${body?.message ?? response.status}`);
    }
    return body.message_id;
  };
}
