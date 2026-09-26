// Supabase-side pieces of the import steps, kept out of migrate.js (which
// parses the CLI at load time) so they can be unit-tested with a fake client.

import { IN_CHUNK } from './db.js';

// Verifications upsert on their natural key and UPDATE on conflict, so a
// re-run applies changed votes/comments. Only AFTER triggers exist on
// verifications: the UPDATE path fires verifications_after_update (recount;
// may move a pending report to 'verified'), which the report finalize step
// and side-effect suppression undo as for inserts.
export const VERIFICATIONS_UPSERT = { onConflict: 'report_id,verifier_id' };

/**
 * Wrap a ctx.report resolver so it only returns ids of reports that exist in
 * Supabase (`existingIds`). A report whose write failed has an id in the
 * state file but no row; referencing it would fail the whole row's FK.
 * With `existingIds` null (dry run) the resolver is returned unchanged.
 */
export function existingReportResolver(resolve, existingIds) {
  if (!existingIds) return resolve;
  return (id) => {
    const uuid = resolve(id);
    return uuid && existingIds.has(uuid) ? uuid : null;
  };
}

/**
 * Set is_active = true on the imported alerts that were active in Firestore
 * (`entries`: [{ sourceId, row }]). A failing chunk is retried per alert; an
 * alert that still fails is reported through `warn(sourceId, reason)` and left
 * inactive instead of aborting the run. Returns the number re-activated.
 */
export async function reactivateAlerts(sb, entries, warn) {
  const active = entries.filter((e) => e.row.is_active);
  let done = 0;
  const update = async (ids) => {
    try {
      const { error } = await sb.from('alerts').update({ is_active: true }).in('id', ids);
      return error ? error.message ?? String(error) : null;
    } catch (e) {
      return e.message;
    }
  };
  for (let i = 0; i < active.length; i += IN_CHUNK) {
    const chunk = active.slice(i, i + IN_CHUNK);
    if (!(await update(chunk.map((e) => e.row.id)))) { done += chunk.length; continue; }
    for (const e of chunk) {
      const error = await update([e.row.id]);
      if (error) warn(e.sourceId, `re-activation failed: ${error}; alert left inactive`);
      else done += 1;
    }
  }
  return done;
}
