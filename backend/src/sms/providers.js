// SMS provider clients. Everything provider-specific (URLs, payload shapes,
// auth) lives here; callers only see { configured, name, send(toE164, text) }.
import { HTTP_TIMEOUT_MS } from '../http.js';
import { log as defaultLog } from '../log.js';

export const TERMII_SEND_URL = 'https://api.ng.termii.com/api/sms/send';
export const twilioMessagesUrl = (accountSid) =>
  `https://api.twilio.com/2010-04-01/Accounts/${encodeURIComponent(accountSid)}/Messages.json`;

async function readJson(res) {
  try {
    return await res.json();
  } catch {
    return {};
  }
}

function providerError(name, res, json) {
  const detail = json?.message ?? json?.error ?? JSON.stringify(json);
  const err = new Error(`${name} HTTP ${res.status}: ${detail}`.slice(0, 500));
  err.status = res.status;
  err.provider = name.toLowerCase();
  // Twilio: numeric error code (https://www.twilio.com/docs/api/errors).
  if (json?.code != null) err.code = json.code;
  err.detail = typeof detail === 'string' ? detail : '';
  return err;
}

/**
 * Twilio error codes that are about the recipient number itself (invalid,
 * not mobile, unsubscribed, unroutable, region not allowed); every retry
 * would fail the same way for that number.
 */
export const TWILIO_RECIPIENT_ERROR_CODES = new Set([
  21211, // invalid 'To' phone number
  21217, // phone number does not appear to be valid
  21401, // invalid phone number
  21407, // this phone number type does not support SMS
  21408, // permission to send to this region not enabled
  21610, // recipient unsubscribed (STOP)
  21612, // cannot route to this number
  21614, // 'To' number is not a valid mobile number
]);

/** Termii's replies about the recipient (invalid number, DND-blocked). */
const TERMII_RECIPIENT_ERROR =
  /invalid\s+(phone|mobile|recipient|destination|number)|(phone|mobile)\s*(number)?\s+(is\s+)?invalid|not\s+a\s+valid\s+(phone|mobile)|\bdnd\b|do.not.disturb/i;

/** 401/402/403: bad credentials, no balance or a suspended account. Not the
 * number's fault, and fixable by an operator, so retried (and logged loudly). */
export function isSmsAccountError(err) {
  return [401, 402, 403].includes(err?.status);
}

/**
 * A recipient-specific refusal the provider will repeat for this number, so
 * the send is not retried. Only explicit bad-number answers count: account
 * problems (401/402/403), rate limits, timeouts and unknown client errors
 * are retried.
 */
export function isPermanentSmsError(err) {
  const status = err?.status;
  if (!Number.isInteger(status) || status < 400 || status >= 500) return false;
  if (isSmsAccountError(err) || status === 408 || status === 429) return false;
  if (err.provider === 'twilio') return status === 400 && TWILIO_RECIPIENT_ERROR_CODES.has(Number(err.code));
  if (err.provider === 'termii') return TERMII_RECIPIENT_ERROR.test(err.detail ?? err.message ?? '');
  return false;
}

/** Termii (Nigeria). `to` is international format without '+', e.g. 2348031234567. */
export function createTermii({ apiKey, senderId, fetchImpl = globalThis.fetch }) {
  return {
    name: 'termii',
    configured: Boolean(apiKey && senderId),
    async send(toE164, text) {
      const res = await fetchImpl(TERMII_SEND_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({
          api_key: apiKey,
          to: toE164.replace(/^\+/, ''),
          from: senderId,
          sms: text,
          type: 'plain',
          channel: 'generic',
        }),
        signal: AbortSignal.timeout(HTTP_TIMEOUT_MS),
      });
      const json = await readJson(res);
      if (!res.ok) throw providerError('Termii', res, json);
      return { id: json?.message_id ?? null };
    },
  };
}

/** Twilio Programmable Messaging (form-encoded, HTTP basic auth SID:token). */
export function createTwilio({ accountSid, authToken, from, fetchImpl = globalThis.fetch }) {
  return {
    name: 'twilio',
    configured: Boolean(accountSid && authToken && from),
    async send(toE164, text) {
      const res = await fetchImpl(twilioMessagesUrl(accountSid), {
        method: 'POST',
        headers: {
          Authorization: `Basic ${Buffer.from(`${accountSid}:${authToken}`).toString('base64')}`,
          'Content-Type': 'application/x-www-form-urlencoded',
          Accept: 'application/json',
        },
        body: new URLSearchParams({ To: toE164, From: from, Body: text }).toString(),
        signal: AbortSignal.timeout(HTTP_TIMEOUT_MS),
      });
      const json = await readJson(res);
      if (!res.ok) throw providerError('Twilio', res, json);
      return { id: json?.sid ?? null };
    },
  };
}

/**
 * Picks the provider from config.smsProvider ('termii' | 'twilio' | unset).
 * An unset/unknown/incomplete provider yields `configured: false` and a send()
 * that logs and skips instead of throwing.
 */
export function createSmsProvider(config = {}, { fetchImpl = globalThis.fetch, logger = defaultLog } = {}) {
  const provider = String(config.smsProvider ?? '').toLowerCase();
  let client = null;
  if (provider === 'termii') {
    client = createTermii({ apiKey: config.termiiApiKey, senderId: config.smsSenderId, fetchImpl });
  } else if (provider === 'twilio') {
    client = createTwilio({
      accountSid: config.twilioAccountSid,
      authToken: config.twilioAuthToken,
      from: config.twilioFrom,
      fetchImpl,
    });
  }
  if (client?.configured) return client;
  return {
    name: provider || 'none',
    configured: false,
    async send(toE164) {
      logger.warn('sms.not_configured', { provider: provider || null, skipped: toE164 });
      return { skipped: true };
    },
  };
}
