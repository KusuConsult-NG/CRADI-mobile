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

/** Minutes a report may stay pending before it escalates. */
export const escalationTimeoutMinutes = (settings) =>
  positiveInt(settings.escalationTimeoutMinutes, 60);

export function positiveInt(value, fallback) {
  const n = Number.parseInt(value ?? '', 10);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}
