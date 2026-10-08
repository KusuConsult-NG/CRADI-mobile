/**
 * Does the purge delete exactly the test leftovers, and refuse everything else?
 *
 * The script deletes production accounts and rows, so what is worth pinning is
 * not the happy path but every way it declines: a real account that happens to
 * match the pattern, an id that matches `dart-` without the stamp, a count that
 * disagrees, a run with no `--delete`. Each is asserted against a stand-in that
 * records every call, so the claims are about what was sent.
 *
 * Needs a Postgres carrying the schema and the fixture; skips itself otherwise.
 *
 *   PG_URL=postgres://… node --test purge-dart-accounts.test.mjs
 */
import { test, before, after, beforeEach, describe } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import pg from 'pg';

const PG = process.env.PG_URL ?? 'postgres://postgres@127.0.0.1:5433/cradi_mig';

let reachable = true;
let client;
let server;
let base;
let calls;
let accounts;   // id -> { email, labels }
let rows;       // table -> Set of row ids
let profileIds;

function run(args = [], env = {}) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, ['purge-dart-accounts.mjs', ...args], {
      cwd: import.meta.dirname,
      env: {
        ...process.env,
        PG_URL: PG,
        AW_ENDPOINT: base,
        AW_PROJECT: 'test',
        AW_KEY: 'test',
        APPWRITE_DATABASE_ID: 'cradi',
        ...env,
      },
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (d) => (stdout += d));
    child.stderr.on('data', (d) => (stderr += d));
    child.on('close', (code) => resolve({ code, stdout, stderr, out: stdout + stderr }));
  });
}

const deleted = () =>
  calls.filter((c) => c.method === 'DELETE').map((c) => c.path.replace('/v1/', ''));

before(async () => {
  client = new pg.Client({ connectionString: PG });
  try {
    await client.connect();
  } catch {
    reachable = false;
    return;
  }
  profileIds = (await client.query('select id::text as id from profiles order by id')).rows.map(
    (r) => r.id,
  );

  server = createServer(async (req, res) => {
    const url = new URL(req.url, 'http://x');
    calls.push({ method: req.method, path: url.pathname });
    const send = (code, body) => {
      res.writeHead(code, { 'content-type': 'application/json' });
      res.end(body === null ? '' : JSON.stringify(body));
    };

    if (req.method === 'GET' && url.pathname === '/v1/users') {
      const all = [...accounts.entries()].map(([id, a]) => ({
        $id: id,
        email: a.email,
        labels: a.labels,
      }));
      return send(200, { total: all.length, users: all });
    }
    const um = /^\/v1\/users\/([^/]+)$/.exec(url.pathname);
    if (req.method === 'DELETE' && um) {
      const id = decodeURIComponent(um[1]);
      if (!accounts.has(id)) return send(404, { message: 'User not found' });
      accounts.delete(id);
      return send(204, null);
    }
    const lm = /^\/v1\/tablesdb\/cradi\/tables\/([a-z_]+)\/rows$/.exec(url.pathname);
    if (req.method === 'GET' && lm) {
      const t = rows.get(lm[1]);
      if (!t) return send(404, { message: `Table not found: ${lm[1]}` });
      const all = [...t].map((id) => ({ $id: id }));
      return send(200, { total: all.length, rows: all });
    }
    const rm = /^\/v1\/tablesdb\/cradi\/tables\/([a-z_]+)\/rows\/([^/]+)$/.exec(url.pathname);
    if (req.method === 'DELETE' && rm) {
      const t = rows.get(rm[1]);
      const id = decodeURIComponent(rm[2]);
      if (!t?.has(id)) return send(404, { message: 'Row not found' });
      t.delete(id);
      return send(204, null);
    }
    return send(404, { message: `unexpected ${req.method} ${url.pathname}` });
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${server.address().port}/v1`;
});

after(async () => {
  await client?.end().catch(() => {});
  server?.close();
});

beforeEach(() => {
  calls = [];
  // What the live project looks like: the real accounts, plus two runs' worth
  // of prep-dart.mjs leftovers with the labels it grants.
  accounts = new Map(profileIds?.map((id) => [id, { email: `${id}@example.ng`, labels: [] }]));
  for (const stamp of ['1791415108729', '1791415123194']) {
    accounts.set(`dart-${stamp}`, {
      email: `dart-${stamp}@example.test`,
      labels: ['ewr', 'approved'],
    });
    accounts.set(`dart-reporter-${stamp}`, {
      email: `dart-reporter-${stamp}@example.test`,
      labels: [],
    });
  }
  rows = new Map([
    [
      'profiles',
      new Set([
        ...profileIds,
        'dart-1791415108729', 'dart-reporter-1791415108729',
        'dart-1791415123194', 'dart-reporter-1791415123194',
      ]),
    ],
    ['reports', new Set(['dart-foreign-1791415108729', 'dart-foreign-1791415123194'])],
  ]);
});

describe('purging the test leftovers', () => {
  test('the audit changes nothing and counts all three kinds', async (t) => {
    if (!reachable) return t.skip(`no Postgres at ${PG}`);
    const { code, out } = await run();
    assert.equal(code, 1, 'labelled accounts and leaked rows are findings');
    assert.deepEqual(deleted(), [], 'an audit must not delete');
    assert.equal(accounts.size, profileIds.length + 4);
    assert.match(out, /left by prep-dart\.mjs\s+4/, out);
    assert.match(out, /of those, holding labels\s+2/, out);
    assert.match(out, /dart profiles rows\s+4/, out);
    assert.match(out, /dart-foreign reports rows\s+2/, out);
    assert.match(out, /CONFIRM_DELETE_DART=4/, out);
  });

  test('the labels are reported, because they are the severity', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    const { out } = await run();
    assert.match(out, /hold Appwrite labels, so they are not inert/, out);
    assert.match(out, /"labels": \[\s*"ewr",\s*"approved"\s*\]/, out);
  });

  test('deletes every leftover, and not one real account', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    const { code, out } = await run(['--delete'], { CONFIRM_DELETE_DART: '4' });
    assert.equal(code, 0, out);

    // Exactly the four accounts, four profiles rows and two reports rows.
    assert.deepEqual(
      deleted().filter((p) => p.startsWith('users/')).sort(),
      [
        'users/dart-1791415108729', 'users/dart-1791415123194',
        'users/dart-reporter-1791415108729', 'users/dart-reporter-1791415123194',
      ],
    );
    assert.equal(deleted().filter((p) => p.includes('/tables/profiles/')).length, 4);
    assert.equal(deleted().filter((p) => p.includes('/tables/reports/')).length, 2);

    // Every real account and every real profiles row untouched.
    for (const id of profileIds) {
      assert.ok(accounts.has(id), `${id} was deleted`);
      assert.ok(rows.get('profiles').has(id), `profiles/${id} was deleted`);
    }
    assert.equal(accounts.size, profileIds.length);
    assert.equal(rows.get('reports').size, 0);
  });

  test('rows go before the accounts that own them', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    await run(['--delete'], { CONFIRM_DELETE_DART: '4' });
    const order = deleted();
    const lastRow = Math.max(...order.flatMap((p, i) => (p.includes('/rows/') ? [i] : [])));
    const firstAccount = Math.min(...order.flatMap((p, i) => (p.startsWith('users/') ? [i] : [])));
    // Otherwise a row whose read("user:<id>") names a deleted account is left
    // behind: readable by nobody, invisible, and still there.
    assert.ok(lastRow < firstAccount, `rows must be deleted first: ${order.join(', ')}`);
  });

  test('no real profile id can match the pattern in the first place', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    /*
     * The premise the whole script rests on, asserted directly rather than
     * through the guard.
     *
     * `profiles.id` is a uuid column, so a real id can never read as
     * `dart-<digits>` — which means the script's collision check cannot fire
     * against this schema and a test of it would be theatre. What IS worth
     * pinning is the premise: if the pattern ever did match a real id, the
     * script would delete a real account. So it is checked against every id in
     * the fixture, and against the uuid shape itself.
     */
    const ACCOUNT = /^dart-(?:reporter-)?\d+$/;
    for (const id of profileIds) {
      assert.doesNotMatch(id, ACCOUNT, `${id} would be treated as a test account`);
    }
    const { rows: typed } = await client.query(
      `select data_type from information_schema.columns
        where table_name = 'profiles' and column_name = 'id'`,
    );
    assert.equal(
      typed[0].data_type,
      'uuid',
      'profiles.id is no longer a uuid, so a real id could match the pattern —' +
        " re-read the script's collision guard, which is the only thing standing" +
        ' between that and a deleted account',
    );
  });

  test('refuses when the stated count is not the counted one', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    for (const value of ['5', '0', 'all', undefined]) {
      calls = [];
      const { code, out } = await run(['--delete'], { CONFIRM_DELETE_DART: value });
      assert.equal(code, 2, `CONFIRM_DELETE_DART=${value} should refuse: ${out}`);
      assert.deepEqual(deleted(), [], `${value}: nothing may be deleted on a refusal`);
      assert.match(out, /and this run counted 4 account\(s\)/, out);
    }
    assert.equal(accounts.size, profileIds.length + 4);
  });

  test('ignores an id that is dart-shaped without the stamp', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    // Somebody's hand-made account. `^dart-` alone would have matched it.
    accounts.set('dart-keepme', { email: 'real.person@example.ng', labels: ['admin'] });
    const { out } = await run();
    assert.match(out, /left by prep-dart\.mjs\s+4/, out);

    calls = [];
    await run(['--delete'], { CONFIRM_DELETE_DART: '4' });
    assert.ok(accounts.has('dart-keepme'), 'it deleted a hand-made account');
    assert.ok(!deleted().includes('users/dart-keepme'), 'it tried to delete it');
  });

  test('a clean project audits clean', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    await run(['--delete'], { CONFIRM_DELETE_DART: '4' });
    calls = [];
    const { code, out } = await run();
    assert.equal(code, 0, out);
    assert.match(out, /left by prep-dart\.mjs\s+0/, out);
    assert.doesNotMatch(out, /thing\(s\) to know/, out);
  });

  test('refuses to decide anything without the real ids', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    /*
     * A `PG_URL` aimed at the wrong database is the dangerous mistake here: it
     * would make every account look like a leftover. Both shapes of that are
     * refusals, with the cause named — the first draft of this script threw a
     * stack trace instead, which is the same outcome dressed as a crash.
     */
    const wrongDb = await run([], { PG_URL: PG.replace(/\/[^/]+$/, '/postgres') });
    assert.equal(wrongDb.code, 2, wrongDb.out);
    assert.match(wrongDb.out, /cannot read public\.profiles/, wrongDb.out);
    assert.match(wrongDb.out, /Check PG_URL/, wrongDb.out);
    assert.deepEqual(deleted(), [], 'nothing may be read or deleted');

    calls = [];
    const unreachable = await run([], { PG_URL: 'postgres://nobody@127.0.0.1:1/nope' });
    assert.equal(unreachable.code, 2, unreachable.out);
    assert.match(unreachable.out, /cannot reach/, unreachable.out);
    assert.deepEqual(deleted(), []);
  });
});
