import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadConfig, smsConfigured } from '../src/config.js';
import { withTimeout, HTTP_TIMEOUT_MS } from '../src/http.js';
import { errMessage, silentLog } from '../src/log.js';

const minimal = {
  SUPABASE_URL: 'https://example.supabase.co',
  SUPABASE_SERVICE_ROLE_KEY: 'service-role-key',
};

test('loadConfig reports what is missing rather than throwing', () => {
  const { missing, status } = loadConfig({});
  assert.deepEqual(missing, ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY']);
  assert.equal(status.supabase, false);
  assert.equal(status.onesignal, false);
  assert.equal(status.resend, false);
  assert.equal(status.sms, false);
});

test('a whitespace-only value counts as missing', () => {
  const { missing, config } = loadConfig({ SUPABASE_URL: '   ', SUPABASE_SERVICE_ROLE_KEY: '\t' });
  assert.deepEqual(missing, ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY']);
  assert.equal(config.supabaseUrl, undefined);
});

test('values are trimmed', () => {
  const { config } = loadConfig({ ...minimal, SUPABASE_URL: '  https://x.supabase.co  ' });
  assert.equal(config.supabaseUrl, 'https://x.supabase.co');
});

test('sender defaults are applied when unset', () => {
  const { config } = loadConfig(minimal);
  assert.equal(config.fromEmail, 'noreply@cradi.ng');
  assert.equal(config.fromName, 'EWER Alert System');
});

test('ports and poll intervals fall back on junk values', () => {
  for (const bad of ['', '   ', 'abc', '0', '-5', undefined]) {
    const { config } = loadConfig({ ...minimal, PORT: bad, WORKER_POLL_MS: bad, ESCALATION_POLL_MS: bad });
    assert.equal(config.port, 8080, `PORT=${JSON.stringify(bad)}`);
    assert.equal(config.workerPollMs, 5000);
    assert.equal(config.escalationPollMs, 60000);
  }
});

test('a valid port is used', () => {
  const { config } = loadConfig({ ...minimal, PORT: '3000' });
  assert.equal(config.port, 3000);
});

test('a trailing-garbage port still parses its leading digits', () => {
  // parseInt semantics, documented here so a change is deliberate.
  const { config } = loadConfig({ ...minimal, PORT: '8080abc' });
  assert.equal(config.port, 8080);
});

test('CORS origins are split, trimmed and emptied of blanks', () => {
  const { config } = loadConfig({
    ...minimal,
    CORS_ORIGINS: ' https://a.example , ,https://b.example,',
  });
  assert.deepEqual(config.corsOrigins, ['https://a.example', 'https://b.example']);
});

test('no CORS_ORIGINS means no allowed origins', () => {
  assert.deepEqual(loadConfig(minimal).config.corsOrigins, []);
});

test('a non-UUID OneSignal channel id is dropped with a warning', () => {
  const { config, warnings } = loadConfig({ ...minimal, ONESIGNAL_ANDROID_CHANNEL_ID: 'default-channel' });
  assert.equal(config.oneSignalAndroidChannelId, undefined);
  assert.equal(warnings.length, 1);
  assert.equal(warnings[0].event, 'config.onesignal_channel_invalid');
});

test('a valid OneSignal channel UUID is kept, in any case', () => {
  const uuid = '3F2504E0-4F89-11D3-9A0C-0305E82C3301';
  const { config, warnings } = loadConfig({ ...minimal, ONESIGNAL_ANDROID_CHANNEL_ID: uuid });
  assert.equal(config.oneSignalAndroidChannelId, uuid);
  assert.deepEqual(warnings, []);
});

test('status flags require the whole credential pair', () => {
  assert.equal(loadConfig({ ...minimal, ONESIGNAL_APP_ID: 'app' }).status.onesignal, false);
  assert.equal(
    loadConfig({ ...minimal, ONESIGNAL_APP_ID: 'app', ONESIGNAL_REST_API_KEY: 'k' }).status.onesignal,
    true,
  );
  assert.equal(loadConfig({ ...minimal, RESEND_API_KEY: 'k' }).status.resend, true);
});

test('smsConfigured needs every credential of the named provider', () => {
  assert.equal(smsConfigured({ smsProvider: undefined }), false);
  assert.equal(smsConfigured({ smsProvider: 'carrier-pigeon' }), false);

  assert.equal(smsConfigured({ smsProvider: 'termii', termiiApiKey: 'k' }), false);
  assert.equal(smsConfigured({ smsProvider: 'termii', termiiApiKey: 'k', smsSenderId: 'CRADI' }), true);

  assert.equal(smsConfigured({ smsProvider: 'twilio', twilioAccountSid: 'a', twilioAuthToken: 'b' }), false);
  assert.equal(
    smsConfigured({ smsProvider: 'twilio', twilioAccountSid: 'a', twilioAuthToken: 'b', twilioFrom: '+1' }),
    true,
  );
});

test('SMS_PROVIDER is matched case-insensitively', () => {
  const { config, status } = loadConfig({
    ...minimal,
    SMS_PROVIDER: 'Termii',
    TERMII_API_KEY: 'k',
    SMS_SENDER_ID: 'CRADI',
  });
  assert.equal(config.smsProvider, 'termii');
  assert.equal(status.sms, true);
});

test('withTimeout passes an abort signal to the wrapped fetch', async () => {
  let seen;
  const fetchImpl = async (_input, init) => {
    seen = init.signal;
    return 'ok';
  };
  const result = await withTimeout(fetchImpl)('https://example.test');
  assert.equal(result, 'ok');
  assert.ok(seen, 'a signal must be supplied');
  assert.equal(seen.aborted, false);
});

test('withTimeout aborts a hung upstream', async () => {
  const fetchImpl = (_input, init) =>
    new Promise((_resolve, reject) => {
      init.signal.addEventListener('abort', () => reject(init.signal.reason));
    });
  // AbortSignal.timeout's own timer does not hold the event loop open, so
  // keep it alive for the duration of the wait.
  const keepAlive = setTimeout(() => {}, 1000);
  try {
    await assert.rejects(withTimeout(fetchImpl, 5)('https://example.test'), (err) => {
      assert.equal(err.name, 'TimeoutError');
      return true;
    });
  } finally {
    clearTimeout(keepAlive);
  }
});

test("withTimeout combines the caller's signal with its own", async () => {
  const controller = new AbortController();
  const fetchImpl = (_input, init) =>
    new Promise((_resolve, reject) => {
      init.signal.addEventListener('abort', () => reject(init.signal.reason));
    });
  const pending = withTimeout(fetchImpl, 60_000)('https://example.test', { signal: controller.signal });
  controller.abort(new Error('caller gave up'));
  await assert.rejects(pending, /caller gave up/);
});

test('withTimeout keeps the caller init fields', async () => {
  let seen;
  const fetchImpl = async (_input, init) => {
    seen = init;
    return 'ok';
  };
  await withTimeout(fetchImpl)('https://example.test', { method: 'POST', body: '{}' });
  assert.equal(seen.method, 'POST');
  assert.equal(seen.body, '{}');
});

test('the default timeout is 15s', () => {
  assert.equal(HTTP_TIMEOUT_MS, 15_000);
});

test('errMessage unwraps an Error and stringifies anything else', () => {
  assert.equal(errMessage(new Error('boom')), 'boom');
  assert.equal(errMessage(new TypeError('bad type')), 'bad type');
  assert.equal(errMessage('plain string'), 'plain string');
  assert.equal(errMessage(null), 'null');
  assert.equal(errMessage(undefined), 'undefined');
  assert.equal(errMessage({ code: 42 }), '[object Object]');
});

test('silentLog accepts every level without output', () => {
  assert.doesNotThrow(() => {
    silentLog.info('x', { a: 1 });
    silentLog.warn('x');
    silentLog.error('x');
  });
});
