import { readFileSync } from 'node:fs';
const { project, key } = JSON.parse(readFileSync('env.json', 'utf8'));
const EP = 'http://localhost:8080/v1';
const H = { 'x-appwrite-project': project, 'x-appwrite-key': key };
const J = { 'content-type': 'application/json', ...H };
const j = async (p, o = {}) => { const r = await fetch(`${EP}${p}`, { ...o, headers: J }); return { status: r.status, body: await r.json().catch(() => null) }; };

// An event-triggered Function, plus a schedule — the escalation cron shape.
const f = await j('/functions', { method: 'POST', body: JSON.stringify({
  functionId: 'on-report', name: 'on-report', runtime: 'node-20.0', entrypoint: 'main.js', timeout: 30,
  events: ['databases.cradi.collections.reports.documents.*.create'],
  schedule: '*/15 * * * *',
}) });
console.log('function with events + schedule:', f.status, f.status >= 400 ? f.body?.message?.slice(0, 80) : `events=${f.body.events.length} schedule="${f.body.schedule}"`);

const form = new FormData();
form.append('entrypoint', 'main.js'); form.append('activate', 'true');
form.append('code', new Blob([readFileSync('/home/user/appwrite-spike/fn/on-report.tar.gz')], { type: 'application/gzip' }), 'c.tar.gz');
const d = await fetch(`${EP}/functions/on-report/deployments`, { method: 'POST', headers: H, body: form });
const db = await d.json();
for (let i = 0; i < 40; i++) { const s = (await j(`/functions/on-report/deployments/${db.$id}`)).body; if (['ready','failed'].includes(s?.status)) { console.log('build:', s.status); break; } await new Promise(r => setTimeout(r, 3000)); }

const before = (await j('/functions/on-report/executions')).body?.total ?? 0;
console.log('executions before:', before);

// Create a report THROUGH THE FUNCTION, as a user would.
const s = await fetch(`${EP}/account/sessions/email`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-appwrite-project': project }, body: JSON.stringify({ email: 'citizen@example.test', password: 'SpikePassword123' }) });
const cookie = (s.headers.get('set-cookie') ?? '').split(';')[0];
await fetch(`${EP}/functions/create-report/executions`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-appwrite-project': project, cookie },
  body: JSON.stringify({ body: JSON.stringify({ hazard_type: 'Flooding', state: 'Benue', lga: 'Makurdi', ward: 'North' }), async: false, method: 'POST' }) });

for (let i = 0; i < 20; i++) {
  const ex = (await j('/functions/on-report/executions')).body;
  if ((ex?.total ?? 0) > before) {
    const e = ex.executions[0];
    console.log(`event fired: trigger=${e.trigger} status=${e.status}`);
    console.log('  log:', (e.logs || '').trim().slice(0, 140));
    break;
  }
  if (i === 19) console.log('no event execution appeared');
  await new Promise(r => setTimeout(r, 2000));
}

// The negative read that matters.
const other = await fetch(`${EP}/account/sessions/email`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-appwrite-project': project }, body: JSON.stringify({ email: 'ewv@example.test', password: 'SpikePassword123' }) });
console.log('\n(ewv has the label, so is expected to see everything — the real negative is a ward outsider)');
