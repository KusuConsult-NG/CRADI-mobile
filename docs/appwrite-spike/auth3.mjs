import { readFileSync } from 'node:fs';
const { project, key } = JSON.parse(readFileSync('env.json', 'utf8'));
const EP = 'http://localhost:8080/v1';
const srv = async (p, o = {}) => { const r = await fetch(`${EP}${p}`, { method: o.method ?? 'GET', headers: { 'content-type': 'application/json', 'x-appwrite-project': project, 'x-appwrite-key': key }, body: o.body ? JSON.stringify(o.body) : undefined }); return { status: r.status, body: await r.json().catch(() => null) }; };
const cli = async (p, o = {}) => { const h = { 'content-type': 'application/json', 'x-appwrite-project': project }; if (o.cookie) h.cookie = o.cookie; const r = await fetch(`${EP}${p}`, { method: o.method ?? 'GET', headers: h, body: o.body ? JSON.stringify(o.body) : undefined }); return { status: r.status, body: await r.json().catch(() => null), cookie: (r.headers.get('set-cookie') ?? '').split(';')[0] }; };

const id = 'auth3' + Date.now().toString().slice(-6);
const email = `${id}@example.test`;
await srv('/users', { method: 'POST', body: { userId: id, email, password: 'SpikePassword123', name: 'Auth Three' } });
const sess = await cli('/account/sessions/email', { method: 'POST', body: { email, password: 'SpikePassword123' } });

console.log('--- built-ins are link-based (localhost url now allowed)');
const v = await cli('/account/verification', { method: 'POST', body: { url: 'http://localhost/verify' }, cookie: sess.cookie });
console.log('  /account/verification ->', v.status, v.status < 400 ? `secret=${JSON.stringify(v.body.secret)} (empty = emailed as a link)` : JSON.stringify(v.body?.message).slice(0,70));
const r = await cli('/account/recovery', { method: 'POST', body: { email, url: 'http://localhost/reset' } });
console.log('  /account/recovery     ->', r.status, r.status < 400 ? `secret=${JSON.stringify(r.body.secret)}` : JSON.stringify(r.body?.message).slice(0,70));

console.log('\n--- the code-based route we would actually build');
console.log('  1. mint    POST /users/{id}/tokens {length:6}');
const tok = await srv(`/users/${id}/tokens`, { method: 'POST', body: { length: 6, expire: 900 } });
console.log('     ->', tok.status, JSON.stringify(tok.body?.secret));
console.log('  2. user types it: POST /account/sessions/token');
const s2 = await cli('/account/sessions/token', { method: 'POST', body: { userId: id, secret: tok.body?.secret } });
console.log('     ->', s2.status, s2.status < 400 ? 'session established' : '');
console.log('  3a. mark verified server-side: PATCH /users/{id}/verification');
const mv = await srv(`/users/${id}/verification`, { method: 'PATCH', body: { emailVerification: true } });
console.log('     ->', mv.status, `emailVerification=${mv.body?.emailVerification}`);
console.log('  3b. set password server-side (recovery): PATCH /users/{id}/password');
const pw = await srv(`/users/${id}/password`, { method: 'PATCH', body: { password: 'BrandNewPassword456' } });
console.log('     ->', pw.status);
const relog = await cli('/account/sessions/email', { method: 'POST', body: { email, password: 'BrandNewPassword456' } });
console.log('  4. sign in with the new password ->', relog.status);
const old = await cli('/account/sessions/email', { method: 'POST', body: { email, password: 'SpikePassword123' } });
console.log('  5. old password refused ->', old.status);
