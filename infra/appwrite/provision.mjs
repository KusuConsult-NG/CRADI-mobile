#!/usr/bin/env node
/**
 * Brings an Appwrite project to the state `plan.mjs` declares.
 *
 *   APPWRITE_ENDPOINT=https://<region>.cloud.appwrite.io/v1 \
 *   APPWRITE_PROJECT_ID=... APPWRITE_API_KEY=... \
 *   node infra/appwrite/provision.mjs [--dry-run] [--only=collections,buckets,...]
 *
 * **Idempotent.** Every step checks before it writes and reports
 * `created` / `exists` / `updated`, so a half-finished run is resumed by
 * running it again. That is not a nicety: Phase 4 lost a whole project to
 * `docker compose down` on a volumeless MariaDB, and the only reason it
 * was cheap is that the spike was scripted. This is the same insurance
 * for the real project.
 *
 * **It does not create the project**, the region, or the API key. Those
 * are console actions, and the region is a decision nobody should make
 * from a script — see the README.
 *
 * **It never deletes anything.** A column that is in the project and not
 * in the plan is reported, not dropped. Dropping a column drops its data,
 * and this is a tool that will be run against a project holding live
 * reports.
 */
import {
  BUCKETS,
  COLLECTIONS,
  DATABASE_ID,
  DATABASE_NAME,
  ENDPOINT as PLANNED_ENDPOINT,
  FUNCTIONS,
  FUNCTION_VERSION,
  SINGLE_BUCKET,
} from './plan.mjs';

const ENDPOINT = process.env.APPWRITE_ENDPOINT ?? PLANNED_ENDPOINT;
const PROJECT = process.env.APPWRITE_PROJECT_ID;
const KEY = process.env.APPWRITE_API_KEY;

const args = new Set(process.argv.slice(2));
const DRY = args.has('--dry-run');
// For a tier that allows one bucket. The previous project ran this way.
const SINGLE = args.has('--single-bucket');
/**
 * Keep going past a quota refusal and report every limit at the end.
 *
 * Stopping is right when provisioning for real — everything after the
 * first refusal fails the same way and buries the reason. It is wrong
 * when the question being asked *is* "what does this plan allow",
 * because then each limit costs a whole round trip to discover. This
 * mode answers the whole question in one run.
 */
const PROBE = args.has('--probe');
const only = [...args].find((a) => a.startsWith('--only='))?.slice(7)?.split(',');
const wants = (step) => !only || only.includes(step);

if (PROBE) {
  console.log(
    '# probe: continuing past quota refusals to find every limit in one run',
  );
}

const tally = { created: 0, exists: 0, updated: 0, skipped: 0, failed: 0, extra: 0 };
const notes = [];
/** Every quota refusal seen, when --probe keeps going past them. */
const limits = [];

function say(state, what, detail = '') {
  tally[state] = (tally[state] ?? 0) + 1;
  const mark = { created: '+', exists: '=', updated: '~', skipped: '.', failed: '!', extra: '?' }[state];
  console.log(`${mark} ${what}${detail ? `  ${detail}` : ''}`);
}

async function api(path, { method = 'GET', body } = {}) {
  if (DRY) {
    // A dry run touches nothing, including reads: the point is to print
    // the plan against an empty project, from a machine that may have no
    // route to Appwrite at all. So every read answers 404 — "not there
    // yet" — and every write answers "would have".
    return method === 'GET'
      ? { status: 404, ok: false, body: null, dry: true }
      : { status: 0, ok: true, body: null, dry: true };
  }
  const response = await fetch(`${ENDPOINT}${path}`, {
    method,
    headers: {
      'content-type': 'application/json',
      'x-appwrite-project': PROJECT,
      'x-appwrite-key': KEY,
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const text = await response.text();
  let parsed = null;
  if (text) {
    try { parsed = JSON.parse(text); } catch { parsed = { message: text }; }
  }
  return { status: response.status, ok: response.ok, body: parsed };
}

/** Creates [path] unless it is already there. */
async function ensure(label, getPath, createPath, payload) {
  const found = await api(getPath);
  if (found.ok) return { state: 'exists', body: found.body };
  if (found.status !== 404) {
    say('failed', label, `read: ${found.status} ${found.body?.message ?? ''}`);
    return { state: 'failed' };
  }
  const created = await api(createPath, { method: 'POST', body: payload });
  if (created.ok || created.dry) return { state: 'created', body: created.body };
  if (created.status === 409) return { state: 'exists', body: null };
  // A quota refusal is the one failure worth stopping the whole run for:
  // everything after it would fail the same way and bury the reason in
  // two hundred lines of output.
  if (isQuota(created)) {
    if (!PROBE) throw new QuotaExceeded(label, created);
    limits.push({ what: label, message: created.body?.message ?? created.status });
    say('failed', label, `LIMIT: ${created.body?.message ?? created.status}`);
    return { state: 'failed' };
  }
  say('failed', label, `${created.status} ${created.body?.message ?? ''}`);
  return { state: 'failed' };
}

class QuotaExceeded extends Error {
  constructor(label, response) {
    super(`${label}: ${response.body?.message ?? response.status}`);
    this.label = label;
    this.response = response;
  }
}

const isQuota = (r) =>
  r.status === 402 ||
  /limit|quota|plan|upgrade/i.test(String(r.body?.message ?? '')) ||
  String(r.body?.type ?? '').includes('limit');

// ───────────────────────────── steps ────────────────────────────────────

async function database() {
  const r = await ensure(
    `database ${DATABASE_ID}`,
    `/tablesdb/${DATABASE_ID}`,
    '/tablesdb',
    { databaseId: DATABASE_ID, name: DATABASE_NAME, enabled: true },
  );
  say(r.state, `database ${DATABASE_ID}`);
}

/**
 * The plan's column type -> Appwrite's route segment.
 *
 * `double` is the Postgres name and the one the plan uses; Appwrite's
 * route is `/columns/float`. Mapping it wrong is a 404 that reads
 * "Route not found", which says nothing about which column or why.
 */
const columnPath = (type) =>
  ({
    string: 'string',
    integer: 'integer',
    double: 'float',
    boolean: 'boolean',
    datetime: 'datetime',
  })[type];

async function collections() {
  for (const c of COLLECTIONS) {
    const table = await ensure(
      `collection ${c.id}`,
      `/tablesdb/${DATABASE_ID}/tables/${c.id}`,
      `/tablesdb/${DATABASE_ID}/tables`,
      {
        tableId: c.id,
        name: c.name,
        permissions: c.permissions ?? [],
        rowSecurity: c.documentSecurity ?? false,
        enabled: true,
      },
    );
    say(table.state, `collection ${c.id}`, `${c.columns.length} columns`);
    if (table.state === 'failed') continue;

    const listed = await api(
      `/tablesdb/${DATABASE_ID}/tables/${c.id}/columns?queries[]=${encodeURIComponent(
        JSON.stringify({ method: 'limit', values: [500] }),
      )}`,
    );
    const existing = new Map(
      (listed.body?.columns ?? []).map((col) => [col.key, col]),
    );

    for (const col of c.columns) {
      if (existing.has(col.key)) {
        say('exists', `  ${c.id}.${col.key}`);
        continue;
      }
      const made = await api(
        `/tablesdb/${DATABASE_ID}/tables/${c.id}/columns/${columnPath(col.type)}`,
        {
          method: 'POST',
          body: {
            key: col.key,
            required: col.required ?? false,
            ...(col.type === 'string' ? { size: col.size ?? 8192 } : {}),
            array: col.array ?? false,
          },
        },
      );
      if (made.ok || made.dry) say('created', `  ${c.id}.${col.key}`, col.type);
      else if (made.status === 409) say('exists', `  ${c.id}.${col.key}`);
      else if (isQuota(made)) {
        if (!PROBE) throw new QuotaExceeded(`${c.id}.${col.key}`, made);
        limits.push({ what: `${c.id}.${col.key}`, message: made.body?.message ?? made.status });
        say('failed', `  ${c.id}.${col.key}`, `LIMIT: ${made.body?.message ?? made.status}`);
      }
      else say('failed', `  ${c.id}.${col.key}`, `${made.status} ${made.body?.message ?? ''}`);
    }

    // Reported, never dropped: a column in the project and not in the
    // plan may be holding live data somebody still needs.
    for (const key of existing.keys()) {
      if (!c.columns.some((col) => col.key === key)) {
        say('extra', `  ${c.id}.${key}`, 'in the project, not in the plan');
        notes.push(`${c.id}.${key} exists but is not planned — left alone`);
      }
    }

    for (const index of c.indexes ?? []) {
      const made = await api(`/tablesdb/${DATABASE_ID}/tables/${c.id}/indexes`, {
        method: 'POST',
        body: { key: index.key, type: index.type, columns: index.attributes },
      });
      if (made.ok || made.dry) say('created', `  index ${c.id}.${index.key}`);
      else if (made.status === 409) say('exists', `  index ${c.id}.${index.key}`);
      else say('failed', `  index ${c.id}.${index.key}`, `${made.status} ${made.body?.message ?? ''}`);
    }
  }
}

async function buckets() {
  for (const b of SINGLE ? [SINGLE_BUCKET] : BUCKETS) {
    const r = await ensure(`bucket ${b.id}`, `/storage/buckets/${b.id}`, '/storage/buckets', {
      bucketId: b.id,
      name: b.name,
      permissions: b.permissions,
      fileSecurity: b.fileSecurity,
      maximumFileSize: b.maximumFileSize,
      allowedFileExtensions: b.allowedFileExtensions,
      compression: b.compression,
      encryption: b.encryption,
      antivirus: b.antivirus,
      enabled: true,
    });
    say(r.state, `bucket ${b.id}`);
  }
}

/**
 * The two quotas no pricing page states plainly, and the two this design
 * cannot do without: Phase 0 needs a team per ward (584) and Phase 3 a
 * topic per targetable group (~650).
 *
 * Probe only. It creates one of each with an obvious throwaway id, to
 * learn whether the plan permits any at all — it does not create 584 of
 * anything, and it cleans up after itself.
 */
async function probeLimits() {
  for (const [label, path, body] of [
    ['team', '/teams', { teamId: 'probe-ward-delete-me', name: 'probe (delete me)' }],
    ['topic', '/messaging/topics', { topicId: 'probe-topic-delete-me', name: 'probe (delete me)' }],
  ]) {
    const made = await api(path, { method: 'POST', body });
    if (made.ok || made.status === 409) {
      say(made.status === 409 ? 'exists' : 'created', `${label} (probe)`);
      // Leave nothing behind: this is somebody's real project.
      const id = Object.values(body)[0];
      const gone = await api(`${path}/${id}`, { method: 'DELETE' });
      if (!gone.ok && gone.status !== 404) {
        notes.push(`probe ${label} ${id} could not be deleted — remove it by hand`);
      }
    } else if (isQuota(made)) {
      limits.push({ what: label, message: made.body?.message ?? made.status });
      say('failed', `${label} (probe)`, `LIMIT: ${made.body?.message ?? made.status}`);
    } else {
      say('failed', `${label} (probe)`, `${made.status} ${made.body?.message ?? ''}`);
    }
  }
}

async function functions() {
  for (const f of FUNCTIONS) {
    const r = await ensure(`function ${f.id}`, `/functions/${f.id}`, '/functions', {
      functionId: f.id,
      name: f.name,
      runtime: 'node-22',
      version: FUNCTION_VERSION,
      execute: f.execute,
      events: f.events ?? [],
      schedule: f.schedule ?? '',
      scopes: f.scopes,
      entrypoint: f.entrypoint,
      enabled: true,
    });
    say(r.state, `function ${f.id}`, f.schedule ? `cron ${f.schedule}` : (f.events ? `${f.events.length} events` : ''));
    if (r.state === 'created' && !DRY) {
      notes.push(`${f.id}: created, but NOT deployed — push code with the Appwrite CLI`);
    }
  }
}

// ───────────────────────────── run ──────────────────────────────────────

async function main() {
  if (!DRY && (!PROJECT || !KEY)) {
    console.error(
      'Set APPWRITE_PROJECT_ID and APPWRITE_API_KEY (and APPWRITE_ENDPOINT to\n' +
        `override ${PLANNED_ENDPOINT}), or pass --dry-run to print the plan.\n\n` +
        'The key must be a FRESH server key. Two keys from the previous\n' +
        'project are in public git history and must not be reused.',
    );
    process.exit(2);
  }
  console.log(
    DRY
      ? '# dry run — nothing is written, and nothing is read either'
      : `# ${ENDPOINT} project ${PROJECT}`,
  );

  try {
    if (wants('database')) await database();
    if (wants('collections')) await collections();
    if (wants('buckets')) await buckets();
    if (wants('functions')) await functions();
    if (PROBE && wants('limits')) await probeLimits();
  } catch (e) {
    if (e instanceof QuotaExceeded) {
      console.error(`\n! stopped at ${e.label}: the project's plan refused it.`);
      console.error(`  ${e.response.body?.message ?? e.response.status}`);
      console.error(
        '\n  This is the tier question the migration doc has been asking since\n' +
          '  Phase 1. Nothing after this point would have succeeded either.',
      );
      if (/bucket/i.test(e.label)) {
        console.error(
          '\n  The previous Appwrite project hit this exact limit — its config\n' +
            '  says "Due to Appwrite free tier limits (max 1 bucket)". Re-run\n' +
            '  with --single-bucket to provision one shared bucket instead,\n' +
            '  which is safe while file-level permissions stay on.',
        );
      }
      process.exit(3);
    }
    throw e;
  }

  console.log(`\n${Object.entries(tally).map(([k, v]) => `${k}=${v}`).join(' ')}`);
  for (const note of notes) console.log(`  note: ${note}`);
  if (limits.length) {
    console.log(`\n${limits.length} quota limit(s) on this plan:`);
    for (const l of limits) console.log(`  - ${l.what}: ${l.message}`);
  }
  // A failure must not exit 0. This project has shipped a checker that
  // reported success over twenty failures; not again.
  if (tally.failed > 0) process.exit(1);
}

await main();
