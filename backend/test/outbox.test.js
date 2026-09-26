import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHandlers, processEvent, runOutboxBatch } from '../src/outbox.js';
import { fakePush, fakeRepo, logger, profile } from './helpers.js';

const report = {
  id: 'r1',
  user_id: 'reporter',
  ward: 'Ward 1',
  lga: 'Port Harcourt',
  hazard_type: 'Flood',
  severity: 'critical',
  status: 'pending',
};

function setup(data, pushOpts) {
  const repo = fakeRepo(data);
  const push = fakePush(pushOpts);
  const handlers = createHandlers({ repo, push, logger });
  return { repo, push, handlers };
}

test('report_created pushes to approved ewm peers in same ward+lga, excluding reporter', async () => {
  const { repo, push, handlers } = setup({
    reports: [report],
    profiles: [
      profile('reporter', 'ewm', { lga: 'Port Harcourt' }),
      profile('peer1', 'ewm', { lga: 'Port Harcourt' }),
      profile('peer2', 'ewm', { lga: 'Port Harcourt', is_disabled: true }),
      profile('peer3', 'ewm', { lga: 'Port Harcourt', is_approved: false }),
      profile('peer4', 'ewm', { lga: 'Port Harcourt', ward: 'Ward 2' }),
      profile('peer5', 'ewm', { lga: 'Ikeja' }),
      profile('peer6', 'ewv', { lga: 'Port Harcourt' }),
    ],
    events: [{ id: 1, event_type: 'report_created', payload: { report_id: 'r1' } }],
  });
  assert.equal(await runOutboxBatch({ repo, handlers, logger }), 1);
  assert.equal(push.calls.length, 1);
  assert.deepEqual(push.calls[0].ids, ['peer1']);
  assert.equal(push.calls[0].n.data.type, 'verification_request');
  assert.equal(push.calls[0].key, 'outbox:1:verifiers');
  assert.equal(repo.state.events[0].processed_at, 'now');
  assert.equal(repo.state.events[0].last_error, null);
});

test('report_created for a no-longer-pending report is processed without push', async () => {
  const { repo, push, handlers } = setup({
    reports: [{ ...report, status: 'verified' }],
    events: [{ id: 1, event_type: 'report_created', payload: { report_id: 'r1' } }],
  });
  await runOutboxBatch({ repo, handlers, logger });
  assert.equal(push.calls.length, 0);
  assert.equal(repo.state.events[0].processed_at, 'now');
});

test('report_status_changed -> approved notifies reporter and broadcasts to lga tag', async () => {
  const { repo, push, handlers } = setup({
    reports: [{ ...report, status: 'approved' }],
    events: [
      { id: 7, event_type: 'report_status_changed', payload: { report_id: 'r1', old_status: 'verified', new_status: 'approved' } },
    ],
  });
  await runOutboxBatch({ repo, handlers, logger });
  assert.equal(push.calls.length, 2);
  assert.deepEqual(push.calls[0].ids, ['reporter']);
  assert.equal(push.calls[0].n.data.status, 'approved');
  assert.equal(push.calls[1].kind, 'tag');
  assert.equal(push.calls[1].tagKey, 'lga');
  assert.equal(push.calls[1].tagValue, 'port_harcourt');
  assert.equal(push.calls[1].n.title, '🚨 Verified Hazard Alert');
  assert.deepEqual(push.calls[1].n.data, { type: 'validated_alert', report_id: 'r1' });
});

test('report_status_changed -> rejected omits the reason from the push, no broadcast', async () => {
  const { repo, push, handlers } = setup({
    reports: [{ ...report, status: 'rejected' }],
    events: [
      {
        id: 8,
        event_type: 'report_status_changed',
        payload: { report_id: 'r1', old_status: 'pending', new_status: 'rejected', reason: 'Duplicate report' },
      },
    ],
  });
  await runOutboxBatch({ repo, handlers, logger });
  assert.equal(push.calls.length, 1);
  assert.equal(push.calls[0].n.body, '❌ Your report was rejected — open the app for details.');
  assert.doesNotMatch(JSON.stringify(push.calls[0].n), /Duplicate/);
  assert.deepEqual(push.calls[0].n.data, { type: 'report_status', report_id: 'r1', status: 'rejected' });
});

test('report_status_changed is skipped when the report has since changed status', async () => {
  const { repo, push, handlers } = setup({
    reports: [{ ...report, status: 'rejected' }],
    events: [
      { id: 9, event_type: 'report_status_changed', payload: { report_id: 'r1', old_status: 'verified', new_status: 'approved' } },
    ],
  });
  await runOutboxBatch({ repo, handlers, logger });
  assert.equal(push.calls.length, 0);
  assert.equal(repo.state.events[0].processed_at, 'now');
  assert.match(repo.state.events[0].last_error, /stale: report now rejected/);
});

test('alert_created: All -> all subscribers; LGA -> tag filter', async () => {
  const { repo, push, handlers } = setup({
    alerts: [
      { id: 'a1', title: 'Flood watch', message: 'Stay alert', target_lga: 'All', is_active: true },
      { id: 'a2', title: 'Storm', message: 'Take cover', target_lga: 'Obio/Akpor', is_active: true },
    ],
    events: [
      { id: 1, event_type: 'alert_created', payload: { alert_id: 'a1' } },
      { id: 2, event_type: 'alert_created', payload: { alert_id: 'a2' } },
    ],
  });
  await runOutboxBatch({ repo, handlers, logger });
  assert.equal(push.calls[0].kind, 'all');
  assert.deepEqual(push.calls[0].n, { title: 'Flood watch', body: 'Stay alert', data: { type: 'admin_alert', alert_id: 'a1', severity: null } });
  assert.equal(push.calls[1].kind, 'tag');
  assert.equal(push.calls[1].tagValue, 'obio_akpor');
});

test('unknown event type is marked processed with "unknown event"', async () => {
  const { repo, handlers } = setup({ events: [{ id: 3, event_type: 'mystery', payload: {} }] });
  const outcome = await processEvent(repo.state.events[0], { repo, handlers, logger });
  assert.equal(outcome, 'unknown');
  assert.equal(repo.state.events[0].processed_at, 'now');
  assert.equal(repo.state.events[0].last_error, 'unknown event');
});

test('invalid payload is marked processed (permanent) with a note', async () => {
  const { repo, handlers } = setup({ events: [{ id: 4, event_type: 'report_created', payload: {} }] });
  await runOutboxBatch({ repo, handlers, logger });
  assert.equal(repo.state.events[0].processed_at, 'now');
  assert.match(repo.state.events[0].last_error, /invalid payload/);
});

test('push failure leaves event unprocessed with last_error (retried by claim backoff)', async () => {
  const { repo, handlers } = setup(
    { reports: [report], profiles: [profile('peer1', 'ewm', { lga: 'Port Harcourt' })], events: [{ id: 5, event_type: 'report_created', payload: { report_id: 'r1' } }] },
    { failOn: 'users' },
  );
  await runOutboxBatch({ repo, handlers, logger });
  assert.equal(repo.state.events[0].processed_at, undefined);
  assert.match(repo.state.events[0].last_error, /push users failed/);
});

test('handler table does not dispatch inherited properties', async () => {
  const { repo, handlers } = setup({ events: [{ id: 6, event_type: 'toString', payload: {} }] });
  assert.equal(await processEvent(repo.state.events[0], { repo, handlers, logger }), 'unknown');
});
