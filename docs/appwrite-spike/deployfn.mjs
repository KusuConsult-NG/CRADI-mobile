import { readFileSync } from 'node:fs';
const { project, key } = JSON.parse(readFileSync('env.json', 'utf8'));
const EP = 'http://localhost:8080/v1';
const H = { 'x-appwrite-project': project, 'x-appwrite-key': key };
const j = async (p, o = {}) => { const r = await fetch(`${EP}${p}`, { ...o, headers: { 'content-type': 'application/json', ...H } }); return { status: r.status, body: await r.json().catch(() => null) }; };

// profiles collection, so the Function has something to check.
await j('/databases/cradi/collections', { method: 'POST', body: JSON.stringify({ collectionId: 'profiles', name: 'profiles', documentSecurity: true, permissions: [] }) });
for (const [k, t] of [['name','string'],['role','string'],['state','string'],['lga','string'],['ward','string']])
  await j(`/databases/cradi/collections/profiles/attributes/${t}`, { method: 'POST', body: JSON.stringify({ key: k, size: 128, required: false }) });
await j('/databases/cradi/collections/profiles/attributes/boolean', { method: 'POST', body: JSON.stringify({ key: 'is_disabled', required: false, default: false }) });
// reports needs the fields the Function writes.
for (const k of ['hazard_type','description','user_id','status'])
  await j(`/databases/cradi/collections/reports/attributes/string`, { method: 'POST', body: JSON.stringify({ key: k, size: 512, required: false }) });
await j('/databases/cradi/collections/reports/attributes/integer', { method: 'POST', body: JSON.stringify({ key: 'verification_count', required: false, default: 0 }) });
await j('/databases/cradi/collections/reports/attributes/boolean', { method: 'POST', body: JSON.stringify({ key: 'escalated', required: false, default: false }) });
await new Promise(r => setTimeout(r, 4000));

await j('/databases/cradi/collections/profiles/documents', { method: 'POST', body: JSON.stringify({
  documentId: 'ewm-a', data: { name: 'EWM A', role: 'ewm', state: 'Benue', lga: 'Makurdi', ward: 'North', is_disabled: false }, permissions: ['read("user:ewm-a")'] }) });
await j('/databases/cradi/collections/profiles/documents', { method: 'POST', body: JSON.stringify({
  documentId: 'citizen', data: { name: 'Citizen', role: 'user', state: 'Benue', lga: 'Makurdi', ward: 'North', is_disabled: false }, permissions: ['read("user:citizen")'] }) });

const fn = await j('/functions', { method: 'POST', body: JSON.stringify({
  functionId: 'create-report', name: 'create-report', runtime: 'node-20.0',
  execute: ['users'], entrypoint: 'main.js', timeout: 30,
}) });
console.log('create function:', fn.status, fn.body?.message?.slice(0, 70) ?? 'ok');

for (const [k, v] of [['APPWRITE_ENDPOINT', 'http://appwrite/v1'], ['APPWRITE_PROJECT', project], ['APPWRITE_API_KEY', key]]) {
  const r = await j('/functions/create-report/variables', { method: 'POST', body: JSON.stringify({ key: k, value: v }) });
  if (r.status >= 400) console.log('  var', k, r.status, r.body?.message?.slice(0, 50));
}

const form = new FormData();
form.append('entrypoint', 'main.js');
form.append('activate', 'true');
form.append('code', new Blob([readFileSync('/home/user/appwrite-spike/fn/create-report.tar.gz')], { type: 'application/gzip' }), 'code.tar.gz');
const dep = await fetch(`${EP}/functions/create-report/deployments`, { method: 'POST', headers: H, body: form });
const depBody = await dep.json().catch(() => null);
console.log('deployment:', dep.status, depBody?.$id ?? depBody?.message?.slice(0, 80));

for (let i = 0; i < 40; i++) {
  const d = await j(`/functions/create-report/deployments/${depBody.$id}`);
  if (['ready', 'failed'].includes(d.body?.status)) { console.log('build:', d.body.status); if (d.body.status === 'failed') console.log((d.body.buildLogs || '').slice(-600)); break; }
  await new Promise(r => setTimeout(r, 3000));
}
