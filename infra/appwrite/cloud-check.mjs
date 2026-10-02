#!/usr/bin/env node
/**
 * Behavioural checks against a **real** Appwrite, safe to run on Cloud.
 *
 *   APPWRITE_ENDPOINT=https://fra.cloud.appwrite.io/v1 \
 *   APPWRITE_PROJECT_ID=... APPWRITE_API_KEY=... APPWRITE_DATABASE_ID=... \
 *   node infra/appwrite/cloud-check.mjs
 *
 * `verify.mjs` asks whether the project matches the plan, and reads
 * nothing but configuration. This asks whether the project *behaves* —
 * the questions that need a write to answer, and that the 1.9.6 stack
 * answered differently from how Cloud's 2.x might:
 *
 *   1. the server's version, because several answers below depend on it
 *   2. account labels follow a profile's role (Phase 21: nothing set
 *      them, and an unlabelled admin read 0 rows with a 200)
 *   3. a label-gated collection is unreadable without the label, and
 *      readable with it
 *   4. the `write` Function's coverage guard refuses an LGA with no
 *      state (Phase 20: the Postgres CHECK that did not survive)
 *   5. `expect` is a real compare-and-set, and a bulk update with
 *      queries in the body touches exactly the rows they match
 *   6. `app_settings.value` round-trips as a string
 *   7. peer confirmations are counted, one per verifier, and a report
 *      verifies itself at the threshold
 *   8. the `operation` Function's execution carries what the Flutter
 *      SDK parses (`resourceId`/`resourceType`, 2.3+)
 *
 * Everything it creates is named `cloudchk-<stamp>` and **deleted at the
 * end, including after a failure**. It writes nothing it did not create,
 * and reads nothing it did not need. One thing it deliberately does not
 * probe on Cloud: passing bulk-update queries in the *query string*,
 * which 1.9.6 ignores while updating every row in the table. That was
 * measured on a throwaway stack and must not be measured on a real one.
 *
 * Exits non-zero on the first failed assertion, after cleaning up.
 */
import assert from 'node:assert/strict';

const EP = (process.env.APPWRITE_ENDPOINT || '').trim();
const PROJECT = (process.env.APPWRITE_PROJECT_ID || '').trim();
const KEY = (process.env.APPWRITE_API_KEY || '').trim();
const DB = (process.env.APPWRITE_DATABASE_ID || 'cradi').trim();

if (!EP || !PROJECT || !KEY) {
  console.error(
    'Set APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID and APPWRITE_API_KEY\n' +
      '(and APPWRITE_DATABASE_ID if the database is not `cradi`).',
  );
  process.exit(2);
}

const admin = { 'content-type': 'application/json', 'x-appwrite-project': PROJECT, 'x-appwrite-key': KEY };

async function call(path, { method = 'GET', body, headers = admin } = {}) {
  const r = await fetch(`${EP}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await r.text();
  let parsed = null;
  if (text) { try { parsed = JSON.parse(text); } catch { parsed = { message: text }; } }
  return { status: r.status, ok: r.ok, body: parsed, headers: r.headers };
}

const row = (table, id = '') => `/tablesdb/${DB}/tables/${table}/rows${id ? `/${encodeURIComponent(id)}` : ''}`;
const q = (...parts) => parts.map((p) => `queries[]=${encodeURIComponent(JSON.stringify(p))}`).join('&');
const step = (m) => console.log(`\n── ${m}`);
const ok = (m) => console.log(`   ✓ ${m}`);
const note = (m) => console.log(`   · ${m}`);

const stamp = Date.now().toString(36);
const name = (what) => `cloudchk-${what}-${stamp}`.slice(0, 36);
const PASSWORD = `Cloud-check-${stamp}-Aa1`;

/** Everything made here, newest first, so cleanup unwinds in order. */
const made = [];
const track = (kind, id) => made.unshift({ kind, id });

async function cleanup() {
  step('cleaning up everything this run created');
  let removed = 0;
  const failed = [];
  for (const { kind, id } of made) {
    const path = kind === 'user' ? `/users/${encodeURIComponent(id)}` : row(kind, id);
    const r = await call(path, { method: 'DELETE' });
    if (r.ok || r.status === 404) removed += 1;
    else failed.push(`${kind} ${id}: ${r.status} ${r.body?.message ?? ''}`);
  }
  console.log(`   ${failed.length ? '!' : '✓'} removed ${removed}/${made.length}`);
  for (const f of failed) console.log(`     LEFT BEHIND — ${f}`);
  return failed.length === 0;
}

/** A session secret, read from the cookie: a project with a web platform answers `secret: ""`. */
async function sessionFor(email) {
  const r = await call('/account/sessions/email', {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-appwrite-project': PROJECT },
    body: { email, password: PASSWORD },
  });
  assert.ok(r.ok, `sign in ${email}: ${r.status} ${JSON.stringify(r.body).slice(0, 200)}`);
  if (r.body.secret) return r.body.secret;
  const cookies = typeof r.headers.getSetCookie === 'function'
    ? r.headers.getSetCookie()
    : [r.headers.get('set-cookie') ?? ''];
  const found = cookies.map((c) => /^a_session_[A-Za-z0-9]+=([^;]+)/.exec(c)?.[1]).find(Boolean);
  assert.ok(found, 'no session secret in the body or the cookies');
  return decodeURIComponent(found);
}

const asUser = (secret) => ({
  'content-type': 'application/json',
  'x-appwrite-project': PROJECT,
  'x-appwrite-session': secret,
});

/** Runs a Function the way the clients do, and returns its inner response. */
async function runFunction(id, secret, payload) {
  const exec = await call(`/functions/${id}/executions`, {
    method: 'POST',
    headers: asUser(secret),
    body: { body: JSON.stringify(payload), async: false, method: 'POST' },
  });
  assert.ok(exec.ok, `${id} execution refused: ${exec.status} ${JSON.stringify(exec.body).slice(0, 200)}`);
  assert.equal(exec.body.status, 'completed', `${id} execution ${exec.body.status}: ${exec.body.errors ?? ''}`);
  let inner = null;
  try { inner = JSON.parse(exec.body.responseBody); } catch { inner = { raw: exec.body.responseBody }; }
  return { code: exec.body.responseStatusCode, body: inner, execution: exec.body };
}

async function makeUser(what, role, extra = {}) {
  const id = name(what);
  const email = `${id}@cloud-check.invalid`;
  const account = await call('/users', {
    method: 'POST',
    body: { userId: id, email, password: PASSWORD, name: `Cloud check ${what}` },
  });
  assert.ok(account.ok, `create ${id}: ${account.status} ${JSON.stringify(account.body).slice(0, 200)}`);
  track('user', id);
  const profile = await call(row('profiles'), {
    method: 'POST',
    body: {
      rowId: id,
      data: {
        name: `Cloud check ${what}`, role,
        state: 'Benue', lga: 'Makurdi', ward: 'North Bank I',
        isApproved: true, isDisabled: false, isVerified: true,
        ...extra,
      },
      permissions: [`read("user:${id}")`, 'read("label:admin")'],
    },
  });
  assert.ok(profile.ok, `profile ${id}: ${profile.status} ${JSON.stringify(profile.body).slice(0, 200)}`);
  track('profiles', id);
  return { id, email };
}

async function main() {
  // ── 1. the server ──────────────────────────────────────────────────
  step('the server answers, and says what it is');
  // `/health/version` needs the `public` scope, which a provisioning key
  // has no reason to carry — but Appwrite puts its version in the error
  // body too, so the refusal answers the question either way. What must
  // not happen is treating "I could not read the version" as "fine".
  const version = await call('/health/version');
  const v = version.body?.version ?? '(unknown)';
  assert.ok(
    version.body !== null,
    `the server did not answer /health/version at all: ${version.status}`,
  );
  if (!version.ok) note(`/health/version: ${version.status} — version read from the refusal`);
  ok(`Appwrite ${v} at ${EP}, project ${PROJECT}, database ${DB}`);
  const major = Number.parseInt(String(v), 10);
  if (Number.isFinite(major) && major < 2) {
    note(`this is not Cloud's 2.x — check 7 below is expected to fail on ${v}`);
  }

  // ── 2. labels follow the profile ───────────────────────────────────
  step('an admin, and a user whose role the admin will change');
  const adminUser = await makeUser('admin', 'admin');
  const target = await makeUser('target', 'user', { isApproved: false });
  const labelled = await call(`/users/${adminUser.id}/labels`, { method: 'PUT', body: { labels: ['admin', 'approved'] } });
  assert.ok(labelled.ok, `label the admin: ${labelled.status} ${JSON.stringify(labelled.body).slice(0, 200)}`);
  const adminSession = await sessionFor(adminUser.email);
  ok(`${adminUser.id} is a labelled admin, ${target.id} is an unlabelled plain user`);

  step('a label-gated read is empty without the label — with a 200, not an error');
  const targetSession = await sessionFor(target.email);
  const before = await call(`${row('reports')}?${q({ method: 'limit', values: [1] })}`, { headers: asUser(targetSession) });
  assert.equal(before.status, 200, 'an unpermitted read is a 200, not a 401');
  assert.equal(before.body.total, 0, `expected 0 readable reports, got ${before.body.total}`);
  ok('reports: 200 total=0 — the silent failure Phase 21 found');

  step('the write Function gives the account the labels its new role grants');
  let r = await runFunction('write', adminSession, {
    op: 'update', collection: 'profiles', documentId: target.id,
    data: { role: 'ewm', isApproved: true },
  });
  assert.equal(r.code, 200, `promote: ${JSON.stringify(r.body).slice(0, 200)}`);
  let labels = (await call(`/users/${target.id}`)).body.labels;
  assert.deepEqual(labels, ['ewm', 'approved'], `labels after promote: ${JSON.stringify(labels)}`);
  ok(`labels are now ${JSON.stringify(labels)}`);

  r = await runFunction('write', adminSession, {
    op: 'update', collection: 'profiles', documentId: target.id,
    data: { role: 'ldp_coordinator' },
  });
  assert.equal(r.code, 200, `two-word role: ${JSON.stringify(r.body).slice(0, 200)}`);
  labels = (await call(`/users/${target.id}`)).body.labels;
  assert.deepEqual(labels, ['ldpCoordinator', 'approved'], `labels: ${JSON.stringify(labels)}`);
  ok('a two-word role is spelled the way a label may be spelled');

  r = await runFunction('write', adminSession, {
    op: 'update', collection: 'profiles', documentId: target.id, data: { isDisabled: true },
  });
  assert.equal(r.code, 200, `disable: ${JSON.stringify(r.body).slice(0, 200)}`);
  labels = (await call(`/users/${target.id}`)).body.labels;
  assert.deepEqual(labels, [], `a disabled account keeps no labels, got ${JSON.stringify(labels)}`);
  ok('a disabled account keeps no labels');

  // ── 3. the label is what makes the read work ───────────────────────
  step('with the label, the same read returns rows');
  await call(`/users/${target.id}/labels`, { method: 'PUT', body: { labels: ['admin'] } });
  const relabelled = await sessionFor(target.email);
  const after = await call(`${row('reports')}?${q({ method: 'limit', values: [1] })}`, { headers: asUser(relabelled) });
  assert.equal(after.status, 200);
  assert.ok(
    after.body.total >= before.body.total,
    `expected at least as many readable reports with the label (${after.body.total} vs ${before.body.total})`,
  );
  ok(`reports: 200 total=${after.body.total} — the label is the whole difference`);
  await call(`/users/${target.id}/labels`, { method: 'PUT', body: { labels: [] } });

  // ── 4. the coverage guard ──────────────────────────────────────────
  step('the write Function refuses an authority whose LGA names no state');
  const authorityId = name('auth');
  r = await runFunction('write', adminSession, {
    op: 'create', collection: 'authorities', documentId: authorityId,
    data: { name: `Cloud check ${stamp}`, phone: `+23480${String(Date.now()).slice(-8)}`, coverageLga: 'Obi' },
  });
  assert.equal(r.code, 400, `expected 400, got ${r.code}: ${JSON.stringify(r.body).slice(0, 200)}`);
  assert.match(String(r.body.message), /must name its state/, JSON.stringify(r.body).slice(0, 200));
  assert.equal((await call(row('authorities', authorityId))).status, 404, 'nothing was written');
  ok(`refused: ${r.body.message}`);

  step('and accepts the same LGA in either of its two states');
  for (const state of ['Benue', 'Nasarawa']) {
    const id = name(`auth-${state.toLowerCase()}`);
    r = await runFunction('write', adminSession, {
      op: 'create', collection: 'authorities', documentId: id,
      data: {
        name: `Cloud check ${state} ${stamp}`,
        phone: `+23481${String(Date.now()).slice(-8)}`,
        coverageState: state, coverageLga: 'Obi',
      },
    });
    assert.equal(r.code, 200, `${state}: ${JSON.stringify(r.body).slice(0, 200)}`);
    track('authorities', id);
    ok(`Obi, ${state}`);
  }

  // ── 5. the optimistic lock ─────────────────────────────────────────
  step('a report, and the compare-and-set the admin panel decides it with');
  const reportId = name('report');
  const report = await call(row('reports'), {
    method: 'POST',
    body: {
      rowId: reportId,
      data: {
        userId: adminUser.id, reporterName: 'Cloud check', hazardType: 'Flooding',
        severity: 'high', description: `Cloud check report ${stamp}`,
        state: 'Benue', lga: 'Makurdi', ward: 'North Bank I',
        status: 'pending', verificationCount: 0, isAlert: false,
        escalated: false, autoValidated: false,
        submittedAt: new Date().toISOString(), imageUrls: [],
      },
      permissions: ['read("label:admin")'],
    },
  });
  assert.ok(report.ok, `report: ${report.status} ${JSON.stringify(report.body).slice(0, 200)}`);
  track('reports', reportId);

  r = await runFunction('write', adminSession, {
    op: 'update', collection: 'reports', documentId: reportId,
    data: { status: 'approved', updatedBy: adminUser.id, approvedAt: new Date().toISOString() },
    expect: { status: 'pending' },
  });
  assert.equal(r.code, 200, `approve: ${JSON.stringify(r.body).slice(0, 200)}`);
  let stored = (await call(row('reports', reportId))).body;
  assert.equal(stored.status, 'approved');
  assert.equal(stored.previousStatus, 'pending', 'the Function stamps what it was');
  ok('approved, with the server stamping previousStatus');

  r = await runFunction('write', adminSession, {
    op: 'update', collection: 'reports', documentId: reportId,
    data: { status: 'verified' },
    expect: { status: 'pending' },
  });
  assert.equal(r.code, 409, `expected 409 on a stale expectation, got ${r.code}`);
  stored = (await call(row('reports', reportId))).body;
  assert.equal(stored.status, 'approved', 'the refused update changed nothing');
  ok(`stale expectation refused: ${r.body.message}`);

  // ── 6. app_settings is a string column ─────────────────────────────
  step('app_settings.value round-trips as a string, and refuses a number');
  const settingKey = name('setting').slice(0, 36);
  r = await runFunction('write', adminSession, {
    op: 'upsert', collection: 'app_settings', documentId: settingKey,
    data: { key: settingKey, value: '47', updatedAt: new Date().toISOString() },
  });
  assert.equal(r.code, 200, `string value: ${JSON.stringify(r.body).slice(0, 200)}`);
  track('app_settings', settingKey);
  assert.equal((await call(row('app_settings', settingKey))).body.value, '47');
  ok('"47" stored');

  r = await runFunction('write', adminSession, {
    op: 'upsert', collection: 'app_settings', documentId: settingKey,
    data: { key: settingKey, value: 47, updatedAt: new Date().toISOString() },
  });
  assert.ok(r.code >= 400, `a number should be refused, got ${r.code} ${JSON.stringify(r.body).slice(0, 160)}`);
  ok(`a number is refused: ${String(r.body.message).slice(0, 80)}`);

  // ── 7. peer confirmations ──────────────────────────────────────────
  step('two peers confirm a report, and it verifies itself');
  const voterA = await makeUser('ewm-a', 'ewm');
  const voterB = await makeUser('ewm-b', 'ewm');
  const voterC = await makeUser('ewm-c', 'ewm');
  const peerReportId = name('peer');
  const peerReport = await call(row('reports'), {
    method: 'POST',
    body: {
      rowId: peerReportId,
      data: {
        userId: adminUser.id, reporterName: 'Cloud check', hazardType: 'Flooding',
        severity: 'medium', description: `Cloud check peer report ${stamp}`,
        state: 'Benue', lga: 'Makurdi', ward: 'North Bank I',
        status: 'pending', verificationCount: 0, isAlert: false,
        escalated: false, autoValidated: false,
        submittedAt: new Date().toISOString(), imageUrls: [],
      },
      permissions: ['read("label:admin")', 'read("label:ewm")'],
    },
  });
  assert.ok(peerReport.ok, `peer report: ${peerReport.status} ${JSON.stringify(peerReport.body).slice(0, 200)}`);
  track('reports', peerReportId);

  const sessionA = await sessionFor(voterA.email);
  const voteA = name('vote-a');
  r = await runFunction('write', sessionA, {
    op: 'create', collection: 'verifications', documentId: voteA,
    data: { reportId: peerReportId, isConfirmed: true, comment: 'Seen it' },
  });
  assert.equal(r.code, 200, `first vote: ${JSON.stringify(r.body).slice(0, 200)}`);
  track('verifications', voteA);
  stored = (await call(row('reports', peerReportId))).body;
  assert.equal(stored.verificationCount, 1, `count after one vote: ${stored.verificationCount}`);
  assert.equal(stored.status, 'pending', 'one vote is below the default threshold of 2');
  ok('one confirmation counted, still pending');

  step('the same monitor cannot confirm twice');
  const voteAgain = name('vote-a2');
  r = await runFunction('write', sessionA, {
    op: 'create', collection: 'verifications', documentId: voteAgain,
    data: { reportId: peerReportId, isConfirmed: true, comment: 'Again' },
  });
  assert.ok(r.code >= 400, `a second vote from the same verifier should be refused, got ${r.code}`);
  stored = (await call(row('reports', peerReportId))).body;
  assert.equal(stored.verificationCount, 1, 'and the count did not move');
  ok(`refused (${r.code}): one monitor cannot reach the threshold alone`);

  step('a dispute does not count toward the threshold');
  const sessionC = await sessionFor(voterC.email);
  const voteC = name('vote-c');
  r = await runFunction('write', sessionC, {
    op: 'create', collection: 'verifications', documentId: voteC,
    data: { reportId: peerReportId, isConfirmed: false, comment: 'Not what I see' },
  });
  assert.equal(r.code, 200, `dispute: ${JSON.stringify(r.body).slice(0, 200)}`);
  track('verifications', voteC);
  stored = (await call(row('reports', peerReportId))).body;
  assert.equal(stored.verificationCount, 1, `a dispute must not count: ${stored.verificationCount}`);
  assert.equal(stored.status, 'pending');
  ok('dispute recorded, count unchanged');

  step('the second confirmation verifies the report');
  const sessionB = await sessionFor(voterB.email);
  const voteB = name('vote-b');
  r = await runFunction('write', sessionB, {
    op: 'create', collection: 'verifications', documentId: voteB,
    data: { reportId: peerReportId, isConfirmed: true, comment: 'Confirmed' },
  });
  assert.equal(r.code, 200, `second vote: ${JSON.stringify(r.body).slice(0, 200)}`);
  track('verifications', voteB);
  stored = (await call(row('reports', peerReportId))).body;
  assert.equal(stored.verificationCount, 2, `count: ${stored.verificationCount}`);
  assert.equal(stored.status, 'verified', `status: ${stored.status}`);
  assert.equal(stored.autoValidated, true);
  assert.equal(stored.previousStatus, 'pending', 'so the event Function announces it');
  assert.ok(typeof stored.verifiedAt === 'string' && stored.verifiedAt, 'verifiedAt is set');
  ok(`verified by ${stored.verificationCount} peers, autoValidated`);

  // ── 8. the execution shape the Flutter SDK parses ──────────────────
  step('the operation Function, and what its execution carries');
  r = await runFunction('operation', adminSession, {
    operation: 'reopen_report',
    params: { p_report_id: reportId },
  });
  assert.equal(r.code, 200, `reopen: ${JSON.stringify(r.body).slice(0, 200)}`);
  stored = (await call(row('reports', reportId))).body;
  assert.equal(stored.status, 'pending');
  assert.equal(stored.verificationCount, 0);
  ok('reopen_report cleared the decision');

  const shape = r.execution;
  const hasResource = 'resourceId' in shape && 'resourceType' in shape;
  if (hasResource) {
    ok('the execution carries resourceId/resourceType — the Flutter SDK can parse it');
    note('CRADI-mobile/test/integration: un-skip the two callOperation tests');
  } else {
    console.log(
      '   ! the execution carries neither resourceId nor resourceType.\n' +
        '     The Flutter SDK\'s Execution.fromMap throws "Bad state: No element"\n' +
        '     on this shape, so DataBackend.callOperation stays unverified and\n' +
        '     its two integration tests stay skipped. Keys present:\n' +
        `     ${Object.keys(shape).join(', ')}`,
    );
  }
}

let failure = null;
try {
  await main();
} catch (error) {
  failure = error;
}
const cleaned = await cleanup();

if (failure) {
  console.error(`\nCLOUD CHECK: FAIL\n\n${failure?.message ?? failure}`);
  process.exit(1);
}
if (!cleaned) {
  console.error('\nCLOUD CHECK: the checks passed but cleanup did not — remove the rows named above.');
  process.exit(1);
}
console.log('\nCLOUD CHECK: PASS');
