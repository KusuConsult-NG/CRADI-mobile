import { test } from 'node:test';
import assert from 'node:assert/strict';
import { runEscalations } from '../src/escalations.js';
import { createHandlers, runOutboxBatch } from '../src/outbox.js';
import { DISPUTE_REASON } from '../src/notifications.js';
import { fakePush, fakeRepo, logger, profile } from './helpers.js';

const base = { id: 'r1', user_id: 'reporter', ward: 'Ward 1', lga: 'Ikeja', hazard_type: 'Flood', severity: 'high', status: 'pending', escalated: false };
const staff = [
  profile('coord', 'ldp_coordinator'),
  profile('ewr1', 'ewr'),
  profile('ewr-other-lga', 'ewr', { lga: 'Epe' }),
  profile('staff', 'project_staff', { lga: 'Epe' }),
  profile('ewv', 'ewv', { lga: 'Kano' }),
  profile('ewm', 'ewm'),
];
const disputed = (id, reportId = 'r1') => ({ id, event_type: 'report_disputed', payload: { report_id: reportId, verification_id: `v${id}` } });

test('report_disputed escalates a pending report, finishes its scheduled escalation and notifies coordinators/staff', async () => {
  const repo = fakeRepo({
    reports: [{ ...base }],
    profiles: staff,
    escalations: [{ id: 'e1', report_id: 'r1', status: 'pending', escalate_at: '2000-01-01T00:00:00.000Z' }],
    events: [disputed(1)],
  });
  const push = fakePush();
  await runOutboxBatch({ repo, handlers: createHandlers({ repo, push, logger }), logger });

  const r = repo.state.reports[0];
  assert.equal(r.status, 'pending');
  assert.equal(r.escalated, true);
  assert.equal(r.escalation_status, 'escalated');
  assert.equal(r.escalation_reason, 'Disputed by a peer monitor');
  assert.equal(repo.state.escalations[0].status, 'processed');
  assert.equal(repo.state.escalations[0].reason, DISPUTE_REASON);

  assert.equal(push.calls.length, 1);
  assert.deepEqual(push.calls[0].ids.sort(), ['coord', 'ewr1', 'ewv', 'staff']);
  assert.equal(push.calls[0].key, 'outbox:1:dispute');
  assert.equal(push.calls[0].n.data.type, 'escalation');
  assert.equal(push.calls[0].n.data.report_id, 'r1');
  assert.equal(repo.state.events[0].processed_at, 'now');
  assert.equal(repo.state.events[0].last_error, null);

  // The timeout cron has nothing left to do for this report.
  assert.deepEqual(await runEscalations({ repo, push, logger }), { processed: 0, skipped: 0, failed: 0 });
  assert.equal(push.calls.length, 1);
});

test('report_disputed: not pending, already escalated, missing -> processed with a note, no push', async () => {
  const repo = fakeRepo({
    reports: [
      { ...base },
      { ...base, id: 'r2', status: 'verified' },
      { ...base, id: 'r3', escalated: true, escalation_reason: 'Auto-escalation: Not verified within the escalation timeout' },
    ],
    profiles: staff,
    events: [disputed(1, 'r2'), disputed(2, 'r3'), disputed(3, 'gone'), disputed(4, 'r1'), disputed(5, 'r1')],
  });
  const push = fakePush();
  await runOutboxBatch({ repo, handlers: createHandlers({ repo, push, logger }), logger });
  const notes = repo.state.events.map((e) => e.last_error);
  assert.deepEqual(notes, ['report no longer pending (verified)', 'report already escalated', 'report not found', null, 'report already escalated']);
  assert.equal(push.calls.length, 1); // only the first dispute of r1
});

test('report_disputed: push failure is retried and the retry still notifies', async () => {
  const repo = fakeRepo({ reports: [{ ...base }], profiles: staff, events: [disputed(9)] });
  const handlers = createHandlers({ repo, push: fakePush({ failOn: 'users' }), logger });
  await runOutboxBatch({ repo, handlers, logger });
  assert.equal(repo.state.events[0].processed_at, undefined);
  assert.equal(repo.state.reports[0].escalated, true);

  const push = fakePush();
  await runOutboxBatch({ repo, handlers: createHandlers({ repo, push, logger }), logger });
  assert.equal(repo.state.events[0].processed_at, 'now');
  assert.equal(push.calls.length, 1);
  assert.equal(push.calls[0].key, 'outbox:9:dispute');
});

test('report_disputed without report_id is a permanent failure', async () => {
  const repo = fakeRepo({ events: [{ id: 1, event_type: 'report_disputed', payload: {} }] });
  await runOutboxBatch({ repo, handlers: createHandlers({ repo, push: fakePush(), logger }), logger });
  assert.match(repo.state.events[0].last_error, /invalid payload/);
  assert.equal(repo.state.events[0].processed_at, 'now');
});

test('timeout cron skips a report already escalated by a dispute', async () => {
  const repo = fakeRepo({
    reports: [{ ...base, escalated: true, escalation_reason: DISPUTE_REASON }],
    escalations: [{ id: 'e1', report_id: 'r1', status: 'pending' }],
    profiles: staff,
  });
  const push = fakePush();
  assert.deepEqual(await runEscalations({ repo, push, logger }), { processed: 0, skipped: 1, failed: 0 });
  assert.equal(repo.state.escalations[0].reason, `Already escalated: ${DISPUTE_REASON}`);
  assert.equal(push.calls.length, 0);
});
