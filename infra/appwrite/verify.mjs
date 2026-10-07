#!/usr/bin/env node
/**
 * Reports where a live project differs from `plan.mjs`. Read-only.
 *
 *   APPWRITE_ENDPOINT=... APPWRITE_PROJECT_ID=... APPWRITE_API_KEY=... \
 *   node infra/appwrite/verify.mjs [--single-bucket]
 *
 * `--single-bucket` checks the one shared bucket
 * `provision.mjs --single-bucket` makes, instead of the two the plan
 * wants. It is the flag and nothing else: `APPWRITE_BUCKET_ID` used to
 * switch this too, and a stale export then checked a bucket the last
 * provisioning run never made.
 *
 * Exits non-zero when anything is missing. A verifier that cannot fail
 * is not a verifier — this project has already shipped one checker that
 * reported success over twenty failures and one that read a 400 as "zero
 * rows", so every read here is checked and an unreadable project is a
 * failure, not an empty diff.
 */
import { BUCKETS, COLLECTIONS, DATABASE_ID, FUNCTIONS, SINGLE_BUCKET } from './plan.mjs';

const ENDPOINT = process.env.APPWRITE_ENDPOINT;
const PROJECT = process.env.APPWRITE_PROJECT_ID;
const KEY = process.env.APPWRITE_API_KEY;

if (!ENDPOINT || !PROJECT || !KEY) {
  console.error('Set APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID and APPWRITE_API_KEY.');
  process.exit(2);
}

const problems = [];
const note = (m) => problems.push(m);

/**
 * Differences that are not failures. `provision.mjs` deletes nothing, so
 * a project carries what earlier runs left — and the exit code has to go
 * on meaning "the plan is not satisfied", or nobody will trust it. These
 * are printed either way and change no exit code.
 */
const extras = [];

async function get(path) {
  const r = await fetch(`${ENDPOINT}${path}`, {
    headers: {
      'content-type': 'application/json',
      'x-appwrite-project': PROJECT,
      'x-appwrite-key': KEY,
    },
  });
  const text = await r.text();
  let body = null;
  if (text) { try { body = JSON.parse(text); } catch { body = { message: text }; } }
  return { status: r.status, ok: r.ok, body };
}

/** Anything but 200 or 404 is "we do not know", which is not "fine". */
function present(r, what) {
  if (r.ok) return true;
  if (r.status === 404) {
    note(`missing: ${what}`);
    return false;
  }
  note(`unreadable: ${what} (${r.status} ${r.body?.message ?? ''})`);
  return false;
}

const db = await get(`/tablesdb/${DATABASE_ID}`);
present(db, `database ${DATABASE_ID}`);

for (const c of COLLECTIONS) {
  const table = await get(`/tablesdb/${DATABASE_ID}/tables/${c.id}`);
  if (!present(table, `collection ${c.id}`)) continue;

  const listed = await get(
    `/tablesdb/${DATABASE_ID}/tables/${c.id}/columns?queries[]=${encodeURIComponent(
      JSON.stringify({ method: 'limit', values: [500] }),
    )}`,
  );
  if (!present(listed, `columns of ${c.id}`)) continue;

  const live = new Map((listed.body.columns ?? []).map((a) => [a.key, a]));
  for (const col of c.columns) {
    const found = live.get(col.key);
    if (!found) {
      note(`missing: ${c.id}.${col.key}`);
      continue;
    }
    // A column stuck in `processing` reads as present and rejects every
    // write, which is the kind of half-state a bare existence check
    // would call fine.
    if (found.status && found.status !== 'available') {
      note(`not available: ${c.id}.${col.key} is ${found.status}`);
    }
    // A warning, not a problem: `provision.mjs` never resizes a column
    // that exists, so this is drift it cannot fix by running again. It is
    // printed because it is what broke the first Cloud run — columns an
    // earlier build made at 8192 pushed four indexes past the 767 limit
    // and filled `reports` — and nothing said so.
    if (col.type === 'string' && found.size != null && found.size !== col.size) {
      console.log(`~  ${c.id}.${col.key} is size ${found.size}, the plan says ${col.size}`);
    }
  }
  for (const key of live.keys()) {
    if (!c.columns.some((col) => col.key === key)) {
      console.log(`?  ${c.id}.${key} is in the project but not in the plan`);
    }
  }

  // Indexes were not checked at all until the first Cloud run, where four
  // of them were refused and this script said the project matched. An
  // index that is missing is not an error anyone sees — the queries it
  // serves still answer, slowly, or fail with "index not found" only on
  // the paths that need one.
  const liveIndexes = new Map((table.body.indexes ?? []).map((i) => [i.key, i]));
  for (const index of c.indexes ?? []) {
    const found = liveIndexes.get(index.key);
    if (!found) {
      note(`missing: index ${c.id}.${index.key}`);
      continue;
    }
    if (found.status && found.status !== 'available') {
      note(`not available: index ${c.id}.${index.key} is ${found.status}${found.error ? ` (${found.error})` : ''}`);
    }
    // 1.9 renamed `attributes` to `columns`; read either.
    const liveCols = found.columns ?? found.attributes ?? [];
    if (liveCols.join(',') !== index.attributes.join(',')) {
      note(`index ${c.id}.${index.key}: covers (${liveCols.join(', ')}), plan says (${index.attributes.join(', ')})`);
    }
    if (found.type && found.type !== index.type) {
      note(`index ${c.id}.${index.key}: is ${found.type}, plan says ${index.type}`);
    }
  }
}

// The same switch `provision.mjs` takes, and only the switch.
//
// `APPWRITE_BUCKET_ID` used to set it too, so that a one-bucket project
// did not report both planned buckets missing forever. The plan is two
// buckets again (the Cloud plan was upgraded — see `plan.mjs`), and that
// variable is still in shells and runbooks from the single-bucket run:
// left as it was, it would check the shared bucket, find it correct, and
// print "the project matches the plan" while neither planned bucket
// existed. That is the verifier-that-cannot-fail this file's header is
// about, so a leftover variable is now named rather than obeyed.
const SINGLE = process.argv.includes('--single-bucket');
if (!SINGLE && process.env.APPWRITE_BUCKET_ID) {
  console.log(
    `note: APPWRITE_BUCKET_ID=${process.env.APPWRITE_BUCKET_ID} is set and` +
      ' --single-bucket is not, so it is ignored: checking the two planned' +
      ' buckets.',
  );
}
for (const b of SINGLE ? [SINGLE_BUCKET] : BUCKETS) {
  const bucket = await get(`/storage/buckets/${b.id}`);
  if (!present(bucket, `bucket ${b.id}`)) continue;
  // The two settings that decide who can read and delete files.
  if (bucket.body.fileSecurity !== b.fileSecurity) {
    note(`bucket ${b.id}: fileSecurity is ${bucket.body.fileSecurity}, plan says ${b.fileSecurity}`);
  }
  const livePerms = [...(bucket.body.$permissions ?? [])].sort().join(',');
  if (livePerms !== [...b.permissions].sort().join(',')) {
    note(`bucket ${b.id}: permissions are [${bucket.body.$permissions}], plan says [${b.permissions}]`);
  }
}

// The buckets the project has and the plan does not. On the Cloud project
// that is the single-bucket run's shared bucket, which still holds every
// file uploaded before the switch to two and which nothing points at now.
// Files are not moved by provisioning, and a bucket going quiet is the
// kind of thing that is only noticed when somebody opens an old report.
const listedBuckets = await get('/storage/buckets?queries[]=' + encodeURIComponent(
  JSON.stringify({ method: 'limit', values: [100] }),
));
if (listedBuckets.ok) {
  const planned = new Set((SINGLE ? [SINGLE_BUCKET] : BUCKETS).map((b) => b.id));
  for (const b of listedBuckets.body?.buckets ?? []) {
    if (!planned.has(b.$id)) {
      extras.push(`bucket ${b.$id} ("${b.name}") is in the project, not in the plan — left alone`);
    }
  }
} else {
  note(`unreadable: the project's bucket list (${listedBuckets.status} ${listedBuckets.body?.message ?? ''})`);
}

for (const f of FUNCTIONS) {
  const fn = await get(`/functions/${f.id}`);
  if (!present(fn, `function ${f.id}`)) continue;
  const live = fn.body;
  if ((live.schedule ?? '') !== (f.schedule ?? '')) {
    note(`function ${f.id}: schedule is "${live.schedule}", plan says "${f.schedule ?? ''}"`);
  }
  const missingScopes = f.scopes.filter((s) => !(live.scopes ?? []).includes(s));
  if (missingScopes.length) {
    note(`function ${f.id}: missing scopes ${missingScopes.join(', ')}`);
  }
  // A Function with no deployment answers every call with a 500 and
  // looks, from the console, exactly like one that is fine.
  //
  // `deployment` was renamed `deploymentId` in 1.9 (with `latest*`
  // aliases), so reading only the old name reported every deployed
  // Function as never deployed — a check that cannot fail is worse than
  // no check. The build status is read too: a deployment that failed to
  // build is present and just as dead.
  const deployment = live.deploymentId ?? live.latestDeploymentId ?? live.deployment;
  const buildStatus = live.latestDeploymentStatus;
  if (!deployment) {
    note(`function ${f.id}: created but never deployed`);
  } else if (buildStatus && buildStatus !== 'ready') {
    note(`function ${f.id}: deployment ${deployment} is "${buildStatus}", not ready`);
  }
}

if (extras.length) {
  console.log(`\n${extras.length} thing(s) in the project the plan does not ask for:`);
  for (const e of extras) console.log(`  ? ${e}`);
}

if (problems.length === 0) {
  console.log('\nThe project matches the plan.');
  process.exit(0);
}
console.error(`\n${problems.length} problem(s):`);
for (const p of problems) console.error(`  - ${p}`);
process.exit(1);
