import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadConfig } from '../src/config.js';
import { startLoop } from '../src/loop.js';
import { createHandlers, runOutboxBatch } from '../src/outbox.js';
import { createRepo } from '../src/repo.js';
import { fakePush, fakeRepo, logger } from './helpers.js';

/** supabase-js stand-in: records each query's builder calls; resolves to `result(calls)`. */
function recordingSupabase(result = () => ({ data: [], error: null })) {
  const queries = [];
  return {
    queries,
    from(table) {
      const calls = [['from', table]];
      queries.push(calls);
      const builder = new Proxy(
        {},
        {
          get(_, prop) {
            if (prop === 'then') {
              return (resolve, reject) => Promise.resolve(result(calls)).then(resolve, reject);
            }
            return (...args) => {
              calls.push([prop, ...args]);
              return builder;
            };
          },
        },
      );
      return builder;
    },
  };
}

test('repo.findAuthorities: with a state, that state or NULL; without one, only NULL coverage_state', async () => {
  const supabase = recordingSupabase();
  const repo = createRepo(supabase);
  await repo.findAuthorities('Obi', 'Benue', 20);
  await repo.findAuthorities('Obi', '  ', 20);
  await repo.findAuthorities('Obi', undefined, 20);
  const [withState, blank, missing] = supabase.queries;
  assert.deepEqual(withState.find((c) => c[0] === 'or'), ['or', 'coverage_state.eq."Benue",coverage_state.is.null']);
  assert.equal(withState.some((c) => c[0] === 'is'), false);
  for (const q of [blank, missing]) {
    assert.deepEqual(q.find((c) => c[0] === 'is'), ['is', 'coverage_state', null]);
    assert.equal(q.some((c) => c[0] === 'or'), false);
  }
});

test('repo.claimSmsDelivery: insert-or-ignore on (report_id, phone); false on conflict', async () => {
  let rows = [{ id: 1 }];
  const supabase = recordingSupabase(() => ({ data: rows, error: null }));
  const repo = createRepo(supabase);
  assert.equal(await repo.claimSmsDelivery({ reportId: 'r1', phone: '+2348030000001', lga: 'ikeja', state: 'lagos' }), true);
  const upsert = supabase.queries[0].find((c) => c[0] === 'upsert');
  assert.deepEqual(upsert, [
    'upsert',
    { report_id: 'r1', phone: '+2348030000001', lga: 'ikeja', state: 'lagos', status: 'claimed' },
    { onConflict: 'report_id,phone', ignoreDuplicates: true },
  ]);
  rows = [];
  assert.equal(await repo.claimSmsDelivery({ reportId: 'r1', phone: '+2348030000001', lga: 'ikeja', state: 'lagos' }), false);
});

test('repo.countSmsDeliveries: same area since the day start, rejected rows excluded', async () => {
  const supabase = recordingSupabase(() => ({ count: 4, error: null }));
  const repo = createRepo(supabase);
  assert.equal(await repo.countSmsDeliveries({ lga: 'ikeja', state: '', since: '2026-09-25T23:00:00.000Z' }), 4);
  const calls = supabase.queries[0];
  assert.deepEqual(calls[0], ['from', 'sms_deliveries']);
  assert.deepEqual(calls.filter((c) => ['eq', 'neq', 'gte'].includes(c[0])), [
    ['eq', 'lga', 'ikeja'],
    ['eq', 'state', ''],
    ['neq', 'status', 'rejected'],
    ['gte', 'created_at', '2026-09-25T23:00:00.000Z'],
  ]);
});

test('config: ONESIGNAL_ANDROID_CHANNEL_ID must be a UUID when set', () => {
  const ok = loadConfig({ ONESIGNAL_ANDROID_CHANNEL_ID: '3f2504e0-4f89-41d3-9a0c-0305e82c3301' });
  assert.equal(ok.config.oneSignalAndroidChannelId, '3f2504e0-4f89-41d3-9a0c-0305e82c3301');
  assert.deepEqual(ok.warnings, []);

  const bad = loadConfig({ ONESIGNAL_ANDROID_CHANNEL_ID: 'my-channel' });
  assert.equal(bad.config.oneSignalAndroidChannelId, undefined);
  assert.deepEqual(bad.warnings.map((w) => w.event), ['config.onesignal_channel_invalid']);

  assert.deepEqual(loadConfig({}).warnings, []);
});

test('runOutboxBatch stops between events once shouldStop() is true', async () => {
  const repo = fakeRepo({
    events: [1, 2, 3].map((id) => ({ id, event_type: 'noop', payload: {} })),
  });
  let stop = false;
  const handlers = {
    async noop() {
      stop = true; // shutdown requested while the first event runs
      return null;
    },
  };
  const claimed = await runOutboxBatch({ repo, handlers, logger, shouldStop: () => stop });
  assert.equal(claimed, 3);
  assert.deepEqual(repo.state.events.map((e) => e.processed_at ?? null), ['now', null, null]);
});

test('startLoop gives the task an isStopped() flag that flips on stop()', async () => {
  let release;
  const seen = [];
  const loop = startLoop(
    'test',
    async ({ isStopped }) => {
      seen.push(isStopped());
      await new Promise((r) => (release = r));
      seen.push(isStopped());
      return true;
    },
    60_000,
    { logger },
  );
  await new Promise((r) => setTimeout(r, 5));
  const stopping = loop.stop();
  release();
  await stopping;
  assert.deepEqual(seen, [false, true]);
});

test('outbox: report_status_changed collects every failure into one retryable error', async () => {
  const repo = fakeRepo({
    reports: [{ id: 'r1', user_id: 'u1', lga: 'Ikeja', ward: 'W', hazard_type: 'Flood', status: 'approved' }],
    events: [{ id: 1, event_type: 'report_status_changed', payload: { report_id: 'r1', old_status: 'verified', new_status: 'approved' } }],
  });
  const authoritySms = {
    calls: 0,
    async notifyApproved() {
      this.calls++;
      throw new Error('sms down');
    },
  };
  const handlers = createHandlers({ repo, push: fakePush({ failOn: 'users' }), authoritySms, logger });
  await runOutboxBatch({ repo, handlers, logger });
  assert.equal(authoritySms.calls, 1);
  const [event] = repo.state.events;
  assert.equal(event.processed_at, undefined);
  assert.match(event.last_error, /reporter push: push users failed; authority sms: sms down/);
});
