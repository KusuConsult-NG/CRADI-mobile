import { createHash } from 'node:crypto';
import { HTTP_TIMEOUT_MS } from './http.js';
import { log as defaultLog } from './log.js';

export const ONESIGNAL_API_URL = 'https://api.onesignal.com/notifications';
export const MAX_EXTERNAL_IDS_PER_REQUEST = 2000;

export function chunk(list, size) {
  const out = [];
  for (let i = 0; i < list.length; i += size) out.push(list.slice(i, i + size));
  return out;
}

// Deterministic UUID from a string, formatted as v4 (version nibble 4, RFC 4122
// variant) because OneSignal validates idempotency_key as a UUID v4. Hash-based,
// so a retried outbox event / escalation gets the same key and never double-sends.
export function idempotencyUuid(name) {
  const h = createHash('sha256').update(name).digest();
  h[6] = (h[6] & 0x0f) | 0x40;
  h[8] = (h[8] & 0x3f) | 0x80;
  const hex = h.subarray(0, 16).toString('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

/**
 * Notification shape used across the service:
 *   { title, body, data }
 * Targets:
 *   sendToUsers(userIds, n, { key })          include_aliases.external_id = Supabase user uuid
 *   sendToTag(tagKey, tagValue, n, { key, andTags })  filters on an (already sanitised) tag,
 *                                              plus optional further tags that must all match
 *   sendToTags({ lga, state }, n, { key })     AND of several tag filters (all must match)
 *   sendToAll(n, { key })                      included_segments ['Total Subscriptions']
 * `key` is an optional string turned into an idempotency_key per request.
 */
export function createOneSignal({
  appId,
  apiKey,
  androidChannelId,
  fetchImpl = globalThis.fetch,
  logger = defaultLog,
} = {}) {
  const configured = Boolean(appId && apiKey);

  async function post(target, notification, key) {
    const body = {
      app_id: appId,
      target_channel: 'push',
      headings: { en: notification.title },
      contents: { en: notification.body },
      data: notification.data ?? {},
      priority: 10,
      ...target,
    };
    if (androidChannelId) body.android_channel_id = androidChannelId;
    if (key) body.idempotency_key = idempotencyUuid(key);

    const res = await fetchImpl(ONESIGNAL_API_URL, {
      method: 'POST',
      headers: {
        Authorization: `Key ${apiKey}`,
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(HTTP_TIMEOUT_MS),
    });
    let json = {};
    try {
      json = await res.json();
    } catch {
      /* non-JSON body */
    }
    if (!res.ok) {
      const detail = Array.isArray(json?.errors) ? json.errors.join('; ') : JSON.stringify(json?.errors ?? json);
      throw new Error(`OneSignal HTTP ${res.status}: ${detail}`.slice(0, 500));
    }
    // 200 with errors (e.g. "All included players are not subscribed") is not a failure.
    if (json?.errors) logger.warn('onesignal.partial', { errors: json.errors });
    return { id: json?.id || null };
  }

  function skip(what) {
    logger.warn('onesignal.not_configured', { skipped: what });
    return { sent: 0, skipped: true };
  }

  // OneSignal ANDs consecutive filter entries (OR needs an explicit
  // { operator: 'OR' } between them), so one entry per tag requires every
  // tag to match. An empty value would match nothing useful: refuse to send.
  async function sendToTags(tags, notification, { key } = {}) {
    const entries = Object.entries(tags ?? {});
    if (entries.length === 0 || entries.some(([k, v]) => !k || !v)) return { sent: 0, skipped: false };
    if (!configured) return skip(`tags:${entries.map(([k, v]) => `${k}=${v}`).join('&')}`);
    await post(
      { filters: entries.map(([k, v]) => ({ field: 'tag', key: k, relation: '=', value: v })) },
      notification,
      key,
    );
    return { sent: 1, skipped: false };
  }

  return {
    configured,

    async sendToUsers(userIds, notification, { key } = {}) {
      const ids = [...new Set((userIds ?? []).filter(Boolean))];
      if (ids.length === 0) return { sent: 0, skipped: false };
      if (!configured) return skip(`users:${ids.length}`);
      const chunks = chunk(ids, MAX_EXTERNAL_IDS_PER_REQUEST);
      for (let i = 0; i < chunks.length; i++) {
        await post(
          { include_aliases: { external_id: chunks[i] } },
          notification,
          key ? `${key}:${i}` : undefined,
        );
      }
      return { sent: chunks.length, skipped: false };
    },

    // `andTags` ({ state: 'benue' }) adds further tags that must also match.
    async sendToTag(tagKey, tagValue, notification, { key, andTags } = {}) {
      if (!tagValue) return { sent: 0, skipped: false };
      return sendToTags({ [tagKey]: tagValue, ...andTags }, notification, { key });
    },

    sendToTags,

    async sendToAll(notification, { key } = {}) {
      if (!configured) return skip('all');
      await post({ included_segments: ['Total Subscriptions'] }, notification, key);
      return { sent: 1, skipped: false };
    },
  };
}

