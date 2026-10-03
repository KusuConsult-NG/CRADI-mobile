/** Phase 0 spike: stand up a project, API key, database. */
const EP = 'http://localhost:8080/v1';
const jar = {};

async function call(path, { method = 'GET', body, project = 'console', key, json = true } = {}) {
  const headers = { 'content-type': 'application/json', 'x-appwrite-project': project };
  if (key) headers['x-appwrite-key'] = key;
  if (jar.cookie) headers['cookie'] = jar.cookie;
  const res = await fetch(`${EP}${path}`, { method, headers, body: body ? JSON.stringify(body) : undefined });
  const setCookie = res.headers.get('set-cookie');
  if (setCookie) jar.cookie = setCookie.split(';')[0];
  const text = await res.text();
  let parsed; try { parsed = JSON.parse(text); } catch { parsed = text; }
  if (!res.ok && json) throw new Error(`${method} ${path} -> ${res.status}: ${text.slice(0, 300)}`);
  return parsed;
}

const email = 'spike@example.test', password = 'SpikePassword123';
try {
  await call('/account', { method: 'POST', body: { userId: 'unique()', email, password, name: 'Spike Root' } });
  console.log('root account created');
} catch (e) { console.log('root account exists or:', String(e).slice(0, 120)); }

await call('/account/sessions/email', { method: 'POST', body: { email, password } });
console.log('signed in');

const team = await call('/teams', { method: 'POST', body: { teamId: 'unique()', name: 'Spike Org' } });
const project = await call('/projects', { method: 'POST', body: { projectId: 'cradi-spike', name: 'CRADI Spike', teamId: team.$id, region: 'default' } });
console.log('project:', project.$id);

const apiKey = await call(`/projects/${project.$id}/keys`, {
  method: 'POST',
  body: { name: 'spike', scopes: [
    'users.read','users.write','teams.read','teams.write',
    'databases.read','databases.write','collections.read','collections.write',
    'attributes.read','attributes.write','indexes.read','indexes.write',
    'documents.read','documents.write','sessions.write',
  ] },
});
console.log('API key created');

const { writeFileSync } = await import('node:fs');
writeFileSync('env.json', JSON.stringify({ project: project.$id, key: apiKey.secret }, null, 2));
console.log('wrote env.json');
