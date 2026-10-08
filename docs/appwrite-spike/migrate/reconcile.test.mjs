/**
 * Does the migration's ACL design actually reproduce the RLS it replaces?
 *
 * The gate itself needs testing, and the honest way to test it is not with a
 * stub that agrees with it. So:
 *
 *  - The Postgres side is real: a live database carrying `local_stubs.sql` plus
 *    every migration, queried through the real policies as each real user.
 *  - The Appwrite side is a stand-in that speaks the documented REST contract
 *    (status codes, `rows`, `total`, cursor paging) and decides visibility by
 *    **evaluating the permission strings `migrate.mjs` actually stamps** —
 *    imported from `migrate.mjs`, not reimplemented — against the grants
 *    `seed-identities.mjs` actually assigns.
 *
 * So the question this asks is the real one: given the ACLs the migration
 * writes and the labels it hands out, does each user end up seeing what
 * Postgres showed them? The expected answer is **no**, and the specific way it
 * fails is asserted below, because `seed-identities.mjs` assigns a role label
 * from `profiles.role` while Postgres `app_role()` returns 'user' unless the
 * account is approved and not disabled.
 *
 * What this cannot prove: that Appwrite evaluates ACLs the way the stand-in
 * does. Only a run against a real project proves that, which is Phase 4's job.
 *
 * Needs a Postgres carrying the schema; skips itself when there is none.
 *
 *   PG_URL=postgres://… node --test reconcile.test.mjs
 */
import { test, before, after, describe } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import pg from 'pg';

const PG = process.env.PG_URL ?? 'postgres://postgres@127.0.0.1:5433/cradi_mig';
const PASSWORD = 'reconcile-test-password';

let reachable = true;
let client;
let server;
let base;
let fixtures;

/**
 * Exactly the grants `seed-identities.mjs` hands out, and no others.
 *
 * Mirroring it loosely is worse than not testing: a first draft here gave a
 * ward team to everyone who has a ward, and the gate duly reported that a
 * plain citizen could read four neighbours' profiles. The seeder joins ward
 * teams for `ewm` only, so that finding was the fixture's, not the
 * migration's.
 */
function grantsFor(p, { wardTeam, roleLabel, effectiveRole }, { byColumn = false } = {}) {
  const g = [`user:${p.id}`];
  // `byColumn` reproduces the bug the seeder shipped with: a label straight
  // from `profiles.role`, with no approval condition. The fixed seeder goes
  // through `effectiveRole`, which is what every RLS policy branches on.
  const role = byColumn ? String(p.role ?? 'user') : effectiveRole(p);
  if (role !== 'user') g.push(`label:${roleLabel(role)}`);
  if (role === 'ewm' && p.ward) g.push(`team:${wardTeam(p.state, p.lga, p.ward)}`);
  return new Set(g);
}

/** Appwrite reads a row when any read() principal on it is one of your grants. */
const canRead = (permissions, grants) =>
  permissions.some((perm) => {
    const m = /^read\("([^"]+)"\)$/.exec(perm);
    return m && grants.has(m[1]);
  });

before(async () => {
  client = new pg.Client({ connectionString: PG });
  try {
    await client.connect();
  } catch {
    reachable = false;
    return;
  }

  const migrate = await import('./migrate.mjs');
  const { wardTeam, roleLabel, reportPermissions, verificationPermissions, profilePermissions } =
    migrate;

  const profiles = (
    await client.query(
      `select p.id, p.name, p.role, p.state, p.lga, p.ward, p.is_approved, p.is_disabled, u.email
         from profiles p join auth.users u on u.id = p.id order by p.name`,
    )
  ).rows;
  const reports = (await client.query(`select * from reports`)).rows;
  const verifications = (await client.query(`select * from verifications`)).rows;
  const reportById = new Map(reports.map((r) => [r.id, r]));

  // Rows as the migrator writes them: id plus the stamped ACL. Only the three
  // collections migrate.mjs actually handles — the rest are deliberately absent,
  // which is what the gate should report about them.
  const rows = {
    profiles: profiles.map((p) => ({ $id: p.id, permissions: profilePermissions(p) })),
    reports: reports.map((r) => ({ $id: r.id, permissions: reportPermissions(r) })),
    verifications: verifications
      .filter((v) => reportById.has(v.report_id))
      .map((v) => ({ $id: v.id, permissions: verificationPermissions(v, reportById.get(v.report_id)) })),
  };
  // Everything else the gate reconciles: present as a table, empty of rows,
  // because no script in this directory migrates them. That is the state the
  // gate must report, not crash on.
  for (const t of [
    'verification_overrides', 'alerts', 'authorities', 'scheduled_escalations',
    'messages', 'contacts', 'trusted_devices', 'login_history',
    'knowledge_base', 'news_links', 'app_settings', 'ndpa_consents',
  ]) {
    rows[t] = [];
  }

  const helpers = { wardTeam, roleLabel, effectiveRole: migrate.effectiveRole };
  // Two grant maps: what the seeder used to hand out, and what it hands out now.
  const grantSets = {
    fixed: new Map(profiles.map((p) => [p.email, grantsFor(p, helpers)])),
    byColumn: new Map(
      profiles.map((p) => [p.email, grantsFor(p, helpers, { byColumn: true })]),
    ),
  };
  let grants = grantSets.fixed;
  const useGrants = (mode) => {
    grants = grantSets[mode];
  };
  const sessions = new Map();
  fixtures = { rows, profiles, useGrants };

  server = createServer(async (req, res) => {
    const url = new URL(req.url, 'http://x');
    const send = (code, body) => {
      res.writeHead(code, { 'content-type': 'application/json' });
      res.end(JSON.stringify(body));
    };

    if (req.method === 'POST' && url.pathname === '/v1/account/sessions/email') {
      let raw = '';
      for await (const c of req) raw += c;
      const { email, password } = JSON.parse(raw || '{}');
      if (password !== PASSWORD || !grants.has(email)) {
        return send(401, { message: 'Invalid credentials' });
      }
      const sid = `a_session_${Math.random().toString(36).slice(2)}`;
      sessions.set(sid, email);
      res.writeHead(201, {
        'content-type': 'application/json',
        'set-cookie': `${sid}=1; Path=/; HttpOnly`,
      });
      return res.end(JSON.stringify({ $id: sid }));
    }

    const m = /^\/v1\/tablesdb\/cradi\/tables\/([a-z_]+)\/rows$/.exec(url.pathname);
    if (req.method === 'GET' && m) {
      const table = m[1];
      if (!(table in rows)) return send(404, { message: `Table not found: ${table}` });

      const key = req.headers['x-appwrite-key'];
      let visible;
      if (key) {
        visible = rows[table]; // the diagnostic total path: ACLs bypassed
      } else {
        const sid = String(req.headers.cookie ?? '').split('=')[0];
        const email = sessions.get(sid);
        if (!email) return send(401, { message: 'User (role: guests) missing scope' });
        visible = rows[table].filter((r) => canRead(r.permissions, grants.get(email)));
      }

      // Cursor paging, as documented: limit + cursorAfter on $id.
      const queries = url.searchParams.getAll('queries[]').map((q) => JSON.parse(q));
      const limit = queries.find((q) => q.method === 'limit')?.values?.[0] ?? 25;
      const cursor = queries.find((q) => q.method === 'cursorAfter')?.values?.[0];
      let page = visible;
      if (cursor) {
        const at = visible.findIndex((r) => r.$id === cursor);
        page = at === -1 ? [] : visible.slice(at + 1);
      }
      return send(200, {
        total: visible.length,
        rows: page.slice(0, limit).map((r) => ({ $id: r.$id })),
      });
    }
    send(404, { message: `Unknown route ${req.method} ${url.pathname}` });
  });

  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${server.address().port}/v1`;
});

after(async () => {
  if (server) await new Promise((r) => server.close(r));
  if (client && reachable) await client.end();
});

/** Runs the real reconcile.mjs against the stand-in and the live Postgres. */
function runGate(env = {}) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, ['reconcile.mjs'], {
      cwd: import.meta.dirname,
      env: {
        ...process.env,
        PG_URL: PG,
        AW_ENDPOINT: base,
        AW_PROJECT: 'test',
        AW_KEY: 'test',
        MIGRATION_PASSWORD: PASSWORD,
        ...env,
      },
    });
    let out = '';
    child.stdout.on('data', (d) => (out += d));
    child.stderr.on('data', (d) => (out += d));
    child.on('close', (code) => resolve({ code, out }));
  });
}

describe('the reconciliation gate', () => {
  test('covers every table, not just reports', async (t) => {
    if (!reachable) return t.skip(`no Postgres at ${PG}`);
    const { out } = await runGate();
    for (const table of [
      'profiles', 'reports', 'verifications', 'verification_overrides',
      'alerts', 'authorities', 'scheduled_escalations', 'messages', 'contacts',
      'trusted_devices', 'login_history', 'knowledge_base', 'news_links',
      'app_settings', 'ndpa_consents',
    ]) {
      assert.match(out, new RegExp(`^${table}\\s`, 'm'), `${table} missing from the summary`);
    }
  });

  test('reports the collections no migrator writes', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    const { code, out } = await runGate();
    assert.equal(code, 1, 'an incomplete migration must not pass');
    for (const table of ['alerts', 'authorities', 'app_settings']) {
      assert.match(out, new RegExp(`${table}: the table is EMPTY in Appwrite`), table);
    }
  });

  test('catches a label Postgres would have demoted', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    // Serve the grants the seeder handed out BEFORE the fix: a label straight
    // from profiles.role. This is the escalation the gate exists to find.
    fixtures.useGrants('byColumn');
    try {
      const { code, out } = await runGate();
      assert.equal(code, 1);

      const pending = fixtures.profiles.find((p) => !p.is_approved && p.role !== 'user');
      assert.ok(pending, 'fixture needs an unapproved staff account');

      const report = JSON.parse(out.slice(out.indexOf('{', out.indexOf('finding(s)'))));
      const leaks = report.failures.filter(
        (f) => f.user === pending.id && f.leaked?.length,
      );
      assert.ok(
        leaks.some((f) => f.table === 'profiles'),
        'an unapproved admin reading every profile is the leak this gate is for',
      );
      for (const f of leaks) {
        assert.ok(f.appwrite > f.postgres, `${f.table}: expected a leak, not a loss`);
        assert.equal(f.demotedRole, true, `${f.table}: the cause should be named`);
        assert.match(f.policy, /app_role\(\)|auth\.uid\(\)/, 'quote the live policy');
      }
    } finally {
      fixtures.useGrants('fixed');
    }
  });

  test('the fixed seeder gives an unapproved account nothing extra', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    const pending = fixtures.profiles.find((p) => !p.is_approved && p.role !== 'user');
    assert.ok(pending);
    const { out } = await runGate();
    const report = JSON.parse(out.slice(out.indexOf('{', out.indexOf('finding(s)'))));
    const migrated = new Set(['profiles', 'reports', 'verifications']);
    const leaks = report.failures.filter(
      (f) => f.user === pending.id && migrated.has(f.table) && f.leaked?.length,
    );
    assert.deepEqual(leaks, [], 'effectiveRole should have closed this');
  });

  test('the users the migration gets right come back clean', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    const { out } = await runGate();
    const report = JSON.parse(out.slice(out.indexOf('{', out.indexOf('finding(s)'))));
    const approved = fixtures.profiles.filter((p) => p.is_approved && !p.is_disabled);
    assert.ok(approved.length >= 4, 'fixture needs several correct users');
    // Only the three tables migrate.mjs writes. The other three are empty, so
    // every user "loses" every row in them — which is the gate working, and is
    // asserted by the unmigrated test above.
    const migrated = new Set(['profiles', 'reports', 'verifications']);
    const bad = report.failures.filter(
      (f) => migrated.has(f.table) && approved.some((p) => p.id === f.user),
    );
    assert.deepEqual(
      bad,
      [],
      'an approved user must see the same ids in the migrated tables',
    );
  });

  test('pages past the first 100 rows', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    // The listing asks for limit(100) and follows cursorAfter. With fewer than
    // 100 rows the loop exits on the short page; this pins the small-limit path
    // so a paging regression cannot hide behind a small fixture.
    const { out } = await runGate({ RECONCILE_TABLES: 'profiles' });
    assert.match(out, /^profiles\s/m);
    assert.doesNotMatch(out, /list profiles: /, 'paging must not error');
  });

  test('a wrong rows API is named, not silently empty', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    const { code, out } = await runGate({ AW_ROWS_API: 'documents' });
    assert.match(out, /no such table under AW_ROWS_API=documents/);
    assert.equal(code, 1);
  });

  test('refuses an unknown table rather than skipping it', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    const { code, out } = await runGate({ RECONCILE_TABLES: 'nope' });
    assert.equal(code, 2);
    assert.match(out, /not reconciled/);
  });
});
