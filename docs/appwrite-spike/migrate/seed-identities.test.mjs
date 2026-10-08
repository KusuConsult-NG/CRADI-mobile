/**
 * Does the identity seeder carry each account's own password across?
 *
 * This file exists because the version it tests was NOT the version that ran.
 * The cutover's step 5.1 chose to import Supabase's bcrypt hashes so that
 * nobody has to reset a password; the seeder that actually ran against the
 * production project was the earlier one, which created every account with a
 * single shared `MIGRATION_PASSWORD`. Nothing failed, nothing was red, and the
 * summary line read "users created" either way. A test that watches which
 * endpoint each row goes to is the only thing that tells the two apart.
 *
 *  - The Postgres side is real: `auth.users` rows carrying a bcrypt hash, a
 *    hash in another format, and no hash at all — the three branches.
 *  - The Appwrite side is a stand-in that speaks the two documented creation
 *    endpoints and records every call, so the assertions are about what was
 *    sent rather than about a count the script chose to print.
 *
 * Needs a Postgres carrying the schema; skips itself when there is none.
 *
 *   PG_URL=postgres://… node --test seed-identities.test.mjs
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
let accounts;

/** Runs seed-identities.mjs against the stand-in and the live Postgres. */
function runSeed(env = {}) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, ['seed-identities.mjs'], {
      cwd: import.meta.dirname,
      env: {
        ...process.env,
        PG_URL: PG,
        AW_ENDPOINT: base,
        AW_PROJECT: 'test',
        AW_KEY: 'test',
        ...env,
      },
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (d) => (stdout += d));
    child.stderr.on('data', (d) => (stderr += d));
    child.on('close', (code) =>
      resolve({
        code,
        stdout,
        stderr,
        out: stdout + stderr,
        report: stdout.includes('{') ? JSON.parse(stdout.slice(stdout.indexOf('{'))) : null,
      }),
    );
  });
}

before(async () => {
  client = new pg.Client({ connectionString: PG });
  try {
    await client.connect();
  } catch {
    reachable = false;
    return;
  }

  server = createServer(async (req, res) => {
    const url = new URL(req.url, 'http://x');
    let raw = '';
    for await (const c of req) raw += c;
    const body = raw ? JSON.parse(raw) : {};
    const send = (code, payload) => {
      res.writeHead(code, { 'content-type': 'application/json' });
      res.end(JSON.stringify(payload));
    };
    calls.push({ method: req.method, path: url.pathname, body });

    // The two creation endpoints, and the difference between them is the
    // whole subject: `/users/bcrypt` takes the hash as `password`, `/users`
    // takes no password at all.
    if (req.method === 'POST' && (url.pathname === '/v1/users' || url.pathname === '/v1/users/bcrypt')) {
      const id = String(body.userId ?? '');
      if (accounts.has(id)) {
        return send(409, { message: 'A user with the same id, email, or phone already exists' });
      }
      accounts.set(id, { password: body.password ?? null, hashed: url.pathname.endsWith('/bcrypt') });
      return send(201, { $id: id, email: body.email ?? '', name: body.name ?? '' });
    }
    if (req.method === 'PUT' && /^\/v1\/users\/[^/]+\/labels$/.test(url.pathname)) {
      return send(200, { $id: 'x', labels: body.labels ?? [] });
    }
    if (req.method === 'POST' && url.pathname === '/v1/teams') return send(201, { $id: body.teamId });
    if (req.method === 'POST' && /^\/v1\/teams\/[^/]+\/memberships$/.test(url.pathname)) {
      return send(201, { $id: 'm' });
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
  accounts = new Map();
});

/**
 * Every failure the fixture is supposed to produce, and nothing else.
 *
 * The fixture carries one account whose hash is argon2, so a correct run always
 * exits 1 and always reports that one line. Asserting `code === 0` would mean
 * removing that account, and with it the only coverage of the branch where a
 * password cannot come across.
 */
/** Just the account-creation calls for [id] — a membership POST carries a userId too. */
const creationsOf = (id) =>
  calls.filter(
    (c) =>
      c.method === 'POST' &&
      (c.path === '/v1/users' || c.path === '/v1/users/bcrypt') &&
      c.body.userId === id,
  );

function unexpectedFailures(report) {
  return (report?.failures ?? []).filter((f) => !/not bcrypt/.test(f));
}

describe('importing the passwords', () => {
  test('a bcrypt hash goes across verbatim, and never as a plaintext', async (t) => {
    if (!reachable) return t.skip(`no Postgres at ${PG}`);
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

    const { report, out } = await runSeed();
    assert.deepEqual(unexpectedFailures(report), [], out);
    assert.equal(report.passwords.imported, expected.size, out);
    assert.equal(report.passwords.alreadyExisted, 0, out);

    for (const [id, hash] of expected) {
      const sent = creationsOf(id);
      assert.equal(sent.length, 1, `${id} should be created exactly once`);
      assert.equal(sent[0].path, '/v1/users/bcrypt', `${id} must not go to /users`);
      assert.equal(sent[0].body.password, hash, `${id}: the hash must cross unchanged`);
    }
    // The shared password this replaced: no creation call may carry one.
    for (const c of calls.filter((x) => x.path === '/v1/users')) {
      assert.equal(c.body.password, undefined, 'a plaintext password was sent');
    }
  });

  test('an account with no hash gets no password, which is what it had', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    const none = (
      await client.query(
        `select p.id from profiles p join auth.users u on u.id = p.id
          where coalesce(u.encrypted_password, '') = ''`,
      )
    ).rows.map((r) => r.id);
    assert.ok(none.length, 'fixture needs an account with no hash');

    const { report, out } = await runSeed();
    assert.deepEqual(unexpectedFailures(report), [], out);
    assert.equal(report.passwords.none, none.length, out);
    for (const id of none) {
      const [sent] = creationsOf(id);
      assert.equal(sent.path, '/v1/users', `${id}: nothing to import, so no hash endpoint`);
      assert.equal(sent.body.password, undefined);
    }
  });

  test('a hash in another format is named, not silently dropped', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    const other = (
      await client.query(
        `select p.id from profiles p join auth.users u on u.id = p.id
          where coalesce(u.encrypted_password, '') <> ''
            and u.encrypted_password !~ '^\\$2[aby]\\$[0-9]{2}\\$'`,
      )
    ).rows.map((r) => r.id);
    assert.ok(other.length, 'fixture needs an account with a non-bcrypt hash');

    // Non-zero: losing a password is a finding, not a note. The account is
    // still created, because an account nobody can sign into is better than a
    // profile with no account at all — but the run does not read as clean.
    const { code, report, out } = await runSeed();
    assert.equal(code, 1, out);
    assert.equal(report.passwords.notBcrypt, other.length, out);
    for (const id of other) {
      assert.ok(
        report.failures.some((f) => f.startsWith(`${id}:`) && /not bcrypt/.test(f)),
        `${id} should be named in the failures: ${JSON.stringify(report.failures)}`,
      );
      assert.equal(creationsOf(id)[0].path, '/v1/users');
    }
  });

  test('a re-run says the hashes were NOT imported, rather than claiming they were', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    const first = await runSeed();
    assert.deepEqual(unexpectedFailures(first.report), [], first.out);
    const imported = first.report.passwords.imported;
    assert.ok(imported > 0);

    // Same accounts, second run. Appwrite takes a hash only at creation —
    // `PATCH /users/{id}/password` accepts a plaintext and nothing sets a
    // pre-existing hash on an existing account — so this is the one step of
    // the cutover that does NOT converge on a re-run. It has to say so.
    calls = [];
    const second = await runSeed();
    assert.equal(second.report.passwords.imported, 0, 'a 409 is not an import');
    assert.equal(second.report.passwords.alreadyExisted, first.report.users, second.out);
    assert.equal(second.code, 1, 'a run that imported no password must not read as clean');
    const warned = second.report.failures.filter((f) => /was NOT imported/.test(f));
    assert.equal(second.report.passwords.notBcrypt, 1, 'the argon2 account is still named');
    assert.equal(warned.length, imported, second.out);
    assert.ok(/delete the account and re-run/.test(warned[0]), warned[0]);
  });

  test('refuses to run at all where there is no hash column to read', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    // A Supabase export that dropped `encrypted_password` would otherwise
    // create every account passwordless and report success, which is the
    // silent 650-password reset this step exists to avoid.
    const admin = new pg.Client({ connectionString: PG.replace(/\/[^/]+$/, '/postgres') });
    await admin.connect();
    await admin.query('drop database if exists cradi_nohash');
    await admin.query('create database cradi_nohash');
    await admin.end();
    const bare = new pg.Client({ connectionString: PG.replace(/\/[^/]+$/, '/cradi_nohash') });
    await bare.connect();
    await bare.query('create schema auth');
    await bare.query('create table auth.users (id uuid primary key, email text)');
    await bare.end();

    const { code, out } = await runSeed({ PG_URL: PG.replace(/\/[^/]+$/, '/cradi_nohash') });
    assert.equal(code, 2, out);
    assert.match(out, /no encrypted_password column/);
    // And nothing was created on the way to finding out.
    assert.deepEqual(
      calls.filter((c) => c.path.startsWith('/v1/users')),
      [],
      'the check must come before the first write',
    );
  });
});
