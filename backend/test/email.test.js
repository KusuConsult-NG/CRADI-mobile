import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  authorizeRecipient,
  createEmailHandler,
  createRateLimiter,
  isPrivilegedProfile,
} from '../src/email/service.js';
import { escapeHtml, templates } from '../src/email/templates.js';
import { logger } from './helpers.js';

const users = {
  'tok-user': { id: 'u1', email: 'Alice@Example.com' },
  'tok-staff': { id: 's1', email: 'staff@example.com' },
  'tok-disabled': { id: 'd1', email: 'd@example.com' },
  'tok-pending-staff': { id: 'p1', email: 'p@example.com' },
};
const profiles = {
  u1: { id: 'u1', role: 'user', is_approved: false, is_disabled: false },
  s1: { id: 's1', role: 'ldp_coordinator', is_approved: true, is_disabled: false },
  d1: { id: 'd1', role: 'admin', is_approved: true, is_disabled: true },
  p1: { id: 'p1', role: 'ewm', is_approved: false, is_disabled: false },
};

function setup({ sendEmail, now } = {}) {
  const sent = [];
  let t = 0;
  const clock = now ?? { get: () => t, advance: (ms) => (t += ms) };
  const handle = createEmailHandler({
    verifyToken: async (tok) => users[tok] ?? null,
    getProfile: async (id) => profiles[id] ?? null,
    sendEmail:
      sendEmail === undefined
        ? async (msg) => {
            sent.push(msg);
            return { id: `m${sent.length}` };
          }
        : sendEmail,
    limiter: createRateLimiter({ now: () => clock.get() }),
    logger,
  });
  return { handle, sent, clock };
}

const welcome = (to) => ({ type: 'welcome', to, data: { name: 'Alice', email: to } });

test('isPrivilegedProfile requires approved, enabled staff role', () => {
  assert.equal(isPrivilegedProfile(profiles.s1), true);
  assert.equal(isPrivilegedProfile(profiles.u1), false);
  assert.equal(isPrivilegedProfile(profiles.d1), false);
  assert.equal(isPrivilegedProfile(profiles.p1), false);
});

test('authorizeRecipient: own address (case-insensitive) ok, others forbidden for non-staff', () => {
  assert.equal(authorizeRecipient({ user: users['tok-user'], profile: profiles.u1, to: 'alice@example.COM' }).ok, true);
  assert.equal(authorizeRecipient({ user: users['tok-user'], profile: profiles.u1, to: 'bob@example.com' }).status, 403);
  assert.equal(authorizeRecipient({ user: users['tok-staff'], profile: profiles.s1, to: 'bob@example.com' }).ok, true);
  assert.equal(authorizeRecipient({ user: users['tok-disabled'], profile: profiles.d1, to: 'd@example.com' }).status, 403);
});

test('missing or invalid bearer token -> 401', async () => {
  const { handle } = setup();
  assert.equal((await handle({ authorization: undefined, body: welcome('a@b.co') })).status, 401);
  assert.equal((await handle({ authorization: 'Bearer nope', body: welcome('a@b.co') })).status, 401);
});

test('validation: unknown type, verification dropped, bad to, bad reset link', async () => {
  const { handle } = setup();
  const auth = 'Bearer tok-staff';
  assert.equal((await handle({ authorization: auth, body: { type: 'verification', to: 'a@b.co', data: {} } })).status, 400);
  assert.equal((await handle({ authorization: auth, body: { type: 'welcome', to: ['a@b.co'], data: {} } })).status, 400);
  assert.equal((await handle({ authorization: auth, body: { type: 'welcome', to: 'a@b.co, c@d.co', data: {} } })).status, 400);
  assert.equal(
    (await handle({ authorization: auth, body: { type: 'passwordReset', to: 'a@b.co', data: { resetLink: 'javascript:alert(1)' } } })).status,
    400,
  );
});

test('non-staff can email only themselves', async () => {
  const { handle, sent } = setup();
  const other = await handle({ authorization: 'Bearer tok-user', body: welcome('bob@example.com') });
  assert.equal(other.status, 403);
  const own = await handle({ authorization: 'Bearer tok-user', body: welcome('alice@example.com') });
  assert.equal(own.status, 200);
  assert.equal(own.body.success, true);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].to, 'alice@example.com');
});

test('per-recipient limit 1/min and per-caller limit 20/hour', async () => {
  const { handle, clock } = setup();
  const auth = 'Bearer tok-staff';
  assert.equal((await handle({ authorization: auth, body: welcome('x@example.com') })).status, 200);
  assert.equal((await handle({ authorization: auth, body: welcome('x@example.com') })).status, 429);
  clock.advance(60_001);
  assert.equal((await handle({ authorization: auth, body: welcome('x@example.com') })).status, 200);

  for (let i = 0; i < 18; i++) {
    assert.equal((await handle({ authorization: auth, body: welcome(`r${i}@example.com`) })).status, 200);
  }
  // 20 sent this hour
  assert.equal((await handle({ authorization: auth, body: welcome('new@example.com') })).status, 429);
  clock.advance(60 * 60_000);
  assert.equal((await handle({ authorization: auth, body: welcome('new@example.com') })).status, 200);
});

test('provider errors are not leaked to the client', async () => {
  const { handle } = setup({
    sendEmail: async () => {
      throw new Error('Resend HTTP 403: secret domain detail');
    },
  });
  const res = await handle({ authorization: 'Bearer tok-staff', body: welcome('y@example.com') });
  assert.equal(res.status, 502);
  assert.deepEqual(res.body, { success: false, error: 'Failed to send email' });
});

test('email not configured -> 503', async () => {
  const { handle } = setup({ sendEmail: null });
  assert.equal((await handle({ authorization: 'Bearer tok-staff', body: welcome('z@example.com') })).status, 503);
});

test('templates escape caller-supplied HTML', () => {
  assert.equal(escapeHtml('<b>"x"&\''), '&lt;b&gt;&quot;x&quot;&amp;&#39;');
  const { html } = templates.welcome({ name: '<script>alert(1)</script>', email: 'a@b.co' });
  assert.ok(!html.includes('<script>'));
  assert.ok(html.includes('&lt;script&gt;'));
  const alert = templates.hazardAlert({ hazardType: 'Flood', severity: 'Critical', description: '<img src=x>', lga: 'Ikeja' });
  assert.ok(alert.subject.startsWith('🚨 CRITICAL: Flood'));
  assert.ok(!alert.html.includes('<img src=x>'));
});
