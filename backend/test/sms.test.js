import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadConfig, smsConfigured } from '../src/config.js';
import { normalizeNigerianPhone } from '../src/sms/phone.js';
import { TERMII_SEND_URL, createSmsProvider, twilioMessagesUrl } from '../src/sms/providers.js';
import { SMS_MAX_CHARS, authoritySmsText, createAuthoritySms } from '../src/sms/authorities.js';
import { createHandlers, runOutboxBatch } from '../src/outbox.js';
import { fakeFetch, fakePush, fakeRepo, fakeSms, logger } from './helpers.js';

const report = {
  id: 'r1',
  user_id: 'reporter',
  ward: 'Ward 1',
  lga: 'Ikeja',
  hazard_type: 'Flood',
  severity: 'high',
  description: 'River overflowing near the market.',
  status: 'approved',
};
const authority = (id, phone, lga = 'Ikeja') => ({ id, name: id, phone, coverage_lga: lga });

test('normalizeNigerianPhone: local, international and invalid spellings', () => {
  for (const input of ['08031234567', '0803 123 4567', '803-123-4567', '2348031234567', '+2348031234567', '+234 (0)803 123 4567', '002348031234567', '+234 0803 123 4567']) {
    assert.equal(normalizeNigerianPhone(input), '+2348031234567', input);
  }
  assert.equal(normalizeNigerianPhone('09012345678'), '+2349012345678');
  for (const bad of [null, '', 'abc', '0803123456', '080312345678', '+14155550100', '+44 20 7946 0958', '0003123456789']) {
    assert.equal(normalizeNigerianPhone(bad), null, String(bad));
  }
});

test('authoritySmsText: format and 320-char limit', () => {
  assert.equal(
    authoritySmsText(report),
    'EWER ALERT: HIGH Flood reported in Ward 1, Ikeja. River overflowing near the market. - verified by community monitors.',
  );
  assert.equal(
    authoritySmsText({ ...report, ward: '', description: '' }),
    'EWER ALERT: HIGH Flood reported in Ikeja. - verified by community monitors.',
  );
  const long = authoritySmsText({ ...report, description: 'x '.repeat(400) });
  assert.ok(long.length <= SMS_MAX_CHARS);
  assert.match(long, /\.\.\. - verified by community monitors\.$/);
});

test('Termii provider request shape', async () => {
  const fetchImpl = fakeFetch({ json: { message_id: 'abc', message: 'Successfully Sent' } });
  const sms = createSmsProvider({ smsProvider: 'termii', termiiApiKey: 'tk', smsSenderId: 'EWER' }, { fetchImpl, logger });
  assert.equal(sms.configured, true);
  assert.deepEqual(await sms.send('+2348031234567', 'hello'), { id: 'abc' });
  const [{ url, init }] = fetchImpl.calls;
  assert.equal(url, TERMII_SEND_URL);
  assert.equal(url, 'https://api.ng.termii.com/api/sms/send');
  assert.equal(init.method, 'POST');
  assert.equal(init.headers['Content-Type'], 'application/json');
  assert.ok(init.signal instanceof AbortSignal);
  assert.deepEqual(JSON.parse(init.body), {
    api_key: 'tk',
    to: '2348031234567',
    from: 'EWER',
    sms: 'hello',
    type: 'plain',
    channel: 'generic',
  });
});

test('Twilio provider request shape', async () => {
  const fetchImpl = fakeFetch({ status: 201, json: { sid: 'SM1' } });
  const sms = createSmsProvider(
    { smsProvider: 'twilio', twilioAccountSid: 'AC123', twilioAuthToken: 'tok', twilioFrom: '+15005550006' },
    { fetchImpl, logger },
  );
  assert.deepEqual(await sms.send('+2348031234567', 'hello there'), { id: 'SM1' });
  const [{ url, init }] = fetchImpl.calls;
  assert.equal(url, 'https://api.twilio.com/2010-04-01/Accounts/AC123/Messages.json');
  assert.equal(url, twilioMessagesUrl('AC123'));
  assert.equal(init.headers.Authorization, `Basic ${Buffer.from('AC123:tok').toString('base64')}`);
  assert.equal(init.headers['Content-Type'], 'application/x-www-form-urlencoded');
  assert.ok(init.signal instanceof AbortSignal);
  const form = new URLSearchParams(init.body);
  assert.deepEqual(Object.fromEntries(form), { To: '+2348031234567', From: '+15005550006', Body: 'hello there' });
});

test('provider HTTP error throws; unset/incomplete provider logs and skips', async () => {
  const failing = createSmsProvider(
    { smsProvider: 'termii', termiiApiKey: 'tk', smsSenderId: 'EWER' },
    { fetchImpl: fakeFetch({ status: 401, json: { message: 'Invalid api key' } }), logger },
  );
  await assert.rejects(failing.send('+2348031234567', 'x'), /Termii HTTP 401: Invalid api key/);

  const fetchImpl = fakeFetch();
  for (const cfg of [{}, { smsProvider: 'termii', termiiApiKey: 'tk' }, { smsProvider: 'carrier-pigeon' }]) {
    const sms = createSmsProvider(cfg, { fetchImpl, logger });
    assert.equal(sms.configured, false);
    assert.deepEqual(await sms.send('+2348031234567', 'x'), { skipped: true });
  }
  assert.equal(fetchImpl.calls.length, 0);
});

test('config: sms status requires provider + its credentials', () => {
  assert.equal(loadConfig({}).status.sms, false);
  assert.equal(loadConfig({ SMS_PROVIDER: 'Termii', TERMII_API_KEY: 'k', SMS_SENDER_ID: 'EWER' }).status.sms, true);
  assert.equal(loadConfig({ SMS_PROVIDER: 'twilio', TWILIO_ACCOUNT_SID: 'a', TWILIO_AUTH_TOKEN: 'b' }).status.sms, false);
  assert.equal(smsConfigured({ smsProvider: 'twilio', twilioAccountSid: 'a', twilioAuthToken: 'b', twilioFrom: '+1' }), true);
});

test('authority SMS: lga match, per-event limit from settings, invalid/duplicate phones skipped', async () => {
  const repo = fakeRepo({
    settings: { max_sms_per_alert_event: 3 },
    authorities: [
      authority('a1', '08031234567'),
      authority('a2', 'not a phone'),
      authority('a3', '+234 803 123 4567'), // same number as a1
      authority('a4', '08050000000'),
      authority('other', '08060000000', 'Epe'),
    ],
  });
  const sms = fakeSms();
  const svc = createAuthoritySms({ repo, sms, logger });
  const summary = await svc.notifyApproved(report);
  assert.deepEqual(repo.state.authorityQueries, [{ lga: 'Ikeja', limit: 3 }]);
  assert.deepEqual(sms.sent.map((s) => s.to), ['+2348031234567']);
  assert.equal(summary.invalid, 1);
  assert.equal(sms.sent[0].text, authoritySmsText(report));

  // Default per-event limit is 20.
  const repo2 = fakeRepo({ authorities: [] });
  await createAuthoritySms({ repo: repo2, sms, logger }).notifyApproved(report);
  assert.deepEqual(repo2.state.authorityQueries, [{ lga: 'Ikeja', limit: 20 }]);
});

test('authority SMS: daily cap per LGA, resets next Lagos day', async () => {
  let t = Date.parse('2026-09-26T10:00:00Z');
  const repo = fakeRepo({
    settings: { max_sms_per_lga_per_day: 3 },
    authorities: [authority('a1', '08030000001'), authority('a2', '08030000002')],
  });
  const sms = fakeSms();
  const svc = createAuthoritySms({ repo, sms, logger, now: () => t });
  await svc.notifyApproved({ ...report, id: 'r1' });
  const second = await svc.notifyApproved({ ...report, id: 'r2' });
  assert.equal(sms.sent.length, 3);
  assert.equal(second.capped, 1);
  assert.equal(svc.dailyCount('Ikeja'), 3);

  // Other LGA is counted separately.
  repo.state.authorities.push(authority('e1', '08030000009', 'Epe'));
  await svc.notifyApproved({ ...report, id: 'r3', lga: 'Epe' });
  assert.equal(sms.sent.length, 4);

  // 23:30 UTC is already the next day in Lagos (UTC+1).
  t = Date.parse('2026-09-26T23:30:00Z');
  await svc.notifyApproved({ ...report, id: 'r4' });
  assert.equal(sms.sent.length, 6);
  assert.equal(svc.dailyCount('Ikeja'), 2);
});

test('authority SMS: dedupe per report; retry after partial failure sends only the missing ones', async () => {
  const repo = fakeRepo({ authorities: [authority('a1', '08030000001'), authority('a2', '08030000002')] });
  const sms = fakeSms({ failFor: true });
  const svc = createAuthoritySms({ repo, sms, logger });

  // All fail -> throws so the outbox retries.
  await assert.rejects(svc.notifyApproved(report), /SMS to authorities failed/);

  // Partial failure -> no throw, report completed; the failed number is not retried.
  sms.send = async (to, text) => {
    if (to === '+2348030000002') throw new Error('boom');
    sms.sent.push({ to, text });
  };
  const partial = await svc.notifyApproved(report);
  assert.deepEqual({ sent: partial.sent, failed: partial.failed }, { sent: 1, failed: 1 });
  assert.deepEqual(await svc.notifyApproved(report), { sent: 0, note: 'sms already sent for report' });
  assert.equal(sms.sent.length, 1);
});

test('authority SMS: provider not configured -> skipped, no DB lookups', async () => {
  const repo = fakeRepo({ authorities: [authority('a1', '08030000001')] });
  const svc = createAuthoritySms({ repo, sms: fakeSms({ configured: false }), logger });
  assert.deepEqual(await svc.notifyApproved(report), { sent: 0, note: 'sms not configured' });
  assert.equal(repo.state.authorityQueries.length, 0);
});

test('outbox: approval transition texts authorities once, even when the event is retried', async () => {
  const repo = fakeRepo({
    reports: [{ ...report }],
    authorities: [authority('a1', '08030000001')],
    events: [
      { id: 1, event_type: 'report_status_changed', payload: { report_id: 'r1', old_status: 'verified', new_status: 'approved' } },
      { id: 2, event_type: 'report_status_changed', payload: { report_id: 'r1', old_status: 'approved', new_status: 'approved' } },
    ],
  });
  const sms = fakeSms();
  const push = fakePush();
  let failTag = true;
  const flakyPush = {
    ...push,
    async sendToTag(...args) {
      const r = await push.sendToTag(...args);
      if (failTag) {
        failTag = false;
        throw new Error('tag push failed');
      }
      return r;
    },
  };
  // The broadcast fails on the first attempt (before the SMS step); the retry sends the SMS.
  const handlers = createHandlers({ repo, push: flakyPush, authoritySms: createAuthoritySms({ repo, sms, logger }), logger });
  await runOutboxBatch({ repo, handlers, logger });
  assert.equal(repo.state.events[0].processed_at, undefined); // failed before SMS
  assert.equal(sms.sent.length, 0);
  assert.equal(repo.state.events[1].processed_at, 'now'); // not a transition: no SMS

  await runOutboxBatch({ repo, handlers, logger });
  assert.equal(repo.state.events[0].processed_at, 'now');
  assert.equal(sms.sent.length, 1);

  // Re-running the same event (e.g. a replayed outbox row) does not text again.
  delete repo.state.events[0].processed_at;
  await runOutboxBatch({ repo, handlers, logger });
  assert.equal(sms.sent.length, 1);
});
