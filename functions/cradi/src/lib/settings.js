/**
 * `app_settings`, read once per Function run.
 *
 * The Railway worker cached these with a TTL because it was long-lived.
 * A Function is not: each run is a fresh process, so "once per run" is
 * the whole cache, and the read is one query.
 */
import { Query, listRowsOrThrow } from './appwrite.js';

export async function getSettings() {
  try {
    const rows = await listRowsOrThrow('app_settings', [Query.limit(100)]);
    const out = {};
    for (const row of rows) {
      if (row.key) out[row.key] = row.value;
    }
    return out;
  } catch {
    // Defaults are better than a dead run: every caller treats a missing
    // setting as its documented default, and refusing to escalate because
    // a settings read failed would be the worse failure.
    return {};
  }
}

/**
 * Minutes a report may stay pending before it escalates.
 *
 * The key is `escalation_timeout_minutes`, as stored — these are row
 * *values* in the `key` column, not column names, so the camel/snake
 * translation the rest of the migration did does not apply to them. Read
 * as `settings.escalationTimeoutMinutes` this silently found nothing and
 * fell back on every run, which made the admin panel's setting do
 * nothing. The fallback was wrong too: Postgres defaulted to 30.
 */
export const escalationTimeoutMinutes = (settings) =>
  positiveInt(settings.escalation_timeout_minutes, 30);

export function positiveInt(value, fallback) {
  const n = Number.parseInt(value ?? '', 10);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}
