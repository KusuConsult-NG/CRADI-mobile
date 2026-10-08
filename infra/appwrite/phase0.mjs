#!/usr/bin/env node
/**
 * Phase 0 of the cutover, in one command. Writes no migrated data.
 *
 *   APPWRITE_ENDPOINT=https://fra.cloud.appwrite.io/v1 \
 *   APPWRITE_PROJECT_ID=... APPWRITE_API_KEY=... \
 *   node infra/appwrite/phase0.mjs
 *
 * This is first contact with the real project, and the one thing the test
 * harness in `docs/appwrite-spike/migrate` cannot answer: it models how Appwrite
 * evaluates ACLs, and only Appwrite can confirm the model. So it runs, in order
 * and stopping at the first failure:
 *
 *   1. **preflight** — are the three variables set, and is the endpoint
 *      reachable at all? A denied CONNECT and a rejected API key look nothing
 *      alike and must not be reported alike.
 *   2. **verify.mjs** — does the live project match `plan.mjs`? Read-only.
 *   3. **cloud-check.mjs** — does it *behave*? Eight probes that need a write
 *      to answer. Everything it creates is named `cloudchk-<stamp>` and deleted
 *      at the end, including after a failure.
 *
 * It deliberately does **not** run `seed-identities.mjs`, `copy-tables.mjs` or
 * `copy-storage.mjs`. Those are the migration, they need Supabase credentials
 * and a write freeze, and `seed-identities.mjs` sets a shared password on every
 * real account — a decision Phase 5.1 of the runbook leaves open. Phase 0 is
 * what you run before any of that, and on its own it changes nothing you would
 * have to undo.
 *
 * Exits 0 when the project is ready for Phase 1, 2 when it is not configured or
 * not reachable, 1 when a check failed.
 */
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, '..', '..');

const REQUIRED = ['APPWRITE_ENDPOINT', 'APPWRITE_PROJECT_ID', 'APPWRITE_API_KEY'];

const value = (name) => (process.env[name] ?? '').trim();

function preflightEnv() {
  const missing = REQUIRED.filter((n) => !value(n));
  if (missing.length) {
    console.error(`Not configured: ${missing.join(', ')} ${missing.length > 1 ? 'are' : 'is'} unset.`);
    console.error(
      '\nThese belong in the environment, never on the command line or in a file\n' +
        'in the repository — this one has leaked three credentials into public\n' +
        'history already. The API key needs database, users, teams, functions and\n' +
        'storage scopes.',
    );
    return false;
  }
  // Said out loud before anything else: the costly mistake on this project is a
  // run that looked right because nobody could see where it went.
  console.log(`endpoint   ${value('APPWRITE_ENDPOINT')}`);
  console.log(`project    ${value('APPWRITE_PROJECT_ID')}`);
  console.log(`database   ${value('APPWRITE_DATABASE_ID') || 'cradi (default)'}`);
  console.log(`api key    ${value('APPWRITE_API_KEY').slice(0, 6)}… (${value('APPWRITE_API_KEY').length} chars)`);
  if (value('APPWRITE_BUCKET_ID')) {
    console.error(
      '\nAPPWRITE_BUCKET_ID is set. Unset it: `verify.mjs` reads it as a note only\n' +
        'now, but `plan.mjs` still takes it as the single-bucket id, so a stale\n' +
        'value describes a bucket the last provisioning run never made.',
    );
    return false;
  }
  return true;
}

/**
 * Which database everything will use, and whether they will agree.
 *
 * `verify.mjs` cannot answer this, and it is worth being precise about why:
 * `plan.mjs` takes `DATABASE_ID` from the same `APPWRITE_DATABASE_ID`, so a
 * passing verify means "the database this variable names matches the plan". It
 * says nothing about whether that is the database the app reads. The two
 * questions look identical in the output and are not.
 *
 * Five places resolve this independently, and every one of them defaults to
 * `cradi`. If the variable says anything else, all five must carry it — and the
 * Flutter one is a compile-time define, so it is baked into the APK and cannot
 * be changed afterwards. Get it wrong and the data sits in one database while
 * the app reads another, which Appwrite answers with `200 {"total": 0}`: an
 * empty app and no error anywhere.
 */
async function preflightDatabase() {
  const url = value('APPWRITE_ENDPOINT').replace(/\/+$/, '');
  const head = {
    'x-appwrite-project': value('APPWRITE_PROJECT_ID'),
    'x-appwrite-key': value('APPWRITE_API_KEY'),
  };
  const inUse = value('APPWRITE_DATABASE_ID') || 'cradi';

  let found = null;
  try {
    const r = await fetch(`${url}/tablesdb`, { headers: head, signal: AbortSignal.timeout(20_000) });
    if (r.ok) {
      const body = await r.json().catch(() => null);
      const list = body?.databases ?? body?.tablesDB ?? body?.tablesdb ?? null;
      if (Array.isArray(list)) found = list.map((d) => String(d.$id));
    }
  } catch {
    // Not fatal: the listing is a diagnosis, and the two checks that decide the
    // exit code do not depend on it.
  }

  if (!found) {
    console.log(`\ndatabases  could not be listed; proceeding with "${inUse}"`);
    return true;
  }

  console.log(`\ndatabases  ${found.map((d) => (d === inUse ? `${d}  <- in use` : d)).join('\n           ')}`);

  if (!found.includes(inUse)) {
    console.error(
      `\n"${inUse}" is not among them. Provision it, or correct` +
        ' APPWRITE_DATABASE_ID.',
    );
    return false;
  }

  const extras = found.filter((d) => d !== inUse);
  if (extras.length) {
    /*
     * An extra database is not harmless, and which way it bites depends on
     * whether it is the default.
     *
     * A component resolves the database on its own, and every one of them falls
     * back to `cradi`. So while a leftover NON-default database exists, a
     * component still carrying that old id reads a valid, empty database and is
     * answered `200 {"total": 0}` — an empty screen and no error. Delete it and
     * the same component gets a 404 instead: still broken, but loudly, and
     * traceable in one step.
     *
     * Before anything is migrated both are empty and a stale pointer costs
     * nothing. After Phase 2 the real data is in one of them, and that is when
     * the silence matters. So this is worth clearing up now rather than then.
     */
    console.log(
      `\n${extras.length} other database(s) in this project: ${extras.join(', ')}`,
    );
    console.log(
      '  Nothing here reads them — every component defaults to "cradi" — so they\n' +
        '  are only reachable by something still carrying the old id. While they\n' +
        '  exist, such a component reads an empty database and is answered 200 with\n' +
        '  no rows; without them it gets a 404. The second is far easier to find,\n' +
        '  and before Phase 2 both are equally empty, so now is the cheap moment to\n' +
        '  remove them.',
    );
  }

  if (value('APPWRITE_DATABASE_ID') && value('APPWRITE_DATABASE_ID') !== 'cradi') {
    console.log(
      `\nAPPWRITE_DATABASE_ID is "${inUse}", not the default "cradi". Five things\n` +
        '  resolve the database independently and each defaults to "cradi", so all\n' +
        '  five must say "' + inUse + '":\n' +
        '    - the two Appwrite Functions   APPWRITE_DATABASE_ID, set per Function\n' +
        '    - the admin, server side       APPWRITE_DATABASE_ID\n' +
        '    - the admin, browser side      NEXT_PUBLIC_APPWRITE_DATABASE_ID\n' +
        '    - the Flutter app              APPWRITE_DATABASE_ID in env.json — a\n' +
        '                                   COMPILE-TIME define, baked into the APK\n' +
        '    - the migration scripts        APPWRITE_DATABASE_ID in this shell\n' +
        '\n  verify.mjs cannot catch a mismatch: plan.mjs takes its id from this same\n' +
        '  variable, so it checks the database you named, whichever one that is.',
    );
  }
  return true;
}

/**
 * Is the endpoint reachable, and is it Appwrite?
 *
 * `/health/version` needs no key, so a failure here is the network or the URL
 * and nothing else. Worth its own step because the failure modes are confusable
 * and expensive: a proxy or policy denial answers CONNECT with 403 and surfaces
 * as an opaque `fetch failed`, which reads exactly like a bad endpoint, which
 * reads nothing like a rejected key — and only the last of those is about the
 * project.
 */
async function preflightReach() {
  const url = `${value('APPWRITE_ENDPOINT').replace(/\/+$/, '')}/health/version`;
  let r;
  try {
    r = await fetch(url, { signal: AbortSignal.timeout(20_000) });
  } catch (e) {
    const cause = String(e.cause?.message ?? e.message);
    console.error(`\nCannot reach ${url}\n  ${cause}`);
    console.error(
      '\nNothing was contacted, so this says nothing about the project. If the\n' +
        'host is blocked by a network policy rather than down, the policy is what\n' +
        'has to change — a credential will not help.',
    );
    return false;
  }
  const text = await r.text();
  let body = null;
  try {
    body = JSON.parse(text);
  } catch {
    // Not JSON at all, so whatever answered was not Appwrite.
  }

  if (!r.ok || !body) {
    // A gateway, proxy or egress policy that refuses the host answers with its
    // own status and its own body — not Appwrite's. Blaming the endpoint or the
    // key here is the mistake this step exists to prevent, so relay what
    // actually answered.
    const said = text.trim().slice(0, 200) || '(empty body)';
    console.error(`\n${url} answered ${r.status}, and not as Appwrite would.`);
    console.error(`  it said: ${said}`);
    console.error(
      '\nNothing reached the project, so this says nothing about it or about the\n' +
        'API key. Something between here and the host refused the request — most\n' +
        'often a network egress policy that does not list it. That is what has to\n' +
        'change; no credential will help.',
    );
    return false;
  }
  console.log(`reachable  Appwrite ${body.version ?? '(version not reported)'}`);
  return true;
}

function run(label, script, args = []) {
  return new Promise((done) => {
    console.log(`\n${'─'.repeat(72)}\n${label}\n${'─'.repeat(72)}`);
    const child = spawn(process.execPath, [resolve(HERE, script), ...args], {
      cwd: REPO,
      stdio: 'inherit',
      env: process.env,
    });
    child.on('close', (code) => done(code ?? 1));
  });
}

const single = process.argv.includes('--single-bucket');

if (!preflightEnv()) process.exit(2);
if (!(await preflightReach())) process.exit(2);
if (!(await preflightDatabase())) process.exit(2);

const verify = await run(
  'verify.mjs — does the project match plan.mjs? (read-only)',
  'verify.mjs',
  single ? ['--single-bucket'] : [],
);
if (verify !== 0) {
  console.error(
    `\nPhase 0 stopped: verify.mjs exited ${verify}.\n` +
      'Provision what is missing (`node infra/appwrite/provision.mjs`) and run\n' +
      'this again. Nothing was written.',
  );
  process.exit(verify === 2 ? 2 : 1);
}

const behaves = await run(
  'cloud-check.mjs — does the project behave? (creates and deletes cloudchk-* rows)',
  'cloud-check.mjs',
);
if (behaves !== 0) {
  console.error(
    `\nPhase 0 stopped: cloud-check.mjs exited ${behaves}.\n` +
      'Read its last assertion — it names the behaviour that differed. If it\n' +
      'reported that cleanup failed, remove the `cloudchk-*` rows it names\n' +
      'before running anything else.',
  );
  process.exit(behaves === 2 ? 2 : 1);
}

console.log(`\n${'─'.repeat(72)}`);
console.log('Phase 0 passed. The project matches the plan and behaves as the');
console.log('migration assumes. Nothing was migrated.');
console.log('\nStill to decide before Phase 2, both in docs/CUTOVER-RUNBOOK.md:');
console.log('  5.1  what happens to everyone\'s password — the seeder sets one');
console.log('       shared password on every account, so every user\'s own stops');
console.log('       working. The hash-import alternative is unimplemented.');
console.log('  4.3  the write freeze. Migrating an unfrozen database makes');
console.log('       whether a row survives depend on when the copier read it.');
