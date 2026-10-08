/**
 * Removes the accounts and rows `infra/appwrite/local/prep-dart.mjs` left behind.
 *
 * That script is for a local stack: it creates verified accounts whose password
 * is a literal in this repository, gives them `label:ewr` and `label:approved`,
 * writes a `profiles` row with `role: 'ewr', isApproved: true`, and files a
 * report — and it cleans up nothing. Nothing stopped it following whatever
 * `APPWRITE_ENDPOINT` was exported, so it ran against the production Cloud
 * project eleven times. Those accounts are a published staff credential, which
 * is why this is a purge rather than tidying.
 *
 * It is deliberately NOT part of `reseed-passwords.mjs`. That script deletes
 * only accounts whose id is a Postgres profile id, and refuses to touch
 * anything else precisely so it can never delete a real sign-up. These ids are
 * not profile ids, so removing them is a separate, deliberate act with its own
 * confirmation.
 *
 *   PG_URL              the Postgres whose profiles decide what is NOT ours
 *   AW_ENDPOINT / AW_PROJECT / AW_KEY   the project to clean
 *   APPWRITE_DATABASE_ID  the database holding the rows. Defaults to `cradi`.
 *
 * Audit, which writes nothing:
 *
 *   node purge-dart-accounts.mjs
 *
 * Then, with the count the audit reports:
 *
 *   CONFIRM_DELETE_DART=22 node purge-dart-accounts.mjs --delete
 *
 * Exits 0 audit clean or purge complete, 1 a finding to decide on, 2 not
 * configured, not reachable, or the interlock disagreed.
 */
import pg from 'pg';
import { appwriteTarget } from './target.mjs';

const { endpoint: EP, project, aw } = appwriteTarget();
const PG = process.env.PG_URL ?? 'postgres://postgres:postgres@localhost:5432/cradi_mig';
const DB = process.env.APPWRITE_DATABASE_ID ?? 'cradi';
const DELETE = process.argv.includes('--delete');

/*
 * Exactly the three id shapes `prep-dart.mjs` builds, and nothing wider.
 *
 * It writes `dart-${Date.now()}`, `dart-reporter-${Date.now()}` and
 * `dart-foreign-${Date.now()}`, each `.slice(0, 36)` — which never truncates at
 * thirteen-digit millisecond stamps. The digits are required: a pattern of
 * `^dart-` alone would match an account somebody named by hand, and this script
 * deletes what it matches.
 */
const ACCOUNT = /^dart-(?:reporter-)?\d+$/;
const REPORT = /^dart-foreign-\d+$/;

const rowsPath = (table) => `/tablesdb/${DB}/tables/${table}/rows`;

/** Every account in the project, paged. */
async function allAccounts() {
  const out = [];
  let cursor = null;
  for (;;) {
    const queries = [JSON.stringify({ method: 'limit', values: [100] })];
    if (cursor) queries.push(JSON.stringify({ method: 'cursorAfter', values: [cursor] }));
    const qs = queries.map((q) => `queries[]=${encodeURIComponent(q)}`).join('&');
    const r = await aw(`/users?${qs}`);
    if (r.status !== 200) {
      throw new Error(`list users: ${r.status} ${String(r.body?.message ?? '').slice(0, 140)}`);
    }
    const page = r.body?.users ?? [];
    out.push(
      ...page.map((u) => ({
        id: u.$id,
        email: u.email ?? '',
        // The severity question: an account holding `ewr` can read
        // `verification_overrides`, vote, and reopen a report.
        labels: Array.isArray(u.labels) ? u.labels : [],
      })),
    );
    if (page.length < 100) break;
    cursor = page[page.length - 1].$id;
  }
  return out;
}

/** Every row id in [table], paged. Returns null when the table is not there. */
async function allRowIds(table) {
  const out = [];
  let cursor = null;
  for (;;) {
    const queries = [JSON.stringify({ method: 'limit', values: [100] })];
    if (cursor) queries.push(JSON.stringify({ method: 'cursorAfter', values: [cursor] }));
    const qs = queries.map((q) => `queries[]=${encodeURIComponent(q)}`).join('&');
    const r = await aw(`${rowsPath(table)}?${qs}`);
    if (r.status === 404) return null;
    if (r.status !== 200) {
      throw new Error(`list ${table}: ${r.status} ${String(r.body?.message ?? '').slice(0, 140)}`);
    }
    const page = r.body?.rows ?? [];
    out.push(...page.map((d) => d.$id));
    if (page.length < 100) break;
    cursor = page[page.length - 1].$id;
  }
  return out;
}

/*
 * The real ids, and a refusal rather than a stack trace when they are missing.
 *
 * Everything below decides what is a leftover by what is NOT in this set, so a
 * `PG_URL` aimed at the wrong database is the dangerous mistake here — it would
 * make every account look unreal. An empty set and a missing table mean the
 * same thing for that purpose: this script cannot tell a test account from a
 * person, and must not start deleting on the pattern alone.
 */
const client = new pg.Client({ connectionString: PG });
try {
  await client.connect();
} catch (e) {
  console.error(`cannot reach ${PG.replace(/:[^:@/]*@/, ':***@')}: ${String(e.message).slice(0, 120)}`);
  process.exit(2);
}
let realIds;
try {
  realIds = new Set(
    (await client.query('select id::text as id from profiles')).rows.map((r) => r.id),
  );
} catch (e) {
  console.error(
    `cannot read public.profiles: ${String(e.message).slice(0, 120)}\n` +
      'Without it there is no way to tell a test leftover from a real account,' +
      ' and the id pattern alone is not enough to delete on. Check PG_URL.',
  );
  await client.end().catch(() => {});
  process.exit(2);
} finally {
  await client.end().catch(() => {});
}

if (!realIds.size) {
  console.error(
    'public.profiles is empty, so every Appwrite account would look like a' +
      ' leftover. Check PG_URL. Nothing was read from Appwrite.',
  );
  process.exit(2);
}

const accounts = await allAccounts();
const dartAccounts = accounts.filter((a) => ACCOUNT.test(a.id));

/*
 * The guard that matters more than the count.
 *
 * If an id matches the pattern AND is a real Postgres profile, then either a
 * real person is named `dart-<digits>` or the two namespaces have collided —
 * and in both cases deleting is the wrong move. It stops the whole run rather
 * than skipping the one account, because the premise this script rests on, that
 * nothing matching the pattern is real, has failed.
 */
const collisions = dartAccounts.filter((a) => realIds.has(a.id));

const dartProfiles = (await allRowIds('profiles'))?.filter((id) => ACCOUNT.test(id)) ?? null;
const dartReports = (await allRowIds('reports'))?.filter((id) => REPORT.test(id)) ?? null;
const withLabels = dartAccounts.filter((a) => a.labels.length);

console.log(`\nproject ${project} at ${EP}, database ${DB}`);
console.log(`${'appwrite accounts'.padEnd(30)} ${String(accounts.length).padStart(5)}`);
console.log(`${'  left by prep-dart.mjs'.padEnd(30)} ${String(dartAccounts.length).padStart(5)}`);
console.log(`${'  of those, holding labels'.padEnd(30)} ${String(withLabels.length).padStart(5)}`);
console.log(
  `${'dart profiles rows'.padEnd(30)} ` +
    `${dartProfiles === null ? '   (no table)' : String(dartProfiles.length).padStart(5)}`,
);
console.log(
  `${'dart-foreign reports rows'.padEnd(30)} ` +
    `${dartReports === null ? '   (no table)' : String(dartReports.length).padStart(5)}`,
);

const findings = [];
if (collisions.length) {
  findings.push({
    finding:
      'STOP: an id matching the test-account pattern is a real Postgres profile.' +
      ' Nothing will be deleted. Either a real person is named like a test' +
      ' account, or the two id namespaces have collided — this script assumes' +
      ' they cannot, and that assumption has failed.',
    accounts: collisions.slice(0, 20),
  });
}
if (withLabels.length) {
  findings.push({
    finding:
      `${withLabels.length} of these accounts hold Appwrite labels, so they are` +
      ' not inert: prep-dart.mjs grants ewr and approved, and its password is a' +
      ' literal in this repository. Anyone who can read the repo can sign in as' +
      ' them and use whatever those labels grant. Purge, then treat the password' +
      ' as disclosed.',
    accounts: withLabels.slice(0, 20).map((a) => ({ id: a.id, labels: a.labels })),
  });
}
if (dartReports?.length) {
  findings.push({
    finding:
      `${dartReports.length} dart-foreign report row(s) are in ${DB} and not in` +
      ' Postgres. They carry read("label:ewr"), read("label:admin") and' +
      ' read("label:ewv"), so every admin and verifier can see them — which means' +
      " Phase 4's gate should have reported them as a leak and did not. Purging" +
      ' them removes the exposure; the gate missing them is a separate bug worth' +
      ' chasing.',
    rows: dartReports.slice(0, 20),
  });
}

if (findings.length) {
  console.log(`\n${findings.length} thing(s) to know:`);
  console.log(JSON.stringify(findings, null, 2));
}

if (!DELETE) {
  console.log(
    `\nAudit only; nothing was changed.` +
      (collisions.length
        ? '\nFix the collision above before running --delete.\n'
        : `\nTo purge:\n  CONFIRM_DELETE_DART=${dartAccounts.length}` +
          ' node purge-dart-accounts.mjs --delete\n'),
  );
  process.exit(findings.length ? 1 : 0);
}

if (collisions.length) {
  console.error('\nRefusing to delete: see the collision above. Nothing was changed.');
  process.exit(2);
}

const confirmed = Number(process.env.CONFIRM_DELETE_DART ?? NaN);
if (confirmed !== dartAccounts.length) {
  console.error(
    `\nRefusing to delete. CONFIRM_DELETE_DART is` +
      ` ${process.env.CONFIRM_DELETE_DART ?? '(unset)'} and this run counted` +
      ` ${dartAccounts.length} account(s). Re-read the audit and pass that number.`,
  );
  process.exit(2);
}

const failures = [];
let deleted = { accounts: 0, profiles: 0, reports: 0 };

// Rows first, then the accounts. The other order would leave a row whose
// `read("user:<id>")` names an account that no longer exists — readable by
// nobody, invisible, and still there.
for (const [table, ids, key] of [
  ['profiles', dartProfiles ?? [], 'profiles'],
  ['reports', dartReports ?? [], 'reports'],
]) {
  for (const id of ids) {
    const r = await aw(`${rowsPath(table)}/${encodeURIComponent(id)}`, { method: 'DELETE' });
    if (r.status === 204 || r.status === 200 || r.status === 404) deleted[key] += 1;
    else failures.push(`${table}/${id}: ${r.status} ${String(r.body?.message ?? '').slice(0, 90)}`);
  }
}
for (const a of dartAccounts) {
  const r = await aw(`/users/${encodeURIComponent(a.id)}`, { method: 'DELETE' });
  if (r.status === 204 || r.status === 200 || r.status === 404) deleted.accounts += 1;
  else failures.push(`${a.id}: ${r.status} ${String(r.body?.message ?? '').slice(0, 90)}`);
}

console.log(JSON.stringify({ deleted, failed: failures.length, failures }, null, 2));
if (failures.length) {
  console.error('\nSome remain. Re-run the audit: this is idempotent.');
  process.exit(1);
}
console.log(
  '\nPurged. Two things this does not do: it cannot un-publish the password in' +
    "\nthis repository's history, and it does not stop the next run — that is the" +
    '\nALLOW_REMOTE guard in infra/appwrite/local/prep-dart.mjs.\n',
);
