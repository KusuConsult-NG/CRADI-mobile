import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadConfig } from '../src/config.js';
import { request } from 'node:http';
import { MAX_BODY_BYTES, corsHeadersFor, createHttpServer } from '../src/server.js';
import { logger } from './helpers.js';

test('loadConfig: defaults, missing required, feature flags', () => {
  const { config, missing, status } = loadConfig({ PORT: '3000' });
  assert.deepEqual(missing, ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY']);
  assert.deepEqual(status, { supabase: false, onesignal: false, resend: false, sms: false });
  assert.equal(config.port, 3000);
  assert.equal(config.fromEmail, 'noreply@cradi.ng');
  assert.equal(config.fromName, 'EWER Alert System');
  assert.equal(config.workerPollMs, 5000);
  assert.equal(config.escalationPollMs, 60000);

  const full = loadConfig({
    SUPABASE_URL: 'https://x.supabase.co',
    SUPABASE_SERVICE_ROLE_KEY: 'k',
    ONESIGNAL_APP_ID: 'a',
    ONESIGNAL_REST_API_KEY: 'b',
    RESEND_API_KEY: 'c',
    CORS_ORIGINS: 'https://a.com, https://b.com',
  });
  assert.deepEqual(full.missing, []);
  assert.deepEqual(full.status, { supabase: true, onesignal: true, resend: true, sms: false });
  assert.deepEqual(full.config.corsOrigins, ['https://a.com', 'https://b.com']);
});

test('corsHeadersFor', () => {
  assert.deepEqual(corsHeadersFor('https://a.com', []), {});
  assert.deepEqual(corsHeadersFor('https://a.com', ['*']), { 'Access-Control-Allow-Origin': '*' });
  assert.deepEqual(corsHeadersFor('https://a.com', ['https://a.com']), { 'Access-Control-Allow-Origin': 'https://a.com', Vary: 'Origin' });
  assert.deepEqual(corsHeadersFor('https://evil.com', ['https://a.com']), {});
});

test('HTTP: /health, /email routing, bad JSON, 404', async (t) => {
  const seen = [];
  const server = createHttpServer({
    health: () => ({ status: 503, body: { ok: false, config: { supabase: false } } }),
    handleEmail: async (req) => {
      seen.push(req);
      return { status: 200, body: { success: true } };
    },
    corsOrigins: ['https://admin.cradi.ng'],
    logger,
  });
  await new Promise((r) => server.listen(0, r));
  t.after(() => server.close());
  const base = `http://127.0.0.1:${server.address().port}`;

  const h = await fetch(`${base}/health`);
  assert.equal(h.status, 503);
  assert.deepEqual(await h.json(), { ok: false, config: { supabase: false } });

  const pre = await fetch(`${base}/email`, { method: 'OPTIONS', headers: { Origin: 'https://admin.cradi.ng' } });
  assert.equal(pre.status, 204);
  assert.equal(pre.headers.get('access-control-allow-origin'), 'https://admin.cradi.ng');

  const ok = await fetch(`${base}/email`, {
    method: 'POST',
    headers: { Authorization: 'Bearer t', 'Content-Type': 'application/json' },
    body: JSON.stringify({ type: 'welcome', to: 'a@b.co' }),
  });
  assert.equal(ok.status, 200);
  assert.equal(seen[0].authorization, 'Bearer t');
  assert.equal(seen[0].body.type, 'welcome');

  const bad = await fetch(`${base}/email`, { method: 'POST', body: '{nope' });
  assert.equal(bad.status, 400);

  assert.equal((await fetch(`${base}/email`)).status, 405);
  assert.equal((await fetch(`${base}/nope`)).status, 404);
});

test('HTTP: oversized /email body gets a 413 response (not a reset) and handler is not called', async (t) => {
  let called = false;
  const server = createHttpServer({
    health: () => ({ status: 200, body: {} }),
    handleEmail: async () => {
      called = true;
      return { status: 200, body: {} };
    },
    logger,
  });
  await new Promise((r) => server.listen(0, r));
  t.after(() => server.close());
  const { port } = server.address();

  const big = Buffer.alloc(MAX_BODY_BYTES * 4, 'a');
  const res = await new Promise((resolve, reject) => {
    const req = request({ port, path: '/email', method: 'POST', headers: { 'Content-Type': 'application/json' } }, (r) => {
      let data = '';
      r.on('data', (c) => (data += c));
      r.on('end', () => resolve({ status: r.statusCode, headers: r.headers, body: data }));
    });
    req.on('error', reject);
    req.end(big);
  });
  assert.equal(res.status, 413);
  assert.equal(res.headers.connection, 'close');
  assert.deepEqual(JSON.parse(res.body), { success: false, error: 'Payload too large' });
  assert.equal(called, false);

  // fetch() sees the 413 as well.
  const f = await fetch(`http://127.0.0.1:${port}/email`, { method: 'POST', body: big });
  assert.equal(f.status, 413);
});
