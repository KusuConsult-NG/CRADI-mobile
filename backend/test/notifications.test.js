import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  alertTarget,
  escalationQueries,
  reporterStatusMessage,
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
  assert.equal(reporterStatusMessage('rejected', 'Duplicate'), '❌ Your report was not validated. Reason: Duplicate');
  assert.equal(reporterStatusMessage('rejected'), '❌ Your report was not validated.');
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
  assert.equal(v.body, 'A hazard report in Ward 1, Ikeja needs your verification.');
  assert.deepEqual({ type: v.data.type, report_id: v.data.report_id }, { type: 'verification_request', report_id: 'r1' });

  const a = validatedAlertNotification(report);
  assert.equal(a.title, '🚨 HIGH Alert: Flood');
  assert.equal(a.data.type, 'validated_alert');
});

test('alertTarget: All -> everyone, otherwise sanitised lga tag', () => {
  assert.deepEqual(alertTarget({ target_lga: 'All' }), { all: true });
  assert.deepEqual(alertTarget({ target_lga: 'all' }), { all: true });
  assert.deepEqual(alertTarget({ target_lga: '' }), { all: true });
  assert.deepEqual(alertTarget({ target_lga: 'Port Harcourt' }), { all: false, tagKey: 'lga', tagValue: 'port_harcourt' });
});
