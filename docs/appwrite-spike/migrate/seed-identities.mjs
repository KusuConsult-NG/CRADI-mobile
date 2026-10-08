/**
 * Identities must exist before their documents are stamped with them.
 *
 * Real cutover does this from `profiles`: every user becomes an Appwrite
 * account, every ward becomes a team, every role becomes a label. Order
 * matters — an ACL naming a team that does not exist is accepted silently
 * and grants nobody anything, which is the quietest possible migration bug.
 */
import pg from 'pg';
import { wardTeam } from './migrate.mjs';
// The running system's own rule, not a second copy of it: `write.js` calls this
// on every change to role, isApproved or isDisabled, so a migrated account must
// start with exactly what that would give it. It also returns `approved`, which
// `plan.mjs` requires for `messages` and which this script never used to set.
import { accountLabels } from '../../../functions/cradi/src/lib/policy.js';
import { appwriteTarget } from './target.mjs';
const { aw } = appwriteTarget();

/**
 * Supabase stores its passwords as bcrypt, and Appwrite will take them as they
 * are — so every user keeps the password they already have.
 *
 * `POST /users/bcrypt` (`createBcryptUser`) takes `userId`, `email`, `password`
 * and `name`, where `password` is the hash rather than a plaintext. This is the
 * whole reason the cutover does not force ~650 password resets, and it is why
 * nothing here needs a shared `MIGRATION_PASSWORD` any more: there is no
 * password for anyone to know.
 *
 * An account with no hash is not an error. A user who only ever signed in by
 * magic link or OAuth has `encrypted_password` null or empty, and gets a
 * passwordless account — `POST /users` requires only `userId`, with email,
 * name and password all optional — which is exactly what they had.
 */
const BCRYPT = /^\$2[aby]\$\d{2}\$/;

const client = new pg.Client({ connectionString: process.env.PG_URL ?? 'postgres://postgres:postgres@localhost:5432/cradi_mig' });
await client.connect();
// Fail here rather than quietly creating 650 accounts nobody has the password
// to: without this column there is no hash to import, and 5.1 of the runbook
// decided that passwords survive the cutover.
const hasHash = (await client.query(
  `select count(*) > 0 as present from information_schema.columns
    where table_schema = 'auth' and table_name = 'users'
      and column_name = 'encrypted_password'`,
)).rows[0].present;
if (!hasHash) {
  console.error(
    'auth.users has no encrypted_password column, so no password can be' +
      ' imported.\nThat is the whole point of this step — see 5.1 in' +
      ' docs/CUTOVER-RUNBOOK.md.',
  );
  await client.end();
  process.exit(2);
}

// The address comes from auth.users, never synthesised: a derived local
// part collided for every profile sharing an id prefix, and five of six
// users silently failed to create.
const rows = (await client.query(
  `select p.id, p.name, p.role, p.state, p.lga, p.ward,
          p.is_approved, p.is_disabled, u.email, u.encrypted_password
     from profiles p join auth.users u on u.id = p.id order by p.id`,
)).rows;

const teams = new Set();
for (const p of rows) if (p.ward) teams.add(wardTeam(p.state, p.lga, p.ward));
// Reports can sit in wards no profile lives in.
for (const r of (await client.query('select distinct state, lga, ward from reports')).rows) teams.add(wardTeam(r.state, r.lga, r.ward));

let madeTeams = 0;
for (const t of teams) { const r = await aw('/teams', { method: 'POST', body: JSON.stringify({ teamId: t, name: t }) }); if (r.status === 201) madeTeams += 1; }

let users = 0, labelled = 0, joined = 0;
/** Accounts whose password came across, and those that never had one. */
let withHash = 0, withoutHash = 0, unknownHash = 0, existed = 0;
const failures = [];
for (const p of rows) {
  // The Postgres uuid verbatim: 36 chars, and Appwrite allows dashes
  // after the first character. Any transformation here has to be repeated
  // identically wherever an ACL names a user, and the first version of this
  // script stripped the dashes in one place and not the other — which
  // Appwrite accepted in silence and left every document readable by nobody.
  const uid = p.id;
  const hash = String(p.encrypted_password ?? '').trim();
  const importable = BCRYPT.test(hash);
  let created;
  if (importable) {
    created = await aw('/users/bcrypt', { method: 'POST', body: JSON.stringify({ userId: uid, email: p.email, password: hash, name: p.name ?? '' }) });
  } else {
    // A hash in some other format is not silently dropped: it is counted and
    // named, because the holder loses their password and nobody would notice.
    if (hash) { unknownHash += 1; failures.push(`${p.id}: password hash is not bcrypt (${hash.slice(0, 4)}…), left without one`); }
    else withoutHash += 1;
    created = await aw('/users', { method: 'POST', body: JSON.stringify({ userId: uid, email: p.email, name: p.name ?? '' }) });
  }
  if (created.status === 201) {
    users += 1;
    if (importable) withHash += 1;
  } else if (created.status === 409) {
    // The account was already there, so its password is whatever the run that
    // created it set — NOT this hash. Appwrite can take a hash only at
    // creation: `PATCH /users/{id}/password` accepts a plaintext and there is
    // no endpoint that sets a pre-existing hash on an existing account. So a
    // 409 is the one case where re-running this script does NOT converge, and
    // it must not be counted as an import or the summary will claim 650
    // passwords were carried across while changing none of them.
    existed += 1;
    if (importable) {
      failures.push(
        `${p.id}: account already exists, so the bcrypt hash was NOT imported;` +
          ' delete the account and re-run, or the user cannot sign in with their' +
          ' Supabase password',
      );
    }
  } else {
    failures.push(`${p.id}: ${created.status} ${String(created.body?.message).slice(0, 90)}`);
  }
  const labels = accountLabels({ role: p.role, isApproved: p.is_approved, isDisabled: p.is_disabled });
  if (labels.length) { const lr = await aw(`/users/${uid}/labels`, { method: 'PUT', body: JSON.stringify({ labels }) });
    if (lr.status === 200) labelled += 1; else failures.push(`labels ${labels.join('+')}: ${lr.status}`); }
  if (labels.includes('ewm') && p.ward) {
    const r = await aw(`/teams/${wardTeam(p.state, p.lga, p.ward)}/memberships`, { method: 'POST', body: JSON.stringify({ userId: uid, roles: ['ewm'], url: 'http://localhost/' }) });
    if (r.status < 400) joined += 1;
  }
}
await client.end();
console.log(JSON.stringify({
  teams: teams.size, teamsCreated: madeTeams, users, labelled,
  wardMemberships: joined,
  passwords: {
    imported: withHash, none: withoutHash, notBcrypt: unknownHash,
    alreadyExisted: existed,
  },
  failures,
}, null, 2));
if (failures.length) process.exitCode = 1;
