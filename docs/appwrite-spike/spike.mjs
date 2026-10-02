/**
 * Phase 0 — can Appwrite express CRADI's ward-scoped read rule?
 *
 * The policy being modelled, from supabase/migrations:
 *
 *   user_id = auth.uid()
 *   or (app_role() = 'ewm' and ward = my_ward() and lga = my_lga())
 *   or app_role() in ('ewv','ewr','ldp_coordinator','project_staff','admin','techSupport')
 *
 * Mapped to Appwrite as: read("user:<owner>") for the first clause,
 * read("team:<ward>") for the second, read("label:<role>") for the third.
 */
import { readFileSync } from 'node:fs';
const { project, key } = JSON.parse(readFileSync('env.json', 'utf8'));
const EP = 'http://localhost:8080/v1';

async function admin(path, { method = 'GET', body } = {}) {
  const res = await fetch(`${EP}${path}`, {
    method,
    headers: { 'content-type': 'application/json', 'x-appwrite-project': project, 'x-appwrite-key': key },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${method} ${path} -> ${res.status}: ${text.slice(0, 250)}`);
  return text ? JSON.parse(text) : null;
}

/** Act as a signed-in user: returns a fetch bound to their session cookie. */
async function signIn(email, password) {
  const res = await fetch(`${EP}/account/sessions/email`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-appwrite-project': project },
    body: JSON.stringify({ email, password }),
  });
  if (!res.ok) throw new Error(`sign-in ${email}: ${res.status} ${await res.text()}`);
  const cookie = (res.headers.get('set-cookie') ?? '').split(';')[0];
  return async (path) => {
    const r = await fetch(`${EP}${path}`, {
      headers: { 'content-type': 'application/json', 'x-appwrite-project': project, cookie },
    });
    return { status: r.status, body: await r.json().catch(() => null) };
  };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---- database and collection -------------------------------------------
await admin('/databases', { method: 'POST', body: { databaseId: 'cradi', name: 'cradi' } }).catch(() => {});
await admin('/databases/cradi/collections', {
  method: 'POST',
  body: {
    collectionId: 'reports', name: 'reports',
    permissions: [], documentSecurity: true, // per-document ACLs decide reads
  },
}).catch(() => {});
for (const k of ['state', 'lga', 'ward', 'title']) {
  await admin('/databases/cradi/collections/reports/attributes/string', {
    method: 'POST', body: { key: k, size: 128, required: true },
  }).catch(() => {});
}
await sleep(3000); // the databases worker creates attributes asynchronously

// ---- two wards, as teams ------------------------------------------------
const wardA = await admin('/teams', { method: 'POST', body: { teamId: 'ward-benue-makurdi-centre', name: 'Makurdi/Centre' } }).catch(() => ({ $id: 'ward-benue-makurdi-centre' }));
const wardB = await admin('/teams', { method: 'POST', body: { teamId: 'ward-benue-makurdi-north', name: 'Makurdi/North' } }).catch(() => ({ $id: 'ward-benue-makurdi-north' }));

// ---- three users --------------------------------------------------------
async function user(id, email, label) {
  await admin('/users', { method: 'POST', body: { userId: id, email, password: 'SpikePassword123', name: id } }).catch(() => {});
  if (label) await admin(`/users/${id}/labels`, { method: 'PUT', body: { labels: [label] } });
  return id;
}
await user('citizen', 'citizen@example.test');
await user('ewm-a', 'ewma@example.test');
await user('ewm-b', 'ewmb@example.test');
await user('ewv', 'ewv@example.test', 'ewv');

async function join(teamId, userId) {
  await admin(`/teams/${teamId}/memberships`, {
    method: 'POST', body: { userId, roles: ['ewm'], url: 'http://localhost/' },
  }).catch((e) => console.log('  join note:', String(e).slice(0, 110)));
}
await join(wardA.$id, 'ewm-a');
await join(wardB.$id, 'ewm-b');

// ---- one report per ward, ACLs stamped at creation ----------------------
async function report(id, ward, teamId) {
  await admin('/databases/cradi/collections/reports/documents', {
    method: 'POST',
    body: {
      documentId: id,
      data: { state: 'Benue', lga: 'Makurdi', ward, title: `flood in ${ward}` },
      permissions: [
        'read("user:citizen")',      // the reporter
        `read("team:${teamId}")`,    // EWMs of that ward
        'read("label:ewv")',         // statewide verifier roles
      ],
    },
  }).catch((e) => console.log('  doc note:', String(e).slice(0, 110)));
}
await report('rep-a', 'Centre', wardA.$id);
await report('rep-b', 'North', wardB.$id);

// ---- the matrix ---------------------------------------------------------
const as = {
  citizen: await signIn('citizen@example.test', 'SpikePassword123'),
  ewmA: await signIn('ewma@example.test', 'SpikePassword123'),
  ewmB: await signIn('ewmb@example.test', 'SpikePassword123'),
  ewv: await signIn('ewv@example.test', 'SpikePassword123'),
};

async function canRead(who, doc) {
  const { status } = await as[who](`/databases/cradi/collections/reports/documents/${doc}`);
  return status === 200;
}
async function lists(who) {
  const { body } = await as[who]('/databases/cradi/collections/reports/documents');
  return (body?.documents ?? []).map((d) => d.$id).sort().join(',') || '(none)';
}

console.log('\n--- Q1: can a ward-scoped read be expressed as document permissions?');
for (const [who, doc, expect] of [
  ['citizen', 'rep-a', true], ['citizen', 'rep-b', true],
  ['ewmA', 'rep-a', true], ['ewmA', 'rep-b', false],
  ['ewmB', 'rep-b', true], ['ewmB', 'rep-a', false],
  ['ewv', 'rep-a', true], ['ewv', 'rep-b', true],
]) {
  const got = await canRead(who, doc);
  console.log(`  ${got === expect ? 'OK  ' : 'FAIL'} ${who} reads ${doc}: ${got} (expected ${expect})`);
}

console.log('\n--- list is filtered, not just get');
for (const who of ['citizen', 'ewmA', 'ewmB', 'ewv']) console.log(`  ${who} lists: ${await lists(who)}`);

console.log('\n--- Q2: EWM A is transferred to ward B. No document is touched.');
const memberships = await admin(`/teams/${wardA.$id}/memberships`);
const m = memberships.memberships.find((x) => x.userId === 'ewm-a');
if (m) await admin(`/teams/${wardA.$id}/memberships/${m.$id}`, { method: 'DELETE' });
await join(wardB.$id, 'ewm-a');
await sleep(1500);
const after = await signIn('ewma@example.test', 'SpikePassword123');
const a = await after('/databases/cradi/collections/reports/documents/rep-a');
const b = await after('/databases/cradi/collections/reports/documents/rep-b');
console.log(`  ewmA reads rep-a (old ward): ${a.status === 200} (expected false)`);
console.log(`  ewmA reads rep-b (new ward): ${b.status === 200} (expected true)`);
