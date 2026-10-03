/**
 * The outbox, rebuilt on Appwrite.
 *
 * Phase 6 settled this by experiment, and the answer was not the
 * convenient one. An event Function registered on document-create that
 * throws every time, watched for three minutes, ran **once**. No retry,
 * ever; the event is gone. At-least-once delivery is the only reason the
 * outbox existed, so the outbox is not deleted — it is rebuilt as a
 * collection that a scheduled Function drains.
 *
 * ## What is lost, and it is not nothing
 *
 * In Postgres the outbox row is written by a trigger **inside the same
 * transaction as the report**: either both exist or neither does. Here the
 * event Function runs after the write commits and can fail — cold start,
 * crash, bad deploy — leaving a report with no outbox row, no
 * notification, and nothing that will ever notice. `reconcile.js` is the
 * sweep that makes that detectable. It is not free and it is not exact.
 *
 * ## The claim
 *
 * `claim_outbox_events` was one statement with `FOR UPDATE SKIP LOCKED`.
 * Appwrite has no equivalent, so two overlapping drains can claim the same
 * document. Phase 6's finding is that for push and email **it does not
 * matter**: Appwrite refuses a duplicate `messageId` with 409, so the
 * outbox id becomes the message id and the second send is refused by the
 * server. Idempotency replaces locking.
 *
 * SMS is different — Termii has no such protection and a duplicate flood
 * warning to an authority is not a harmless retry — so `sms_deliveries`
 * carries the claim instead. See `termii.js`.
 */
import {
  Query,
  createRow,
  fnv1a64,
  listRowsOrThrow,
  updateRow,
} from './appwrite.js';

export const COLLECTION = 'notification_outbox';
export const BATCH_SIZE = 50;
export const MAX_ATTEMPTS = 8;

/** Thrown for events that can never succeed. Marked processed with the note. */
export class PermanentEventError extends Error {}

/**
 * Exponential backoff, capped at an hour — the same curve the SQL had:
 * `least(60, power(2, attempts))` minutes.
 */
export const backoffMs = (attempts) =>
  Math.min(60, 2 ** attempts) * 60_000;

/**
 * Writes one outbox document.
 *
 * Called by the event Function, which does nothing else: an at-most-once
 * trigger should carry as little work as possible, because everything it
 * does is work that can silently not happen.
 *
 * The id is deterministic so the same event enqueued twice — by a retry,
 * or by `reconcile.js` finding what it thinks is a gap — collides with a
 * 409 instead of notifying twice.
 */
export async function enqueue({ eventType, key, payload }) {
  const id = eventId(eventType, key);
  const created = await createRow(COLLECTION, id, {
    eventType,
    payload: JSON.stringify(payload ?? {}),
    attempts: 0,
    availableAt: new Date().toISOString(),
    processedAt: null,
    note: null,
  });
  if (created.status === 409) return { id, duplicate: true };
  if (!created.ok) {
    throw new Error(`outbox enqueue failed: ${created.status}`);
  }
  return { id, duplicate: false };
}

/**
 * `<eventType>-<key>`, within Appwrite's 36 characters.
 *
 * The obvious trim — keep the last 36 — is wrong here for the same reason
 * it was wrong for file ids: a uuid key is already 36, so every event
 * type on the same report would trim to the bare uuid and collide.
 * `report_created` and `report_disputed` on one report are two different
 * notifications, and the second would be silently dropped as a duplicate
 * of the first.
 *
 * So: the type, which is short and worth reading in the console, plus a
 * digest of the whole thing.
 */
export function eventId(eventType, key) {
  const slug = `${eventType}-${key}`.replace(/[^A-Za-z0-9._-]/g, '-');
  if (slug.length <= 36) return slug;
  const head = eventType.replace(/[^A-Za-z0-9]/g, '-').slice(0, 19).replace(/-+$/, '');
  return `${head}-${fnv1a64(slug)}`;
}

/**
 * Claims up to [limit] due events: bumps `attempts` and pushes
 * `availableAt` forward, so a run that dies mid-batch leaves work that
 * comes back rather than work that is stuck.
 *
 * Not atomic. Two overlapping drains can both claim; see the note above
 * for why that is survivable and where it is not.
 */
export async function claim(limit = BATCH_SIZE, now = Date.now) {
  const due = await listRowsOrThrow(COLLECTION, [
    Query.isNull('processedAt'),
    Query.lessThanEqual('availableAt', new Date(now()).toISOString()),
    Query.lessThan('attempts', MAX_ATTEMPTS),
    Query.orderAsc('availableAt'),
    Query.limit(limit),
  ]);

  const claimed = [];
  for (const event of due) {
    const attempts = (event.attempts ?? 0) + 1;
    const updated = await updateRow(COLLECTION, event.$id, {
      attempts,
      availableAt: new Date(now() + backoffMs(attempts)).toISOString(),
    });
    // A document that vanished between the list and the claim is somebody
    // else's business now, not a failure.
    if (updated.ok) claimed.push({ ...event, attempts });
  }
  return claimed;
}

export const markProcessed = (id, note) =>
  updateRow(COLLECTION, id, {
    processedAt: new Date().toISOString(),
    note: note ? String(note).slice(0, 500) : null,
  });

/**
 * Records a failure. The claim already pushed `availableAt` forward, so
 * this only writes the reason — and gives up at [MAX_ATTEMPTS], which the
 * claim query enforces by refusing to pick the document up again.
 */
export const markFailed = (id, error) =>
  updateRow(COLLECTION, id, { note: String(error).slice(0, 500) });

/** Parses the stored payload, which is JSON text rather than a sub-document. */
export function payloadOf(event) {
  if (!event.payload) return {};
  try {
    return JSON.parse(event.payload);
  } catch {
    throw new PermanentEventError('payload is not JSON');
  }
}
