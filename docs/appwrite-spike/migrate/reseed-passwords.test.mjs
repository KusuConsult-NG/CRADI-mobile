/**
 * Does the recovery delete exactly the accounts it should, and nothing else?
 *
 * This script deletes real production accounts, so the things worth pinning are
 * its refusals: an account it did not create, an interlock that disagrees, a
 * run with no `--delete` at all. Each is asserted against a stand-in that
 * records every call, so the claims are about what was sent rather than about a
 * count the script chose to print.
 *
 * Needs a Postgres carrying the schema and the fixture; skips itself otherwise.
 *
 *   PG_URL=postgres://… node --test reseed-passwords.test.mjs
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
let accounts;      // id -> { email, sessions }
let profileIds;

function run(args = [], env = {}) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, ['reseed-passwords.mjs', ...args], {
      cwd: import.meta.dirname,
      env: { ...process.env, PG_URL: PG, AW_ENDPOINT: base, AW_PROJECT: 'test', AW_KEY: 'test', ...env },
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (d) => (stdout += d));
    child.stderr.on('data', (d) => (stderr += d));
    child.on('close', (code) => resolve({ code, stdout, stderr, out: stdout + stderr }));
  });
}

/** Runs seed-identities.mjs against the same stand-in. */
function seed() {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, ['seed-identities.mjs'], {
      cwd: import.meta.dirname,
      env: { ...process.env, PG_URL: PG, AW_ENDPOINT: base, AW_PROJECT: 'test', AW_KEY: 'test' },
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (d) => (stdout += d));
    child.stderr.on('data', (d) => (stderr += d));
    child.on('close', (code) =>
      resolve({
        code,
        out: stdout + stderr,
        report: JSON.parse(stdout.slice(stdout.indexOf('{'))),
      }),
    );
  });
}

const deletesSent = () =>
  calls.filter((c) => c.method === 'DELETE').map((c) => c.path.replace('/v1/users/', ''));

/**
 * The findings the fixture is supposed to produce, and nothing else.
 *
 * It carries one account whose hash is argon2, so a correct audit always
 * reports that one and always exits 1. Asserting a clean exit would mean
 * removing that account, and with it the coverage of the case where a password
 * cannot come across at all.
 */
function unexpectedFindings(out) {
  const at = out.indexOf('[');
  if (at === -1) return [];
  const end = out.lastIndexOf(']');
  let findings;
  try {
    findings = JSON.parse(out.slice(at, end + 1));
  } catch {
    return [{ finding: `could not parse the findings block from:\n${out}` }];
  }
  return findings.filter((f) => !/not bcrypt/.test(f.finding));
}

before(async () => {
  client = new pg.Client({ connectionString: PG });
  try {
    await client.connect();
  } catch {
    reachable = false;
    return;
  }
  profileIds = (
    await client.query(
      `select p.id from profiles p join auth.users u on u.id = p.id order by p.id`,
    )
  ).rows.map((r) => r.id);

  server = createServer(async (req, res) => {
    const url = new URL(req.url, 'http://x');
    calls.push({ method: req.method, path: url.pathname });
    const send = (code, body) => {
      res.writeHead(code, { 'content-type': 'application/json' });
      res.end(body === null ? '' : JSON.stringify(body));
    };

    if (req.method === 'GET' && url.pathname === '/v1/users') {
      const all = [...accounts.entries()].map(([id, a]) => ({ $id: id, email: a.email, name: '' }));
      const queries = url.searchParams.getAll('queries[]').map((q) => JSON.parse(q));
      const limit = queries.find((q) => q.method === 'limit')?.values?.[0] ?? 25;
      const cursor = queries.find((q) => q.method === 'cursorAfter')?.values?.[0];
      let page = all;
      if (cursor) {
        const at = all.findIndex((u) => u.$id === cursor);
        page = at === -1 ? [] : all.slice(at + 1);
      }
      return send(200, { total: all.length, users: page.slice(0, limit) });
    }
    const sm = /^\/v1\/users\/([^/]+)\/sessions$/.exec(url.pathname);
    if (req.method === 'GET' && sm) {
      const a = accounts.get(decodeURIComponent(sm[1]));
      if (!a) return send(404, { message: 'User not found' });
      return send(200, { total: a.sessions, sessions: Array.from({ length: a.sessions }, (_, i) => ({ $id: `s${i}` })) });
    }
    // What `seed-identities.mjs` calls, so the test can run the recovery to its
    // actual end — deleted, then re-created WITH the hash — rather than stopping
    // at the delete and assuming the rest.
    if (req.method === 'POST' && (url.pathname === '/v1/users' || url.pathname === '/v1/users/bcrypt')) {
      let raw = '';
      for await (const c of req) raw += c;
      const b = JSON.parse(raw || '{}');
      const id = String(b.userId ?? '');
      if (accounts.has(id)) return send(409, { message: 'A user with the same id already exists' });
      accounts.set(id, {
        email: b.email ?? '',
        sessions: 0,
        // The two things the recovery exists to change.
        password: b.password ?? null,
        hashed: url.pathname.endsWith('/bcrypt'),
      });
      return send(201, { $id: id, email: b.email ?? '' });
    }
    if (req.method === 'PUT' && /^\/v1\/users\/[^/]+\/labels$/.test(url.pathname)) {
      return send(200, { $id: 'x', labels: [] });
    }
    if (req.method === 'POST' && url.pathname === '/v1/teams') return send(201, { $id: 't' });
    if (req.method === 'POST' && /^\/v1\/teams\/[^/]+\/memberships$/.test(url.pathname)) {
      return send(201, { $id: 'm' });
    }

    const um = /^\/v1\/users\/([^/]+)$/.exec(url.pathname);
    if (req.method === 'DELETE' && um) {
      const id = decodeURIComponent(um[1]);
      if (!accounts.has(id)) return send(404, { message: 'User not found' });
      accounts.delete(id);
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
  // The production state this script is for: every profile has an account, and
  // nobody has signed in yet.
  accounts = new Map(profileIds?.map((id) => [id, { email: `${id}@example.ng`, sessions: 0 }]));
});

describe('recovering the passwords', () => {
  test('the audit changes nothing, and names the command that would', async (t) => {
    if (!reachable) return t.skip(`no Postgres at ${PG}`);
    const { code, out } = await run();
    assert.deepEqual(unexpectedFindings(out), [], out);
    assert.equal(code, 1, 'the fixture has a non-bcrypt hash, which is a finding');
    assert.deepEqual(deletesSent(), [], 'an audit must not delete');
    assert.equal(accounts.size, profileIds.length);
    assert.match(out, new RegExp(`CONFIRM_DELETE_USERS=${profileIds.length}`), out);
    assert.match(out, /Audit only; nothing was changed/);
  });

  test('deletes every seeded account, and only those', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    const { code, out } = await run(['--delete'], {
      CONFIRM_DELETE_USERS: String(profileIds.length),
    });
    assert.equal(code, 0, out);
    assert.deepEqual(deletesSent().sort(), [...profileIds].sort());
    assert.equal(accounts.size, 0, 'every seeded account should be gone');
    assert.match(out, /node seed-identities\.mjs/, 'it must say what to run next');
  });

  test('never deletes an account the seeder did not create', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    // A real sign-up made after the migration: an Appwrite-generated id that is
    // not a Postgres profile id. Deleting it would destroy a real user, so the
    // audit reports it, the delete skips it, and the interlock counts without it.
    accounts.set('68ff00112233445566aa', { email: 'new.signup@example.ng', sessions: 1 });

    const audit = await run();
    assert.equal(audit.code, 1, 'an account from outside the seeder is a finding');
    assert.match(audit.out, /1 Appwrite account\(s\) are not in Postgres/, audit.out);
    assert.match(audit.out, /new\.signup@example\.ng/, audit.out);
    // The interlock is the seeded count, which excludes it.
    assert.match(audit.out, new RegExp(`CONFIRM_DELETE_USERS=${profileIds.length}`), audit.out);

    calls = [];
    const del = await run(['--delete'], { CONFIRM_DELETE_USERS: String(profileIds.length) });
    assert.equal(del.code, 0, del.out);
    assert.ok(!deletesSent().includes('68ff00112233445566aa'), 'it deleted a real sign-up');
    assert.deepEqual([...accounts.keys()], ['68ff00112233445566aa']);
  });

  test('refuses when the stated count is not the counted one', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    for (const value of [String(profileIds.length + 1), '0', 'all', undefined]) {
      calls = [];
      const { code, out } = await run(['--delete'], { CONFIRM_DELETE_USERS: value });
      assert.equal(code, 2, `CONFIRM_DELETE_USERS=${value} should refuse: ${out}`);
      assert.deepEqual(deletesSent(), [], `${value}: nothing may be deleted on a refusal`);
      assert.match(out, /Refusing to delete/, out);
    }
    assert.equal(accounts.size, profileIds.length);
  });

  test('reports a live session rather than quietly ending it', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    const [first] = profileIds;
    accounts.get(first).sessions = 2;
    const { code, out } = await run();
    assert.equal(code, 1, 'somebody signed in with the shared password is a finding');
    assert.match(out, /1 seeded account\(s\) have a live session/, out);
    assert.match(out, /with live sessions\s+1/, out);
  });

  test('the recovery ends with every importable hash actually imported', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    // The state production is in: accounts that exist, created by the old
    // seeder, so none of them carries a hash.
    for (const a of accounts.values()) {
      a.password = 'SharedMigrationPassword';
      a.hashed = false;
    }
    const expected = new Map(
      (
        await client.query(
          `select p.id, u.encrypted_password as hash from profiles p
             join auth.users u on u.id = p.id
            where u.encrypted_password ~ '^\\$2[aby]\\$[0-9]{2}\\$'`,
        )
      ).rows.map((r) => [r.id, r.hash]),
    );
    assert.ok(expected.size >= 2, 'fixture needs several bcrypt accounts');

    // Re-seeding WITHOUT deleting first changes nothing — the 409 path, and the
    // reason this script has to exist at all.
    const blocked = await seed();
    assert.equal(blocked.report.passwords.imported, 0, blocked.out);
    assert.equal(blocked.report.passwords.alreadyExisted, profileIds.length, blocked.out);
    for (const a of accounts.values()) assert.equal(a.hashed, false, 'nothing should have changed');

    const del = await run(['--delete'], { CONFIRM_DELETE_USERS: String(profileIds.length) });
    assert.equal(del.code, 0, del.out);

    const after = await seed();
    assert.equal(after.report.passwords.alreadyExisted, 0, after.out);
    assert.equal(after.report.passwords.imported, expected.size, after.out);
    // The assertion the whole operation is for: each account now holds its own
    // hash, byte for byte, and got there through the hash endpoint.
    for (const [id, hash] of expected) {
      const a = accounts.get(id);
      assert.ok(a, `${id} should have been re-created`);
      assert.equal(a.hashed, true, `${id} must go through /users/bcrypt`);
      assert.equal(a.password, hash, `${id}: the hash must cross unchanged`);
    }
    // And the shared password is nowhere in the project any more.
    for (const [id, a] of accounts) {
      assert.notEqual(a.password, 'SharedMigrationPassword', `${id} still holds the shared one`);
    }
  });

  test('a second delete is a no-op, not a failure', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    await run(['--delete'], { CONFIRM_DELETE_USERS: String(profileIds.length) });
    // Everything is gone, so the audit now counts zero seeded accounts and the
    // interlock for a re-run is 0 — which is the honest number.
    calls = [];
    const { code, out } = await run(['--delete'], { CONFIRM_DELETE_USERS: '0' });
    assert.equal(code, 0, out);
    assert.deepEqual(deletesSent(), []);
    assert.match(out, new RegExp(`in postgres, not here\\s+${profileIds.length}`), out);
  });
});
