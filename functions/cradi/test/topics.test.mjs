import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import operation from '../src/operation.js';
import { eventsFor } from '../src/on-write.js';
import { createHandlers } from '../src/lib/handlers.js';
import { alertTopics } from '../src/lib/notifications.js';
import {
  desiredTopics,
  reconcileSubscriptions,
  subscriberId,
} from '../src/lib/topics.js';
import { MAX_ID } from '../src/lib/appwrite.js';
import { context, fakeAppwrite, profile } from './helpers.mjs';

/** A push target as `GET /users/{id}/targets` returns one. */
const pushTarget = (id, userId = 'u1') => ({
  $id: id,
  userId,
  providerType: 'push',
  identifier: `token-${id}`,
  expired: false,
});

const benue = { state: 'Benue', lga: 'Obi' };

describe('desiredTopics', () => {
  it('puts everyone in all-users, including a profile with no location', () => {
    assert.deepEqual(desiredTopics(profile()), ['all-users']);
    assert.deepEqual(desiredTopics({}), ['all-users']);
    assert.deepEqual(desiredTopics(null), ['all-users']);
  });

  it('adds the state topic, then the state-scoped LGA topic', () => {
    assert.deepEqual(desiredTopics({ state: 'Benue' }), ['all-users', 'state-benue']);
    assert.deepEqual(desiredTopics(benue), [
      'all-users',
      'state-benue',
      'lga-benue-obi',
    ]);
  });

  /**
   * The property the whole module exists for, and it is asserted against
   * the sender rather than against a second slug: whatever `alertTopics`
   * would address for an alert at this location must be a topic the
   * profile is in. A subscription that differs by one character is a
   * subscription to nothing, and Appwrite reports the send as successful
   * either way.
   */
  it('covers every topic the sender would address for that location', () => {
    for (const where of [
      { state: 'Benue', lga: 'Obi' },
      { state: 'Nasarawa', lga: 'Obi' },
      { state: 'Plateau', lga: 'Langtang North' },
      { state: 'Federal Capital Territory', lga: 'Abuja Municipal' },
    ]) {
      const subscribed = new Set(desiredTopics(where));
      // An alert to the whole country.
      assert.ok(alertTopics({ targetState: null, targetLga: 'All' }).all);
      assert.ok(subscribed.has('all-users'));
      // An alert to the state, and one to the LGA — which is also the
      // topic an approved report in that LGA is broadcast to.
      for (const lga of ['All', where.lga]) {
        for (const topic of alertTopics({ targetState: where.state, targetLga: lga }).topics) {
          assert.ok(subscribed.has(topic), `${topic} not subscribed for ${JSON.stringify(where)}`);
        }
      }
    }
  });

  it('keeps the two Obis apart', () => {
    const [, , inBenue] = desiredTopics({ state: 'Benue', lga: 'Obi' });
    const [, , inNasarawa] = desiredTopics({ state: 'Nasarawa', lga: 'Obi' });
    assert.notEqual(inBenue, inNasarawa);
    assert.equal(inBenue, alertTopics({ targetState: 'Benue', targetLga: 'Obi' }).topics[0]);
  });

  it('degrades the same way the report broadcast does for an LGA with no state', () => {
    // `alerts` has a check constraint for this; `profiles` does not, and
    // the report path reaches the name-only topic too.
    assert.deepEqual(desiredTopics({ lga: 'Obi' }), ['all-users', 'lga-obi']);
  });
});

describe('subscriberId', () => {
  it('is deterministic, distinct per target and topic, and fits an id', () => {
    const a = subscriberId('t1', 'lga-benue-obi');
    assert.equal(a, subscriberId('t1', 'lga-benue-obi'));
    assert.notEqual(a, subscriberId('t2', 'lga-benue-obi'));
    assert.notEqual(a, subscriberId('t1', 'state-benue'));
    assert.ok(a.length <= MAX_ID, `${a} is ${a.length} characters`);
    // Two long ids that share a prefix must not collide, which is the
    // reason this is a digest rather than a trimmed composite.
    assert.notEqual(
      subscriberId('target-aaaaaaaaaaaaaaaaaaaa', 'lga-plateau-langtang-north'),
      subscriberId('target-aaaaaaaaaaaaaaaaaaaa', 'lga-plateau-langtang-south'),
    );
  });
});

describe('reconcileSubscriptions', () => {
  const world = (over = {}) => ({
    rows: { profiles: { u1: profile(over.profile ?? benue) } },
    targets: over.targets ?? [pushTarget('d1')],
    topics: over.topics ?? [],
  });

  it('creates each topic and subscribes every push target to it', async () => {
    const fake = fakeAppwrite(world());
    const result = await reconcileSubscriptions({
      userId: 'u1',
      profile: fake.store.profiles.u1,
    });

    assert.deepEqual(result.topics, ['all-users', 'state-benue', 'lga-benue-obi']);
    assert.equal(result.subscribed, 3);
    assert.deepEqual([...fake.topics].sort(), ['all-users', 'lga-benue-obi', 'state-benue']);
    assert.deepEqual(
      [...fake.subscribers.values()].map((s) => s.topicId).sort(),
      ['all-users', 'lga-benue-obi', 'state-benue'],
    );
    assert.deepEqual(fake.store.profiles.u1.pushTopics, result.topics);
  });

  it('subscribes every device, and leaves the email target alone', async () => {
    const fake = fakeAppwrite(
      world({
        targets: [
          pushTarget('phone'),
          pushTarget('tablet'),
          { $id: 'mail', userId: 'u1', providerType: 'email', identifier: 'a@b.ng' },
          // Another user's device, which must not be touched.
          pushTarget('somebody-else', 'u2'),
        ],
      }),
    );
    const result = await reconcileSubscriptions({
      userId: 'u1',
      profile: fake.store.profiles.u1,
    });

    assert.equal(result.targets, 2);
    assert.equal(result.subscribed, 6);
    assert.deepEqual(
      [...new Set([...fake.subscribers.values()].map((s) => s.targetId))].sort(),
      ['phone', 'tablet'],
    );
  });

  it('skips an expired target, whose token the provider has refused', async () => {
    const fake = fakeAppwrite(
      world({ targets: [{ ...pushTarget('dead'), expired: true }, pushTarget('live')] }),
    );
    const result = await reconcileSubscriptions({
      userId: 'u1',
      profile: fake.store.profiles.u1,
    });

    assert.equal(result.targets, 1);
    assert.deepEqual(
      [...new Set([...fake.subscribers.values()].map((s) => s.targetId))],
      ['live'],
    );
  });

  it('does nothing the second time, and writes nothing', async () => {
    const fake = fakeAppwrite(world());
    await reconcileSubscriptions({ userId: 'u1', profile: fake.store.profiles.u1 });
    const writes = () =>
      fake.calls.filter((c) => c.method === 'PATCH' && c.path.includes('/profiles/rows/u1')).length;
    const after = writes();

    const again = await reconcileSubscriptions({
      userId: 'u1',
      profile: fake.store.profiles.u1,
    });

    // Every subscribe came back 409, which is the server telling us the
    // device was already in the topic.
    assert.equal(again.subscribed, 0);
    assert.equal(again.removed, 0);
    assert.equal(again.changed, false);
    assert.equal(writes(), after, 'reconciling twice wrote the profile twice');
  });

  it('moves a user: the old LGA goes, the new one arrives', async () => {
    const fake = fakeAppwrite(world());
    await reconcileSubscriptions({ userId: 'u1', profile: fake.store.profiles.u1 });

    // The admin moves them to Nasarawa.
    fake.store.profiles.u1.state = 'Nasarawa';
    const moved = await reconcileSubscriptions({
      userId: 'u1',
      profile: fake.store.profiles.u1,
    });

    assert.deepEqual(moved.topics, ['all-users', 'state-nasarawa', 'lga-nasarawa-obi']);
    assert.equal(moved.removed, 2, 'the Benue topics should have been unsubscribed');
    const live = [...fake.subscribers.values()].map((s) => s.topicId).sort();
    assert.deepEqual(live, ['all-users', 'lga-nasarawa-obi', 'state-nasarawa']);
    assert.deepEqual(fake.store.profiles.u1.pushTopics, moved.topics);
  });

  it('subscribes nothing and claims nothing for a user with no device', async () => {
    const fake = fakeAppwrite(world({ targets: [] }));
    const result = await reconcileSubscriptions({
      userId: 'u1',
      profile: fake.store.profiles.u1,
    });

    assert.deepEqual(result.topics, []);
    assert.equal(result.targets, 0);
    // No topic is created for somebody who cannot receive anything —
    // 770 empty LGA topics against an unmeasured quota is the thing
    // this avoids.
    assert.equal(fake.topics.size, 0);
    assert.ok(!fake.calls.some((c) => c.path === '/messaging/topics' && c.method === 'POST'));
  });

  it('empties the stored topics when the last device is gone', async () => {
    const fake = fakeAppwrite(
      world({ profile: { ...benue, pushTopics: ['all-users', 'state-benue'] }, targets: [] }),
    );
    const result = await reconcileSubscriptions({
      userId: 'u1',
      profile: fake.store.profiles.u1,
    });

    assert.deepEqual(result.topics, []);
    assert.equal(result.changed, true);
    assert.deepEqual(fake.store.profiles.u1.pushTopics, []);
  });

  it('reuses a topic that already exists rather than failing on the 409', async () => {
    const fake = fakeAppwrite(world({ topics: ['all-users'] }));
    const result = await reconcileSubscriptions({
      userId: 'u1',
      profile: fake.store.profiles.u1,
    });
    assert.equal(result.subscribed, 3);
  });

  it('throws on a refusal that is not a 409, rather than reporting success', async () => {
    const fake = fakeAppwrite({
      ...world(),
      fail: { 'POST /messaging/topics/state-benue/subscribers': { status: 500, body: { message: 'boom' } } },
    });
    await assert.rejects(
      () => reconcileSubscriptions({ userId: 'u1', profile: fake.store.profiles.u1 }),
      /boom|500/,
    );
    // And the profile was not told it holds subscriptions it does not.
    assert.equal(fake.store.profiles.u1.pushTopics, undefined);
  });
});

describe('the profile event that drives it', () => {
  const event = 'databases.cradi.tables.profiles.rows.u1.update';

  it('raises a topic event beside the access one', () => {
    const types = eventsFor(event, profile(benue)).map((e) => e.eventType);
    assert.deepEqual(types, ['user_access_changed', 'push_topics_changed']);
  });

  it('keys an edit that does not move the user as the same event', () => {
    // The outbox refuses a duplicate id, so the same key is how an
    // unrelated profile edit costs nothing — and how the handler's own
    // write back of `pushTopics` does not start a loop.
    const before = eventsFor(event, profile(benue))[1].key;
    const after = eventsFor(event, profile({ ...benue, phone: '08031234567', role: 'ewm' }))[1].key;
    assert.equal(before, after);
  });

  it('keys a move as a different event', () => {
    const before = eventsFor(event, profile(benue))[1].key;
    const moved = eventsFor(event, profile({ state: 'Nasarawa', lga: 'Obi' }))[1].key;
    assert.notEqual(before, moved);
  });

  it('keeps the key within an Appwrite id', () => {
    const key = eventsFor(event, profile({ state: 'Federal Capital Territory', lga: 'Abuja Municipal' }))[1].key;
    assert.ok(key.length <= MAX_ID, `${key} is ${key.length} characters`);
  });
});

describe('push_topics_changed', () => {
  const handlers = (deps) => createHandlers(deps);
  const outboxEvent = { $id: 'e1' };

  it('reconciles the user named in the payload', async () => {
    const fake = fakeAppwrite({
      rows: { profiles: { u1: profile(benue) } },
      targets: [pushTarget('d1')],
    });
    const note = await handlers({}).push_topics_changed(outboxEvent, { userId: 'u1' });

    assert.equal(note, null);
    assert.equal(fake.subscribers.size, 3);
  });

  it('says so when there is no device yet, instead of failing', async () => {
    fakeAppwrite({ rows: { profiles: { u1: profile(benue) } }, targets: [] });
    const note = await handlers({}).push_topics_changed(outboxEvent, { userId: 'u1' });
    assert.match(note, /no push targets/);
  });

  it('skips a profile that is gone', async () => {
    fakeAppwrite({ rows: { profiles: {} } });
    const note = await handlers({}).push_topics_changed(outboxEvent, { userId: 'u1' });
    assert.equal(note, 'profile not found');
  });

  it('refuses a payload with no user', async () => {
    fakeAppwrite({});
    await assert.rejects(
      () => handlers({}).push_topics_changed(outboxEvent, {}),
      /userId missing/,
    );
  });
});

describe('sync_push_subscriptions', () => {
  it('subscribes the caller’s own devices, with no parameter to forge', async () => {
    const fake = fakeAppwrite({
      rows: { profiles: { u1: profile(benue), u2: profile({ state: 'Plateau', lga: 'Jos North' }) } },
      targets: [pushTarget('d1', 'u1'), pushTarget('d2', 'u2')],
    });

    const ctx = context(
      // A userId in the params is ignored: the dispatcher reads the
      // header Appwrite sets.
      { operation: 'sync_push_subscriptions', params: { userId: 'u2' } },
      { userId: 'u1' },
    );
    await operation(ctx);

    assert.equal(ctx.captured.status, 200);
    assert.deepEqual(ctx.captured.body.topics, ['all-users', 'state-benue', 'lga-benue-obi']);
    assert.equal(ctx.captured.body.targets, 1);
    assert.deepEqual(
      [...new Set([...fake.subscribers.values()].map((s) => s.targetId))],
      ['d1'],
    );
  });

  it('is refused for a disabled account, like every other operation', async () => {
    fakeAppwrite({
      rows: { profiles: { u1: profile({ ...benue, isDisabled: true }) } },
      targets: [pushTarget('d1')],
    });
    const ctx = context({ operation: 'sync_push_subscriptions' }, { userId: 'u1' });
    await operation(ctx);
    assert.equal(ctx.captured.status, 403);
  });
});
