import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ONESIGNAL_API_URL, chunk, createOneSignal, idempotencyUuid } from '../src/onesignal.js';
import { logger } from './helpers.js';

function fakeFetch(responses = []) {
  const calls = [];
  const fn = async (url, init) => {
    calls.push({ url, init, body: JSON.parse(init.body) });
    const r = responses.shift() ?? { status: 200, json: { id: 'n1' } };
    return { ok: r.status < 300, status: r.status, json: async () => r.json };
  };
  fn.calls = calls;
  return fn;
}

const n = { title: 'T', body: 'B', data: { type: 'x' } };

test('chunk splits lists', () => {
  assert.deepEqual(chunk([1, 2, 3, 4, 5], 2), [[1, 2], [3, 4], [5]]);
});

test('idempotencyUuid is deterministic and a valid UUID v4 (version 4, RFC variant)', () => {
  const a = idempotencyUuid('outbox:1:x');
  assert.equal(a, idempotencyUuid('outbox:1:x'));
  assert.notEqual(a, idempotencyUuid('outbox:2:x'));
  assert.match(a, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
});

test('sendToUsers posts external_id aliases with Key auth, chunked at 2000', async () => {
  const fetchImpl = fakeFetch();
  const os = createOneSignal({ appId: 'app', apiKey: 'rest', androidChannelId: 'chan', fetchImpl, logger });
  const ids = Array.from({ length: 4500 }, (_, i) => `u${i}`);
  await os.sendToUsers(ids, n, { key: 'k' });
  assert.equal(fetchImpl.calls.length, 3);
  const first = fetchImpl.calls[0];
  assert.equal(first.url, ONESIGNAL_API_URL);
  assert.equal(first.init.headers.Authorization, 'Key rest');
  assert.equal(first.body.app_id, 'app');
  assert.equal(first.body.target_channel, 'push');
  assert.deepEqual(first.body.headings, { en: 'T' });
  assert.deepEqual(first.body.contents, { en: 'B' });
  assert.equal(first.body.android_channel_id, 'chan');
  assert.equal(first.body.include_aliases.external_id.length, 2000);
  assert.equal(fetchImpl.calls[2].body.include_aliases.external_id.length, 500);
  assert.notEqual(first.body.idempotency_key, fetchImpl.calls[1].body.idempotency_key);
  assert.equal(first.body.idempotency_key, idempotencyUuid('k:0'));
  assert.ok(first.init.signal instanceof AbortSignal, 'request has a timeout signal');
});

test('sendToTag uses a tag filter; sendToAll uses Total Subscriptions', async () => {
  const fetchImpl = fakeFetch();
  const os = createOneSignal({ appId: 'app', apiKey: 'rest', fetchImpl, logger });
  await os.sendToTag('lga', 'ikeja', n);
  await os.sendToAll(n);
  assert.deepEqual(fetchImpl.calls[0].body.filters, [{ field: 'tag', key: 'lga', relation: '=', value: 'ikeja' }]);
  assert.equal(fetchImpl.calls[0].body.android_channel_id, undefined);
  assert.deepEqual(fetchImpl.calls[1].body.included_segments, ['Total Subscriptions']);
});

test('sendToTags ANDs one tag filter per tag (no OR operator)', async () => {
  const fetchImpl = fakeFetch();
  const os = createOneSignal({ appId: 'app', apiKey: 'rest', fetchImpl, logger });
  assert.deepEqual(await os.sendToTags({ lga: 'obi', state: 'benue' }, n, { key: 'k' }), { sent: 1, skipped: false });
  const { filters } = fetchImpl.calls[0].body;
  assert.deepEqual(filters, [
    { field: 'tag', key: 'lga', relation: '=', value: 'obi' },
    { field: 'tag', key: 'state', relation: '=', value: 'benue' },
  ]);
  assert.ok(!filters.some((f) => f.operator), 'no OR operator between the tag filters');
  assert.equal(fetchImpl.calls[0].body.included_segments, undefined);
  assert.equal(fetchImpl.calls[0].body.idempotency_key, idempotencyUuid('k'));
});

test('sendToTag with andTags filters on the tag AND the extra tags', async () => {
  const fetchImpl = fakeFetch();
  const os = createOneSignal({ appId: 'app', apiKey: 'rest', fetchImpl, logger });
  await os.sendToTag('lga', 'obi', n, { key: 'b', andTags: { state: 'benue' } });
  assert.deepEqual(fetchImpl.calls[0].body.filters, [
    { field: 'tag', key: 'lga', relation: '=', value: 'obi' },
    { field: 'tag', key: 'state', relation: '=', value: 'benue' },
  ]);
});

test('sendToTags with no tags or an empty value sends nothing', async () => {
  const fetchImpl = fakeFetch();
  const os = createOneSignal({ appId: 'app', apiKey: 'rest', fetchImpl, logger });
  assert.deepEqual(await os.sendToTags({}, n), { sent: 0, skipped: false });
  assert.deepEqual(await os.sendToTags({ lga: 'obi', state: '' }, n), { sent: 0, skipped: false });
  assert.deepEqual(await os.sendToTag('lga', '', n), { sent: 0, skipped: false });
  assert.equal(fetchImpl.calls.length, 0);
  const unconfigured = createOneSignal({ fetchImpl, logger });
  assert.deepEqual(await unconfigured.sendToTags({ lga: 'obi', state: 'benue' }, n), { sent: 0, skipped: true });
  assert.equal(fetchImpl.calls.length, 0);
});

test('HTTP errors throw; 200 with errors does not', async () => {
  const fetchImpl = fakeFetch([{ status: 400, json: { errors: ['bad app_id'] } }, { status: 200, json: { id: '', errors: ['All included players are not subscribed'] } }]);
  const os = createOneSignal({ appId: 'app', apiKey: 'rest', fetchImpl, logger });
  await assert.rejects(os.sendToAll(n), /OneSignal HTTP 400: bad app_id/);
  await os.sendToAll(n);
});

test('unconfigured client is a logged no-op', async () => {
  const fetchImpl = fakeFetch();
  const os = createOneSignal({ fetchImpl, logger });
  assert.equal(os.configured, false);
  assert.deepEqual(await os.sendToUsers(['u1'], n), { sent: 0, skipped: true });
  assert.deepEqual(await os.sendToAll(n), { sent: 0, skipped: true });
  assert.equal(fetchImpl.calls.length, 0);
});
