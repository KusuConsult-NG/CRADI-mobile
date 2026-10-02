import { readFileSync } from 'node:fs';
const { project, key } = JSON.parse(readFileSync('env.json', 'utf8'));
const EP = 'http://localhost:8080/v1';
const cookieFor = async (email) => {
  const s = await fetch(`${EP}/account/sessions/email`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-appwrite-project': project }, body: JSON.stringify({ email, password: 'SpikePassword123' }) });
  return (s.headers.get('set-cookie') ?? '').split(';')[0];
};
const citizen = await cookieFor('citizen@example.test');

console.log('--- 1. a client CANNOT write the reports collection directly');
const direct = await fetch(`${EP}/databases/cradi/collections/reports/documents`, {
  method: 'POST', headers: { 'content-type': 'application/json', 'x-appwrite-project': project, cookie: citizen },
  body: JSON.stringify({ documentId: 'unique()', data: { state: 'Benue', lga: 'Makurdi', ward: 'North', title: 'direct', status: 'approved' } }) });
console.log('   direct POST ->', direct.status, direct.status >= 400 ? '(refused)' : 'WROTE — collection is open!');

console.log('\n--- 2. the Function writes it, and decides the fields the client may not');
async function callFn(body, cookie) {
  const r = await fetch(`${EP}/functions/create-report/executions`, {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-appwrite-project': project, cookie },
    body: JSON.stringify({ body: JSON.stringify(body), async: false, method: 'POST' }) });
  const e = await r.json();
  return { http: r.status, code: e.responseStatusCode, out: e.responseBody, errors: e.errors?.slice(0, 200) };
}
const ok = await callFn({ hazard_type: 'Flooding', description: 'water rising', state: 'Benue', lga: 'Makurdi', ward: 'North' }, citizen);
console.log('   execution ->', ok.http, 'fn status', ok.code);
console.log('   returned:', ok.out?.slice(0, 160));
if (ok.errors) console.log('   errors:', ok.errors);

console.log('\n--- 3. a client claiming status=approved is overruled');
const sneaky = await callFn({ hazard_type: 'Flooding', description: 'sneaky', state: 'Benue', lga: 'Makurdi', ward: 'North', status: 'approved', verification_count: 99, escalated: true }, citizen);
console.log('   returned:', sneaky.out?.slice(0, 160));

console.log('\n--- 4. the report it created is ward-scoped');
const id = JSON.parse(ok.out || '{}').id;
if (id) {
  for (const [who, email, expect] of [['ewm-a (in ward North)', 'ewma@example.test', 200], ['ewv (label)', 'ewv@example.test', 200], ['owner', 'citizen@example.test', 200]]) {
    const c = await cookieFor(email);
    const r = await fetch(`${EP}/databases/cradi/collections/reports/documents/${id}`, { headers: { 'x-appwrite-project': project, cookie: c } });
    console.log(`   ${who} -> ${r.status} (expect ${expect})`);
  }
}
