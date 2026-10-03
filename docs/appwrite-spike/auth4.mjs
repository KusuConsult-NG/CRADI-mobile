import { readFileSync } from 'node:fs';
const { project } = JSON.parse(readFileSync('env.json', 'utf8'));
const EP = 'http://localhost:8080/v1';
const cli = async (p, o = {}) => { const h = { 'content-type': 'application/json', 'x-appwrite-project': project }; if (o.cookie) h.cookie = o.cookie; const r = await fetch(`${EP}${p}`, { method: o.method ?? 'GET', headers: h, body: o.body ? JSON.stringify(o.body) : undefined }); return { status: r.status, body: await r.json().catch(() => null), cookie: (r.headers.get('set-cookie') ?? '').split(';')[0] }; };

const s = await cli('/account/sessions/email', { method: 'POST', body: { email: 'ewmb@example.test', password: 'SpikePassword123' } });
console.log('session expires:', s.body?.expire, '| provider:', s.body?.provider);
const list = await cli('/account/sessions', { cookie: s.cookie });
console.log('sessions listed:', list.status, '| count:', list.body?.total, '| fields:', Object.keys(list.body?.sessions?.[0] ?? {}).filter(k => /ip|device|os|client|country|current/i.test(k)).join(','));
const refreshed = await cli(`/account/sessions/${s.body.$id}`, { method: 'PATCH', cookie: s.cookie });
console.log('refresh (PATCH /account/sessions/{id}):', refreshed.status, refreshed.body?.expire ?? JSON.stringify(refreshed.body?.message).slice(0,60));
const one = await cli(`/account/sessions/${s.body.$id}`, { method: 'DELETE', cookie: s.cookie });
console.log('delete one session:', one.status);
