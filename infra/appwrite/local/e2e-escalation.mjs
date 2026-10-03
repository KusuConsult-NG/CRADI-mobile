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

// The escalation sweep is one task of the worker Function, which the
// schedule runs every minute; the execution to wait for is the worker's.
step('nothing is called — waiting for the cron');
// A *new* schedule execution, by its timestamp.
//
// The old test watched `escalate`'s own execution list and took a
// rising total as proof one had run. The worker's list also carries
// every event delivery, and seeding this report produces a handful of
// those — so a rising total stopped meaning "the cron fired" and the
// loop broke on a schedule execution from before the row existed. The
// report was then read a second too early and the suite reported "not
// escalated" for a sweep that had not run yet.
const since = Date.now();
const deadline = since + 150_000;
let fired = null;
while (Date.now() < deadline) {
  const now = await call(`/functions/worker/executions?${q({ method: 'orderDesc', attribute: '$createdAt' }, { method: 'limit', values: [25] })}`);
  fired = (now.body?.executions ?? []).find(
    (e) => e.trigger === 'schedule' && new Date(e.$createdAt).getTime() >= since,
  );
  if (fired && fired.status !== 'waiting' && fired.status !== 'processing') break;
  fired = null;
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
// Asked for by id rather than found among the newest messages. The id
// is derived from the escalation — that determinism is what makes a
// repeated sweep a 409 instead of a second warning — and a tick now
// runs the drain too, so "the newest message addressed to the
// coordinator" can be an unrelated ward push.
const escalationId = `escalation-${reportId}`.slice(0, 36);
const found = await call(`/messaging/messages/${encodeURIComponent(escalationId)}`);
assert.ok(found.ok, `no escalation push ${escalationId}: ${found.status}`);
const push = found.body;
assert.ok((push.users ?? []).includes(coordinatorId), 'the coordinator was not notified');
assert.ok(!(push.users ?? []).includes(reporterId), 'the reporter must not be told to review their own report');
ok(`${push.$id} -> ${push.users.length} recipient(s)`);

step('a second run does not notify again');
// There is no conditional update in Appwrite; what stands in for it is
// Appwrite refusing a duplicate messageId.
const again = await call('/functions/worker/executions', {
  method: 'POST', body: { body: '{}', async: false, method: 'POST' },
});
assert.equal(again.body.status, 'completed');
// Newest first: an unordered page of 25 stopped containing this run's
// message once the stack had sent more than 25, which read as "the
// coordinator was notified 0 times" — the opposite of what it checks.
const sameAgain = await call(
  `/messaging/messages?${q({ method: 'orderDesc', attribute: '$createdAt' }, { method: 'limit', values: [100] })}`,
);
// Counted by the escalation's own message id, not by "everything
// addressed to the coordinator". A tick runs the drain as well as the
// sweep now, and the drain legitimately delivers the ward's other
// outbox events to the same coordinator — so counting recipients
// counted unrelated pushes and read as a duplicate escalation.
const copies = (sameAgain.body?.messages ?? []).filter(
  (m) => (m.messageId ?? m.$id) === escalationId,
);
assert.equal(copies.length, 1, `the escalation was sent ${copies.length} times`);
assert.ok(
  (copies[0].users ?? []).includes(coordinatorId),
  'the one escalation is still addressed to the coordinator',
);
ok('still exactly one escalation notification');

console.log('\nESCALATION CRON: PASS');
