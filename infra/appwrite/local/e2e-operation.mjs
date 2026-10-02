/**
 * The `operation` Function, end to end.
 *
 *   source infra/appwrite/local/.env.local
 *   node infra/appwrite/local/e2e-operation.mjs
 *
 * This exists because the Dart adapter's `callOperation` cannot be run
 * against this stack: SDK 26 replaced the `Execution` model's
 * `functionId` with `resourceId`/`resourceType`, and a self-hosted
 * server below 2.0 still answers with the old shape, so the SDK throws
 * while parsing before it ever reads the response body. Appwrite Cloud
 * is 2.3 and matches the SDK; 2.3 self-hosted cannot stand in here
 * because its deployments are built through an image this environment's
 * network policy will not let us pull.
 *
 * So the Function is exercised over HTTP instead, as the adapter would
 * call it. What stays unverified locally is only the SDK's parse step —
 * see the skipped group in
 * `test/integration/appwrite_realtime_files_ops_live_test.dart`.
 */
import assert from 'node:assert/strict';

const EP = process.env.APPWRITE_ENDPOINT;
const PROJECT = process.env.APPWRITE_PROJECT_ID;
const KEY = process.env.APPWRITE_API_KEY;
const DB = process.env.APPWRITE_DATABASE_ID ?? 'cradi';
const admin = { 'content-type': 'application/json', 'x-appwrite-project': PROJECT, 'x-appwrite-key': KEY };

const step = (m) => console.log(`\n── ${m}`);
const ok = (m) => console.log(`   ✓ ${m}`);

async function call(path, { method = 'GET', body, headers = admin } = {}) {
  const r = await fetch(`${EP}${path}`, {
    method, headers, body: body === undefined ? undefined : JSON.stringify(body),
  });
  const t = await r.text();
  let b = null;
  if (t) { try { b = JSON.parse(t); } catch { b = { message: t }; } }
  return { status: r.status, ok: r.ok, body: b };
}
const row = (table, id = '') => `/tablesdb/${DB}/tables/${table}/rows${id ? `/${id}` : ''}`;

/** Runs the Function and returns its inner response, as the adapter does. */
async function operation(session, payload) {
  const exec = await call('/functions/operation/executions', {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-appwrite-project': PROJECT, 'x-appwrite-session': session },
    body: { body: JSON.stringify(payload), async: false, method: 'POST' },
  });
  assert.ok(exec.ok, `execution refused: ${exec.status} ${JSON.stringify(exec.body).slice(0, 200)}`);
  assert.equal(exec.body.status, 'completed', `execution ${exec.body.status}: ${exec.body.errors}`);
  let inner = null;
  try { inner = JSON.parse(exec.body.responseBody); } catch { inner = { raw: exec.body.responseBody }; }
  return { code: exec.body.responseStatusCode, body: inner };
}

const stamp = Date.now();
const reviewerId = `op-ewr-${stamp}`.slice(0, 36);
const reporterId = `op-user-${stamp}`.slice(0, 36);
const reportId = `op-report-${stamp}`.slice(0, 36);

async function makeUser(id, name, role) {
  await call('/users', {
    method: 'POST',
    body: { userId: id, email: `${id}@example.test`, password: 'OpPassword123', name },
  });
  const p = await call(row('profiles'), {
    method: 'POST',
    body: {
      rowId: id,
      data: {
        name, role, state: 'Benue', lga: 'Makurdi', ward: 'North Bank I',
        isApproved: true, isDisabled: false, isVerified: true,
      },
      permissions: [`read("user:${id}")`],
    },
  });
  assert.ok(p.ok, `profile ${id}: ${JSON.stringify(p.body).slice(0, 200)}`);
  const s = await call('/account/sessions/email', {
    method: 'POST',
    body: { email: `${id}@example.test`, password: 'OpPassword123' },
  });
  assert.ok(s.ok, `sign-in ${id}: ${JSON.stringify(s.body).slice(0, 200)}`);
  return s.body.secret;
}

step('a reviewer and an ordinary reporter');
const reviewer = await makeUser(reviewerId, 'Op Reviewer', 'ewr');
const reporter = await makeUser(reporterId, 'Op Reporter', 'user');
ok(`${reviewerId} is ewr, ${reporterId} is a plain user`);

step('a closed report carrying a peer vote');
const report = await call(row('reports'), {
  method: 'POST',
  body: {
    rowId: reportId,
    data: {
      hazardType: 'flood', description: 'For the reopen test',
      state: 'Benue', lga: 'Makurdi', ward: 'North Bank I',
      severity: 'high', status: 'approved', verificationCount: 1,
      escalated: true, userId: reporterId,
    },
  },
});
assert.ok(report.ok, `report: ${JSON.stringify(report.body).slice(0, 300)}`);
const vote = await call(row('verifications'), {
  method: 'POST',
  body: {
    rowId: `op-vote-${stamp}`.slice(0, 36),
    data: {
      reportId, verifierId: reviewerId, verifierName: 'Op Reviewer',
      isConfirmed: true,
      submittedAt: new Date().toISOString(),
      state: 'Benue', lga: 'Makurdi', ward: 'North Bank I',
    },
  },
});
assert.ok(vote.ok, `vote: ${JSON.stringify(vote.body).slice(0, 300)}`);
ok(`${reportId} is approved, escalated, with 1 vote`);

step('an unknown operation is refused, not silently ignored');
const unknown = await operation(reviewer, { operation: 'drop_everything' });
assert.equal(unknown.code, 400, `expected 400, got ${unknown.code}`);
assert.match(unknown.body.message ?? '', /Unknown operation/i);
ok(`${unknown.code} ${unknown.body.type}: ${unknown.body.message}`);

step('reopening an already-pending report is refused');
const alreadyPending = await call(row('reports'), {
  method: 'POST',
  body: {
    rowId: `op-live-${stamp}`.slice(0, 36),
    data: {
      hazardType: 'flood', description: 'Still open',
      state: 'Benue', lga: 'Makurdi', ward: 'North Bank I',
      severity: 'high', status: 'pending', userId: reporterId,
    },
  },
});
assert.ok(alreadyPending.ok, `live report: ${JSON.stringify(alreadyPending.body).slice(0, 200)}`);
const live = await operation(reviewer, {
  operation: 'reopen_report', params: { p_report_id: alreadyPending.body.$id },
});
assert.equal(live.code, 400, `expected 400, got ${live.code}`);
ok(`${live.code}: ${live.body.message}`);

step('an ordinary reporter may not reopen a report');
const refused = await operation(reporter, {
  operation: 'reopen_report', params: { p_report_id: reportId },
});
assert.equal(refused.code, 403, `expected 403, got ${refused.code}`);
ok(`${refused.code}: ${refused.body.message}`);

step('...and the report is untouched');
const untouched = await call(row('reports', reportId));
assert.equal(untouched.body.status, 'approved', 'a refused call must change nothing');
assert.equal(untouched.body.verificationCount, 1);
ok('still approved, vote still counted');

step('the reviewer reopens it');
const reopened = await operation(reviewer, {
  operation: 'reopen_report', params: { p_report_id: reportId },
});
assert.equal(reopened.code, 200, `expected 200, got ${reopened.code}: ${JSON.stringify(reopened.body).slice(0, 200)}`);
ok('200');

step('the report is pending again, with its votes cleared');
const after = await call(row('reports', reportId));
assert.equal(after.body.status, 'pending');
assert.equal(after.body.verificationCount, 0);
assert.equal(after.body.escalated, false);
assert.equal(after.body.updatedBy, reviewerId);
assert.equal(after.body.escalationStatus, 'pending');
assert.equal(after.body.rejectionReason, null);
ok(`status=pending verificationCount=0 escalated=false updatedBy=${after.body.updatedBy}`);

step('the peer vote is gone, not merely uncounted');
const votes = await call(
  `${row('verifications')}?queries[]=${encodeURIComponent(JSON.stringify({ method: 'equal', attribute: 'reportId', values: [reportId] }))}`,
);
assert.equal(votes.body.total, 0, `expected no votes, found ${votes.body.total}`);
ok('0 verifications remain');

step('a report that does not exist is a 404, not a crash');
const missing = await operation(reviewer, {
  operation: 'reopen_report', params: { p_report_id: `no-such-${stamp}`.slice(0, 36) },
});
assert.equal(missing.code, 404, `expected 404, got ${missing.code}`);
ok(`${missing.code}: ${missing.body.message}`);

console.log('\nOPERATION FUNCTION: PASS');
