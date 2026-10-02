/**
 * The sweep for events that never happened.
 *
 * Phase 6 named this as the one loss with no clean mitigation, and this
 * is the unclean one.
 *
 * In Postgres the outbox row is written by a trigger **inside the same
 * transaction as the report**: either both exist or neither does. In
 * Appwrite the event Function runs after the write commits and can fail —
 * cold start timeout, runtime crash, a bad deploy — leaving a report in
 * the database with no outbox document, no notification, and nothing that
 * will ever notice. That is the one failure this system exists to
 * prevent, so "nothing will ever notice" is not an acceptable resting
 * place even if the mitigation is imperfect.
 *
 *   schedule: *(slash)5 * * * *      (every five minutes)
 *   scopes:   documents.read, documents.write
 *
 * ## Why it is not exact
 *
 * It compares reports created in a recent window against the outbox
 * documents that should exist for them. Three honest limitations:
 *
 * 1. **It only catches creates.** A missed `report_status_changed` is
 *    invisible here, because the report carries no record of which
 *    transitions were announced. Catching those would mean an
 *    announcement log, which is a second outbox.
 * 2. **The window is a guess.** Too short and a Function that was down
 *    for an hour is missed; too long and every run re-reads work it has
 *    already checked. Twenty minutes against a five-minute schedule
 *    gives four overlapping passes before a gap is lost.
 * 3. **It cannot double-notify**, which is the one part that *is*
 *    exact: outbox ids are deterministic, so re-enqueueing something
 *    that was handled collides with a 409. That is why the sweep is safe
 *    to run as often as you like.
 */
import { Query, listRowsOrThrow } from './lib/appwrite.js';
import { handler } from './lib/http.js';
import { COLLECTION as OUTBOX, enqueue, eventId } from './lib/outbox.js';

/** How far back to look. Four passes at a five-minute schedule. */
export const WINDOW_MINUTES = 20;
export const BATCH = 200;

export default handler(async ({ log, error }) => {
  const since = new Date(Date.now() - WINDOW_MINUTES * 60_000).toISOString();

  const summary = { checked: 0, missing: 0, enqueued: 0 };
  for (const spec of SWEEPS) {
    const rows = await listRowsOrThrow(spec.collection, [
      Query.greaterThanEqual('$createdAt', since),
      Query.orderAsc('$createdAt'),
      Query.limit(BATCH),
    ]);
    summary.checked += rows.length;

    for (const row of rows) {
      const want = spec.event(row);
      if (!want) continue;
      const id = eventId(want.eventType, want.key);
      if (await outboxHas(id)) continue;

      summary.missing += 1;
      try {
        const { duplicate } = await enqueue(want);
        if (!duplicate) summary.enqueued += 1;
        // A gap is not routine. Logged at error level because a run that
        // finds one means an event Function failed silently, and that is
        // worth somebody looking at even though this repaired it.
        error(
          `reconcile: ${spec.collection}/${row.$id} had no ${want.eventType} ` +
            `outbox document; enqueued ${id}`,
        );
      } catch (e) {
        error(`reconcile: could not enqueue ${id}: ${e?.message ?? e}`);
      }
    }
  }

  // Logged every run, including the quiet ones: "0 missing" is the
  // evidence that the sweep ran at all, and a sweep that silently stops
  // running looks exactly like a system with no gaps.
  log(`reconcile ${JSON.stringify(summary)} window=${WINDOW_MINUTES}m`);
  return summary;
});

/** What each collection owes the outbox at creation time. */
export const SWEEPS = [
  {
    collection: 'reports',
    event: (row) => ({
      eventType: 'report_created',
      key: row.$id,
      payload: { reportId: row.$id },
    }),
  },
  {
    collection: 'alerts',
    event: (row) => ({
      eventType: 'alert_created',
      key: row.$id,
      payload: { alertId: row.$id },
    }),
  },
  {
    collection: 'verifications',
    // Only a dispute owes an event, which is the same rule `on-write.js`
    // applies — stated once here and once there, because the sweep must
    // not invent work the trigger would never have created.
    event: (row) =>
      row.isConfirmed === false
        ? {
            eventType: 'report_disputed',
            key: row.reportId ?? row.$id,
            payload: { reportId: row.reportId, verificationId: row.$id },
          }
        : null,
  },
];

async function outboxHas(id) {
  const { getRow } = await import('./lib/appwrite.js');
  const found = await getRow(OUTBOX, id);
  if (found.status === 404) return false;
  if (!found.ok) {
    // A failed read must not read as "missing": that would re-enqueue on
    // every transient error. The 409 on a duplicate id would catch it
    // anyway, but the error log would be noise and the signal above —
    // "an event Function failed silently" — would stop meaning anything.
    throw new Error(`outbox read failed: ${found.status}`);
  }
  return true;
}
