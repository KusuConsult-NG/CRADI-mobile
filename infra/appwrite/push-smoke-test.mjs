#!/usr/bin/env node
/**
 * End-to-end smoke test for Push Target Registration and Location Reconciliation
 * as specified in docs/DEPLOYMENT.md §7 steps 2 and 8.
 *
 * Runs against live Appwrite Cloud:
 *   1. Registers a device target for a user in Benue / Obi
 *   2. Reconciles topics: asserts target is subscribed to all-users, state-benue, lga-benue-obi
 *   3. Asserts profiles.pushTopics records the subscribed topics
 *   4. Moves the user from Benue / Obi to Nasarawa / Obi (step 8)
 *   5. Reconciles topics: asserts target is removed from Benue topics and added to Nasarawa topics
 *   6. Asserts alert isolation: target is in lga-nasarawa-obi and NOT in lga-benue-obi
 *   7. Cleans up all created resources
 */
import assert from 'node:assert/strict';

const EP = (process.env.APPWRITE_ENDPOINT || '').trim();
const PROJECT = (process.env.APPWRITE_PROJECT_ID || '').trim();
const KEY = (process.env.APPWRITE_API_KEY || '').trim();
const DB = (process.env.APPWRITE_DATABASE_ID || 'cradi').trim();
const CLIENT_FUNCTION = (process.env.APPWRITE_FN_CLIENT || 'client').trim();

if (!EP || !PROJECT || !KEY) {
  console.error('Missing APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, or APPWRITE_API_KEY');
  process.exit(2);
}

const adminHeaders = {
  'content-type': 'application/json',
  'x-appwrite-project': PROJECT,
  'x-appwrite-key': KEY,
};

async function call(path, { method = 'GET', body, headers = adminHeaders } = {}) {
  const r = await fetch(`${EP}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await r.text();
  let parsed = null;
  if (text) {
    try { parsed = JSON.parse(text); } catch { parsed = { message: text }; }
  }
  return { status: r.status, ok: r.ok, body: parsed };
}

const rowPath = (table, id = '') => `/tablesdb/${DB}/tables/${table}/rows${id ? `/${encodeURIComponent(id)}` : ''}`;
const step = (m) => console.log(`\n── ${m}`);
const ok = (m) => console.log(`   ✓ ${m}`);
const note = (m) => console.log(`   · ${m}`);

const stamp = Date.now().toString(36);
const userId = `push-user-${stamp}`.slice(0, 36);
const targetId = `dev-target-${stamp}`.slice(0, 36);
const email = `pushtest-${stamp}@example.org`;
const password = `PushTest-${stamp}-Aa1!`;

const made = [];

async function cleanup() {
  step('cleaning up smoke test resources');
  let cleaned = 0;
  for (const item of made) {
    try {
      if (item.kind === 'target') {
        await call(`/users/${encodeURIComponent(item.userId)}/targets/${encodeURIComponent(item.id)}`, { method: 'DELETE' });
        cleaned++;
      } else if (item.kind === 'profile') {
        await call(rowPath('profiles', item.id), { method: 'DELETE' });
        cleaned++;
      } else if (item.kind === 'user') {
        await call(`/users/${encodeURIComponent(item.id)}`, { method: 'DELETE' });
        cleaned++;
      }
    } catch (_) {}
  }
  ok(`cleaned ${cleaned} resources`);
}

async function run() {
  console.log(`\n=== Push End-to-End Smoke Test (§7 Steps 2 & 8) ===`);
  console.log(`Endpoint: ${EP}`);
  console.log(`Project:  ${PROJECT}`);
  console.log(`Database: ${DB}`);

  try {
    // 1. Create test user
    step('1. Create user and session');
    const userRes = await call('/users', {
      method: 'POST',
      body: { userId, email, password, name: `Push Test ${stamp}` },
    });
    assert.ok(userRes.ok, `Failed to create user: ${JSON.stringify(userRes.body)}`);
    made.push({ kind: 'user', id: userId });
    ok(`user created: ${userId}`);

    // Create session to act as user
    const sessionRes = await call('/account/sessions/email', {
      method: 'POST',
      body: { email, password },
    });
    assert.ok(sessionRes.ok, `Failed to create session: ${JSON.stringify(sessionRes.body)}`);
    const sessionSecret = sessionRes.body.secret;
    const userHeaders = {
      'content-type': 'application/json',
      'x-appwrite-project': PROJECT,
      'x-appwrite-session': sessionSecret,
    };
    ok(`user session created`);

    // 2. Create profile in Benue / Obi
    step('2. Create user profile in Benue / Obi');
    const profileRes = await call(rowPath('profiles'), {
      method: 'POST',
      body: {
        rowId: userId,
        data: {
          name: `Push Test ${stamp}`,
          email,
          role: 'user',
          state: 'Benue',
          lga: 'Obi',
          isApproved: true,
          pushTopics: [],
        },
      },
    });
    assert.ok(profileRes.ok, `Failed to create profile: ${JSON.stringify(profileRes.body)}`);
    made.push({ kind: 'profile', id: userId });
    ok(`profile created in state: Benue, lga: Obi`);

    // 3. Register push target (§7 step 2)
    step('3. Register device push target (§7 step 2)');
    const targetRes = await call('/account/targets/push', {
      method: 'POST',
      headers: userHeaders,
      body: {
        targetId,
        identifier: `fcm-token-${stamp}`,
        name: `Smoke Device ${stamp}`,
        providerId: process.env.APPWRITE_PUSH_PROVIDER_ANDROID || 'fcm',
      },
    });
    assert.ok(targetRes.ok, `Failed to register push target: ${JSON.stringify(targetRes.body)}`);
    made.push({ kind: 'target', userId, id: targetId });
    ok(`device target registered: ${targetId}`);

    // 4. Invoke sync_push_subscriptions via operation Function
    step('4. Invoke sync_push_subscriptions operation');
    const opRes = await call(`/functions/${CLIENT_FUNCTION}/executions`, {
      method: 'POST',
      headers: userHeaders,
      body: {
        body: JSON.stringify({ operation: 'sync_push_subscriptions' }),
        path: '/operation',
        method: 'POST',
        async: false,
      },
    });
    assert.ok(opRes.ok, `Operation call failed: ${JSON.stringify(opRes.body)}`);
    const opBody = JSON.parse(opRes.body.responseBody || '{}');
    assert.equal(opRes.body.responseStatusCode, 200, `Operation returned non-200: ${opRes.body.responseBody}`);
    ok(`operation returned 200: ${JSON.stringify(opBody)}`);

    // 5. Verify subscriptions in Benue topics
    step('5. Verify target subscribed to all-users, state-benue, and lga-benue-obi');
    const profileCheck1 = await call(rowPath('profiles', userId));
    assert.ok(profileCheck1.ok, `Failed to get profile: ${JSON.stringify(profileCheck1.body)}`);
    const topics1 = profileCheck1.body.pushTopics || [];
    note(`profile pushTopics: ${JSON.stringify(topics1)}`);
    assert.ok(topics1.includes('all-users'), 'all-users topic missing from profile');
    assert.ok(topics1.includes('state-benue'), 'state-benue topic missing from profile');
    assert.ok(topics1.includes('lga-benue-obi'), 'lga-benue-obi topic missing from profile');
    ok(`profile pushTopics correctly recorded`);

    // Check subscribers endpoint in Appwrite Cloud
    const lgaBenueSubs = await call(`/messaging/topics/lga-benue-obi/subscribers`);
    assert.ok(lgaBenueSubs.ok, `Failed to list lga-benue-obi subscribers: ${JSON.stringify(lgaBenueSubs.body)}`);
    const isSubscribedBenue = (lgaBenueSubs.body.subscribers || []).some((s) => s.targetId === targetId);
    assert.ok(isSubscribedBenue, `Target ${targetId} not found in lga-benue-obi subscribers`);
    ok(`target verified as subscriber of lga-benue-obi in Appwrite Messaging`);

    // 6. Move user to Nasarawa / Obi (§7 step 8)
    step('6. Move user between LGAs: Benue -> Nasarawa (§7 step 8)');
    const updateRes = await call(rowPath('profiles', userId), {
      method: 'PATCH',
      body: {
        data: {
          state: 'Nasarawa',
          lga: 'Obi',
        },
      },
    });
    assert.ok(updateRes.ok, `Failed to update profile location: ${JSON.stringify(updateRes.body)}`);
    ok(`profile updated to state: Nasarawa, lga: Obi`);

    // 7. Re-sync push subscriptions
    step('7. Re-sync subscriptions after location change');
    const opRes2 = await call(`/functions/${CLIENT_FUNCTION}/executions`, {
      method: 'POST',
      headers: userHeaders,
      body: {
        body: JSON.stringify({ operation: 'sync_push_subscriptions' }),
        path: '/operation',
        method: 'POST',
        async: false,
      },
    });
    assert.ok(opRes2.ok, `Operation call failed: ${JSON.stringify(opRes2.body)}`);
    assert.equal(opRes2.body.responseStatusCode, 200, `Operation returned non-200: ${opRes2.body.responseBody}`);
    ok(`sync operation completed after location change`);

    // 8. Verify topic reconciliation
    step('8. Verify reconciliation: old LGA unsubscribed, new LGA subscribed');
    const profileCheck2 = await call(rowPath('profiles', userId));
    assert.ok(profileCheck2.ok, `Failed to get updated profile: ${JSON.stringify(profileCheck2.body)}`);
    const topics2 = profileCheck2.body.pushTopics || [];
    note(`updated profile pushTopics: ${JSON.stringify(topics2)}`);
    assert.ok(topics2.includes('all-users'), 'all-users topic missing');
    assert.ok(topics2.includes('state-nasarawa'), 'state-nasarawa topic missing');
    assert.ok(topics2.includes('lga-nasarawa-obi'), 'lga-nasarawa-obi topic missing');
    assert.ok(!topics2.includes('state-benue'), 'state-benue was NOT unsubscribed');
    assert.ok(!topics2.includes('lga-benue-obi'), 'lga-benue-obi was NOT unsubscribed');
    ok(`profile.pushTopics reconciled: Benue dropped, Nasarawa added`);

    // 9. Verify isolation at Messaging API level
    step('9. Verify isolation at Appwrite Messaging level');
    const lgaBenueSubs2 = await call(`/messaging/topics/lga-benue-obi/subscribers`);
    assert.ok(lgaBenueSubs2.ok);
    const stillInBenue = (lgaBenueSubs2.body.subscribers || []).some((s) => s.targetId === targetId);
    assert.ok(!stillInBenue, `Target is STILL subscribed to old LGA (lga-benue-obi)!`);
    ok(`target confirmed REMOVED from old LGA (lga-benue-obi)`);

    const lgaNasarawaSubs = await call(`/messaging/topics/lga-nasarawa-obi/subscribers`);
    assert.ok(lgaNasarawaSubs.ok);
    const inNasarawa = (lgaNasarawaSubs.body.subscribers || []).some((s) => s.targetId === targetId);
    assert.ok(inNasarawa, `Target is NOT subscribed to new LGA (lga-nasarawa-obi)!`);
    ok(`target confirmed SUBSCRIBED to new LGA (lga-nasarawa-obi)`);

    console.log(`\n======================================================`);
    console.log(`🎉 PUSH END-TO-END (§7 STEPS 2 & 8) VERIFIED AND PASSED!`);
    console.log(`======================================================\n`);
  } finally {
    await cleanup();
  }
}

run().catch((e) => {
  console.error('\nFAIL:', e);
  cleanup().finally(() => process.exit(1));
});
