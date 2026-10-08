/**
 * Where these scripts point, and with what credentials.
 *
 * They were written against the local stack, so three of the four baked the
 * endpoint in (`http://localhost:8080/v1`) and read the project and key from
 * the spike's `env.json`. The cutover runbook then told an operator to pass
 * `AW_ENDPOINT` / `AW_PROJECT` / `AW_KEY` — which only `migrate.mjs` read. The
 * other three ignored all three variables and went to localhost, or died on a
 * missing file, while the runbook presented the step as "run this against
 * Appwrite Cloud".
 *
 * That is the expensive class of mistake on this project specifically, because
 * Appwrite answers an unpermitted or misdirected read with `200 {"total": 0}`
 * rather than an error: a migration aimed at the wrong project does not fail,
 * it reports that there was nothing to do.
 *
 * So, in order: the environment wins, the spike's own `env.json` is the
 * fallback for local runs, and anything missing is fatal here — at startup,
 * naming what to set — rather than a 401 forty rows in.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
/** `setup.mjs` writes it beside itself, one level up from this directory. */
const SPIKE_ENV = resolve(HERE, '..', 'env.json');

function fromFile() {
  try {
    const { project, key } = JSON.parse(readFileSync(SPIKE_ENV, 'utf8'));
    return { project, key, source: SPIKE_ENV };
  } catch {
    return null;
  }
}

/**
 * Resolves the Appwrite target, or exits non-zero explaining what is missing.
 *
 * The key is required by all four scripts. `reconcile.mjs` used to be the
 * exception — it signed in as each user with the shared seed password — but
 * since the seeder imports Supabase's bcrypt hashes, nobody knows any user's
 * password and the gate mints its sessions with the key instead.
 */
let resolved = null;

export function appwriteTarget() {
  // Memoised: `seed-identities.mjs` imports `migrate.mjs` for `wardTeam`, so
  // two modules in one process ask for the target. One resolution, one log
  // line, and no way for the two to disagree.
  if (resolved) return resolved;
  const endpoint = (process.env.AW_ENDPOINT ?? 'http://localhost:8080/v1').trim();
  const file = fromFile();
  const project = (process.env.AW_PROJECT ?? file?.project ?? '').trim();
  const key = (process.env.AW_KEY ?? file?.key ?? '').trim();

  const missing = [];
  if (!project) missing.push('AW_PROJECT');
  if (!key) missing.push('AW_KEY');
  if (missing.length) {
    console.error(
      `Cannot reach Appwrite: ${missing.join(' and ')} not set, and ${SPIKE_ENV}` +
        ` ${file ? 'does not supply it' : 'does not exist'}.\n` +
        'Set AW_ENDPOINT / AW_PROJECT / AW_KEY for Cloud, or run the spike\'s' +
        ' setup.mjs for a local stack.',
    );
    process.exit(2);
  }

  // Said out loud, every run. The whole failure mode this guards against is a
  // run that looked right because nobody could see where it went.
  console.error(`appwrite: ${endpoint} project ${project}`);

  const headers = {
    'content-type': 'application/json',
    'x-appwrite-project': project,
    ...(key ? { 'x-appwrite-key': key } : {}),
  };
  const aw = async (path, init = {}) => {
    const r = await fetch(`${endpoint}${path}`, { ...init, headers });
    return { status: r.status, body: await r.json().catch(() => null) };
  };
  resolved = { endpoint, project, key, headers, aw };
  return resolved;
}
