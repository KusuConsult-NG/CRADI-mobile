/**
 * Re-create the seeded Appwrite accounts so each one carries its own password.
 *
 * Why this exists: the production project was seeded by a version of
 * `seed-identities.mjs` that gave every account one shared
 * `MIGRATION_PASSWORD`. The current version imports each account's own bcrypt
 * hash from `auth.users.encrypted_password` — but Appwrite accepts a hash only
 * at **creation**. `PATCH /users/{userId}/password` takes a plaintext, and no
 * endpoint sets a pre-existing hash on an existing account. So there is no
 * in-place fix: the accounts have to be deleted and created again.
 *
 * What that costs, and why now rather than later. Deleting an account does not
 * touch the rows it owns: every row ACL names `user:<uuid>`, the uuid is the
 * Postgres id, and re-creating with the same `userId` restores the match
 * exactly. What it does destroy is that account's sessions, labels and team
 * memberships — `seed-identities.mjs` re-creates the labels and memberships in
 * the same run, and before the app ships there are no sessions and no
 * registered push targets to lose. After it ships, the same operation logs out
 * every signed-in user and drops their push targets.
 *
 *   PG_URL              the Supabase Postgres these accounts came from
 *   AW_ENDPOINT / AW_PROJECT / AW_KEY   the project to repair
 *
 * Audit, which writes nothing:
 *
 *   node reseed-passwords.mjs
 *
 * Then, if the audit is clean, the delete — the count is an interlock, and it
 * must equal what the audit just reported:
 *
 *   CONFIRM_DELETE_USERS=170 node reseed-passwords.mjs --delete
 *   node seed-identities.mjs          # re-creates them, with the hashes
 *
 * Exit 0 audit clean or delete complete, 1 a finding the operator must decide
 * on, 2 not configured, not reachable, or the interlock disagreed.
 */
import pg from 'pg';
import { appwriteTarget } from './target.mjs';

const { endpoint: EP, project, key: KEY, aw } = appwriteTarget();
const PG = process.env.PG_URL ?? 'postgres://postgres:postgres@localhost:5432/cradi_mig';
const DELETE = process.argv.includes('--delete');
/*
 * Proceed even though the re-seed would leave people worse off.
 *
 * This exists because the audit refuses the delete when re-seeding would import
 * fewer passwords than the accounts hold today — and that refusal has to be
 * overridable for the one legitimate case, a project whose users genuinely have
 * no password to import. It is not a `--force`: every other refusal stands.
 */
const ACCEPT_LOSS = process.argv.includes('--accept-password-loss');
const BCRYPT = /^\$2[aby]\$\d{2}\$/;

/** Every Appwrite account in the project, paged. */
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
        name: u.name ?? '',
        // Appwrite stamps `passwordUpdate` when an account is given a password
        // and leaves it empty when it has none, which is the only way from
        // outside to tell "can sign in" from "cannot". Absent entirely — an
        // older server, a changed model — reads as unknown rather than as
        // either answer, and the interlock below falls back accordingly.
        hasPassword: 'passwordUpdate' in u ? Boolean(u.passwordUpdate) : null,
      })),
    );
    if (page.length < 100) break;
    cursor = page[page.length - 1].$id;
  }
  return out;
}

/**
 * Whether anybody has signed in to [id].
 *
 * Asked per account rather than assumed. A session on a seeded account means
 * somebody has used the shared password, which is both the reason to hurry and
 * a thing the operator must see before a delete logs them out.
 */
async function sessionCount(id) {
  const r = await aw(`/users/${encodeURIComponent(id)}/sessions`);
  if (r.status !== 200) return null;
  return Array.isArray(r.body?.sessions) ? r.body.sessions.length : (r.body?.total ?? null);
}

const client = new pg.Client({ connectionString: PG });
await client.connect();

const rows = (
  await client.query(
    `select p.id, u.email, u.encrypted_password
       from profiles p join auth.users u on u.id = p.id order by p.id`,
  )
).rows;
await client.end();

if (!rows.length) {
  console.error('no profiles joined to auth.users — wrong PG_URL?');
  process.exit(2);
}

const fromPg = new Map(rows.map((r) => [r.id, r]));
const accounts = await allAccounts();

// Only an account whose id is a Postgres profile id was created by the seeder.
// Anything else is a real sign-up made after the migration, or an account
// somebody made by hand, and it is never this script's to delete.
const seeded = accounts.filter((a) => fromPg.has(a.id));
const foreign = accounts.filter((a) => !fromPg.has(a.id));
const absent = rows.filter((r) => !accounts.some((a) => a.id === r.id));

const hashes = { bcrypt: 0, none: 0, other: 0 };
for (const r of rows) {
  const h = String(r.encrypted_password ?? '').trim();
  if (BCRYPT.test(h)) hashes.bcrypt += 1;
  else if (h) hashes.other += 1;
  else hashes.none += 1;
}

let withSessions = 0;
const signedIn = [];
for (const a of seeded) {
  const n = await sessionCount(a.id);
  if (n) {
    withSessions += 1;
    signedIn.push({ id: a.id, email: a.email, sessions: n });
  }
}

console.log(`\nproject ${project} at ${EP}`);
console.log(`${'postgres accounts'.padEnd(26)} ${String(rows.length).padStart(5)}`);
console.log(`${'appwrite accounts'.padEnd(26)} ${String(accounts.length).padStart(5)}`);
console.log(`${'  seeded (deletable)'.padEnd(26)} ${String(seeded.length).padStart(5)}`);
console.log(`${'  NOT from the seeder'.padEnd(26)} ${String(foreign.length).padStart(5)}`);
console.log(`${'  in postgres, not here'.padEnd(26)} ${String(absent.length).padStart(5)}`);
console.log(`${'  with live sessions'.padEnd(26)} ${String(withSessions).padStart(5)}`);
const withPassword = seeded.filter((a) => a.hasPassword === true).length;
const passwordKnown = seeded.some((a) => a.hasPassword !== null);
if (passwordKnown) {
  console.log(`${'  with a password now'.padEnd(26)} ${String(withPassword).padStart(5)}`);
}
console.log(
  `\nafter re-seeding, passwords: ${hashes.bcrypt} imported,` +
    ` ${hashes.none} passwordless (no hash to import),` +
    ` ${hashes.other} WITHOUT one (hash is not bcrypt)`,
);

const findings = [];
/*
 * The interlock this script was missing, and the reason it is here.
 *
 * The first version treated "what would be imported" as information and let the
 * delete proceed on the operator's count alone. Pointed at the real project it
 * printed `0 imported, 170 passwordless` and still said "to delete the 170
 * seeded account(s): …" — because its only password finding was a hash in the
 * wrong *format*, and a hash that is simply absent is not that. Running it
 * would have replaced 170 accounts that could sign in with 170 that could not:
 * strictly worse than the shared password it was meant to repair, and
 * irreversible, since the accounts it deleted were the only place that password
 * existed.
 *
 * So the invariant is now stated and enforced: the operation must not reduce
 * the number of accounts that can sign in. It compares what the re-seed would
 * import against what the accounts hold TODAY — not against the row count,
 * which says nothing about passwords.
 */
const wouldLose = passwordKnown
  ? Math.max(0, withPassword - hashes.bcrypt)
  : (hashes.bcrypt === 0 && seeded.length > 0 ? seeded.length : 0);
if (wouldLose > 0) {
  findings.push({
    finding:
      `STOP: re-seeding would import ${hashes.bcrypt} password(s) for ` +
      `${seeded.length} account(s), leaving ${wouldLose} of them unable to sign in` +
      (passwordKnown ? ` that can today` : ' (this server does not report which have one)') +
      '. Postgres has no bcrypt hash to import for them, which usually means' +
      ' auth.users was mirrored through Supabase\'s Auth REST admin API —' +
      ' /auth/v1/admin/users does not return encrypted_password. Point PG_URL at' +
      ' the Supabase Postgres directly (port 5432 or the 6543 pooler), or load an' +
      ' export of auth.users(id, encrypted_password) into the mirror, then audit' +
      ' again. --accept-password-loss overrides this if the accounts genuinely' +
      ' have no password to keep.',
    importable: hashes.bcrypt,
    seeded: seeded.length,
    haveAPasswordNow: passwordKnown ? withPassword : 'unknown',
  });
}
if (foreign.length) {
  findings.push({
    finding: `${foreign.length} Appwrite account(s) are not in Postgres, so the seeder did not` +
      ' create them. They will NOT be deleted. If any is a real sign-up, the app is already' +
      ' live and deleting the rest logs those people out — decide before running --delete.',
    accounts: foreign.slice(0, 20),
  });
}
if (withSessions) {
  findings.push({
    finding: `${withSessions} seeded account(s) have a live session, so somebody has signed in` +
      ' with the shared password. Deleting ends those sessions.',
    accounts: signedIn.slice(0, 20),
  });
}
if (hashes.other) {
  findings.push({
    finding: `${hashes.other} account(s) have a hash that is not bcrypt. Re-seeding creates them` +
      ' without a password, so those users must reset. They are named by seed-identities.mjs.',
  });
}

if (findings.length) {
  console.log(`\n${findings.length} thing(s) to decide before deleting:`);
  console.log(JSON.stringify(findings, null, 2));
}

if (!DELETE) {
  console.log(
    `\nAudit only; nothing was changed. To delete the ${seeded.length} seeded account(s):\n` +
      `  CONFIRM_DELETE_USERS=${seeded.length} node reseed-passwords.mjs --delete\n` +
      '  node seed-identities.mjs\n',
  );
  process.exit(findings.length ? 1 : 0);
}

// The interlock. The operator has to state the number, and it has to match what
// this run just counted — so a command copied from an older audit, or aimed at
// a project with a different population, stops here instead of deleting a set
// nobody looked at.
// Checked before the count, because no count makes this one acceptable.
if (wouldLose > 0 && !ACCEPT_LOSS) {
  console.error(
    `\nRefusing to delete: ${wouldLose} account(s) would come back unable to sign in.` +
      ' Read the finding above. Nothing was changed.',
  );
  process.exit(2);
}

const confirmed = Number(process.env.CONFIRM_DELETE_USERS ?? NaN);
if (confirmed !== seeded.length) {
  console.error(
    `\nRefusing to delete. CONFIRM_DELETE_USERS is ${process.env.CONFIRM_DELETE_USERS ?? '(unset)'}` +
      ` and this run counted ${seeded.length} seeded account(s). Re-read the audit above and` +
      ' pass the number it reports.',
  );
  process.exit(2);
}

console.log(`\ndeleting ${seeded.length} account(s)…`);
let deleted = 0;
let gone = 0;
const failures = [];
for (const a of seeded) {
  const r = await aw(`/users/${encodeURIComponent(a.id)}`, { method: 'DELETE' });
  // 204 is the delete; 404 means it went between the listing and now, which is
  // the same end state and not a failure.
  if (r.status === 204 || r.status === 200) deleted += 1;
  else if (r.status === 404) gone += 1;
  else failures.push(`${a.id}: ${r.status} ${String(r.body?.message ?? '').slice(0, 90)}`);
}

console.log(
  JSON.stringify({ deleted, alreadyGone: gone, failed: failures.length, failures }, null, 2),
);
if (failures.length) {
  console.error(
    '\nSome accounts remain. Re-run the audit: this script is idempotent, and a' +
      ' second --delete only touches what is still there.',
  );
  process.exit(1);
}
console.log(
  '\nNow re-create them, with their own passwords:\n  node seed-identities.mjs\n' +
    'Expect passwords.alreadyExisted: 0 — anything else means an account survived' +
    ' and kept its old password.\n',
);
