import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  alertTarget,
  escalationQueries,
  adminAlertNotification,
  clampText,
  disputeEscalationNotification,
  escalationNotification,
  reporterStatusMessage,
  reporterStatusNotification,
  selectRecipientIds,
  shouldBroadcastApproval,
  validatedAlertNotification,
  verificationRequestNotification,
  verifierQuery,
} from '../src/notifications.js';

const report = { id: 'r1', user_id: 'u-reporter', ward: 'Ward 1', lga: 'Ikeja', hazard_type: 'Flood', severity: 'high' };

test('verifierQuery targets ewm in the same ward and lga, excluding the reporter', () => {
  assert.deepEqual(verifierQuery(report), {
    roles: ['ewm'],
    lga: 'Ikeja',
    ward: 'Ward 1',
    excludeId: 'u-reporter',
    limit: 50,
  });
  assert.equal(verifierQuery({ ...report, ward: '' }), null);
});

test('escalationQueries: lga-scoped coordinators/ewr + global staff/ewv', () => {
  const qs = escalationQueries(report);
  assert.deepEqual(qs[0], { roles: ['ldp_coordinator', 'ewr'], lga: 'Ikeja', excludeId: 'u-reporter', limit: 50 });
  assert.deepEqual(qs[1], { roles: ['project_staff', 'ewv'], excludeId: 'u-reporter', limit: 50 });
  assert.equal(escalationQueries({ ...report, lga: '' }).length, 1);
});

test('selectRecipientIds dedupes, drops excluded, unapproved and disabled', () => {
  const ids = selectRecipientIds(
    [
      [{ id: 'a' }, { id: 'b' }, { id: 'u-reporter' }],
      [{ id: 'b' }, { id: 'c', is_disabled: true }, { id: 'd', is_approved: false }, { id: 'e' }, null],
    ],
    { excludeId: 'u-reporter' },
  );
  assert.deepEqual(ids, ['a', 'b', 'e']);
});

test('reporter status messages', () => {
  assert.match(reporterStatusMessage('verified'), /verified/);
  assert.match(reporterStatusMessage('approved'), /approved/);
  assert.equal(reporterStatusMessage('rejected'), '❌ Your report was rejected — open the app for details.');
  assert.match(reporterStatusMessage('pending'), /awaiting/);
});

test('broadcast only on transition into approved', () => {
  assert.equal(shouldBroadcastApproval('verified', 'approved'), true);
  assert.equal(shouldBroadcastApproval('pending', 'approved'), true);
  assert.equal(shouldBroadcastApproval('approved', 'approved'), false);
  assert.equal(shouldBroadcastApproval('approved', 'rejected'), false);
  assert.equal(shouldBroadcastApproval('pending', 'verified'), false);
});

test('notification texts', () => {
  const v = verificationRequestNotification(report);
  assert.equal(v.title, '📋 Verification Request');
  assert.equal(v.body, 'A report in your area needs verification. Open the app for details.');
  assert.deepEqual(v.data, { type: 'verification_request', report_id: 'r1' });

  const a = validatedAlertNotification(report);
  assert.equal(a.title, '🚨 Verified Hazard Alert');
  assert.deepEqual(a.data, { type: 'validated_alert', report_id: 'r1' });
});

test('report pushes carry no location names, hazard text, description or reasons', () => {
  const sensitive = {
    ...report,
    ward: 'Secret Ward',
    lga: 'Secret LGA',
    hazard_type: 'Other: armed men at Mr X house',
    description: 'private details',
    rejection_reason: 'reporter lied',
  };
  const all = [
    verificationRequestNotification(sensitive),
    reporterStatusNotification(sensitive, 'rejected', 'reporter lied'),
    reporterStatusNotification(sensitive, 'weird<status>'),
    validatedAlertNotification(sensitive),
    escalationNotification(sensitive),
    disputeEscalationNotification(sensitive),
  ];
  for (const n of all) {
    const text = JSON.stringify(n);
    for (const secret of ['Secret', 'armed', 'private', 'lied', 'Other', 'weird']) {
      assert.doesNotMatch(text, new RegExp(secret), `${n.data.type} leaks ${secret}`);
    }
    assert.equal(n.data.report_id, 'r1');
  }
});

test('admin alerts are sent but normalised and capped', () => {
  const n = adminAlertNotification({
    id: 'a1',
    title: `  Flood\n\twarning ${'x'.repeat(200)}`,
    message: 'm'.repeat(1000),
    severity: 'critical',
  });
  assert.ok(n.title.length <= 80);
  assert.ok(n.title.startsWith('Flood warning x'));
  assert.ok(n.title.endsWith('…'));
  assert.equal(n.body.length, 240);
  assert.deepEqual(n.data, { type: 'admin_alert', alert_id: 'a1', severity: 'critical' });
  assert.equal(adminAlertNotification({ id: 'a2', title: 'T', message: '', severity: 'bogus' }).body, 'T');
  assert.equal(adminAlertNotification({ id: 'a2', title: 'T', severity: 'bogus' }).data.severity, null);
  assert.equal(clampText('abc', 5), 'abc');
});

test('alertTarget: All -> everyone, otherwise sanitised lga tag', () => {
  assert.deepEqual(alertTarget({ target_lga: 'All' }), { all: true });
  assert.deepEqual(alertTarget({ target_lga: 'all' }), { all: true });
  assert.deepEqual(alertTarget({ target_lga: '' }), { all: true });
  assert.deepEqual(alertTarget({ target_lga: 'Port Harcourt' }), { all: false, tags: { lga: 'port_harcourt' } });
  assert.deepEqual(alertTarget({ target_lga: 'Port Harcourt', target_state: null }), { all: false, tags: { lga: 'port_harcourt' } });
  assert.deepEqual(alertTarget({ target_lga: 'All', target_state: '  ' }), { all: true });
});

test('alertTarget: target_state requires both the lga and the state tag', () => {
  assert.deepEqual(alertTarget({ target_lga: 'Obi', target_state: 'Benue' }), {
    all: false,
    tags: { lga: 'obi', state: 'benue' },
  });
  assert.deepEqual(alertTarget({ target_lga: 'Obi', target_state: 'Nasarawa' }), {
    all: false,
    tags: { lga: 'obi', state: 'nasarawa' },
  });
  // State-wide alert: every LGA in the state.
  assert.deepEqual(alertTarget({ target_lga: 'All', target_state: 'Plateau' }), { all: false, tags: { state: 'plateau' } });
  assert.deepEqual(alertTarget({ target_lga: 'Jos North', target_state: 'Cross River' }), {
    all: false,
    tags: { lga: 'jos_north', state: 'cross_river' },
  });
});
