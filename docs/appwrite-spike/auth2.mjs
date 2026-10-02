import { readFileSync } from 'node:fs';
const { project, key } = JSON.parse(readFileSync('env.json', 'utf8'));
const EP = 'http://localhost:8080/v1';
async function srv(path, { method = 'GET', body } = {}) {
  const r = await fetch(`${EP}${path}`, { method, headers: { 'content-type': 'application/json', 'x-appwrite-project': project, 'x-appwrite-key': key }, body: body ? JSON.stringify(body) : undefined });
  return { status: r.status, body: await r.json().catch(() => null) };
}
async function client(path, { method = 'GET', body, cookie } = {}) {
  const h = { 'content-type': 'application/json', 'x-appwrite-project': project };
  if (cookie) h.cookie = cookie;
  const r = await fetch(`${EP}${path}`, { method, headers: h, body: body ? JSON.stringify(body) : undefined });
  return { status: r.status, body: await r.json().catch(() => null), cookie: (r.headers.get('set-cookie') ?? '').split(';')[0] };
}
const id = 'auth2' + Date.now().toString().slice(-6);
const email = `${id}@example.test`;
await srv('/users', { method: 'POST', body: { userId: id, email, password: 'SpikePassword123', name: 'Auth Two' } });
const sess = await client('/account/sessions/email', { method: 'POST', body: { email, password: 'SpikePassword123' } });

console.log('--- Q1: email verification (1.6 path)');
const v = await client('/account/verification', { method: 'POST', body: { url: 'https://example.test/verify' }, cookie: sess.cookie });
console.log('  POST /account/verification ->', v.status, v.status >= 400 ? JSON.stringify(v.body?.message).slice(0,90) : `keys=${Object.keys(v.body).join(',')} secret=${JSON.stringify(v.body.secret)}`);

console.log('--- Q2: password recovery (1.6 path)');
const r = await client('/account/recovery', { method: 'POST', body: { email, url: 'https://example.test/reset' } });
console.log('  POST /account/recovery    ->', r.status, r.status >= 400 ? JSON.stringify(r.body?.message).slice(0,90) : `keys=${Object.keys(r.body).join(',')} secret=${JSON.stringify(r.body.secret)}`);

console.log('\n--- Q4: can a server-minted 6-digit token become a real session?');
const tok = await srv(`/users/${id}/tokens`, { method: 'POST', body: { length: 6, expire: 900 } });
console.log('  minted secret:', JSON.stringify(tok.body?.secret));
const made = await client('/account/sessions/token', { method: 'POST', body: { userId: id, secret: tok.body?.secret } });
console.log('  POST /account/sessions/token ->', made.status, made.status < 400 ? `session ${made.body.$id} for ${made.body.userId}` : JSON.stringify(made.body?.message).slice(0,100));

console.log('\n--- Q5: and does a wrong code fail?');
const bad = await client('/account/sessions/token', { method: 'POST', body: { userId: id, secret: '000000' } });
console.log('  wrong secret ->', bad.status, JSON.stringify(bad.body?.message).slice(0, 80));
