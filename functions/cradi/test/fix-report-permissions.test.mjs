/**
 * The permissions migration, run as a child process against a stub
 * Appwrite.
 *
 * A subprocess and a real socket rather than a stubbed `fetch`, because
 * the script is a script: it reads its configuration from the
 * environment at load, it writes to stdout, and it exits with a status
 * somebody's shell will branch on. Importing it as a module would test
 * none of that, and the parts most worth testing here — that it pages
 * with a cursor, that a second run writes nothing, that a partial
 * failure does not exit 0 — are all in the plumbing.
 */
import assert from 'node:assert/strict';
import { describe, it, before, after } from 'node:test';
import { createServer } from 'node:http';
import { execFile } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

import { lgaLabel, wardTeam } from '../src/lib/appwrite.js';

const here = dirname(fileURLToPath(import.meta.url));
const SCRIPT = resolve(here, '../../../infra/appwrite/fix-report-permissions.mjs');

/** State the stub serves, replaced per test. */
let world;

const run = (...extra) =>
  new Promise((done) => {
    execFile(
      process.execPath,
      [SCRIPT, ...extra],
      {
        env: {
          ...process.env,
          APPWRITE_ENDPOINT: `http://127.0.0.1:${port}/v1`,
          APPWRITE_PROJECT_ID: 'test',
          APPWRITE_API_KEY: 'test-key',
          APPWRITE_DATABASE_ID: 'cradi',
        },
      },
      (error, stdout, stderr) => done({ code: error?.code ?? 0, stdout, stderr }),
    );
  });

let server;
let port;

before(async () => {
  server = createServer((req, res) => {
    const url = new URL(req.url, 'http://x');
    const path = url.pathname.replace(/^\/v1/, '');
    let raw = '';
    req.on('data', (c) => { raw += c; });
    req.on('end', () => {
      const body = raw ? JSON.parse(raw) : undefined;
      const reply = (status, payload) => {
        res.writeHead(status, { 'content-type': 'application/json' });
        res.end(JSON.stringify(payload ?? null));
      };
      world.calls.push({ method: req.method, path, body });

      const row = path.match(/^\/tablesdb\/[^/]+\/tables\/([^/]+)\/rows(?:\/(.+))?$/);
      if (row) {
        const [, table, id] = row;
        const rows = world[table] ?? [];
        if (req.method === 'GET' && !id) {
          const queries = url.searchParams.getAll('queries[]').map((q) => JSON.parse(q));
          const limit = queries.find((q) => q.method === 'limit')?.values[0] ?? 25;
          const after = queries.find((q) => q.method === 'cursorAfter')?.values[0];
          const sorted = [...rows].sort((a, b) => (a.$id < b.$id ? -1 : 1));
          const from = after ? sorted.findIndex((r) => r.$id === after) + 1 : 0;
          return reply(200, { total: sorted.length, rows: sorted.slice(from, from + limit) });
        }
        if (req.method === 'PATCH' && id) {
          if (world.failRows?.has(decodeURIComponent(id))) return reply(500, { message: 'nope' });
          const found = rows.find((r) => r.$id === decodeURIComponent(id));
          if (!found) return reply(404, { message: 'not found' });
          if (body.permissions) found.$permissions = body.permissions;
          Object.assign(found, body.data ?? {});
          return reply(200, found);
        }
      }
      const user = path.match(/^\/users\/([^/]+)(\/labels)?$/);
      if (user) {
        const [, id, labels] = user;
        const found = world.users?.[decodeURIComponent(id)];
        if (!found) return reply(404, { message: 'user not found' });
        if (req.method === 'PUT' && labels) {
          found.labels = body.labels;
          return reply(200, found);
        }
        return reply(200, found);
      }
      return reply(404, { message: `stub has no ${req.method} ${path}` });
    });
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  port = server.address().port;
});

after(() => server.close());

const report = (id, status, over = {}) => ({
  $id: id,
  status,
  userId: `reporter-${id}`,
  state: 'Benue',
  lga: 'Makurdi',
  ward: 'North Bank I',
  $permissions: [
    `read("user:reporter-${id}")`,
    `read("team:${wardTeam('Benue', 'Makurdi', 'North Bank I')}")`,
    'read("label:ewv")',
    'read("label:ewr")',
    'read("label:admin")',
  ],
  ...over,
});

describe('the permissions migration', () => {
  it('writes nothing without --apply', async () => {
    world = { calls: [], reports: [report('r1', 'approved')] };
    const { code, stdout } = await run('--only=reports');
    assert.equal(code, 0);
    assert.match(stdout, /dry run/);
    assert.match(stdout, /would rewrite r1/);
    assert.equal(world.calls.filter((c) => c.method === 'PATCH').length, 0);
  });

  it('gives an approved report the scope the rule now says', async () => {
    world = { calls: [], reports: [report('r1', 'approved')] };
    const { code } = await run('--only=reports', '--apply');
    assert.equal(code, 0);
    assert.deepEqual(world.reports[0].$permissions, [
      'read("user:reporter-r1")',
      `read("team:${wardTeam('Benue', 'Makurdi', 'North Bank I')}")`,
      `read("label:${lgaLabel('Benue', 'Makurdi')}")`,
      'read("label:projectStaff")',
      'read("label:ewv")',
      'read("label:admin")',
      'read("label:ewr")',
      'read("label:media")',
    ]);
  });

  it('takes Early Responder off a report that was never validated', async () => {
    // The old ACL granted `ewr` on every report at creation, so the
    // backlog hands them every rejected and pending report in the
    // system. Removing that is the half of this migration that is not
    // about granting anything.
    world = { calls: [], reports: [report('r1', 'pending'), report('r2', 'rejected')] };
    const { code } = await run('--only=reports', '--apply');
    assert.equal(code, 0);
    for (const row of world.reports) {
      assert.ok(!row.$permissions.includes('read("label:ewr")'), row.$id);
    }
  });

  it('pages past the first hundred rows', async () => {
    // Cursor paging, so a rewrite that changes nothing about ordering
    // still reaches row 101. An offset into a table being written as it
    // is read skips rows, which is the failure that would leave a
    // migration looking complete.
    world = {
      calls: [],
      reports: Array.from({ length: 250 }, (_, n) =>
        report(`r${String(n).padStart(4, '0')}`, 'approved')),
    };
    const { code, stdout } = await run('--only=reports', '--apply');
    assert.equal(code, 0);
    assert.match(stdout, /250 checked, 250 changed/);
    for (const row of world.reports) {
      assert.ok(row.$permissions.includes('read("label:media")'), row.$id);
    }
  });

  it('is idempotent: a second run writes nothing', async () => {
    world = { calls: [], reports: [report('r1', 'approved'), report('r2', 'pending')] };
    await run('--only=reports', '--apply');
    world.calls = [];
    const { code, stdout } = await run('--only=reports', '--apply');
    assert.equal(code, 0);
    assert.match(stdout, /2 checked, 0 changed, 2 already correct/);
    assert.equal(world.calls.filter((c) => c.method === 'PATCH').length, 0);
  });

  it('does not exit 0 when a row could not be written', async () => {
    // A half-done migration that reports success is worse than one that
    // fails: nobody runs it again.
    world = {
      calls: [],
      reports: [report('r1', 'approved'), report('r2', 'approved')],
      failRows: new Set(['r2']),
    };
    const { code, stderr } = await run('--only=reports', '--apply');
    assert.equal(code, 1);
    assert.match(stderr, /failed: reports\/r2/);
    // And it kept going rather than stopping at the first refusal.
    assert.ok(world.reports[0].$permissions.includes('read("label:media")'));
  });

  it('re-derives the labels an account should be holding', async () => {
    world = {
      calls: [],
      profiles: [
        { $id: 'c1', role: 'ldp_coordinator', isApproved: true, state: 'Benue', lga: 'Makurdi' },
        { $id: 'm1', role: 'media', isApproved: true },
        { $id: 'u1', role: 'user', isApproved: true },
      ],
      users: {
        c1: { $id: 'c1', labels: ['ldpCoordinator', 'approved'] },
        m1: { $id: 'm1', labels: [] },
        u1: { $id: 'u1', labels: ['approved'] },
      },
    };
    const { code, stdout } = await run('--only=labels', '--apply');
    assert.equal(code, 0);
    assert.deepEqual(world.users.c1.labels,
      ['ldpCoordinator', 'approved', lgaLabel('Benue', 'Makurdi')]);
    assert.deepEqual(world.users.m1.labels, ['media', 'approved']);
    // Already right, so untouched.
    assert.deepEqual(world.users.u1.labels, ['approved']);
    assert.match(stdout, /3 checked, 2 changed, 1 already correct/);
  });

  it('skips a profile with no account behind it', async () => {
    // The one-time migration left some, and a 404 there is not a failure.
    world = {
      calls: [],
      profiles: [{ $id: 'ghost', role: 'ewm', isApproved: true }],
      users: {},
    };
    const { code, stdout } = await run('--only=labels', '--apply');
    assert.equal(code, 0);
    assert.match(stdout, /no account for profile ghost/);
  });
});
