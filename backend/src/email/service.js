// POST /email: authenticated transactional email via Resend.
import { HTTP_TIMEOUT_MS } from '../http.js';
import { errMessage, log as defaultLog } from '../log.js';
import { templates, validateTemplateData } from './templates.js';

/** Roles allowed to email addresses other than their own (coordination staff only). */
export const ANY_RECIPIENT_ROLES = new Set(['admin', 'ldp_coordinator', 'project_staff']);
export const RECIPIENT_WINDOW_MS = 60_000; // 1 email per recipient per minute
export const CALLER_WINDOW_MS = 60 * 60_000;
export const CALLER_MAX_PER_WINDOW = 20; // per caller per hour

const EMAIL_RE = /^[^\s@<>(),;:"\\[\]]+@[^\s@<>(),;:"\\[\]]+\.[^\s@<>(),;:"\\[\]]+$/;

export function normalizeEmail(value) {
  return typeof value === 'string' ? value.trim().toLowerCase() : '';
}

export function isValidEmail(value) {
  return typeof value === 'string' && value.length <= 254 && EMAIL_RE.test(value);
}

/** Approved, enabled admin / LDP coordinator / project staff. */
export function isPrivilegedProfile(profile) {
  return Boolean(profile && profile.is_approved && !profile.is_disabled && ANY_RECIPIENT_ROLES.has(profile.role));
}

/**
 * Anti-abuse policy. Returns { ok: true } or { ok: false, status, error }.
 * Only approved admin / ldp_coordinator / project_staff may email any address;
 * everyone else (including ewm, ewv, ewr and techSupport) only their own.
 */
export function authorizeRecipient({ user, profile, to }) {
  if (profile?.is_disabled) return { ok: false, status: 403, error: 'Forbidden' };
  if (isPrivilegedProfile(profile)) return { ok: true };
  const own = normalizeEmail(user?.email);
  if (own && own === normalizeEmail(to)) return { ok: true };
  return { ok: false, status: 403, error: 'You may only send email to your own address' };
}

/** Sliding-window in-memory rate limiter keyed by string. */
export function createRateLimiter({ now = () => Date.now() } = {}) {
  const hits = new Map();
  return {
    /** True if `key` has fewer than `max` hits within `windowMs`. */
    allowed(key, max, windowMs) {
      const t = now();
      const list = (hits.get(key) ?? []).filter((ts) => t - ts < windowMs);
      hits.set(key, list);
      return list.length < max;
    },
    record(key) {
      const list = hits.get(key) ?? [];
      list.push(now());
      hits.set(key, list);
    },
    sweep(maxWindowMs = CALLER_WINDOW_MS) {
      const t = now();
      for (const [k, list] of hits) {
        const kept = list.filter((ts) => t - ts < maxWindowMs);
        if (kept.length) hits.set(k, kept);
        else hits.delete(k);
      }
    },
    size: () => hits.size,
  };
}

export function createResendSender({ apiKey, fromEmail, fromName, fetchImpl = globalThis.fetch }) {
  return async function sendEmail({ to, subject, html }) {
    const res = await fetchImpl('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: `${fromName} <${fromEmail}>`, to: [to], subject, html }),
      signal: AbortSignal.timeout(HTTP_TIMEOUT_MS),
    });
    let json = {};
    try {
      json = await res.json();
    } catch {
      /* ignore */
    }
    if (!res.ok) throw new Error(`Resend HTTP ${res.status}: ${json?.message ?? 'unknown error'}`);
    return { id: json?.id ?? null };
  };
}

/**
 * Framework-free request handler. Returns { status, body }.
 * deps: { verifyToken(token) -> user|null, getProfile(id) -> profile|null,
 *         sendEmail({to,subject,html}) -> {id} | null (null = not configured), limiter, logger }
 */
export function createEmailHandler({ verifyToken, getProfile, sendEmail, limiter = createRateLimiter(), logger = defaultLog }) {
  const fail = (status, error) => ({ status, body: { success: false, error } });

  return async function handleEmail({ authorization, body }) {
    const match = /^Bearer\s+(.+)$/i.exec(authorization ?? '');
    if (!match) return fail(401, 'Unauthorized');

    let user;
    try {
      user = await verifyToken(match[1].trim());
    } catch (err) {
      logger.warn('email.verify_failed', { error: errMessage(err) });
      user = null;
    }
    if (!user?.id) return fail(401, 'Invalid token');

    const { type, to, data = {} } = body && typeof body === 'object' ? body : {};
    if (typeof type !== 'string' || !Object.hasOwn(templates, type)) {
      return fail(400, `Unknown type. Valid: ${Object.keys(templates).join(', ')}`);
    }
    if (!isValidEmail(to)) return fail(400, '"to" must be a single valid email address');
    if (data === null || typeof data !== 'object' || Array.isArray(data)) return fail(400, '"data" must be an object');
    const dataError = validateTemplateData(type, data);
    if (dataError) return fail(400, dataError);

    let profile;
    try {
      profile = await getProfile(user.id);
    } catch (err) {
      logger.error('email.profile_failed', { user_id: user.id, error: errMessage(err) });
      return fail(500, 'Internal error');
    }
    const auth = authorizeRecipient({ user, profile, to });
    if (!auth.ok) return fail(auth.status, auth.error);

    const recipientKey = `to:${normalizeEmail(to)}`;
    const callerKey = `caller:${user.id}`;
    if (!limiter.allowed(recipientKey, 1, RECIPIENT_WINDOW_MS)) {
      return fail(429, 'Rate limit: wait 60 s before sending to this address again');
    }
    if (!limiter.allowed(callerKey, CALLER_MAX_PER_WINDOW, CALLER_WINDOW_MS)) {
      return fail(429, 'Rate limit: too many emails, try again later');
    }
    if (!sendEmail) return fail(503, 'Email service not configured');

    limiter.record(recipientKey);
    limiter.record(callerKey);
    try {
      const { subject, html } = templates[type](data);
      const result = await sendEmail({ to: to.trim(), subject, html });
      logger.info('email.sent', { type, user_id: user.id, id: result?.id ?? null });
      return { status: 200, body: { success: true, messageId: result?.id ?? null } };
    } catch (err) {
      logger.error('email.send_failed', { type, user_id: user.id, error: errMessage(err) });
      return fail(502, 'Failed to send email');
    }
  };
}
