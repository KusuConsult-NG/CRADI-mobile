/**
 * The event Function: writes one outbox document, and nothing else.
 *
 * Registered on the document events that used to fire AFTER triggers:
 *
 *   tablesdb.cradi.tables.reports.rows.*.create
 *   tablesdb.cradi.tables.reports.rows.*.update
 *   tablesdb.cradi.tables.verifications.rows.*.create
 *   tablesdb.cradi.tables.alerts.rows.*.create
 *   tablesdb.cradi.tables.profiles.rows.*.update
 *
 * It is deliberately the smallest thing that can work, because Phase 6
 * measured what happens when it fails: an event Function that throws is
 * executed **once**, never retried, and the event is gone. Everything
 * this does is work that can silently not happen, so it does one write
 * and leaves the rest to `drain.js`, which is scheduled and therefore
 * retried.
 *
 * It cannot tell a status *change* from a write that left the status
 * alone — Appwrite's event payload is the document, with no "before".
 * That is what `previousStatus` on the report is for: the write Function
 * records it, and this compares.
 */
import { enqueue } from './lib/outbox.js';

export default async ({ req, res, log, error }) => {
  const event = req.headers['x-appwrite-event'] ?? '';
  let doc = {};
  try {
    doc = JSON.parse(req.bodyRaw || '{}');
  } catch {
    error(`event ${event}: body is not JSON`);
    return res.json({ enqueued: null }, 200);
  }

  const enqueued = [];
  try {
    for (const spec of eventsFor(event, doc)) {
      const { id, duplicate } = await enqueue(spec);
      enqueued.push({ id, duplicate });
    }
  } catch (e) {
    // There is no retry, so there is nothing to gain by failing loudly
    // except the log line — and the log line is the only thing that will
    // ever say this happened. `reconcile.js` is what actually catches it.
    error(`event ${event}: enqueue failed: ${e?.stack ?? e}`);
    return res.json({ enqueued, failed: true }, 500);
  }

  log(`event ${event} -> ${enqueued.length} outbox document(s)`);
  return res.json({ enqueued }, 200);
};

/** Which outbox events a document event produces. Pure, and tested. */
export function eventsFor(event, doc) {
  const id = doc.$id;
  if (!id) return [];

  if (event.includes('.reports.rows.') && event.endsWith('.create')) {
    return [{ eventType: 'report_created', key: id, payload: { reportId: id } }];
  }

  if (event.includes('.reports.rows.') && event.endsWith('.update')) {
    // Appwrite hands over the document, not the change. The write
    // Function stamps `previousStatus` whenever it writes `status`, so
    // its *absence* means this edit did not touch the status — a
    // description fix, a photo added. Treating absence as "changed from
    // nothing" would re-announce the report on every edit.
    const from = doc.previousStatus;
    const to = doc.status ?? null;
    if (from === undefined || from === null || !to || from === to) return [];
    return [
      {
        eventType: 'report_status_changed',
        // Keyed by the transition, not the report: a report that goes
        // pending -> approved -> rejected owes two notifications, and
        // keying by report alone would collapse them into one.
        key: `${id}-${from ?? 'none'}-${to}`,
        payload: { reportId: id, oldStatus: from, newStatus: to },
      },
    ];
  }

  if (event.includes('.verifications.rows.') && event.endsWith('.create')) {
    // Only a dispute escalates early; a confirmation is counted by the
    // write Function and needs no notification of its own.
    if (doc.isConfirmed !== false) return [];
    return [
      {
        eventType: 'report_disputed',
        key: doc.reportId ?? id,
        payload: { reportId: doc.reportId, verificationId: id },
      },
    ];
  }

  if (event.includes('.alerts.rows.') && event.endsWith('.create')) {
    return [{ eventType: 'alert_created', key: id, payload: { alertId: id } }];
  }

  if (event.includes('.profiles.rows.') && event.endsWith('.update')) {
    return [
      {
        eventType: 'user_access_changed',
        // Keyed by the value, so enabling and disabling the same account
        // are two events and the second is not dropped as a duplicate of
        // the first.
        key: `${id}-${doc.isDisabled === true ? 'off' : 'on'}`,
        payload: { userId: id },
      },
    ];
  }

  return [];
};
