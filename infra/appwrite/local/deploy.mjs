/**
 * Pushes the Function code to the local Appwrite and waits for builds.
 *
 *   source infra/appwrite/local/.env.local
 *   node infra/appwrite/local/deploy.mjs
 *
 * All seven share one source tree (`functions/cradi`) and differ only by
 * entrypoint, so this uploads the same tarball seven times.
 *
 * The Appwrite CLI does this too. A script is used here because the CLI
 * wants an interactive login and this has to run unattended.
 */
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

import { FUNCTIONS } from '../plan.mjs';

const EP = process.env.APPWRITE_ENDPOINT;
const PROJECT = process.env.APPWRITE_PROJECT_ID;
const KEY = process.env.APPWRITE_API_KEY;
if (!EP || !PROJECT || !KEY) {
  console.error('source infra/appwrite/local/.env.local first');
  process.exit(2);
}

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '../../../functions/cradi');
const tarball = '/tmp/cradi-functions.tar.gz';

const H = { 'x-appwrite-project': PROJECT, 'x-appwrite-key': KEY };
const api = async (path, init = {}) => {
  const r = await fetch(`${EP}${path}`, {
    ...init,
    headers: { 'content-type': 'application/json', ...H, ...(init.headers ?? {}) },
  });
  return { status: r.status, ok: r.ok, body: await r.json().catch(() => null) };
};

// Exclude the tests: they are 60% of the tree and a Function that ships
// its own test harness pays for it on every cold start.
execFileSync('tar', [
  '-czf', tarball, '-C', root,
  '--exclude=test', '--exclude=tools', '--exclude=node_modules',
  'package.json', 'src',
]);
console.log(`packaged ${(readFileSync(tarball).length / 1024).toFixed(0)}KB`);

/**
 * Inside a Function, Appwrite is reachable on the compose network, not
 * on the host port. `http://appwrite.local/v1` is the service name — the
 * localhost URL the provisioner uses would resolve to the Function's
 * own container.
 */
const VARIABLES = {
  // Appwrite injects APPWRITE_FUNCTION_API_ENDPOINT itself, pointing at
  // the project's public domain — which a runtime container cannot
  // reach, because it is on the runtimes network and the domain
  // resolves outside it. `lib/appwrite.js` prefers the injected one,
  // correctly, since on Cloud it is right. So override it here.
  APPWRITE_FUNCTION_API_ENDPOINT: 'http://appwrite.local/v1',
  APPWRITE_ENDPOINT: 'http://appwrite.local/v1',
  APPWRITE_PROJECT: PROJECT,
  APPWRITE_API_KEY: KEY,
  APPWRITE_DATABASE_ID: process.env.APPWRITE_DATABASE_ID ?? 'cradi',
};

const deployments = [];
let problems = 0;

for (const fn of FUNCTIONS) {
  // Clear first, then set. A variable is addressed by its generated
  // `$id`, not by its key, so the obvious `PUT .../variables/<key>`
  // silently does nothing — which is how seven Functions ran with none
  // of their configuration and reported only "fetch failed".
  const existing = await api(`/functions/${fn.id}/variables`);
  for (const v of existing.body?.variables ?? []) {
    await api(`/functions/${fn.id}/variables/${v.$id}`, { method: 'DELETE' });
  }
  for (const [key, value] of Object.entries(VARIABLES)) {
    const made = await api(`/functions/${fn.id}/variables`, {
      method: 'POST',
      // `variableId` became required in 1.9; without it the create is
      // refused 400 and the Function runs with no configuration at all.
      body: JSON.stringify({ variableId: 'unique()', key, value }),
    });
    if (!made.ok) {
      // Loudly. A missing variable is not a cosmetic failure here.
      console.log(`  ! ${fn.id} var ${key}: ${made.status} ${made.body?.message ?? ''}`);
      problems += 1;
    }
  }

  const form = new FormData();
  form.append('entrypoint', fn.entrypoint);
  form.append('activate', 'true');
  form.append(
    'code',
    new Blob([readFileSync(tarball)], { type: 'application/gzip' }),
    'code.tar.gz',
  );
  const res = await fetch(`${EP}/functions/${fn.id}/deployments`, {
    method: 'POST',
    headers: H,
    body: form,
  });
  const body = await res.json().catch(() => null);
  if (!res.ok) {
    console.log(`! ${fn.id}: ${res.status} ${body?.message ?? ''}`);
    continue;
  }
  deployments.push([fn.id, body.$id]);
  console.log(`+ ${fn.id} -> ${body.$id}`);
}

console.log('\nwaiting for builds…');
let failed = 0;
for (const [id, deploymentId] of deployments) {
  let status = 'unknown';
  for (let i = 0; i < 60; i++) {
    const d = await api(`/functions/${id}/deployments/${deploymentId}`);
    status = d.body?.status ?? 'unknown';
    if (['ready', 'failed'].includes(status)) break;
    await new Promise((r) => setTimeout(r, 3000));
  }
  console.log(`  ${status === 'ready' ? '+' : '!'} ${id}: ${status}`);
  if (status !== 'ready') {
    failed += 1;
    const d = await api(`/functions/${id}/deployments/${deploymentId}`);
    const logs = d.body?.buildLogs ?? '';
    if (logs) console.log(`    ${logs.slice(-500).replace(/\n/g, '\n    ')}`);
  }
}

// A build that did not reach `ready` answers every call with a 500 and
// looks healthy in the console, so it must not exit 0.
if (failed || problems) process.exit(1);
console.log('\nall builds ready');
