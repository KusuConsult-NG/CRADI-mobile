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
 * ## The live mode
 *
 * With `SMS_LIVE_NUMBER` set this sends a **real SMS through Termii**
 * to that number, which is the last thing the stand-in cannot prove:
 * Termii's own API contract, from a deployed Function. It needs
 * `TERMII_API_KEY` and `TERMII_SENDER_ID` in the environment, costs
 * money, and reaches a real handset — so the number is given
 * explicitly and never defaulted.
 *
 * The danger in live mode is not the number you pass, it is the ones
 * you do not: `notifyApproved` texts **every** authority covering the
 * report's LGA. Against a real project with real local-government
 * contacts in it, approving a report in a covered LGA would text them
 * all. So before anything is approved, this asserts that exactly one
 * authority covers the chosen LGA and that it is the one this run
 * created. If any other row covers it, the run stops and sends
 * nothing.
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
const LIVE = (process.env.SMS_LIVE_NUMBER ?? '').trim();
const NETWORK = process.env.APPWRITE_RUNTIMES_NETWORK ?? 'runtimes19';
const PORT = Number(process.env.SMS_STANDIN_PORT ?? 8099);

let BASE_URL = null;
if (!LIVE) {
  /**
   * Stand-in mode only works against a local stack, and must refuse to
   * run anywhere else.
   *
   * It redeploys the worker with `TERMII_BASE_URL` pointing at a private
   * address on this machine's docker network. On a remote project that
   * address is unreachable, so the worker is left aimed at nothing and
   * every authority SMS fails — the same outage a deploy without the
   * Termii pair causes, arrived at from the other direction and just as
   * quiet. Recovering means another deploy, which is not obvious when
   * the symptom is "no SMS" rather than an error.
   *
   * Live mode is exempt and is the way to exercise a remote project: it
   * leaves `TERMII_BASE_URL` unset so the worker calls Termii itself,
   * which is the contract this cannot otherwise prove. Its own
   * assertions above cover the cost of that.
   */
  const host = new URL(EP).hostname;
  if (host !== 'appwrite.local' && host !== 'localhost' && host !== '127.0.0.1') {
    console.error(
      `Refusing to run: the stand-in rewrites the deployed worker's\n`
        + `TERMII_BASE_URL to an address on this machine's docker network,\n`
        + `which ${host} cannot reach — it would leave the worker unable to\n`
        + `send any authority SMS until the next deploy.\n\n`
        + 'To exercise a remote project, use live mode, which leaves\n'
        + 'TERMII_BASE_URL alone and sends through Termii for real:\n'
        + '  SMS_LIVE_NUMBER=+234XXXXXXXXXX node infra/appwrite/local/e2e-sms-deployed.mjs\n\n'
        + 'It costs money and reaches a handset, and refuses unless exactly\n'
        + 'one authority covers the LGA it uses.',
    );
    process.exit(3);
  }

  const gateway = execFileSync('docker', [
    'network', 'inspect', NETWORK, '-f', '{{range .IPAM.Config}}{{.Gateway}}{{end}}',
  ]).toString().trim();
  assert.ok(gateway, `no gateway for the ${NETWORK} network`);
  BASE_URL = `http://${gateway}:${PORT}`;
} else {
  // Termii's own API, which is what `TERMII_BASE_URL` defaults to.
  for (const required of ['TERMII_API_KEY', 'TERMII_SENDER_ID']) {
    assert.ok(
      (process.env[required] ?? '').trim(),
      `${required} must be set for a live send; put it in the environment, not here`,
    );
  }
  assert.match(
    LIVE,
    /^\+234\d{10}$/,
    `SMS_LIVE_NUMBER must be a full E.164 Nigerian number, got "${LIVE}"`,
  );
}

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
const standIn = createServer((req, res) => {
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
if (LIVE) {
  console.log(`LIVE: a real SMS will be sent to ${LIVE} via Termii as "${process.env.TERMII_SENDER_ID}"`);
} else {
  await new Promise((resolve) => standIn.listen(PORT, '0.0.0.0', resolve));
  console.log(`stand-in Termii on ${BASE_URL} (container-reachable)`);
}

// An LGA with no authorities of its own, asserted below rather than
// assumed: every authority covering the report's LGA is texted.
const LGA = process.env.SMS_TEST_LGA ?? 'Makurdi';
const STATE = process.env.SMS_TEST_STATE ?? 'Benue';
const PHONE = LIVE || '+2348030000009';

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
  const deployEnv = LIVE
    ? // Termii's real API: `TERMII_BASE_URL` must not be carried over
      // from a previous stand-in run, or the "live" send goes nowhere.
      { ...process.env, TERMII_BASE_URL: undefined }
    : {
        ...process.env,
        TERMII_API_KEY: 'standin-key',
        TERMII_SENDER_ID: 'CRADI',
        TERMII_BASE_URL: BASE_URL,
      };
  execFileSync('node', [join(here, 'deploy.mjs')], { env: deployEnv, stdio: 'pipe' });
  ok(LIVE ? 'deployed against Termii\u2019s own API' : `deployed with TERMII_BASE_URL=${BASE_URL}`);

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

  // THE guard. `notifyApproved` texts every authority covering the
  // report's LGA, so on a project with real local-government contacts
  // in it the blast radius of this run is "whoever covers Makurdi",
  // not "the number I passed". Checked after the insert, so it also
  // catches a second copy of our own row from an interrupted run.
  const covering = await call(`${row('authorities')}?${[
    { method: 'equal', attribute: 'coverageLga', values: [LGA] },
    { method: 'limit', values: [100] },
  ].map((q) => `queries[]=${encodeURIComponent(JSON.stringify(q))}`).join('&')}`);
  assert.ok(covering.ok, `authorities: ${covering.status}`);
  const others = (covering.body?.rows ?? []).filter((a) => a.$id !== authorityId);
  assert.equal(
    others.length,
    0,
    `${others.length} other authorities already cover ${LGA} and would be texted too: ` +
      `${others.map((a) => `${a.$id} ${a.phone}`).join(', ')}. ` +
      'Pick an uncovered LGA with SMS_TEST_LGA / SMS_TEST_STATE, or remove them first.',
  );
  ok(`${LGA} is covered by this run's authority and no other`);

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

  if (LIVE) {
    // Nothing of ours sits between the Function and Termii here, so
    // the evidence is the delivery row and the execution's own log.
    // Termii's `message_id` in that log is the thing that can be
    // looked up in their dashboard, which is the point of the run.
    ok('the drain completed without error');
  } else {
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
    assert.match(sent.body.sms, new RegExp(LGA), `text: ${sent.body.sms}`);
    ok(`to=${sent.body.to} from=${sent.body.from} "${String(sent.body.sms).slice(0, 70)}…"`);
  }

  step('and recorded the delivery, so a second drain does not re-send');
  const deliveries = await call(`${row('sms_deliveries')}?queries[]=${encodeURIComponent(
    JSON.stringify({ method: 'equal', attribute: 'reportId', values: [reportId] }),
  )}`);
  const claims = deliveries.body?.rows ?? [];
  assert.equal(claims.length, 1, `claims: ${JSON.stringify(claims).slice(0, 200)}`);
  for (const c of claims) track('sms_deliveries', c.$id);
  assert.equal(
    claims[0].status,
    'sent',
    `the delivery was not recorded as sent: ${JSON.stringify(claims[0]).slice(0, 300)}\n` +
      `  logs: ${(tick.logs || '').slice(-600)}`,
  );
  ok(`${claims[0].$id} status=${claims[0].status}`);
  if (LIVE) {
    // The Function logs Termii's reply; printing it is how the run is
    // checked against the Termii dashboard and the handset.
    console.log(`\n   Termii, as the Function saw it:\n${(tick.logs || '').slice(-800)}`);
  }

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
  if (!LIVE) standIn.close();
}
