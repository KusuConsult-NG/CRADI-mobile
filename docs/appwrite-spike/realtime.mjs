/** Q3: does Realtime survive per-document ACLs, and is it filtered? */
import { readFileSync } from 'node:fs';
const { project, key } = JSON.parse(readFileSync('env.json', 'utf8'));
const EP = 'http://localhost:8080/v1';

async function admin(path, { method = 'GET', body } = {}) {
  const res = await fetch(`${EP}${path}`, {
    method, headers: { 'content-type': 'application/json', 'x-appwrite-project': project, 'x-appwrite-key': key },
    body: body ? JSON.stringify(body) : undefined,
  });
  const t = await res.text();
  if (!res.ok) throw new Error(`${method} ${path} -> ${res.status}: ${t.slice(0, 200)}`);
  return t ? JSON.parse(t) : null;
}
async function cookieFor(email) {
  const res = await fetch(`${EP}/account/sessions/email`, {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-appwrite-project': project },
    body: JSON.stringify({ email, password: 'SpikePassword123' }),
  });
  return (res.headers.get('set-cookie') ?? '').split(';')[0];
}

// ewm-b is in ward B only.
const cookie = await cookieFor('ewmb@example.test');
const url = `ws://localhost:8081/v1/realtime?project=${project}&channels[]=databases.cradi.collections.reports.documents`;
const seen = [];
const { default: WS } = await import('ws');
const ws = new WS(url, { headers: { cookie } });

const opened = new Promise((resolve, reject) => {
  ws.addEventListener('open', () => resolve('open'));
  ws.addEventListener('error', (e) => reject(new Error('ws error: ' + (e.message ?? 'unknown'))));
});
ws.addEventListener('message', (ev) => {
  const msg = JSON.parse(ev.data);
  if (msg.type === 'event' && msg.data?.payload?.$id) seen.push(msg.data.payload.$id);
  if (msg.type === 'error') seen.push('ERROR:' + JSON.stringify(msg.data).slice(0, 120));
});

await opened;
console.log('realtime: connected as ewm-b');
await new Promise((r) => setTimeout(r, 1500));

const wardA = 'ward-benue-makurdi-centre', wardB = 'ward-benue-makurdi-north';
async function make(id, teamId) {
  await admin('/databases/cradi/collections/reports/documents', {
    method: 'POST',
    body: {
      documentId: id,
      data: { state: 'Benue', lga: 'Makurdi', ward: id, title: 'live ' + id },
      permissions: ['read("user:citizen")', `read("team:${teamId}")`, 'read("label:ewv")'],
    },
  });
}
await make('live-a-' + Date.now().toString().slice(-5), wardA);
await new Promise((r) => setTimeout(r, 1200));
await make('live-b-' + Date.now().toString().slice(-5), wardB);
await new Promise((r) => setTimeout(r, 2500));
ws.close();

const a = seen.filter((s) => s.startsWith('live-a')).length;
const b = seen.filter((s) => s.startsWith('live-b')).length;
console.log(`  events for the OTHER ward (ward A): ${a}  (expected 0)`);
console.log(`  events for THIS ward  (ward B): ${b}  (expected 1)`);
console.log(`  raw: ${JSON.stringify(seen)}`);
