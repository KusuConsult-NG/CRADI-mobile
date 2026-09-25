import { test } from 'node:test';
import assert from 'node:assert/strict';
import { runEscalations } from '../src/escalations.js';
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
  assert.equal(r.escalation_reason, 'Auto-escalation: No verification within 30 minutes');

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
  assert.match(repo.state.escalations[0].reason, /push users failed/);
});
