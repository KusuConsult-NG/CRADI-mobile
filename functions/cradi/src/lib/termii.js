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

/**
 * `+234…` — the format the rest of the system stores and compares.
 *
 * Not the format Termii's API wants, which is the same digits without
 * the `+`; `termiiSender` strips it on the way out. Kept with the `+`
 * here because `sms_deliveries.phone`, the admin panel and the
 * `authorities` rows all use E.164, and the deterministic claim id is
 * derived from it.
 */
export function normalisePhone(input) {
  // A faithful port of `backend/src/sms/phone.js`, which is also what
  // the admin panel's `lib/phone.ts` mirrors — so a number the panel
  // accepts is one this can text, which was the point of writing it
  // once. The first port of it was a shorter reimplementation that
  // dropped two of the spellings and, worse, validated nothing: it
  // turned "+234 (0)803 123 4567" into a fourteen-digit number and
  // passed "+2349" straight through, both of which reach Termii as a
  // send to nobody.
  if (input == null) return null;
  let digits = String(input).replace(/\(0\)/g, '').replace(/[^\d+]/g, '');
  let international = false;
  if (digits.startsWith('+')) {
    digits = digits.slice(1);
    international = true;
  } else if (digits.startsWith('00')) {
    digits = digits.slice(2);
    international = true;
  }
  if (digits.includes('+')) return null;

  if (digits.startsWith('234') && digits.length >= 13) digits = digits.slice(3);
  else if (international) return null; // another country code
  if (digits.startsWith('0')) digits = digits.slice(1);
  // Nigerian subscriber numbers are 10 digits after the country code.
  if (!/^[1-9]\d{9}$/.test(digits)) return null;
  return `+234${digits}`;
}

/** Termii's replies about the recipient: a bad number, or DND-blocked. */
const RECIPIENT_REFUSAL =
  /invalid\s+(phone|mobile|recipient|destination|number)|(phone|mobile)\s*(number)?\s+(is\s+)?invalid|not\s+a\s+valid\s+(phone|mobile)|number\s+blacklisted|\bdnd\b|do.not.disturb/i;

/**
 * 401, 402, 403: bad credentials, no balance, a suspended account.
 *
 * Not the number's fault and not permanent — somebody tops up the
 * account and every queued warning goes out. Treating it as permanent
 * would mark a whole LGA's authorities `rejected` over an unpaid bill,
 * and nothing would ever retry them.
 */
export function isSmsAccountError(error) {
  return [401, 402, 403].includes(error?.status);
}

/**
 * A refusal the provider will repeat for this number, as opposed to an
 * outage, a rate limit or an unpaid account.
 *
 * Status first, then the text. The message alone is not enough: Termii
 * says "Invalid API key" with a 401 and "Invalid phone number" with a
 * 400, and a substring match on `invalid` cannot tell a dead account
 * from a dead number — one is fixed by topping up and retrying, the
 * other is never fixed by retrying at all. The Railway worker this is a
 * port of got that right and the first port of it did not.
 *
 * Erring toward "not permanent" costs a retry; erring the other way
 * silently stops warning an authority, so the match stays narrow.
 */
export function isPermanentSmsError(error) {
  const status = error?.status;
  if (!Number.isInteger(status) || status < 400 || status >= 500) return false;
  if (isSmsAccountError(error) || status === 408 || status === 429) return false;
  return RECIPIENT_REFUSAL.test(String(error?.detail ?? error?.message ?? error));
}

/** Termii's API, unless something points this somewhere else. */
export const TERMII_BASE_URL = 'https://api.ng.termii.com';

/**
 * Where the SMS actually goes.
 *
 * Overridable so the path can be exercised end to end against a stand-in
 * that records what it was sent — the caps, the dedupe claim and the
 * payload are all testable that way, and none of them were, because the
 * only way to run this was to text a real authority. `TERMII_BASE_URL`
 * is unset in production and the default is Termii.
 */
export const termiiBaseUrl = () =>
  String(process.env.TERMII_BASE_URL || TERMII_BASE_URL).replace(/\/+$/, '');

/**
 * How long to wait on Termii before giving up.
 *
 * The drain is a scheduled Function with a time budget, and `fetch` has
 * no default timeout — one hung connection would hold the whole run
 * until Appwrite killed it, taking every other queued notification with
 * it. The Railway worker used the same 15s.
 */
export const SMS_TIMEOUT_MS = 15_000;

/**
 * Builds the sender. **Not async**: it returns the function, not a
 * promise of one.
 *
 * It was `async` and `drain.js` calls it without `await`, so `send` was
 * a Promise and every authority SMS died on `send is not a function`.
 * The SMS suite did not catch it because the suite awaited the builder
 * — it was written to match this signature instead of matching the one
 * caller that matters, which is the same mistake as a fake built from
 * the code it tests. `drain.test.mjs` now calls it the way the drain
 * does.
 */
export function termiiSender({ apiKey, senderId, fetchImpl = fetch }) {
  return async (to, sms) => {
    let response;
    try {
      response = await fetchImpl(`${termiiBaseUrl()}/api/sms/send`, {
        method: 'POST',
        headers: { 'content-type': 'application/json', accept: 'application/json' },
        body: JSON.stringify({
          // **Without the `+`.** Termii wants an international number as
          // bare digits — `2348031234567` — and the Railway worker
          // stripped it on every send, with a comment saying so. The
          // first port of this passed `normalisePhone`'s `+234…`
          // straight through, which is the one field in the payload that
          // decides whether a flood warning is delivered or refused.
          to: String(to).replace(/^\+/, ''),
          from: senderId,
          sms,
          type: 'plain',
          channel: 'generic',
          api_key: apiKey,
        }),
        signal: AbortSignal.timeout(SMS_TIMEOUT_MS),
      });
    } catch (cause) {
      // A timeout or a dead socket. No status, so never permanent: the
      // claim is released and the outbox retries this number.
      const error = new Error(`termii: ${cause?.message ?? cause}`);
      error.cause = cause;
      throw error;
    }
    const body = await response.json().catch(() => ({}));
    // Termii answers 200 with an error message in the body as often as it
    // answers a 4xx, so the body is checked too — a 200 that did not send
    // must not read as sent.
    if (!response.ok || body?.code === 'error' || body?.message_id === undefined) {
      const detail = String(body?.message ?? body?.error ?? response.status);
      const error = new Error(`termii: ${detail}`.slice(0, 500));
      // A 200 carrying `code: 'error'` is still the provider refusing,
      // and what it refused is in the message — so it is classified as a
      // 400 rather than as a success that threw.
      error.status = response.ok ? 400 : response.status;
      error.detail = detail;
      throw error;
    }
    return body.message_id;
  };
}
