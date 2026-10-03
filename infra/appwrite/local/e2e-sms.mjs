/**
 * The authority SMS path, end to end, against a real Appwrite and a
 * stand-in Termii.
 *
 *   source infra/appwrite/local/.env.local
 *   node infra/appwrite/local/e2e-sms.mjs
 *
 * This path had never run. Its unit tests cover the text, the caps and
 * the claim; `e2e.mjs` covers the report reaching the outbox. Between
 * them sat the one thing nobody could exercise without texting a real
 * local authority: `notifyApproved` against real `authorities` rows,
 * real `sms_deliveries` writes, and a real HTTP round trip.
 *
 * So the HTTP round trip goes to a server started here, which records
 * what it was asked to send. `TERMII_BASE_URL` points at it;
 * unset in production, where the default is Termii's own API.
 *
 * ## What this does and does not prove
 *
 * It proves the parts that are ours: which numbers are chosen, the text,
 * both caps, the deterministic claim that makes a duplicate impossible,
 * and the bookkeeping that follows a success and a failure. It runs the
 * real `notifyApproved` against the real database.
 *
 * It does not prove Termii's own API contract, and it does not prove
 * that a Function *container* can reach Termii from wherever it is
 * deployed. The first needs an account; the second needs a deploy. Both
 * are named in docs/CLOUD-VERIFICATION.md rather than quietly implied
 * by a green run here.
 */
import assert from 'node:assert/strict';
import { createServer } from 'node:http';

const EP = process.env.APPWRITE_ENDPOINT;
const PROJECT = process.env.APPWRITE_PROJECT_ID;
const KEY = process.env.APPWRITE_API_KEY;
const DB = process.env.APPWRITE_DATABASE_ID ?? 'cradi';
if (!EP || !PROJECT || !KEY) {
  console.error('source infra/appwrite/local/.env.local first');
  process.exit(2);
}

process.env.APPWRITE_ENDPOINT = EP;
process.env.APPWRITE_PROJECT = PROJECT;
process.env.APPWRITE_API_KEY = KEY;
process.env.APPWRITE_DATABASE_ID = DB;

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
const q = (...parts) => parts.map((p) => `queries[]=${encodeURIComponent(JSON.stringify(p))}`).join('&');
const step = (m) => console.log(`\n── ${m}`);
const ok = (m) => console.log(`   ✓ ${m}`);

const stamp = Date.now().toString(36);
const name = (what) => `sms-${what}-${stamp}`.slice(0, 36);
const made = [];
const track = (kind, id) => made.unshift({ kind, id });

// ── the stand-in ──────────────────────────────────────────────────────
const received = [];
let nextResponse = () => ({ status: 200, body: { message_id: `m-${received.length}` } });

const termii = createServer((req, res) => {
  let raw = '';
  req.on('data', (c) => { raw += c; });
  req.on('end', () => {
    let parsed = null;
    try { parsed = JSON.parse(raw); } catch { parsed = { raw }; }
    received.push({ path: req.url, body: parsed });
    const { status, body } = nextResponse(parsed);
    res.writeHead(status, { 'content-type': 'application/json' });
    res.end(JSON.stringify(body));
  });
});
await new Promise((resolve) => termii.listen(0, '127.0.0.1', resolve));
const port = termii.address().port;
process.env.TERMII_BASE_URL = `http://127.0.0.1:${port}`;
console.log(`stand-in Termii on ${process.env.TERMII_BASE_URL}`);

// Imported after the env is set: `termiiBaseUrl()` reads it per call,
// but `lib/appwrite.js` reads the endpoint at import time.
const { notifyApproved, termiiSender, claimId } = await import('../../../functions/cradi/src/lib/termii.js');

async function cleanup() {
  step('cleaning up');
  let removed = 0;
  const failed = [];
  for (const { kind, id } of made) {
    const r = await call(row(kind, id), { method: 'DELETE' });
    if (r.ok || r.status === 404) removed += 1;
    else failed.push(`${kind} ${id}: ${r.status}`);
  }
  console.log(`   ${failed.length ? '!' : '✓'} removed ${removed}/${made.length}`);
  for (const f of failed) console.log(`     LEFT BEHIND — ${f}`);
  termii.close();
  return failed.length === 0;
}

// `authorities.coverageLga` is matched exactly, so the LGA has to be a
// real one — the Function refuses an unknown pair.
const LGA = 'Makurdi';
const STATE = 'Benue';

async function main() {
  step('three authorities covering one LGA, and a report in it');
  const phones = ['+2348030000001', '+2348030000002', '+2348030000003'];
  for (const [i, phone] of phones.entries()) {
    const id = name(`auth${i}`);
    const made_ = await call(row('authorities'), {
      method: 'POST',
      body: {
        rowId: id,
        data: {
          name: `SMS check ${i} ${stamp}`,
          organization: 'Test',
          phone,
          coverageLga: LGA,
          coverageState: STATE,
        },
      },
    });
    assert.ok(made_.ok, `authority ${i}: ${made_.status} ${JSON.stringify(made_.body).slice(0, 200)}`);
    track('authorities', id);
  }
  const reportId = name('report');
  const report = {
    $id: reportId,
    hazardType: 'Flooding',
    severity: 'high',
    description: 'River over the road at the market end, rising since dawn.',
    ward: 'North Bank I',
    lga: LGA,
    state: STATE,
  };
  const stored = await call(row('reports'), {
    method: 'POST',
    body: {
      rowId: reportId,
      data: {
        ...report,
        userId: 'sms-check',
        reporterName: 'SMS check',
        status: 'approved',
        verificationCount: 0,
        isAlert: false, escalated: false, autoValidated: false,
        submittedAt: new Date().toISOString(),
        imageUrls: [],
      },
      permissions: ['read("label:admin")'],
    },
  });
  assert.ok(stored.ok, `report: ${stored.status} ${JSON.stringify(stored.body).slice(0, 200)}`);
  track('reports', reportId);
  ok(`${phones.length} authorities in ${LGA}, ${STATE}`);

  const send = await termiiSender({ apiKey: 'test-key', senderId: 'EWER' });
  const log = () => {};

  step('the first run texts every authority once');
  let result = await notifyApproved(report, { settings: {}, send, log });
  assert.equal(result.sent, 3, `sent: ${JSON.stringify(result)}`);
  assert.equal(result.failed, 0, `failed: ${JSON.stringify(result)}`);
  assert.equal(received.length, 3, `requests: ${received.length}`);
  for (const phone of phones) track('sms_deliveries', claimId(reportId, phone));
  ok(`3 sent, 3 requests to the stand-in`);

  step('the payload is what Termii expects, and the text reads for a person');
  const first = received[0].body;
  assert.equal(received[0].path, '/api/sms/send');
  assert.equal(first.from, 'EWER');
  assert.equal(first.type, 'plain');
  assert.equal(first.channel, 'generic');
  assert.equal(first.api_key, 'test-key');
  // Bare digits, no `+`. This assertion used to read
  // `phones.includes(first.to)` and passed against a payload Termii
  // would have refused — the stand-in was written from the sender's own
  // assumptions, so it agreed with the bug. The expected value comes
  // from the production worker's rule now, not from the sender.
  assert.ok(
    phones.map((p) => p.replace(/^\+/, '')).includes(first.to),
    `to: ${first.to} — Termii wants 234…, not +234…`,
  );
  assert.ok(!String(first.to).startsWith('+'), `to still carries a +: ${first.to}`);
  assert.match(first.sms, /^EWER ALERT: HIGH Flooding reported in North Bank I, Makurdi\./);
  assert.match(first.sms, / - verified by community monitors\.$/);
  assert.ok(first.sms.length <= 320, `length ${first.sms.length}`);
  ok(first.sms);

  step('every number was texted exactly once');
  const texted = received.map((r) => r.body.to).sort();
  assert.deepEqual(texted, phones.map((p) => p.replace(/^\+/, '')).sort());
  ok(texted.join(', '));

  step('the deliveries are recorded as sent, with the provider id');
  const deliveries = await call(
    `${row('sms_deliveries')}?${q({ method: 'equal', attribute: 'reportId', values: [reportId] }, { method: 'limit', values: [25] })}`,
  );
  assert.ok(deliveries.ok, `deliveries: ${deliveries.status}`);
  assert.equal(deliveries.body.total, 3, `stored: ${deliveries.body.total}`);
  for (const d of deliveries.body.rows) {
    assert.equal(d.status, 'sent', `${d.phone}: ${d.status} ${d.error ?? ''}`);
    assert.equal(d.lga, 'makurdi', 'stored folded for the daily cap');
    assert.equal(d.state, 'benue');
  }
  ok('3 rows, all sent, area folded');

  step('a second run texts nobody: the claim is the lock');
  const before = received.length;
  result = await notifyApproved(report, { settings: {}, send, log });
  assert.equal(result.sent, 0, `sent again: ${JSON.stringify(result)}`);
  assert.equal(received.length, before, 'the stand-in was called again');
  ok(`${result.skipped} skipped, 0 further requests — a duplicate flood warning is not a harmless retry`);

  step('the per-event cap stops the send, counted across runs');
  const cappedReportId = name('capped');
  const capped = { ...report, $id: cappedReportId };
  const storedCapped = await call(row('reports'), {
    method: 'POST',
    body: {
      rowId: cappedReportId,
      data: {
        ...capped, userId: 'sms-check', reporterName: 'SMS check', status: 'approved',
        verificationCount: 0, isAlert: false, escalated: false, autoValidated: false,
        submittedAt: new Date().toISOString(), imageUrls: [],
      },
      permissions: ['read("label:admin")'],
    },
  });
  assert.ok(storedCapped.ok, `capped report: ${storedCapped.status}`);
  track('reports', cappedReportId);

  const atTwo = received.length;
  result = await notifyApproved(capped, {
    settings: { max_sms_per_alert_event: '2' },
    send,
    log,
  });
  assert.equal(result.sent, 2, `with a cap of 2: ${JSON.stringify(result)}`);
  assert.equal(result.skipped, 1, `skipped: ${JSON.stringify(result)}`);
  assert.equal(received.length - atTwo, 2, 'exactly two requests');
  for (const phone of phones) track('sms_deliveries', claimId(cappedReportId, phone));
  ok('2 sent, 1 skipped');

  step('a provider failure is recorded, and does not take the run down');
  const failId = name('fail');
  const failing = { ...report, $id: failId };
  const storedFail = await call(row('reports'), {
    method: 'POST',
    body: {
      rowId: failId,
      data: {
        ...failing, userId: 'sms-check', reporterName: 'SMS check', status: 'approved',
        verificationCount: 0, isAlert: false, escalated: false, autoValidated: false,
        submittedAt: new Date().toISOString(), imageUrls: [],
      },
      permissions: ['read("label:admin")'],
    },
  });
  assert.ok(storedFail.ok, `failing report: ${storedFail.status}`);
  track('reports', failId);

  // Termii answers 200 with an error in the body as often as it answers
  // a 4xx, which is the case worth reproducing: a 200 that did not send
  // must not read as sent.
  nextResponse = () => ({ status: 200, body: { code: 'error', message: 'Invalid phone number' } });
  result = await notifyApproved(failing, { settings: {}, send, log });
  nextResponse = () => ({ status: 200, body: { message_id: `m-${received.length}` } });
  assert.equal(result.sent, 0, `sent despite the error: ${JSON.stringify(result)}`);
  assert.equal(result.failed, 3, `failed: ${JSON.stringify(result)}`);

  const failed = await call(
    `${row('sms_deliveries')}?${q({ method: 'equal', attribute: 'reportId', values: [failId] }, { method: 'limit', values: [25] })}`,
  );
  const rows = failed.body.rows ?? [];
  for (const phone of phones) track('sms_deliveries', claimId(failId, phone));
  // A permanent refusal keeps the claim and records why; a transient one
  // releases it so the next drain can try again. "Invalid phone number"
  // is permanent, so these stay — as `rejected`, the word Postgres's
  // check constraint used and the one the rest of the system reads.
  assert.equal(rows.length, 3, `rows after failure: ${rows.length}`);
  for (const d of rows) {
    assert.equal(d.status, 'rejected', `${d.phone}: ${d.status}`);
    assert.match(String(d.error), /Invalid phone/i);
  }
  ok("3 recorded as rejected, with the provider's reason");

  step("an unpaid account is not the number's fault, so the claim is released");
  // The distinction that decides whether a whole LGA's authorities are
  // written off over a billing problem. 402 means top up and retry; if
  // it were treated as a refused number the rows would say `rejected`
  // and nothing would ever text them again.
  const billingId = name('billing');
  const billing = { ...report, $id: billingId };
  const storedBilling = await call(row('reports'), {
    method: 'POST',
    body: {
      rowId: billingId,
      data: {
        ...billing, userId: 'sms-check', reporterName: 'SMS check', status: 'approved',
        verificationCount: 0, isAlert: false, escalated: false, autoValidated: false,
        submittedAt: new Date().toISOString(), imageUrls: [],
      },
      permissions: ['read("label:admin")'],
    },
  });
  assert.ok(storedBilling.ok, `billing report: ${storedBilling.status}`);
  track('reports', billingId);

  nextResponse = () => ({ status: 402, body: { message: 'Insufficient balance' } });
  let threw = null;
  try {
    await notifyApproved(billing, { settings: {}, send, log });
  } catch (e) {
    threw = e;
  }
  nextResponse = () => ({ status: 200, body: { message_id: `m-${received.length}` } });
  assert.ok(threw, 'a transient failure must surface, so the outbox retries');
  assert.match(String(threw.message), /Insufficient balance/);

  const afterBilling = await call(
    `${row('sms_deliveries')}?${q({ method: 'equal', attribute: 'reportId', values: [billingId] }, { method: 'limit', values: [25] })}`,
  );
  assert.equal(
    afterBilling.body.total,
    0,
    `the claim must be released, not kept as rejected (${afterBilling.body.total} left)`,
  );
  ok('claim released and the error raised — the retry texts them once the account is topped up');
}

let failure = null;
try {
  await main();
} catch (error) {
  failure = error;
}
const cleaned = await cleanup();

if (failure) {
  console.error(`\nSMS END TO END: FAIL\n\n${failure?.message ?? failure}`);
  process.exit(1);
}
if (!cleaned) {
  console.error('\nSMS END TO END: the checks passed but cleanup did not.');
  process.exit(1);
}
console.log('\nSMS END TO END: PASS');
