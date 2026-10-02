/**
 * Stands up a project and an API key on the local Appwrite.
 *
 *   node infra/appwrite/local/bootstrap.mjs
 *
 * Writes `infra/appwrite/local/.env.local` (gitignored) with the project
 * id and key, so `provision.mjs` and the tests can source it.
 *
 * Adapted from the Phase 0 spike's `setup.mjs`. The scopes are wider —
 * these have to cover buckets, functions and messaging, which the spike
 * did not need.
 */
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

// `appwrite`, not `localhost`: the stack sets `_APP_DOMAIN: appwrite`
// so that a Function on the runtimes network can reach the API, and
// Appwrite routes by Host — a request arriving as `localhost:8090` gets
// the console's HTML instead of the API. The host side reaches the same
// name through `127.0.0.1 appwrite` in /etc/hosts; see the README.
const EP = process.env.LOCAL_ENDPOINT ?? 'http://appwrite.local:8090/v1';
/**
 * Overridable because a Function's variables are keyed project-wide and
 * **outlive the Function that owned them**. Delete and recreate a
 * Function and its variables become orphans that no API key can purge —
 * `projects.read` is console-only — and every later attempt to set that
 * key answers 409 while the Function runs with no configuration at all.
 * On a throwaway stack the cheapest fix is a new project.
 */
const PROJECT_ID = process.env.LOCAL_PROJECT_ID ?? 'cradi';

/** Every identifier a CRADI client reports. */
const PLATFORMS = [
  {
    type: 'flutter-android',
    name: 'Android',
    key: 'com.westgatestratagem.climate_app.climate_app',
  },
  {
    type: 'flutter-ios',
    name: 'iOS',
    key: 'com.westgatestratagem.climateapp.climateApp',
  },
  // What a `flutter test` VM reports, from the stub in
  // `test/integration/live_appwrite.dart`.
  { type: 'flutter-linux', name: 'Linux (integration tests)', key: 'com.cradi.test' },
];
const here = dirname(fileURLToPath(import.meta.url));
const jar = {};

async function call(path, { method = 'GET', body, project = 'console', key } = {}) {
  const headers = { 'content-type': 'application/json', 'x-appwrite-project': project };
  if (key) headers['x-appwrite-key'] = key;
  if (jar.cookie) headers.cookie = jar.cookie;
  const res = await fetch(`${EP}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  const setCookie = res.headers.get('set-cookie');
  if (setCookie) jar.cookie = setCookie.split(';')[0];
  const text = await res.text();
  let parsed;
  try { parsed = JSON.parse(text); } catch { parsed = text; }
  return { ok: res.ok, status: res.status, body: parsed };
}

const email = 'root@cradi.test';
const password = 'LocalRootPassword123';

const account = await call('/account', {
  method: 'POST',
  body: { userId: 'unique()', email, password, name: 'Local Root' },
});
console.log(account.ok ? 'root account created' : `root account: ${account.status}`);

const session = await call('/account/sessions/email', {
  method: 'POST',
  body: { email, password },
});
if (!session.ok) throw new Error(`sign-in failed: ${JSON.stringify(session.body).slice(0, 200)}`);
console.log('signed in');

const team = await call('/teams', {
  method: 'POST',
  body: { teamId: 'unique()', name: 'CRADI' },
});
if (!team.ok) throw new Error(`team failed: ${JSON.stringify(team.body).slice(0, 200)}`);

const project = await call('/projects', {
  method: 'POST',
  body: {
    projectId: PROJECT_ID,
    name: 'CRADI',
    teamId: team.body.$id,
    region: 'default',
  },
});
const projectId = project.ok ? project.body.$id : PROJECT_ID;
console.log(`project: ${projectId}${project.ok ? '' : ' (existing)'}`);

/**
 * Appwrite refuses a client it does not recognise:
 *
 *   general_unknown_origin: Invalid Origin. Register your new client
 *   (com.cradi.test) as a new Linux platform on your project console
 *
 * So every identifier the app ships under has to be registered, and so
 * does the one a Flutter test VM reports. This needs a console session
 * — `platforms.write` is not an API-key scope — which is why it lives
 * here and not in `provision.mjs`. On Cloud it is a console step.
 */
for (const platform of PLATFORMS) {
  const made = await call(`/projects/${projectId}/platforms`, {
    method: 'POST',
    body: platform,
  });
  console.log(
    `platform ${platform.type} ${platform.key}: ${made.ok ? 'created' : made.status}`,
  );
}

const key = await call(`/projects/${projectId}/keys`, {
  method: 'POST',
  body: {
    name: 'provisioner',
    scopes: [
      'users.read', 'users.write',
      'teams.read', 'teams.write',
      'databases.read', 'databases.write',
      'collections.read', 'collections.write',
      'attributes.read', 'attributes.write',
      'indexes.read', 'indexes.write',
      'documents.read', 'documents.write',
      'buckets.read', 'buckets.write',
      'files.read', 'files.write',
      'functions.read', 'functions.write',
      'execution.read', 'execution.write',
      'targets.read', 'targets.write',
      'providers.read', 'providers.write',
      'messages.read', 'messages.write',
      'topics.read', 'topics.write',
      'subscribers.read', 'subscribers.write',
      'sessions.write',
    ],
  },
});
if (!key.ok) throw new Error(`key failed: ${JSON.stringify(key.body).slice(0, 300)}`);

const envPath = resolve(here, '.env.local');
writeFileSync(
  envPath,
  `# Local Appwrite only. Generated by bootstrap.mjs; gitignored.\n` +
    `export APPWRITE_ENDPOINT='${EP}'\n` +
    `export APPWRITE_PROJECT_ID='${projectId}'\n` +
    `export APPWRITE_API_KEY='${key.body.secret}'\n` +
    `export APPWRITE_DATABASE_ID='cradi'\n`,
);
console.log(`wrote ${envPath}`);
console.log('\nsource infra/appwrite/local/.env.local');
