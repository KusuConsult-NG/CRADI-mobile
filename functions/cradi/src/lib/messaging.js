/**
 * Push and email, over Appwrite Messaging.
 *
 * Replaces OneSignal (push) and Resend (email). The property this design
 * leans on is the one Phase 3 verified: **Appwrite refuses a duplicate
 * `messageId` with 409**, which is what lets the outbox drain run without
 * an atomic claim. The idempotency key the OneSignal client carried
 * becomes the message id itself, so a second send of the same event is
 * refused by the server rather than deduplicated by a vendor.
 */
import { api } from './appwrite.js';

/** Appwrite ids are 36 characters; a key that is longer is digested. */
import { fnv1a64 } from './appwrite.js';

export function messageId(key) {
  const slug = String(key).replace(/[^A-Za-z0-9._-]/g, '-');
  if (slug.length <= 36 && !/^[._-]/.test(slug)) return slug;
  const head = slug.replace(/^[._-]+/, '').slice(0, 19).replace(/-+$/, '');
  return `${head}-${fnv1a64(slug)}`;
}

/**
 * Sends one push. Returns `'sent'`, `'duplicate'`, or throws.
 *
 * A 409 is success, not failure: it means this exact notification has
 * already been accepted, which is the whole point of deriving the id from
 * the outbox event.
 */
export async function sendPush({ key, users, topics, notification }) {
  if ((users?.length ?? 0) === 0 && (topics?.length ?? 0) === 0) return 'no recipients';
  const sent = await api('/messaging/messages/push', {
    method: 'POST',
    body: {
      messageId: messageId(key),
      title: notification.title,
      body: notification.body,
      ...(notification.data ? { data: notification.data } : {}),
      ...(users?.length ? { users } : {}),
      ...(topics?.length ? { topics } : {}),
      draft: false,
    },
  });
  if (sent.status === 409) return 'duplicate';
  if (!sent.ok) {
    throw new Error(`push failed: ${sent.status} ${sent.body?.message ?? ''}`);
  }
  return 'sent';
}

export async function sendEmail({ key, users, topics, subject, content }) {
  if ((users?.length ?? 0) === 0 && (topics?.length ?? 0) === 0) return 'no recipients';
  const sent = await api('/messaging/messages/email', {
    method: 'POST',
    body: {
      messageId: messageId(key),
      subject,
      content,
      ...(users?.length ? { users } : {}),
      ...(topics?.length ? { topics } : {}),
      draft: false,
    },
  });
  if (sent.status === 409) return 'duplicate';
  if (!sent.ok) {
    throw new Error(`email failed: ${sent.status} ${sent.body?.message ?? ''}`);
  }
  return 'sent';
}
