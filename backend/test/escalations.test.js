import { test } from 'node:test';
import assert from 'node:assert/strict';
import { MAX_ESCALATION_ATTEMPTS, failedAttempts, retryDelayMs, runEscalations } from '../src/escalations.js';
import { fakePush, fakeRepo, logger, profile } from './helpers.js';

const base = { id: 'r1', user_id: 'reporter', ward: 'Ward 1', lga: 'Ikeja', hazard_type: 'Flood', severity: 'high', status: 'pending', escalated: false };

test('pending report is escalated (status stays pending) and coordinators/staff notified once', async () => {
  const repo = fakeRepo({
    reports: [{ ...base }],
    escalations: [{ id: 'e1', report_id: 'r1', status: 'pending' }],
    profiles: [
      profile('coord', 'ldp_coordinator'),
      profile('ewr1', 'ewr'),
      profile('ewr-other-lga', 'ewr', { lga: 'Epe' }),
      profile('staff', 'project_staff', { lga: 'Epe' }),
      profile('ewv', 'ewv', { lga: 'Kano' }),
      profile('disabled', 'ewv', { is_disabled: true }),
      profile('ewm', 'ewm'),
    ],
  });
  const push = fakePush();
  const summary = await runEscalations({ repo, push, logger });
  assert.deepEqual(summary, { processed: 1, skipped: 0, failed: 0 });

  const r = repo.state.reports[0];
  assert.equal(r.status, 'pending');
  assert.equal(r.escalated, true);
  assert.equal(r.escalation_status, 'escalated');
  assert.equal(r.escalation_reason, 'Auto-escalation: Not verified within the escalation timeout');

  assert.equal(push.calls.length, 1);
  assert.deepEqual(push.calls[0].ids.sort(), ['coord', 'ewr1', 'ewv', 'staff']);
  assert.equal(push.calls[0].key, 'escalation:e1');
  assert.equal(repo.state.escalations[0].status, 'processed');

  // Second run: nothing due.
  assert.deepEqual(await runEscalations({ repo, push, logger }), { processed: 0, skipped: 0, failed: 0 });
});

test('report already verified or missing -> escalation skipped with reason', async () => {
  const repo = fakeRepo({
    reports: [{ ...base, status: 'verified' }],
    escalations: [
      { id: 'e1', report_id: 'r1', status: 'pending' },
      { id: 'e2', report_id: 'gone', status: 'pending' },
    ],
  });
  const push = fakePush();
  assert.deepEqual(await runEscalations({ repo, push, logger }), { processed: 0, skipped: 2, failed: 0 });
  assert.equal(repo.state.escalations[0].reason, 'Status: verified');
  assert.equal(repo.state.escalations[1].reason, 'Report not found');
  assert.equal(push.calls.length, 0);
});

test('push failure keeps escalation pending for retry and records the error', async () => {
  const repo = fakeRepo({
    reports: [{ ...base }],
    escalations: [{ id: 'e1', report_id: 'r1', status: 'pending' }],
    profiles: [profile('coord', 'ldp_coordinator')],
  });
  const summary = await runEscalations({ repo, push: fakePush({ failOn: 'users' }), logger });
  assert.equal(summary.failed, 1);
  assert.equal(repo.state.escalations[0].status, 'pending');
  assert.match(repo.state.escalations[0].reason, /^attempt 1: push users failed/);
});

test('failed escalation backs off (escalate_at moves forward) and gives up after the cap', async () => {
  const t0 = Date.parse('2026-01-01T00:00:00Z');
  const repo = fakeRepo({
    reports: [{ ...base }],
    escalations: [{ id: 'e1', report_id: 'r1', status: 'pending', escalate_at: '2025-12-31T23:30:00.000Z' }],
    profiles: [profile('coord', 'ldp_coordinator')],
  });
  const push = fakePush({ failOn: 'users' });
  const esc = repo.state.escalations[0];
  for (let attempt = 1; attempt < MAX_ESCALATION_ATTEMPTS; attempt++) {
    assert.equal((await runEscalations({ repo, push, logger, now: () => t0 })).failed, 1);
    assert.equal(esc.status, 'pending');
    assert.equal(failedAttempts(esc.reason), attempt);
    assert.equal(esc.escalate_at, new Date(t0 + retryDelayMs(attempt)).toISOString());
    // Not due again until the backoff elapses.
    assert.equal((await repo.dueEscalations(10, new Date(t0).toISOString())).length, 0);
    esc.escalate_at = '2025-12-31T23:30:00.000Z';
  }
  await runEscalations({ repo, push, logger, now: () => t0 });
  assert.equal(esc.status, 'skipped');
  assert.match(esc.reason, new RegExp(`^Gave up after ${MAX_ESCALATION_ATTEMPTS} attempts: push users failed`));
  assert.equal((await runEscalations({ repo, push, logger, now: () => t0 })).failed, 0);
});

test('a failing escalation does not starve newer ones', async () => {
  const repo = fakeRepo({
    reports: [{ ...base }, { ...base, id: 'r2' }],
    escalations: [
      { id: 'old', report_id: 'r1', status: 'pending', escalate_at: '2020-01-01T00:00:00.000Z' },
      { id: 'new', report_id: 'r2', status: 'pending', escalate_at: '2020-01-01T00:01:00.000Z' },
    ],
  });
  await runEscalations({ repo, push: fakePush({ failOn: 'users' }), logger, limit: 1, now: () => Date.parse('2020-01-01T00:02:00Z') });
  const [first] = await repo.dueEscalations(1, '2020-01-01T00:10:00.000Z');
  assert.equal(first.id, 'new');
});

test('failedAttempts parses the attempt prefix only', () => {
  assert.equal(failedAttempts(null), 0);
  assert.equal(failedAttempts('Status: verified'), 0);
  assert.equal(failedAttempts('attempt 3: boom'), 3);
});
