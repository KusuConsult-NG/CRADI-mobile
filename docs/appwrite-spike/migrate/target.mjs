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
 * @param {{ requireKey?: boolean }} [opts] `false` for a script that only ever
 *   acts as a signed-in user (`reconcile.mjs`), which needs no API key.
 */
let resolved = null;

export function appwriteTarget({ requireKey = true } = {}) {
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
  if (requireKey && !key) missing.push('AW_KEY');
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

/**
 * The password migrated accounts are created with, and that `reconcile.mjs`
 * then signs in as to compare visibility.
 *
 * It used to be the literal `MigratedPassword123`, in the repository, applied
 * to every account the seeder created. Fine for a spike against a throwaway
 * local stack; a disclosed shared credential for ~650 real accounts the moment
 * the same script is pointed at Cloud, which the runbook told an operator to
 * do. So it has no default.
 *
 * Note what this does *not* solve: Supabase password hashes are not carried
 * over by this script, so every migrated user's own password stops working
 * regardless. See `docs/CUTOVER-RUNBOOK.md` Phase 2 for the two ways out.
 */
export function migrationPassword() {
  const pw = process.env.MIGRATION_PASSWORD ?? '';
  if (pw.length < 8) {
    console.error(
      'MIGRATION_PASSWORD must be set (8+ characters). Both seed-identities.mjs' +
        ' and reconcile.mjs read it, and they must agree for the reconciliation' +
        ' gate to be able to sign in.',
    );
    process.exit(2);
  }
  return pw;
}
