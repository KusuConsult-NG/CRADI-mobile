/**
 * Supabase -> Appwrite, for the three collections that carry the hard parts.
 *
 * Export is plain SQL. Import is the Appwrite REST API. The interesting work
 * is in between: every document must be written with the ACL that reproduces
 * the RLS policy it used to be protected by, and nothing in the source rows
 * says what that ACL is — it was computed at query time from the caller's
 * profile. Phase 1 decided it is computed at WRITE time instead, so this is
 * where that decision is actually paid for.
 *
 *   PG_URL      postgres connection string
 *   AW_ENDPOINT / AW_PROJECT / AW_KEY
 *
 * Idempotent: every document keeps its Postgres uuid as its Appwrite id, so
 * a re-run collides with 409 rather than duplicating. That is the same
 * property Phase 6 leans on for the SMS claim.
 */
import pg from 'pg';

const PG = process.env.PG_URL ?? 'postgres://postgres:postgres@localhost:5432/cradi_mig';
const EP = process.env.AW_ENDPOINT ?? 'http://localhost:8080/v1';
const PROJECT = process.env.AW_PROJECT;
const KEY = process.env.AW_KEY;
const DB = 'cradi';

const H = { 'content-type': 'application/json', 'x-appwrite-project': PROJECT, 'x-appwrite-key': KEY };
const aw = async (path, init = {}) => {
  const r = await fetch(`${EP}${path}`, { ...init, headers: H });
  return { status: r.status, body: await r.json().catch(() => null) };
};

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
export { wardTeam } from '../../../functions/cradi/src/lib/appwrite.js';

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

async function upsert(collection, id, data, permissions) {
  const r = await aw(`/databases/${DB}/collections/${collection}/documents`, {
    method: 'POST', body: JSON.stringify({ documentId: id, data, permissions }),
  });
  if (r.status === 201) return 'created';
  if (r.status === 409) return 'exists';
  throw new Error(`${collection}/${id}: ${r.status} ${JSON.stringify(r.body?.message ?? r.body).slice(0, 160)}`);
}

export async function run({ log = console.log } = {}) {
  const client = new pg.Client({ connectionString: PG });
  await client.connect();
  const counts = {};
  const teams = new Set();

  // ---- profiles -----------------------------------------------------------
  const profiles = (await client.query(
    `select id, name, role, state, lga, ward, is_approved, is_disabled from profiles order by id`,
  )).rows;
  counts.profiles = { source: profiles.length, created: 0, exists: 0 };
  for (const p of profiles) {
    if (p.ward) teams.add(wardTeam(p.state, p.lga, p.ward));
    const r = await upsert('profiles', p.id, {
      name: p.name ?? '', role: p.role ?? 'user',
      state: p.state ?? '', lga: p.lga ?? '', ward: p.ward ?? '',
      is_disabled: Boolean(p.is_disabled),
    }, profilePermissions(p));
    counts.profiles[r] += 1;
  }

  // ---- reports ------------------------------------------------------------
  const reports = (await client.query(
    `select id, user_id, hazard_type, description, state, lga, ward, status,
            verification_count, escalated
       from reports order by id`,
  )).rows;
  counts.reports = { source: reports.length, created: 0, exists: 0 };
  const reportById = new Map();
  for (const r of reports) {
    reportById.set(r.id, r);
    teams.add(wardTeam(r.state, r.lga, r.ward));
    const res = await upsert('reports', r.id, {
      user_id: r.user_id, hazard_type: r.hazard_type ?? '',
      title: r.hazard_type ?? '', description: r.description ?? '',
      state: r.state, lga: r.lga, ward: r.ward, status: r.status,
      verification_count: r.verification_count ?? 0, escalated: Boolean(r.escalated),
    }, reportPermissions(r));
    counts.reports[res] += 1;
  }

  // ---- verifications ------------------------------------------------------
  const verifications = (await client.query(
    `select id, report_id, verifier_id, is_confirmed, comment from verifications order by id`,
  )).rows;
  counts.verifications = { source: verifications.length, created: 0, exists: 0, orphaned: 0 };
  for (const v of verifications) {
    const report = reportById.get(v.report_id);
    if (!report) { counts.verifications.orphaned += 1; continue; }
    const res = await upsert('verifications', v.id, {
      report_id: v.report_id, verifier_id: v.verifier_id,
      is_confirmed: Boolean(v.is_confirmed), comment: v.comment ?? '',
      // Denormalised so the ACL has something to be derived from later, and
      // so a reader never needs the join Appwrite cannot do.
      ward: report.ward, lga: report.lga, state: report.state,
    }, verificationPermissions(v, report));
    counts.verifications[res] += 1;
  }

  await client.end();
  return { counts, teams: [...teams] };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const { counts, teams } = await run();
  console.log(JSON.stringify(counts, null, 2));
  console.log('ward teams referenced:', teams.length, teams.join(', '));
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
