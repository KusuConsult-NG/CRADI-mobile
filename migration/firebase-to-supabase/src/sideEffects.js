// Neutralises notifications caused by the import itself: outbox events queued
// by the reports/alerts triggers for imported rows, and escalations scheduled
// for imported reports. Only rows that reference imported ids are touched, so
// events of real users created during the import are left for the backend.
import { IN_CHUNK, selectAll } from './db.js';

export const SUPPRESS_REASON = 'migration import';
export const BACKEND_STOPPED_FLAG = 'i-stopped-the-backend';

/** Returns an error message if --apply is not allowed, else null. */
export function applyPreflight(args) {
  if (!args.apply || args[BACKEND_STOPPED_FLAG]) return null;
  return `Refusing --apply: stop the backend worker first (Railway: scale the backend service to 0 replicas or
remove its deployment) so imported rows cannot push to real users, then re-run with --apply --${BACKEND_STOPPED_FLAG}.
Scale it back up after the import. See README "Prerequisites".`;
}

/** Outbox rows whose payload references an imported report or alert. */
export function importedEvents(rows, { reportIds, alertIds }) {
  return rows.filter((r) => {
    const p = r.payload ?? {};
    return (p.report_id != null && reportIds.has(String(p.report_id)))
      || (p.alert_id != null && alertIds.has(String(p.alert_id)));
  });
}

/**
 * Marks unprocessed outbox events with id > baseline that reference imported
 * reports/alerts as processed, and skips pending escalations of imported
 * reports. Safe to call repeatedly (after every step). Returns counts.
 */
export async function suppressSideEffects(sb, { baseline, reportIds, alertIds }) {
  const result = { outbox: 0, escalations: 0, errors: [] };
  if (baseline === null || baseline === undefined) return result;
  const at = new Date().toISOString();

  let fresh = [];
  try {
    fresh = await selectAll(sb, 'notification_outbox', 'id,event_type,payload',
      (q) => q.gt('id', baseline).is('processed_at', null));
  } catch (e) {
    result.errors.push(`Could not read notification_outbox rows > ${baseline}: ${e.message}`);
  }
  const eventIds = importedEvents(fresh, { reportIds, alertIds }).map((r) => r.id);
  for (let i = 0; i < eventIds.length; i += IN_CHUNK) {
    const res = await sb.from('notification_outbox')
      .update({ processed_at: at, last_error: SUPPRESS_REASON })
      .in('id', eventIds.slice(i, i + IN_CHUNK)).is('processed_at', null).select('id');
    if (res.error) result.errors.push(`Could not neutralise notification_outbox rows: ${res.error.message}`);
    else result.outbox += res.data.length;
  }

  const ids = [...reportIds];
  for (let i = 0; i < ids.length; i += IN_CHUNK) {
    const res = await sb.from('scheduled_escalations')
      .update({ status: 'skipped', reason: SUPPRESS_REASON, processed_at: at })
      .in('report_id', ids.slice(i, i + IN_CHUNK)).eq('status', 'pending').select('id');
    if (res.error) result.errors.push(`Could not skip scheduled_escalations: ${res.error.message}`);
    else result.escalations += res.data.length;
  }
  return result;
}
