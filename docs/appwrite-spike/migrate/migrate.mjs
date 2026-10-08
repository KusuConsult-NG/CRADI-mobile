/**
 * The ACLs and identities the migration stamps, and nothing else.
 *
 * This used to copy `profiles`, `reports` and `verifications` as well, in
 * snake_case through the deprecated `/databases/…/collections/…/documents` API
 * against the ad-hoc schema `prep.mjs` creates — a schema the project this
 * repository provisions does not have, so those writes could not land in it.
 * `copy-tables.mjs` does the copying now, for all nine collections, through
 * `/tablesdb/…/tables/…/rows`.
 *
 * What stayed is the part that was always the hard bit, and the reason any of
 * this is difficult: every document must carry the ACL that reproduces the RLS
 * policy it used to be protected by, and nothing in the source rows says what
 * that ACL is — it was computed at query time from the caller's profile. Phase
 * 1 decided it is computed at WRITE time instead, and these functions are where
 * that decision is paid for.
 *
 * Imported by `copy-tables.mjs` for the ACLs, by `seed-identities.mjs` for
 * `wardTeam`, and by the tests. Pure: no connection, no credentials.
 */

/*
 * Resolved inside `run()`, not at import.
 *
 * `seed-identities.mjs` and `reconcile.test.mjs` import this module for
 * `wardTeam` and the `*Permissions` builders, which are pure and need no
 * credentials. Resolving at module scope made those imports demand AW_PROJECT
 * and AW_KEY, print a target line, and exit(2) without them.
 *
 * Validation itself was the fix this already needed: it read the environment
 * but did not check it, so an unset AW_KEY sent the header `undefined` and
 * every write came back 401, one row at a time.
 */

/**
 * The ward team id.
 *
 * Imported from the write Function rather than copied, because the two
 * must agree exactly: the ACLs name a team, so one character of drift
 * means every migrated document points at a team nobody is in and the
 * whole ward sees nothing — with no error anywhere.
 *
 * It used to be a copy, and the copy was a plain slug. That was wrong for
 * 35 of the 584 wards, whose ids run up to 50 characters and exceed
 * Appwrite's 36-character limit. `functions/cradi/test/policy.test.mjs`
 * now checks all 584.
 */
// Imported AND re-exported, deliberately in two statements:
// `export { wardTeam } from '...'` re-exports without creating a local
// binding, so `seed-identities.mjs` could import it from here while every call
// inside this file threw `ReferenceError: wardTeam is not defined` — on the
// first profile, before a single document was written.
import { wardTeam } from '../../../functions/cradi/src/lib/appwrite.js';

export { wardTeam };

/**
 * Role name -> Appwrite label.
 *
 * Appwrite labels are alphanumeric only. `ldp_coordinator` and
 * `project_staff` are rejected outright (verified: 400, while
 * `ldpCoordinator` and `projectStaff` are accepted), so every role that
 * carries an underscore in `profiles.role` needs a second spelling.
 *
 * This mapping MUST be the only one. The migrator stamps ACLs with it, the
 * identity sync sets labels with it, and the write Functions stamp new
 * documents with it. If any two disagree the ACL names a label nobody holds,
 * Appwrite accepts it without complaint, and that role silently sees
 * nothing — which looks like empty data, not like a permissions bug.
 */
export const roleLabel = (role) => String(role ?? '').replace(/_(.)/g, (_, c) => c.toUpperCase());

/** Roles that `reports_select` lets see everything. */
const STAFF_ROLES = ['ewv', 'ewr', 'ldp_coordinator', 'project_staff', 'admin', 'techSupport'];
const STAFF_LABELS = STAFF_ROLES.map(roleLabel);

/**
 * The ACL for a report, reproducing reports_select:
 *   user_id = auth.uid()                         -> read("user:<owner>")
 *   ewm and ward = my_ward() and lga = my_lga()  -> read("team:<ward>")
 *   app_role() in (...)                          -> read("label:<role>")
 */
export function reportPermissions(row) {
  return [
    `read("user:${row.user_id}")`,
    `read("team:${wardTeam(row.state, row.lga, row.ward)}")`,
    ...STAFF_LABELS.map((r) => `read("label:${r}")`),
  ];
}

/**
 * Verifications inherit their report's reach. In Postgres that was transitive
 * through an EXISTS subquery filtered by RLS; here it has to be written down,
 * which is why ward and lga are denormalised onto the row (Phase 1).
 */
export function verificationPermissions(row, report) {
  return [
    `read("user:${row.verifier_id}")`,
    `read("team:${wardTeam(report.state, report.lga, report.ward)}")`,
    ...STAFF_LABELS.map((r) => `read("label:${r}")`),
  ];
}

export function profilePermissions(row) {
  return [
    `read("user:${row.id}")`,
    `read("team:${wardTeam(row.state, row.lga, row.ward)}")`,
    ...['admin', 'ldp_coordinator', 'project_staff', 'ewv', 'ewr']
      .map(roleLabel)
      .map((r) => `read("label:${r}")`),
  ];
}


/**
 * The Appwrite user id for a Postgres profile id.
 *
 * Identity, deliberately. It exists as a named function so that every place
 * an ACL is built goes through the same one — the alternative is what the
 * first draft did: strip dashes when creating users, keep them when stamping
 * permissions, and produce a database in which every row migrated perfectly
 * and nobody could read anything.
 */
export const appwriteUserId = (profileId) => profileId;
