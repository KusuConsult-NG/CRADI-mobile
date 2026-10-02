#!/usr/bin/env node
/**
 * Reports where a live project differs from `plan.mjs`. Read-only.
 *
 *   APPWRITE_ENDPOINT=... APPWRITE_PROJECT_ID=... APPWRITE_API_KEY=... \
 *   node infra/appwrite/verify.mjs
 *
 * Exits non-zero when anything is missing. A verifier that cannot fail
 * is not a verifier — this project has already shipped one checker that
 * reported success over twenty failures and one that read a 400 as "zero
 * rows", so every read here is checked and an unreadable project is a
 * failure, not an empty diff.
 */
import { BUCKETS, COLLECTIONS, DATABASE_ID, FUNCTIONS } from './plan.mjs';

const ENDPOINT = process.env.APPWRITE_ENDPOINT;
const PROJECT = process.env.APPWRITE_PROJECT_ID;
const KEY = process.env.APPWRITE_API_KEY;

if (!ENDPOINT || !PROJECT || !KEY) {
  console.error('Set APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID and APPWRITE_API_KEY.');
  process.exit(2);
}

const problems = [];
const note = (m) => problems.push(m);

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
  }
  for (const key of live.keys()) {
    if (!c.columns.some((col) => col.key === key)) {
      console.log(`?  ${c.id}.${key} is in the project but not in the plan`);
    }
  }
}

for (const b of BUCKETS) present(await get(`/storage/buckets/${b.id}`), `bucket ${b.id}`);

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
  if (!live.deployment) note(`function ${f.id}: created but never deployed`);
}

if (problems.length === 0) {
  console.log('The project matches the plan.');
  process.exit(0);
}
console.error(`\n${problems.length} problem(s):`);
for (const p of problems) console.error(`  - ${p}`);
process.exit(1);
