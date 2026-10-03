/** Collections, attributes and ward teams the migration needs to land in. */
import { readFileSync } from 'node:fs';
const { project, key } = JSON.parse(readFileSync('../spike/env.json', 'utf8'));
const EP = 'http://localhost:8080/v1';
const H = { 'content-type': 'application/json', 'x-appwrite-project': project, 'x-appwrite-key': key };
const aw = async (p, o = {}) => { const r = await fetch(`${EP}${p}`, { ...o, headers: H }); return { status: r.status, body: await r.json().catch(() => null) }; };

const str = (c, k, size = 256) => aw(`/databases/cradi/collections/${c}/attributes/string`, { method: 'POST', body: JSON.stringify({ key: k, size, required: false }) });
const int = (c, k) => aw(`/databases/cradi/collections/${c}/attributes/integer`, { method: 'POST', body: JSON.stringify({ key: k, required: false, default: 0 }) });
const bool = (c, k) => aw(`/databases/cradi/collections/${c}/attributes/boolean`, { method: 'POST', body: JSON.stringify({ key: k, required: false, default: false }) });

for (const c of ['profiles', 'reports', 'verifications']) {
  await aw('/databases/cradi/collections', { method: 'POST', body: JSON.stringify({ collectionId: c, name: c, documentSecurity: true, permissions: [] }) });
}
for (const k of ['name', 'role', 'state', 'lga', 'ward']) await str('profiles', k);
await bool('profiles', 'is_disabled');
for (const k of ['user_id', 'hazard_type', 'title', 'state', 'lga', 'ward', 'status']) await str('reports', k);
await str('reports', 'description', 2048);
await int('reports', 'verification_count'); await bool('reports', 'escalated');
for (const k of ['report_id', 'verifier_id', 'ward', 'lga', 'state']) await str('verifications', k);
await str('verifications', 'comment', 1024); await bool('verifications', 'is_confirmed');
await new Promise((r) => setTimeout(r, 6000));

// Ward teams, and label/team membership for the users the data refers to.
const { run, wardTeam } = await import('./migrate.mjs');
console.log('prepared collections; teams are created by seed-identities.mjs');
