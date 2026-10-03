import { readFileSync, writeFileSync } from 'node:fs';
const EP = 'http://localhost:8080/v1';
const jar = {};
async function call(path, { method = 'GET', body } = {}) {
  const headers = { 'content-type': 'application/json', 'x-appwrite-project': 'console' };
  if (jar.cookie) headers.cookie = jar.cookie;
  const res = await fetch(`${EP}${path}`, { method, headers, body: body ? JSON.stringify(body) : undefined });
  const sc = res.headers.get('set-cookie'); if (sc) jar.cookie = sc.split(';')[0];
  const t = await res.text(); if (!res.ok) throw new Error(`${path} ${res.status}: ${t.slice(0,200)}`);
  return JSON.parse(t);
}
await call('/account/sessions/email', { method: 'POST', body: { email: 'spike@example.test', password: 'SpikePassword123' } });
const k = await call('/projects/cradi-spike/keys', { method: 'POST', body: { name: 'spike-full', scopes: [
  'users.read','users.write','teams.read','teams.write',
  'databases.read','databases.write','collections.read','collections.write',
  'attributes.read','attributes.write','indexes.read','indexes.write',
  'documents.read','documents.write','sessions.write',
  'files.read','files.write','buckets.read','buckets.write',
  'targets.read','targets.write','messages.read','messages.write',
  'topics.read','topics.write','subscribers.read','subscribers.write','providers.read','providers.write',
] } });
const env = JSON.parse(readFileSync('env.json','utf8'));
writeFileSync('env.json', JSON.stringify({ ...env, key: k.secret }, null, 2));
console.log('key upgraded with storage + messaging scopes');
