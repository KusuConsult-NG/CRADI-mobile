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
import { test, before, after, beforeEach, describe } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { Readable } from 'node:stream';
import { spawn } from 'node:child_process';
import pg from 'pg';

const PG = process.env.PG_URL ?? 'postgres://postgres@127.0.0.1:5433/cradi_mig';

let reachable = true;
let client;
let server;
let supabase;
let base;
let supabaseBase;
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
function grantsFor(p, { wardTeam, roleLabel, accountLabels }, { byColumn = false } = {}) {
  const g = [`user:${p.id}`];
  // `byColumn` reproduces what both the seeder and `write.js` used to do: the
  // role label from `profiles.role` alone, with no approval condition. The
  // fixed path asks `accountLabels`, which is `app_role()`'s rule and the one
  // the running system uses.
  const labels = byColumn
    ? [String(p.role ?? 'user')].filter((r) => r !== 'user').map(roleLabel)
    : accountLabels({ role: p.role, isApproved: p.is_approved, isDisabled: p.is_disabled });
  for (const l of labels) g.push(`label:${l}`);
  if (labels.includes('ewm') && p.ward) g.push(`team:${wardTeam(p.state, p.lga, p.ward)}`);
  return new Set(g);
}

/** Whether any `read("…")` in [permissions] names a principal the user holds. */
const matches = (permissions, grants) =>
  (permissions ?? []).some((perm) => {
    const m = /^read\("([^"]+)"\)$/.exec(perm);
    return m && grants.has(m[1]);
  });

/**
 * Appwrite's actual rule, which is the whole reason this is modelled rather
 * than assumed: **row permissions are consulted only when the table has row
 * security switched on.** With it off, the table's own permissions decide, and
 * a per-row ACL is stored but inert.
 *
 * `plan.mjs` sets `documentSecurity: true` on `profiles`, `reports` and
 * `verifications` and leaves it off for the six this suite also migrates. A
 * stand-in that consulted row ACLs everywhere would have reported those six as
 * perfectly migrated while the real project served them from a table rule
 * nobody had checked.
 */
/** Whether per-row ACLs are consulted at all for this table. */
const rowSecurity = (t) => t.rowSecurity ?? t.documentSecurity ?? false;

function canRead(table, row, grants, plan) {
  const t = plan.get(table);
  if (!t) return false;
  if (matches(t.permissions, grants)) return true;
  return rowSecurity(t) ? matches(row.permissions, grants) : false;
}

/**
 * May this session LIST the table at all?
 *
 * Appwrite answers 401 — it does not answer an empty page — when row security
 * is off and the table's own permissions name no principal the session holds.
 * Modelled because the gate's handling of that status is the difference between
 * "this user can read nothing here" and "nobody checked", and a stand-in that
 * filtered rows instead of refusing the query left that branch untested and
 * every empty table reading as a clean match.
 */
function canList(table, grants, plan, denied) {
  if (denied.has(table)) return false;
  const t = plan.get(table);
  if (!t) return false;
  return rowSecurity(t) || matches(t.permissions, grants);
}

/** Every principal a signed-in user holds, for matching against ACL strings. */
function principals(p, grants) {
  // `any` and `users` are roles Appwrite gives every request and every session.
  return new Set([...grants, 'any', 'users']);
}

before(async () => {
  client = new pg.Client({ connectionString: PG });
  try {
    await client.connect();
  } catch {
    reachable = false;
    return;
  }

  const plan = new Map(
    (await import('../../../infra/appwrite/plan.mjs')).COLLECTIONS.map((c) => [c.id, c]),
  );
  const { wardTeam, roleLabel } = await import('./migrate.mjs');

  const profiles = (
    await client.query(
      `select p.id, p.name, p.role, p.state, p.lga, p.ward, p.is_approved, p.is_disabled, u.email
         from profiles p join auth.users u on u.id = p.id order by p.name`,
    )
  ).rows;

  // Every table starts empty, as an unmigrated project is. `copy-tables.mjs`
  // writes all nine now, so nothing here pre-populates them — a fixture that
  // did would be asserting about itself.
  const rows = { profiles: [], reports: [], verifications: [] };
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

  const { accountLabels } = await import('../../../functions/cradi/src/lib/policy.js');
  const helpers = { wardTeam, roleLabel, accountLabels };

  // Storage. The object list is real — `storage.objects` in the live database —
  // and each gets deterministic bytes so a size mismatch after the round trip
  // would show. The Appwrite side starts empty, as an unmigrated project is.
  const objects = (
    await client.query(
      `select bucket_id, name from storage.objects
        where name is not null and name <> '' order by bucket_id, name`,
    )
  ).rows.map((o) => ({
    ...o,
    bytes: new Uint8Array(
      Array.from({ length: 64 + (o.name.length % 32) }, (_, i) => (i * 7 + o.name.length) % 256),
    ),
  }));
  const files = { 'report-images': [], 'profile-images': [] };
  // Two grant maps: what the seeder used to hand out, and what it hands out now.
  // Keyed by user id: the gate mints a session for an id, never an email.
  const grantSets = {
    fixed: new Map(profiles.map((p) => [p.id, principals(p, grantsFor(p, helpers))])),
    byColumn: new Map(
      profiles.map((p) => [p.id, principals(p, grantsFor(p, helpers, { byColumn: true }))]),
    ),
  };
  /** The accounts seed-identities.mjs would have created. */
  const accounts = new Set(profiles.map((p) => p.id));
  const tokens = new Map();
  let grants = grantSets.fixed;
  const useGrants = (mode) => {
    grants = grantSets[mode];
  };
  const sessions = new Map();
  const liveSessions = () => sessions.size;
  // Tables the stand-in refuses to list for any session, whatever the plan
  // says. Stands in for the mis-stamped permission that no row count can
  // reveal — see the test that uses it.
  const denied = new Set();
  // The six tables copy-tables.mjs writes. Emptied before every test, because
  // the stand-in's rows are shared mutable state and a test that runs the copier
  // would otherwise decide what the next test sees.
  const COPIED = [
    'profiles', 'reports', 'verifications',
    'alerts', 'authorities', 'app_settings', 'scheduled_escalations',
    'knowledge_base', 'news_links',
  ];
  const clearCopied = () => {
    for (const t of COPIED) rows[t] = [];
  };
  const clearFiles = () => {
    for (const b of Object.keys(files)) files[b] = [];
  };
  const denyList = (table) => denied.add(table);
  const allowList = (table) => denied.delete(table);
  fixtures = {
    rows, profiles, useGrants, clearCopied, COPIED, objects, files, clearFiles,
    denyList, allowList, liveSessions,
  };

  server = createServer(async (req, res) => {
    const url = new URL(req.url, 'http://x');
    const send = (code, body) => {
      res.writeHead(code, { 'content-type': 'application/json' });
      res.end(JSON.stringify(body));
    };

    // `POST /users/{id}/tokens` — the secret comes back only for a keyed call,
    // which is exactly what the gate checks for, so the stand-in enforces it.
    const tm = /^\/v1\/users\/([^/]+)\/tokens$/.exec(url.pathname);
    if (req.method === 'POST' && tm) {
      const userId = decodeURIComponent(tm[1]);
      if (!accounts.has(userId)) return send(404, { message: 'User with the requested ID could not be found' });
      const secret = `tok_${Math.random().toString(36).slice(2, 8)}`;
      const keyed = Boolean(req.headers['x-appwrite-key']);
      if (keyed) tokens.set(secret, userId);
      return send(201, {
        $id: `t_${secret}`,
        userId,
        // Appwrite blanks it without a key. Reading that as "no rows" is the
        // mistake the gate names explicitly.
        secret: keyed ? secret : '',
        expire: new Date(Date.now() + 15 * 60_000).toISOString(),
      });
    }

    // `POST /account/sessions/token` — exchanges the secret for a session, with
    // no key: node-appwrite 29's `createSession` sends only the project header.
    if (req.method === 'POST' && url.pathname === '/v1/account/sessions/token') {
      let raw = '';
      for await (const c of req) raw += c;
      const { userId, secret } = JSON.parse(raw || '{}');
      if (!secret || tokens.get(secret) !== userId) {
        return send(401, { message: 'Invalid token passed in the request' });
      }
      tokens.delete(secret); // single use, as a token is
      const sid = `a_session_${Math.random().toString(36).slice(2)}`;
      sessions.set(sid, userId);
      res.writeHead(201, {
        'content-type': 'application/json',
        'set-cookie': `${sid}=1; Path=/; HttpOnly`,
      });
      return res.end(JSON.stringify({ $id: sid, userId, secret: sid }));
    }

    // `DELETE /account/sessions/current` — the gate ending the session it
    // minted. Modelled so the cleanup is asserted rather than assumed: without
    // it the gate left one live session per user behind, on every run.
    if (req.method === 'DELETE' && url.pathname === '/v1/account/sessions/current') {
      const sid = String(req.headers.cookie ?? '').split('=')[0];
      if (!sessions.has(sid)) return send(401, { message: 'User (role: guests) missing scope' });
      sessions.delete(sid);
      res.writeHead(204);
      return res.end();
    }

    const m = /^\/v1\/tablesdb\/cradi\/tables\/([a-z_]+)\/rows$/.exec(url.pathname);

    if (req.method === 'POST' && m) {
      // What `copy-tables.mjs` writes. Keyed by rowId so a re-run answers 409,
      // which is the idempotency the runbook leans on.
      const table = m[1];
      if (!(table in rows)) return send(404, { message: `Table not found: ${table}` });
      let raw = '';
      for await (const c of req) raw += c;
      const { rowId, data, permissions } = JSON.parse(raw || '{}');
      if (!rowId) return send(400, { message: 'Missing required parameter: rowId' });
      if (rows[table].some((r) => r.$id === rowId)) {
        return send(409, { message: `Row with the requested ID already exists` });
      }
      // Reject a column the plan does not have, exactly as the server would —
      // this is what catches a snake_case write against a camelCase table.
      const planned = new Set((plan.get(table)?.columns ?? []).map((c) => c.key));
      const unknown = Object.keys(data ?? {}).filter((k) => !planned.has(k));
      if (unknown.length) {
        return send(400, { message: `Unknown attribute: "${unknown[0]}"` });
      }
      rows[table].push({ $id: rowId, permissions: permissions ?? [], data });
      return send(201, { $id: rowId, ...data });
    }

    if (req.method === 'GET' && m) {
      const table = m[1];
      if (!(table in rows)) return send(404, { message: `Table not found: ${table}` });

      const key = req.headers['x-appwrite-key'];
      let visible;
      if (key) {
        visible = rows[table]; // the diagnostic total path: ACLs bypassed
      } else {
        const sid = String(req.headers.cookie ?? '').split('=')[0];
        const who = sessions.get(sid);
        if (!who) return send(401, { message: 'User (role: guests) missing scope' });
        const held = grants.get(who);
        if (!canList(table, held, plan, denied)) {
          return send(401, { message: `User (role: users) missing scope (collections.read)` });
        }
        visible = rows[table].filter((r) => canRead(table, r, held, plan));
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
        // Appwrite returns a row's columns alongside its id, and the URL
        // rewrite reads one of them — returning only `$id` left that path
        // untested and passing.
        rows: page.slice(0, limit).map((r) => ({ $id: r.$id, ...(r.data ?? {}) })),
      });
    }
    // What copy-storage.mjs writes, and what the gate lists.
    const sm = /^\/v1\/storage\/buckets\/([a-z-]+)\/files$/.exec(url.pathname);
    if (sm) {
      const bucket = sm[1];
      if (!(bucket in files)) return send(404, { message: 'Bucket not found' });
      if (req.method === 'POST') {
        const form = await new Response(Readable.toWeb(req), {
          headers: { 'content-type': req.headers['content-type'] ?? '' },
        }).formData();
        const fileId = String(form.get('fileId') ?? '');
        if (!fileId) return send(400, { message: 'Missing required parameter: fileId' });
        if (fileId.length > 36) return send(400, { message: 'Invalid `fileId`' });
        if (files[bucket].some((f) => f.$id === fileId)) {
          return send(409, { message: 'File with the requested ID already exists' });
        }
        const blob = form.get('file');
        const bytes = new Uint8Array(await blob.arrayBuffer());
        files[bucket].push({ $id: fileId, name: blob.name, size: bytes.length, bytes });
        return send(201, { $id: fileId, name: blob.name, sizeOriginal: bytes.length });
      }
      if (req.method === 'GET') {
        if (!req.headers['x-appwrite-key']) {
          return send(401, { message: 'User (role: guests) missing scope' });
        }
        const all = files[bucket];
        const qs2 = url.searchParams.getAll('queries[]').map((q) => JSON.parse(q));
        const limit = qs2.find((q) => q.method === 'limit')?.values?.[0] ?? 25;
        const cursor = qs2.find((q) => q.method === 'cursorAfter')?.values?.[0];
        let page = all;
        if (cursor) {
          const at = all.findIndex((f) => f.$id === cursor);
          page = at === -1 ? [] : all.slice(at + 1);
        }
        return send(200, {
          total: all.length,
          files: page.slice(0, limit).map((f) => ({ $id: f.$id, name: f.name })),
        });
      }
    }

    // The rewrite's PATCH.
    const pm = /^\/v1\/tablesdb\/cradi\/tables\/([a-z_]+)\/rows\/(.+)$/.exec(url.pathname);
    if (req.method === 'PATCH' && pm) {
      const [, ptable, rowId] = pm;
      const row = rows[ptable]?.find((r) => r.$id === decodeURIComponent(rowId));
      if (!row) return send(404, { message: 'Row not found' });
      let raw = '';
      for await (const c of req) raw += c;
      const { data } = JSON.parse(raw || '{}');
      row.data = { ...(row.data ?? {}), ...(data ?? {}) };
      return send(200, { $id: row.$id, ...row.data });
    }

    send(404, { message: `Unknown route ${req.method} ${url.pathname}` });
  });

  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${server.address().port}/v1`;

  /*
   * A second origin, standing in for Supabase Storage.
   *
   * The bytes have to come from somewhere, and `copy-storage.mjs` reads them
   * over HTTP from `SUPABASE_URL`. Serving them here makes the copy a real
   * round trip — a download, a multipart upload, and a size to compare — rather
   * than an assertion about what a function returned.
   */
  supabase = createServer((req, res) => {
    const m = /^\/storage\/v1\/object\/public\/([^/]+)\/(.+)$/.exec(req.url ?? '');
    if (!m) {
      res.writeHead(404, { 'content-type': 'application/json' });
      return res.end('{"error":"not found"}');
    }
    const bucket = decodeURIComponent(m[1]);
    const name = m[2].split('/').map(decodeURIComponent).join('/');
    const object = objects.find((o) => o.bucket_id === bucket && o.name === name);
    if (!object) {
      res.writeHead(404, { 'content-type': 'application/json' });
      return res.end('{"error":"Object not found"}');
    }
    res.writeHead(200, { 'content-type': 'image/jpeg' });
    res.end(Buffer.from(object.bytes));
  });
  await new Promise((r) => supabase.listen(0, '127.0.0.1', r));
  supabaseBase = `http://127.0.0.1:${supabase.address().port}`;
});

after(async () => {
  if (server) await new Promise((r) => server.close(r));
  if (supabase) await new Promise((r) => supabase.close(r));
  if (client && reachable) await client.end();
});

/** The gate's findings, or an empty report when it exited clean. */
function findings(out) {
  const at = out.indexOf('finding(s)');
  if (at === -1) return { failures: [], unmigrated: [] };
  return JSON.parse(out.slice(out.indexOf('{', at)));
}

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
        ...env,
      },
    });
    let out = '';
    child.stdout.on('data', (d) => (out += d));
    child.stderr.on('data', (d) => (out += d));
    child.on('close', (code) => resolve({ code, out }));
  });
}

/**
 * Runs copy-tables.mjs against the stand-in and the live Postgres.
 *
 * The streams are kept apart. The copier prints its JSON summary on stdout and
 * its skip and error detail on stderr, and a caller that merged them and then
 * took "everything from the first brace" parsed cleanly only while nothing was
 * ever skipped — the first fixture row the copier declined broke every such
 * test with a JSON syntax error about the summary, which was fine.
 */
function runCopy() {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, ['copy-tables.mjs'], {
      cwd: import.meta.dirname,
      env: {
        ...process.env,
        PG_URL: PG,
        AW_ENDPOINT: base,
        AW_PROJECT: 'test',
        AW_KEY: 'test',
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
        report: JSON.parse(stdout.slice(stdout.indexOf('{'))),
      }),
    );
  });
}

describe('copying every collection', () => {
  beforeEach(() => fixtures?.clearCopied());

  test('writes every row, and the second run is a no-op', async (t) => {
    if (!reachable) return t.skip('no Postgres');

    const first = await runCopy();
    assert.equal(first.code, 0, first.out);
    const counts = first.report.counts;
    for (const table of [
      'profiles', 'reports', 'verifications',
      'alerts', 'authorities', 'app_settings', 'scheduled_escalations',
      'knowledge_base', 'news_links',
    ]) {
      const c = counts[table];
      assert.ok(c, `${table} missing from the summary`);
      assert.ok(c.source > 0, `${table}: fixture has no rows to copy`);
      assert.equal(c.failed, 0, `${table}: ${first.out}`);
      // Every source row is accounted for, as written or as declined on
      // purpose — not "every row was written", which would make the copier's
      // own `skip` predicates a test failure.
      assert.equal(c.created + c.skipped, c.source, `${table}: rows unaccounted for`);
    }

    // And the skips are the declared ones, not a silent shortfall: the fixture
    // carries two orphan reports with no LGA, which is what `copy-tables.mjs`
    // declines and what `reconcile.mjs`'s NOT_COPIED forgives.
    assert.equal(counts.reports.skipped, 2, first.stderr);
    assert.match(first.stderr, /has no LGA/);
    // And the copier's second skip, which follows from the first: a vote on a
    // report that did not migrate has no ward to be read by.
    assert.equal(counts.verifications.skipped, 1, first.stderr);
    assert.match(first.stderr, /was not migrated/);

    // Idempotent: the Postgres key is the Appwrite id, so a re-run collides.
    const second = await runCopy();
    assert.equal(second.code, 0, second.out);
    const again = second.report.counts;
    for (const table of Object.keys(counts)) {
      assert.equal(again[table].created, 0, `${table}: re-run created rows`);
      assert.equal(
        again[table].exists + again[table].skipped,
        counts[table].source,
        `${table}: not 409`,
      );
    }
  });

  test('no Postgres column is silently dropped', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    const { report } = await runCopy();
    assert.deepEqual(
      report.unplannedColumns,
      {},
      'a column with no home in columns.json loses data; add it to the plan',
    );
  });

  test('the gate stops calling them unmigrated', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    await runCopy();
    const { out } = await runGate();
    for (const table of [
      'alerts', 'authorities', 'app_settings', 'scheduled_escalations',
      'knowledge_base', 'news_links',
    ]) {
      assert.doesNotMatch(
        out,
        new RegExp(`${table}: the table is EMPTY in Appwrite`),
        `${table} should be migrated now`,
      );
    }
  });

  test('the gate passes once they are copied', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    await runCopy();
    // Storage too: the gate's verdict now covers whether every file arrived.
    await runCopyStorage();
    const { code, out } = await runGate();

    const report = findings(out);
    // Never a leak, here or anywhere: that is the one thing no declaration
    // forgives.
    assert.deepEqual(
      report.failures.filter((f) => f.leaked?.length),
      [],
      'no user may see a row Postgres would not have shown them',
    );
    assert.deepEqual(report.failures, [], out);
    assert.deepEqual(report.unmigrated, [], out);

    // `authorities` and `scheduled_escalations` are narrower on purpose, and
    // the run says so out loud rather than passing in silence.
    assert.match(out, /authorities: \d+ user\(s\) see fewer rows/);
    assert.match(out, /ACCEPTED as a deliberate narrowing/);
    assert.match(
      out,
      /every user sees exactly what they saw before, in every table, and every stored file arrived/,
    );
    assert.equal(code, 0, out);
  });

  test('it leaves no session behind', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    await runCopy();
    const { code, out } = await runGate();
    assert.equal(code, 0, out);
    // One per user was minted. A read-only check must end them: a session left
    // live for Appwrite's default year reads from outside exactly like somebody
    // signing in with a leaked password, and the password-recovery audit treats
    // that as a finding.
    assert.equal(fixtures.liveSessions(), 0, out);
    assert.doesNotMatch(out, /could not be ended/, out);
  });

  test('the rows the copier declines are forgiven by name, not by filter', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    await runCopy();
    const { code, out } = await runGate();
    assert.equal(code, 0, out);

    // The two orphan reports are still counted on the Postgres side, named,
    // and printed with the reason. An earlier version excluded them from the
    // query, which passed just as quietly but could no longer have told a
    // declared skip from a row that failed to migrate.
    assert.match(out, /reports: 2 source row\(s\) were NOT copied, ACCEPTED by declaration/);
    assert.match(out, /legacy orphan rows with no LGA/);
    assert.match(out, /where lga is null or lga = ''/);
    assert.match(out, /0000000b0f01/, 'the declined ids belong in the output');
    // Both of the copier's skips are declared, not just the one that is easy
    // to see: the second follows from the first and would otherwise read as a
    // loss on every run.
    assert.match(out, /verifications: 1 source row\(s\) were NOT copied/);
    assert.match(out, /a vote on a report that was not copied/);
  });

  test('a row missing for any other reason is still a finding', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    await runCopy();
    // Drop a report that is NOT one of the declared orphans, as a copy that
    // silently lost a row would. The declaration must forgive its two ids and
    // nothing else.
    const victim = fixtures.rows.reports.find((r) => !r.$id.includes('0f0'));
    assert.ok(victim, 'fixture needs a non-orphan report in Appwrite');
    fixtures.rows.reports = fixtures.rows.reports.filter((r) => r !== victim);

    const { code, out } = await runGate();
    assert.equal(code, 1, out);
    const lost = findings(out).failures.filter((f) => f.table === 'reports');
    assert.ok(lost.length, out);
    for (const f of lost) {
      assert.ok(f.lost?.includes(victim.$id), `the lost row should be named: ${f.lost}`);
      // The declared ids are counted beside the loss, never inside it.
      assert.deepEqual(
        f.lost.filter((id) => id.includes('0f0')),
        [],
        'a declared skip must not be reported as a loss',
      );
    }
    // And the declaration is still credited, for the one user whose RLS showed
    // them the orphans in the first place: a citizen never saw them, so there
    // is nothing for the declaration to forgive on their row.
    assert.ok(
      lost.some((f) => f.notCopied === 2),
      'the user who could see the orphans should have both credited',
    );
  });

  test('a table that admits nobody is a finding, not an empty one', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    await runCopy();

    // `messages` is empty in Postgres and empty in Appwrite, so every row
    // count on both sides is zero and no comparison of counts can say anything
    // about it. Only the status code can, and the gate used to read a 401 as
    // `[]` — which made a table nobody could open indistinguishable from a
    // table with nothing in it, and reported it as a clean match.
    const clean = await runGate();
    assert.equal(clean.code, 0, clean.out);
    assert.match(clean.out, /^messages\s+\d+\s+\d+\s+\d+\s+0\s/m, clean.out);

    fixtures.denyList('messages');
    try {
      const { code, out } = await runGate();
      assert.equal(code, 1, 'a table no session can open must not pass');
      const f = findings(out).failures.find((x) => x.table === 'messages');
      assert.ok(f, out);
      assert.match(f.error, /every one of the \d+ sessions was DENIED the table/);
      // The row counts are byte-for-byte what they were in the passing run.
      // The verdict changed because the status code was kept, nothing else.
      assert.match(out, /^messages\s+\d+\s+\d+\s+\d+\s+[1-9]/m, out);
    } finally {
      fixtures.allowList('messages');
    }
  });

  test('the tables that deny on purpose say so in the summary', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    await runCopy();
    const { code, out } = await runGate();
    assert.equal(code, 0, out);
    // Denied for every session, and declared — so it passes, and the `denied`
    // column is what says the permission was exercised at all.
    assert.match(out, /^scheduled_escalations\s+(\d+)\s+\d+\s+\d+\s+\1\s/m, out);
    // Denied for the five who hold neither label, read by the one admin.
    assert.match(out, /^verification_overrides\s+\d+\s+\d+\s+\d+\s+[1-9]/m, out);
  });
});

/** Runs copy-storage.mjs against both stand-ins and the live Postgres. */
function runCopyStorage() {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, ['copy-storage.mjs'], {
      cwd: import.meta.dirname,
      env: {
        ...process.env,
        PG_URL: PG,
        AW_ENDPOINT: base,
        AW_PROJECT: 'test',
        AW_KEY: 'test',
        SUPABASE_URL: supabaseBase,
      },
    });
    let out = '';
    child.stdout.on('data', (d) => (out += d));
    child.stderr.on('data', (d) => (out += d));
    child.on('close', (code) => resolve({ code, out }));
  });
}

describe('copying the storage buckets', () => {
  beforeEach(() => {
    fixtures?.clearFiles();
    fixtures?.clearCopied();
  });

  test('every object arrives, under the id the app will ask for', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    const { fileIdFor } = await import('./storage-ids.mjs');

    const { code, out } = await runCopyStorage();
    assert.equal(code, 0, out);
    const report = JSON.parse(out.slice(out.indexOf('{')));

    let expected = 0;
    for (const o of fixtures.objects) expected += 1;
    const copied = Object.values(report.buckets).reduce((n, b) => n + b.copied, 0);
    assert.equal(copied, expected, out);
    for (const b of Object.values(report.buckets)) assert.equal(b.failed, 0, out);

    // The id is the whole point: a file under any other id is unreachable,
    // because the client derives it from the path and nothing persists it.
    for (const o of fixtures.objects) {
      const want = fileIdFor(o.name);
      const got = fixtures.files[o.bucket_id].find((f) => f.$id === want);
      assert.ok(got, `${o.bucket_id}/${o.name} is not under ${want}`);
      assert.equal(got.size, o.bytes.length, `${o.name}: bytes did not survive`);
    }
  });

  test('a second run copies nothing', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    await runCopyStorage();
    const { code, out } = await runCopyStorage();
    assert.equal(code, 0, out);
    const report = JSON.parse(out.slice(out.indexOf('{')));
    for (const [bucket, b] of Object.entries(report.buckets)) {
      assert.equal(b.copied, 0, `${bucket}: re-run uploaded again`);
      assert.equal(b.exists, b.source, `${bucket}: not answered 409`);
    }
  });

  test('a Supabase URL left on a migrated row is rewritten to Appwrite', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    const { fileIdFor } = await import('./storage-ids.mjs');
    const withUrl = (
      await client.query(
        `select id, image_url from knowledge_base
          where image_url like '%/storage/v1/object/%' limit 1`,
      )
    ).rows[0];
    if (!withUrl) return t.skip('fixture has no Supabase URL on a row');

    await runCopy();            // knowledge_base must exist to be rewritten
    const { out } = await runCopyStorage();
    assert.match(out, /knowledge_base\.imageUrl: 1 of \d+ row\(s\) rewritten/, out);

    const row = fixtures.rows.knowledge_base.find((r) => r.$id === withUrl.id);
    assert.ok(row, 'the row should have been copied');
    const at = /\/storage\/v1\/object\/public\/([^/]+)\/(.+)$/.exec(withUrl.image_url);
    assert.match(
      row.data.imageUrl,
      new RegExp(`/storage/buckets/${at[1]}/files/${fileIdFor(at[2])}/view`),
      row.data.imageUrl,
    );
    assert.doesNotMatch(row.data.imageUrl, /supabase/);
  });

  test('an unmigrated table is named, not reported as nothing to do', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    // Nothing copied yet, so there is no row to carry a URL at all. The run
    // must say that, not "0 of 0 rewritten", which reads like success.
    const { out } = await runCopyStorage();
    assert.match(out, /reports\.imageUrls: no rows yet/, out);
    assert.match(out, /profiles\.profileImageUrl: no rows yet/, out);
  });

  test('the retargeted collections carry their images across', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    const { fileIdFor } = await import('./storage-ids.mjs');
    // The point of the retarget: `migrate.mjs` carried neither image column, so
    // every photograph in the system was lost. copy-tables.mjs carries both.
    const r = (
      await client.query(
        `select id, image_urls from reports
          where array_length(image_urls, 1) > 0 limit 1`,
      )
    ).rows[0];
    const pr = (
      await client.query(
        `select id, profile_image_url from profiles
          where profile_image_url like '%/storage/v1/object/%' limit 1`,
      )
    ).rows[0];
    if (!r || !pr) return t.skip('fixture has no stored images on rows');

    await runCopy();
    const { out } = await runCopyStorage();
    assert.match(out, /reports\.imageUrls: 1 of \d+ row\(s\) rewritten/, out);
    assert.match(out, /profiles\.profileImageUrl: 1 of \d+ row\(s\) rewritten/, out);

    const row = fixtures.rows.reports.find((x) => x.$id === r.id);
    const at = /\/storage\/v1\/object\/public\/([^/]+)\/(.+)$/.exec(r.image_urls[0]);
    assert.deepEqual(row.data.imageUrls, [
      `${base}/storage/buckets/${at[1]}/files/${fileIdFor(at[2])}/view?project=test`,
    ]);

    const prow = fixtures.rows.profiles.find((x) => x.$id === pr.id);
    assert.doesNotMatch(prow.data.profileImageUrl, /supabase/);
  });

  test('the gate reports a missing file, then stops once it is there', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    const before = await runGate();
    assert.equal(before.code, 1);
    assert.match(before.out, /object\(s\) are not in Appwrite under the id/, before.out);

    await runCopyStorage();
    const after = await runGate();
    assert.match(after.out, /^report-images\s/m, after.out);
    assert.doesNotMatch(after.out, /are not in Appwrite under the id/, after.out);
  });
});

describe('the reconciliation gate', () => {
  // Every test here describes the state BEFORE the six are copied.
  beforeEach(() => fixtures?.clearCopied());

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
    await runCopy();
    try {
      const { code, out } = await runGate();
      assert.equal(code, 1);

      const pending = fixtures.profiles.find((p) => !p.is_approved && p.role !== 'user');
      assert.ok(pending, 'fixture needs an unapproved staff account');

      const report = findings(out);
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
        // The live policy, whatever it is for that table — the leak now shows
        // on `authorities` too, whose policy is a bare `is_staff()`.
        assert.match(f.policy, new RegExp(`^${f.table}_select: \\S`), f.policy);
      }
    } finally {
      fixtures.useGrants('fixed');
    }
  });

  test('the fixed seeder gives an unapproved account nothing extra', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    const pending = fixtures.profiles.find((p) => !p.is_approved && p.role !== 'user');
    assert.ok(pending);
    await runCopy();
    const { out } = await runGate();
    const report = findings(out);
    const migrated = new Set(['profiles', 'reports', 'verifications']);
    const leaks = report.failures.filter(
      (f) => f.user === pending.id && migrated.has(f.table) && f.leaked?.length,
    );
    assert.deepEqual(leaks, [], 'effectiveRole should have closed this');
  });

  test('the users the migration gets right come back clean', async (t) => {
    if (!reachable) return t.skip('no Postgres');
    await runCopy();
    const { out } = await runGate();
    const report = findings(out);
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
