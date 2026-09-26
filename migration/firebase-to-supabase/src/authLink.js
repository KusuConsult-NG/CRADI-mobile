// Deciding whether an existing Supabase Auth user may be reused for a Firebase
// user (pure; unit-tested). Reusing an account someone else registered with a
// migrated user's email/phone would hand them that user's profile, reports and
// role, so an existing account is only linked when it is provably safe.

/** app_metadata key set on every Auth user this script creates (not user-editable). */
export const MIGRATION_MARKER = 'migrated_from_firebase';

/** app_metadata written on createUser, identifying the account as ours. */
export function migrationAppMetadata(firebaseUid) {
  return { [MIGRATION_MARKER]: true, firebase_uid: firebaseUid };
}

/**
 * Earliest recorded --apply run (state.data.runs[].startedAt), falling back to
 * `fallback` (this run's start). Accounts created after it may be sign-ups
 * racing the migration.
 */
export function migrationStart(runs, fallback) {
  const times = (runs ?? []).map((r) => Date.parse(r?.startedAt)).filter(Number.isFinite);
  const fb = Date.parse(fallback);
  if (Number.isFinite(fb)) times.push(fb);
  return times.length ? new Date(Math.min(...times)).toISOString() : null;
}

/**
 * Returns null when `existing` may be reused for a Firebase user of `kind`
 * ('email' | 'phone'), otherwise a human-readable reason:
 *   - created by this script (app_metadata marker) → reuse;
 *   - otherwise it must have the matched identifier confirmed (email for email
 *     users, phone for phone users) AND have been created before `startIso`.
 */
export function reuseRefusal(existing, { kind, startIso }) {
  if (!existing) return 'no such user';
  if (existing.app_metadata?.[MIGRATION_MARKER] === true) return null;
  const confirmed = kind === 'phone' ? existing.phone_confirmed_at : existing.email_confirmed_at;
  if (!confirmed) return `existing Supabase user ${existing.id} has an unconfirmed ${kind}`;
  const created = Date.parse(existing.created_at);
  const start = Date.parse(startIso);
  if (!Number.isFinite(created) || !Number.isFinite(start) || created >= start) {
    return `existing Supabase user ${existing.id} was created at ${existing.created_at ?? 'unknown time'}, not before the migration started (${startIso})`;
  }
  return null;
}
