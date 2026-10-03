/**
 * One hazard report, end to end, against the local Appwrite.
 *
 *   source infra/appwrite/local/.env.local
 *   node infra/appwrite/local/e2e.mjs
 *
 * This is the first time any of Phases 9-11 executes. Everything until
 * now was tested against a fake that behaves the way these Functions
 * assume Appwrite behaves; this checks the assumption.
 *
 * It asserts, and exits non-zero when an assertion fails. A script that
 * prints what happened and exits 0 is not a test.
 */
import assert from 'node:assert/strict';

import { messageId } from '../../../functions/cradi/src/lib/messaging.js';

const EP = process.env.APPWRITE_ENDPOINT;
const PROJECT = process.env.APPWRITE_PROJECT_ID;
const KEY = process.env.APPWRITE_API_KEY;
const DB = process.env.APPWRITE_DATABASE_ID ?? 'cradi';

const admin = { 'content-type': 'application/json', 'x-appwrite-project': PROJECT, 'x-appwrite-key': KEY };

async function call(path, { method = 'GET', body, headers = admin, raw = false } = {}) {
  const r = await fetch(`${EP}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await r.text();
  let parsed = null;
  if (text) { try { parsed = JSON.parse(text); } catch { parsed = { message: text }; } }
  return { status: r.status, ok: r.ok, body: parsed, raw: raw ? text : undefined };
}

const row = (table, id = '') => `/tablesdb/${DB}/tables/${table}/rows${id ? `/${id}` : ''}`;
/** Appwrite queries as a query string: `q({method:'limit',values:[5]}, …)`. */
const q = (...parts) => parts.map((p) => `queries[]=${encodeURIComponent(JSON.stringify(p))}`).join('&');
const step = (m) => console.log(`\n── ${m}`);
const ok = (m) => console.log(`   ✓ ${m}`);

const stamp = Date.now();
const reporterId = `e2e-reporter-${stamp}`.slice(0, 36);
const verifierId = `e2e-ewm-${stamp}`.slice(0, 36);

// ─── accounts and profiles ────────────────────────────────────────────
step('two accounts, one reporter and one ward monitor');
for (const [id, name, role] of [
  [reporterId, 'E2E Reporter', 'user'],
  [verifierId, 'E2E Monitor', 'ewm'],
]) {
  const user = await call('/users', {
    method: 'POST',
    body: { userId: id, email: `${id}@example.test`, password: 'E2ePassword123', name },
  });
  assert.ok(user.ok, `create ${id}: ${JSON.stringify(user.body).slice(0, 200)}`);
  const profile = await call(row('profiles'), {
    method: 'POST',
    body: {
      rowId: id,
      data: {
        name, role, email: `${id}@example.test`,
        state: 'Benue', lga: 'Makurdi', ward: 'North Bank I',
        isApproved: true, isDisabled: false, isVerified: true,
      },
      permissions: [`read("user:${id}")`],
    },
  });
  assert.ok(profile.ok, `profile ${id}: ${JSON.stringify(profile.body).slice(0, 200)}`);
}
ok('reporter and ewm created with profiles in Benue/Makurdi/North Bank I');

// ─── a session for the reporter, so the Function sees a real caller ───
step('the reporter signs in');
const session = await call('/account/sessions/email', {
  method: 'POST',
  headers: admin,
  body: { email: `${reporterId}@example.test`, password: 'E2ePassword123' },
});
assert.ok(session.ok, `sign-in: ${JSON.stringify(session.body).slice(0, 200)}`);
const asUser = {
  'content-type': 'application/json',
  'x-appwrite-project': PROJECT,
  'x-appwrite-session': session.body.secret,
};
ok(`session ${session.body.$id}`);

// ─── the collection is closed ─────────────────────────────────────────
step('a client cannot write a report directly');
const direct = await call(row('reports'), {
  method: 'POST',
  headers: asUser,
  body: { rowId: 'unique()', data: { hazardType: 'flood', lga: 'Makurdi' } },
});
assert.ok(!direct.ok, 'the collection must be closed to clients');
assert.ok([401, 403].includes(direct.status), `expected 401/403, got ${direct.status}`);
ok(`refused with ${direct.status} — the collection is closed`);

// ─── the write Function, trying to cheat ──────────────────────────────
step('the reporter files a report through the write Function, claiming it is approved');
const exec = await call('/functions/client/executions', {
  method: 'POST',
  headers: asUser,
  body: {
    path: '/write',
    body: JSON.stringify({
      op: 'create',
      collection: 'reports',
      documentId: `e2e-report-${stamp}`.slice(0, 36),
      data: {
        hazardType: 'flood',
        description: 'Water over the road since dawn',
        state: 'Benue', lga: 'Makurdi', ward: 'North Bank I',
        severity: 'high',
        // The lie Phase 4 exists to defeat.
        status: 'approved',
        verificationCount: 99,
        escalated: true,
        userId: 'somebody-else',
      },
    }),
    async: false,
    method: 'POST',
    headers: { 'content-type': 'application/json' },
  },
});
assert.ok(exec.ok, `execution: ${JSON.stringify(exec.body).slice(0, 300)}`);
const execBody = exec.body;
console.log(`   execution ${execBody.status}, ${execBody.responseStatusCode}, ${execBody.duration?.toFixed?.(3)}s`);
if (execBody.responseStatusCode >= 400 || execBody.status !== 'completed') {
  console.log(`   logs: ${(execBody.logs || '').slice(-400)}`);
  console.log(`   errors: ${(execBody.errors || '').slice(-400)}`);
}
assert.equal(execBody.status, 'completed');
assert.equal(execBody.responseStatusCode, 200, execBody.responseBody?.slice(0, 300));

const written = JSON.parse(execBody.responseBody).document;
const reportId = written.$id;
ok(`report ${reportId} created`);

step('the server overwrote everything the client should not choose');
assert.equal(written.status, 'pending', 'status');
assert.equal(written.verificationCount, 0, 'verificationCount');
assert.equal(written.escalated, false, 'escalated');
assert.equal(written.userId, reporterId, 'userId came from the session, not the body');
assert.equal(written.userName, 'E2E Reporter', 'reporter name denormalised');
assert.equal(written.userRole, 'user', 'reporter role denormalised');
ok('status=pending verificationCount=0 escalated=false userId=<the caller>');

step('the ACL names the ward team');
assert.ok(
  written.$permissions.includes('read("team:ward-benue-makurdi-north-bank-i")'),
  `permissions: ${JSON.stringify(written.$permissions)}`,
);
assert.ok(written.$permissions.includes(`read("user:${reporterId}")`));
ok(written.$permissions.join(' '));

step('the escalation was queued');
const esc = await call(row('scheduled_escalations', reportId));
assert.ok(esc.ok, 'scheduled_escalations row missing');
assert.equal(esc.body.status, 'pending');
ok(`escalateAt ${esc.body.escalateAt}`);

// ─── the event Function ───────────────────────────────────────────────
step('the event Function wrote an outbox document');
let outbox = null;
for (let i = 0; i < 20; i++) {
  // Newest first, and deliberately not the default page. Asking for 25
  // rows in no particular order found nothing once the outbox had more
  // than 25 rows in it — which it does after a few runs against the same
  // stack, so this passed early and failed later for a reason that had
  // nothing to do with the Function.
  const found = await call(
    `${row('notification_outbox')}?${q(
      { method: 'orderDesc', attribute: '$createdAt' },
      { method: 'limit', values: [100] },
    )}`,
  );
  outbox = (found.body?.rows ?? []).find((r) => (r.payload ?? '').includes(reportId));
  if (outbox) break;
  await new Promise((r) => setTimeout(r, 1500));
}
assert.ok(outbox, 'no outbox document — the event Function did not fire');
assert.equal(outbox.eventType, 'report_created');
ok(`${outbox.$id} (${outbox.eventType})`);

// ─── the drain ────────────────────────────────────────────────────────
step('the drain notifies the ward monitor');
// `drain`, `escalate` and `reconcile` are one Function: a scheduled run
// does all three, and an HTTP execution does the same. So this runs the
// worker and reads the drain's slice of its summary.
const drain = await call('/functions/worker/executions', {
  method: 'POST',
  body: { body: '{}', async: false, method: 'POST' },
});
assert.ok(drain.ok, `drain: ${JSON.stringify(drain.body).slice(0, 200)}`);
console.log(`   ${drain.body.status}, ${drain.body.responseStatusCode}: ${(drain.body.responseBody || '').slice(0, 160)}`);
if (drain.body.responseStatusCode >= 400) {
  console.log(`   logs: ${(drain.body.logs || '').slice(-500)}`);
  console.log(`   errors: ${(drain.body.errors || '').slice(-500)}`);
}
assert.equal(drain.body.status, 'completed');
assert.equal(drain.body.responseStatusCode, 200);
// The worker answers with a summary per task — `{drain, escalate,
// reconcile?}` — because one Function now carries all three. Reading
// the whole body as the drain's summary read `claimed undefined`,
// which is the shape of a run that did nothing rather than one that
// worked.
const tick = JSON.parse(drain.body.responseBody);
const summary = tick.drain ?? {};
assert.ok(!summary.failed, `drain failed: ${summary.error ?? ''}`);
assert.ok(summary.claimed >= 1, `claimed ${summary.claimed}; tick=${JSON.stringify(tick)}`);
ok(`claimed=${summary.claimed} processed=${summary.processed} failed=${summary.failed}`);
// The escalation sweep shares the tick, and a thrown one is recorded
// rather than raised — so a silent failure there would otherwise pass
// this suite.
assert.ok(!tick.escalate?.failed, `escalate failed: ${tick.escalate?.error ?? ''}`);
assert.ok(!tick.reconcile?.failed, `reconcile failed: ${tick.reconcile?.error ?? ''}`);

step('the outbox document is marked processed');
const after = await call(row('notification_outbox', outbox.$id));
assert.ok(after.ok);
assert.ok(after.body.processedAt, `not processed; note=${after.body.note}`);
ok(`processedAt ${after.body.processedAt}${after.body.note ? ` (${after.body.note})` : ''}`);

step('a push message exists, addressed to the ward monitor and not the reporter');
// Fetched by id rather than found in a page of recent messages. The id
// is derived from the outbox event — that determinism is what makes a
// repeated send a 409 instead of a second notification — so the test
// can ask for exactly this run's push. Scanning "the newest five"
// worked on an empty stack and failed on a used one, reporting "no push
// addressed to the ward monitor" when the push was there and five
// newer messages were in front of it.
const pushId = messageId(`outbox:${outbox.$id}:verifiers`);
const pushed = await call(`/messaging/messages/${encodeURIComponent(pushId)}`);
assert.ok(pushed.ok, `no push ${pushId}: ${pushed.status} ${JSON.stringify(pushed.body).slice(0, 160)}`);
const push = pushed.body;
assert.ok(
  (push.users ?? []).includes(verifierId),
  `push ${pushId} does not name the ward monitor: ${JSON.stringify(push.users)}`,
);
assert.equal(push.providerType, 'push');
assert.ok(
  !(push.users ?? []).includes(reporterId),
  'the reporter must not be asked to verify their own report',
);
// The privacy rule the Railway worker had and this had to keep: a push
// carries no location names, hazard text or descriptions — only generic
// wording plus an id for the app to resolve after sign-in.
const text = JSON.stringify(push.data ?? {});
for (const leak of ['Makurdi', 'North Bank', 'Water over the road', 'flood']) {
  assert.ok(!text.includes(leak), `push leaked "${leak}": ${text.slice(0, 200)}`);
}
ok(`${push.$id} -> ${push.users.length} monitor(s), no location or hazard text`);

step('cleaning up the accounts and the report this run created');
// Not politeness. The ward monitors a new report notifies are read with
// `Query.limit(50)`, so once fifty of these accumulate in one ward the
// next run's own monitor falls outside the page and the push that
// should name them does not — which reads as "the notification did not
// happen" and is really "the fixtures did". Every suite that creates
// accounts in a shared ward owes this.
{
  let removed = 0;
  const left = [];
  const targets = [
    [row('reports', reportId), 'report'],
    [row('profiles', reporterId), 'reporter profile'],
    [row('profiles', verifierId), 'monitor profile'],
    [`/users/${reporterId}`, 'reporter account'],
    [`/users/${verifierId}`, 'monitor account'],
  ];
  for (const [path, what] of targets) {
    const gone = await call(path, { method: 'DELETE' });
    if (gone.ok || gone.status === 404) removed += 1;
    else left.push(`${what}: ${gone.status}`);
  }
  console.log(`   ${left.length ? '!' : '✓'} removed ${removed}/${targets.length}`);
  for (const l of left) console.log(`     LEFT BEHIND — ${l}`);
}

console.log('\nEND TO END: PASS');
