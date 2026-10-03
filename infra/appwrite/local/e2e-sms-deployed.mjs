/**
 * The authority SMS, sent by a **deployed Function**.
 *
 *   source infra/appwrite/local/.env.local
 *   node infra/appwrite/local/e2e-sms-deployed.mjs
 *
 * `e2e-sms.mjs` runs `notifyApproved` in this process, against a
 * stand-in Termii on loopback. It says so itself: it "does not prove
 * that a Function *container* can reach Termii from wherever it is
 * deployed". That was the last unproven link in the SMS path, and it
 * is the one that fails in the ways a unit test cannot see — a
 * variable the deploy did not carry, an egress rule, a runtime whose
 * `fetch` behaves differently from the one here.
 *
 * So this proves exactly that link and nothing it can fake:
 *
 *  - the stand-in binds on every interface and is addressed by the
 *    docker gateway of the runtimes network, so only a request made
 *    *from inside a runtime container* can arrive;
 *  - the worker is deployed with `TERMII_BASE_URL` pointing there, by
 *    the same `deploy.mjs` production uses, so the variable plumbing
 *    is the real one;
 *  - the report is approved by a row write, the deployed `worker`
 *    picks the event up and writes the outbox row, and a second
 *    execution drains it — both deployed Functions, in sequence.
 *
 * What is left after a green run is Termii's own API contract and a
 * real number, which need an account and somebody's consent. See
 * `docs/CLOUD-VERIFICATION.md`.
 */
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createServer } from 'node:http';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// The producer's own id function, so this asks for the event the
// Function actually wrote rather than one this script guessed at.
import { eventId } from '../../../functions/cradi/src/lib/outbox.js';

const here = dirname(fileURLToPath(import.meta.url));

const EP = process.env.APPWRITE_ENDPOINT;
const PROJECT = process.env.APPWRITE_PROJECT_ID;
const KEY = process.env.APPWRITE_API_KEY;
const DB = process.env.APPWRITE_DATABASE_ID ?? 'cradi';
if (!EP || !PROJECT || !KEY) {
  console.error('source infra/appwrite/local/.env.local first');
  process.exit(2);
}

/**
 * Where a runtime container reaches this process.
 *
 * The docker gateway of the network the runtimes are on. `127.0.0.1`
 * would be the container's own loopback, which is the mistake that
 * would make this test pass by never being called at all — so the
 * assertions below check the stand-in was *reached*, not merely that
 * the Function reported success.
 */
const NETWORK = process.env.APPWRITE_RUNTIMES_NETWORK ?? 'runtimes19';
const PORT = Number(process.env.SMS_STANDIN_PORT ?? 8099);
const gateway = execFileSync('docker', [
  'network', 'inspect', NETWORK, '-f', '{{range .IPAM.Config}}{{.Gateway}}{{end}}',
]).toString().trim();
assert.ok(gateway, `no gateway for the ${NETWORK} network`);
const BASE_URL = `http://${gateway}:${PORT}`;

const admin = { 'content-type': 'application/json', 'x-appwrite-project': PROJECT, 'x-appwrite-key': KEY };
async function call(path, { method = 'GET', body } = {}) {
  const r = await fetch(`${EP}${path}`, {
    method,
    headers: admin,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await r.text();
  let parsed = null;
  if (text) { try { parsed = JSON.parse(text); } catch { parsed = { message: text }; } }
  return { status: r.status, ok: r.ok, body: parsed };
}
const row = (table, id = '') => `/tablesdb/${DB}/tables/${table}/rows${id ? `/${encodeURIComponent(id)}` : ''}`;
const step = (m) => console.log(`\n── ${m}`);
const ok = (m) => console.log(`   ✓ ${m}`);

const stamp = Date.now().toString(36);
const name = (what) => `dsms-${what}-${stamp}`.slice(0, 36);
const made = [];
const track = (kind, id) => made.unshift({ kind, id });

// ── the stand-in, on every interface ──────────────────────────────────
const received = [];
const termii = createServer((req, res) => {
  let raw = '';
  req.on('data', (c) => { raw += c; });
  req.on('end', () => {
    let parsed = null;
    try { parsed = JSON.parse(raw); } catch { parsed = { raw }; }
    received.push({ path: req.url, from: req.socket.remoteAddress, body: parsed });
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ message_id: `m-${received.length}`, code: 'ok' }));
  });
});
await new Promise((resolve) => termii.listen(PORT, '0.0.0.0', resolve));
console.log(`stand-in Termii on ${BASE_URL} (container-reachable)`);

const LGA = 'Makurdi';
const STATE = 'Benue';
const PHONE = '+2348030000009';

async function cleanup() {
  step('cleaning up');
  let removed = 0;
  for (const { kind, id } of made) {
    const r = await call(row(kind, id), { method: 'DELETE' });
    if (r.ok || r.status === 404) removed += 1;
  }
  ok(`removed ${removed}/${made.length}`);
}

async function runWorker(what) {
  const exec = await call('/functions/worker/executions', {
    method: 'POST',
    body: { body: '{}', async: false, method: 'POST' },
  });
  assert.ok(exec.ok, `${what}: ${exec.status} ${JSON.stringify(exec.body).slice(0, 200)}`);
  assert.equal(exec.body.status, 'completed', `${what}: ${(exec.body.errors || '').slice(-400)}`);
  return exec.body;
}

async function main() {
  step('the worker is deployed with the stand-in as its Termii');
  // The real `deploy.mjs`, so the variables travel the way they do in
  // production. A hand-written variable write here would prove that a
  // variable this script set can be read, which is not the question.
  execFileSync('node', [join(here, 'deploy.mjs')], {
    env: {
      ...process.env,
      TERMII_API_KEY: 'standin-key',
      TERMII_SENDER_ID: 'CRADI',
      TERMII_BASE_URL: BASE_URL,
    },
    stdio: 'pipe',
  });
  ok(`deployed with TERMII_BASE_URL=${BASE_URL}`);

  step('an authority covering the LGA, and an approved report in it');
  const authorityId = name('auth');
  const authority = await call(row('authorities'), {
    method: 'POST',
    body: {
      rowId: authorityId,
      data: {
        name: `Deployed SMS check ${stamp}`,
        organization: 'Test',
        phone: PHONE,
        coverageLga: LGA,
        coverageState: STATE,
      },
    },
  });
  assert.ok(authority.ok, `authority: ${authority.status} ${JSON.stringify(authority.body).slice(0, 200)}`);
  track('authorities', authorityId);

  const reportId = name('report');
  const created = await call(row('reports'), {
    method: 'POST',
    body: {
      rowId: reportId,
      data: {
        hazardType: 'Flooding',
        severity: 'high',
        description: 'River over the road at the market end, rising since dawn.',
        ward: 'North Bank I',
        lga: LGA,
        state: STATE,
        userId: 'dsms-check',
        reporterName: 'Deployed SMS check',
        status: 'pending',
        verificationCount: 0,
        isAlert: false, escalated: false, autoValidated: false,
        submittedAt: new Date().toISOString(),
        imageUrls: [],
      },
      permissions: ['read("label:admin")'],
    },
  });
  assert.ok(created.ok, `report: ${created.status} ${JSON.stringify(created.body).slice(0, 200)}`);
  track('reports', reportId);
  ok(`${PHONE} covers ${LGA}, ${STATE}`);

  step('approving it makes the deployed worker queue the event');
  // `previousStatus` is what `write.js` stamps and what `on-write`
  // reads: Appwrite's event payload has no "before".
  const approved = await call(row('reports', reportId), {
    method: 'PATCH',
    body: { data: { status: 'approved', previousStatus: 'pending', approvedAt: new Date().toISOString() } },
  });
  assert.ok(approved.ok, `approve: ${approved.status}`);

  // Asked for by id, not found in a page of recent events. The id is
  // derived from the transition — that determinism is what makes a
  // repeated delivery impossible — and a filtered page is capped at 25
  // of the hundreds this stack has accumulated, so scanning one
  // reported "never queued" for an event that was sitting there.
  const wantEvent = 'report_status_changed';
  const wantId = eventId(wantEvent, `${reportId}-pending-approved`);
  let queued = null;
  for (let i = 0; i < 30 && !queued; i++) {
    const found = await call(row('notification_outbox', wantId));
    if (found.ok) queued = found.body;
    else await new Promise((r) => setTimeout(r, 1000));
  }
  assert.ok(queued, `the deployed worker never queued ${wantId} for ${reportId}`);
  track('notification_outbox', queued.$id);
  ok(`${queued.$id} (${queued.eventType})`);

  step('draining it sends the SMS from inside the container');
  const before = received.length;
  const tick = await runWorker('drain');
  const summary = JSON.parse(tick.responseBody || '{}');
  // The logs and errors, because the failure this is most likely to
  // catch is the container being unable to reach the stand-in at all,
  // and `fetch failed` on its own does not say which host it could not
  // reach.
  assert.ok(
    !summary.drain?.failed,
    `drain failed: ${summary.drain?.error || '(no message)'}\n` +
      `  logs: ${(tick.logs || '').slice(-600)}\n` +
      `  errors: ${(tick.errors || '').slice(-600)}`,
  );

  assert.ok(
    received.length > before,
    'the stand-in was never reached — the deployed Function did not call Termii. ' +
      `logs: ${(tick.logs || '').slice(-600)} errors: ${(tick.errors || '').slice(-400)}`,
  );
  const sent = received[received.length - 1];
  ok(`reached from ${sent.from} (a runtime container, not this process)`);

  step('and it sent what it was supposed to send');
  assert.equal(sent.path, '/api/sms/send', `path: ${sent.path}`);
  // Termii refuses a leading `+`; `termiiSender` strips it.
  assert.equal(sent.body.to, PHONE.replace(/^\+/, ''), `to: ${sent.body.to}`);
  assert.equal(sent.body.from, 'CRADI', `from: ${sent.body.from}`);
  assert.equal(sent.body.api_key, 'standin-key', 'the deployed key was used');
  assert.match(sent.body.sms, /Makurdi/, `text: ${sent.body.sms}`);
  ok(`to=${sent.body.to} from=${sent.body.from} "${String(sent.body.sms).slice(0, 70)}…"`);

  step('and recorded the delivery, so a second drain does not re-send');
  const deliveries = await call(`${row('sms_deliveries')}?queries[]=${encodeURIComponent(
    JSON.stringify({ method: 'equal', attribute: 'reportId', values: [reportId] }),
  )}`);
  const claims = deliveries.body?.rows ?? [];
  assert.equal(claims.length, 1, `claims: ${JSON.stringify(claims).slice(0, 200)}`);
  for (const c of claims) track('sms_deliveries', c.$id);
  ok(`${claims[0].$id} status=${claims[0].status}`);

  const afterFirst = received.length;
  await runWorker('second drain');
  assert.equal(
    received.length,
    afterFirst,
    'a second drain texted the authority again — the claim did not hold',
  );
  ok('the claim held; nobody was texted twice');

  console.log('\nDEPLOYED SMS: PASS');
}

try {
  await main();
} finally {
  await cleanup().catch(() => {});
  termii.close();
}
