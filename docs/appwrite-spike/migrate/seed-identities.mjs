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
import { appwriteTarget, migrationPassword } from './target.mjs';
const { aw } = appwriteTarget();
const PASSWORD = migrationPassword();

const client = new pg.Client({ connectionString: process.env.PG_URL ?? 'postgres://postgres:postgres@localhost:5432/cradi_mig' });
await client.connect();
// The address comes from auth.users, never synthesised: a derived local
// part collided for every profile sharing an id prefix, and five of six
// users silently failed to create.
const rows = (await client.query(
  `select p.id, p.name, p.role, p.state, p.lga, p.ward,
          p.is_approved, p.is_disabled, u.email
     from profiles p join auth.users u on u.id = p.id order by p.id`,
)).rows;

const teams = new Set();
for (const p of rows) if (p.ward) teams.add(wardTeam(p.state, p.lga, p.ward));
// Reports can sit in wards no profile lives in.
for (const r of (await client.query('select distinct state, lga, ward from reports')).rows) teams.add(wardTeam(r.state, r.lga, r.ward));

let madeTeams = 0;
for (const t of teams) { const r = await aw('/teams', { method: 'POST', body: JSON.stringify({ teamId: t, name: t }) }); if (r.status === 201) madeTeams += 1; }

let users = 0, labelled = 0, joined = 0;
const failures = [];
for (const p of rows) {
  // The Postgres uuid verbatim: 36 chars, and Appwrite allows dashes
  // after the first character. Any transformation here has to be repeated
  // identically wherever an ACL names a user, and the first version of this
  // script stripped the dashes in one place and not the other — which
  // Appwrite accepted in silence and left every document readable by nobody.
  const uid = p.id;
  const u = await aw('/users', { method: 'POST', body: JSON.stringify({ userId: uid, email: p.email, password: PASSWORD, name: p.name ?? '' }) });
  if (u.status === 201) users += 1;
  else if (u.status !== 409) failures.push(`${p.id}: ${u.status} ${String(u.body?.message).slice(0, 90)}`);
  const labels = accountLabels({ role: p.role, isApproved: p.is_approved, isDisabled: p.is_disabled });
  if (labels.length) { const lr = await aw(`/users/${uid}/labels`, { method: 'PUT', body: JSON.stringify({ labels }) });
    if (lr.status === 200) labelled += 1; else failures.push(`labels ${labels.join('+')}: ${lr.status}`); }
  if (labels.includes('ewm') && p.ward) {
    const r = await aw(`/teams/${wardTeam(p.state, p.lga, p.ward)}/memberships`, { method: 'POST', body: JSON.stringify({ userId: uid, roles: ['ewm'], url: 'http://localhost/' }) });
    if (r.status < 400) joined += 1;
  }
}
await client.end();
console.log(JSON.stringify({ teams: teams.size, teamsCreated: madeTeams, users, labelled, wardMemberships: joined, failures }, null, 2));
if (failures.length) process.exitCode = 1;
