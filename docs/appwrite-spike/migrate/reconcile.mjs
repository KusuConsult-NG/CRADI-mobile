/**
 * The reconciliation that matters.
 *
 * Row counts prove nothing about a migration whose whole difficulty is
 * access control. This asks the only question worth asking: does each user
 * see exactly what Postgres would have shown them?
 *
 * Source of truth is the live RLS policy, queried as that user. Target is
 * Appwrite, queried with that user's session. Any difference is a migration
 * defect — in either direction, because granting too much is worse than
 * granting too little and both are silent.
 */
import { readFileSync } from 'node:fs';
import pg from 'pg';
const { project, key } = JSON.parse(readFileSync('../spike/env.json', 'utf8'));
const EP = 'http://localhost:8080/v1';
const PG = process.env.PG_URL ?? 'postgres://postgres:postgres@localhost:5432/cradi_mig';

const client = new pg.Client({ connectionString: PG });
await client.connect();

async function postgresSees(userId) {
  await client.query(`select set_config('request.jwt.claim.sub', $1, false)`, [userId]);
  await client.query('set role authenticated');
  const r = await client.query('select id from reports order by id');
  await client.query('reset role');
  return r.rows.map((x) => x.id).sort();
}

async function appwriteSees(userId) {
  const email = (await client.query('select email from auth.users where id = $1', [userId])).rows[0].email;
  const s = await fetch(`${EP}/account/sessions/email`, {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-appwrite-project': project },
    body: JSON.stringify({ email, password: 'MigratedPassword123' }),
  });
  if (!s.ok) return { error: `sign-in ${s.status}` };
  const cookie = (s.headers.get('set-cookie') ?? '').split(';')[0];
  /*
   * Paginated, and loud on failure.
   *
   * The first version asked for `queries[]=limit(100)`, which this version
   * rejects as a syntax error, and then read `b.documents ?? []` — turning a
   * 400 into "this user can see nothing". It reported a total migration
   * failure for a migration that was correct. A reconciler that reads an
   * error as an empty result is worse than no reconciler, because its
   * verdict is confident.
   */
  const ids = [];
  let cursor = null;
  for (;;) {
    const queries = [JSON.stringify({ method: 'limit', values: [100] })];
    if (cursor) queries.push(JSON.stringify({ method: 'cursorAfter', values: [cursor] }));
    const qs = queries.map((q) => `queries[]=${encodeURIComponent(q)}`).join('&');
    const r = await fetch(`${EP}/databases/cradi/collections/reports/documents?${qs}`, {
      headers: { 'x-appwrite-project': project, cookie },
    });
    const b = await r.json();
    if (!r.ok) throw new Error(`list as ${userId}: ${r.status} ${JSON.stringify(b?.message).slice(0, 120)}`);
    const page = b.documents ?? [];
    ids.push(...page.map((d) => d.$id));
    if (page.length < 100) break;
    cursor = page[page.length - 1].$id;
  }
  return ids.sort();
}

const people = (await client.query(
  `select p.id, p.name, p.role, p.ward from profiles p order by p.role, p.name`,
)).rows;

let mismatches = 0;
console.log('user                      role   postgres  appwrite  verdict');
for (const p of people) {
  const before = await postgresSees(p.id);
  const after = await appwriteSees(p.id);
  if (after.error) { console.log(`${(p.name ?? '').padEnd(24)} ${String(p.role).padEnd(6)} ${String(before.length).padStart(8)}  ${after.error}`); mismatches++; continue; }
  const same = before.length === after.length && before.every((x, i) => x === after[i]);
  if (!same) mismatches += 1;
  console.log(`${(p.name ?? '').padEnd(24)} ${String(p.role).padEnd(6)} ${String(before.length).padStart(8)}  ${String(after.length).padStart(8)}  ${same ? 'match' : 'MISMATCH'}`);
  if (!same) {
    console.log(`    postgres: ${before.join(' ')}`);
    console.log(`    appwrite: ${after.join(' ')}`);
  }
}
await client.end();
console.log(mismatches === 0 ? '\nevery user sees exactly what they saw before' : `\n${mismatches} user(s) differ`);
process.exitCode = mismatches ? 1 : 0;
