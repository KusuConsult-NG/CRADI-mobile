/**
 * The escalation cron, firing on its own schedule.
 *
 *   source infra/appwrite/local/.env.local
 *   node infra/appwrite/local/e2e-escalation.mjs
 *
 * Phase 4 accepted a cron schedule and never watched one run, and said
 * so. Phase 6 watched one fire on 1.6.2. This watches *this* Function
 * fire on 1.8 and do its job — which is the part that matters, because
 * a schedule that fires into a Function that then does nothing looks
 * identical from the outside.
 *
 * It does not call the Function. It plants a report that is already
 * overdue and waits, because "the cron fires" is the claim.
 */
import assert from 'node:assert/strict';

const EP = process.env.APPWRITE_ENDPOINT;
const PROJECT = process.env.APPWRITE_PROJECT_ID;
const KEY = process.env.APPWRITE_API_KEY;
const DB = process.env.APPWRITE_DATABASE_ID ?? 'cradi';
const H = { 'content-type': 'application/json', 'x-appwrite-project': PROJECT, 'x-appwrite-key': KEY };

const step = (m) => console.log(`\n── ${m}`);
const ok = (m) => console.log(`   ✓ ${m}`);

async function call(path, { method = 'GET', body } = {}) {
  const r = await fetch(`${EP}${path}`, {
    method, headers: H, body: body === undefined ? undefined : JSON.stringify(body),
  });
  const t = await r.text();
  let b = null;
  if (t) { try { b = JSON.parse(t); } catch { b = { message: t }; } }
  return { status: r.status, ok: r.ok, body: b };
}
const row = (table, id = '') => `/tablesdb/${DB}/tables/${table}/rows${id ? `/${id}` : ''}`;
const q = (...parts) => parts.map((p) => `queries[]=${encodeURIComponent(JSON.stringify(p))}`).join('&');

const stamp = Date.now();
const reporterId = `esc-reporter-${stamp}`.slice(0, 36);
const coordinatorId = `esc-ldp-${stamp}`.slice(0, 36);
const reportId = `esc-report-${stamp}`.slice(0, 36);

step('a reporter and an LGA coordinator, who is who gets told');
for (const [id, name, role] of [
  [reporterId, 'Esc Reporter', 'user'],
  [coordinatorId, 'Esc Coordinator', 'ldp_coordinator'],
]) {
  await call('/users', {
    method: 'POST',
    body: { userId: id, email: `${id}@example.test`, password: 'EscPassword123', name },
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
  assert.ok(p.ok, `profile ${id}: ${JSON.stringify(p.body).slice(0, 160)}`);
}
ok(`${coordinatorId} is the ldp_coordinator for Makurdi`);

step('a report that is already overdue');
// Written with the API key, not through the write Function: this test
// is about the cron, and the write path has its own test.
const report = await call(row('reports'), {
  method: 'POST',
  body: {
    rowId: reportId,
    data: {
      userId: reporterId, userName: 'Esc Reporter', userRole: 'user',
      hazardType: 'flood', description: 'Nobody verified this',
      state: 'Benue', lga: 'Makurdi', ward: 'North Bank I',
      status: 'pending', verificationCount: 0, escalated: false,
    },
    permissions: [`read("user:${reporterId}")`],
  },
});
assert.ok(report.ok, JSON.stringify(report.body).slice(0, 200));

const overdue = new Date(Date.now() - 5 * 60_000).toISOString();
const esc = await call(row('scheduled_escalations'), {
  method: 'POST',
  body: { rowId: reportId, data: { reportId, escalateAt: overdue, status: 'pending' } },
});
assert.ok(esc.ok, JSON.stringify(esc.body).slice(0, 200));
ok(`escalateAt ${overdue} (five minutes ago)`);

step('nothing is called — waiting for the cron');
const before = (await call(`/functions/escalate/executions?${q({ method: 'limit', values: [1] })}`)).body?.total ?? 0;
const deadline = Date.now() + 150_000;
let fired = null;
while (Date.now() < deadline) {
  const now = await call(`/functions/escalate/executions?${q({ method: 'orderDesc', attribute: '$createdAt' }, { method: 'limit', values: [5] })}`);
  fired = (now.body?.executions ?? []).find((e) => e.trigger === 'schedule');
  if (fired && (now.body.total ?? 0) > before) break;
  process.stdout.write('.');
  await new Promise((r) => setTimeout(r, 5000));
}
console.log();
assert.ok(fired, 'the schedule never fired within 150s');
assert.equal(fired.trigger, 'schedule', 'fired, but not by the schedule');
assert.equal(fired.status, 'completed', `${fired.status}: ${(fired.errors || '').slice(-300)}`);
ok(`trigger=${fired.trigger} status=${fired.status} ${fired.responseBody?.slice(0, 80)}`);

step('the report is escalated, and still pending');
const after = await call(row('reports', reportId));
assert.equal(after.body.escalated, true, 'not escalated');
assert.match(after.body.escalationReason ?? '', /Auto-escalation/);
// Escalation is a flag, not a decision: the report stays open.
assert.equal(after.body.status, 'pending');
ok(`escalated=true reason="${after.body.escalationReason}" status=pending`);

step('the escalation row is closed');
const closed = await call(row('scheduled_escalations', reportId));
assert.equal(closed.body.status, 'processed', `status=${closed.body.status} reason=${closed.body.reason}`);
ok(`status=processed at ${closed.body.processedAt}`);

step('the coordinator was notified, and the reporter was not');
const messages = await call(`/messaging/messages?${q({ method: 'orderDesc', attribute: '$createdAt' }, { method: 'limit', values: [10] })}`);
const push = (messages.body?.messages ?? []).find((m) => (m.users ?? []).includes(coordinatorId));
assert.ok(push, 'the coordinator was not notified');
assert.ok(!(push.users ?? []).includes(reporterId), 'the reporter must not be told to review their own report');
assert.equal(push.messageId ?? push.$id, `escalation-${reportId}`.slice(0, 36),
  `message id should be derived from the escalation: ${push.$id}`);
ok(`${push.$id} -> ${push.users.length} recipient(s)`);

step('a second run does not notify again');
// There is no conditional update in Appwrite; what stands in for it is
// Appwrite refusing a duplicate messageId.
const again = await call('/functions/escalate/executions', {
  method: 'POST', body: { body: '{}', async: false, method: 'POST' },
});
assert.equal(again.body.status, 'completed');
const sameAgain = await call(`/messaging/messages?${q({ method: 'limit', values: [25] })}`);
const copies = (sameAgain.body?.messages ?? []).filter((m) => (m.users ?? []).includes(coordinatorId));
assert.equal(copies.length, 1, `the coordinator was notified ${copies.length} times`);
ok('still exactly one notification');

console.log('\nESCALATION CRON: PASS');
