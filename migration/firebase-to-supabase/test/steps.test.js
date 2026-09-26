import { test } from 'node:test';
import assert from 'node:assert/strict';

import { VERIFICATIONS_UPSERT, existingReportResolver, reactivateAlerts } from '../src/steps.js';
import { transformAlert, transformVerificationOverride, transformVerification } from '../src/transform.js';

const R1 = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const R2 = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const ALICE = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

test('verifications upsert updates on conflict (re-runs apply changes)', () => {
  assert.equal(VERIFICATIONS_UPSERT.onConflict, 'report_id,verifier_id');
  assert.ok(!VERIFICATIONS_UPSERT.ignoreDuplicates);
});

test('references to a report whose write failed resolve to null', () => {
  const state = { r1: R1, r2: R2 }; // both have ids in the state file…
  const inDb = new Set([R1]); // …but only r1 was written
  const ctx = {
    now: '2026-09-25T00:00:00.000Z', url: (u) => u, user: (u) => (u === 'alice' ? ALICE : null),
    report: existingReportResolver((id) => state[id] ?? null, inDb),
  };
  assert.equal(ctx.report('r1'), R1);
  assert.equal(ctx.report('r2'), null);
  assert.equal(ctx.report('nope'), null);

  // Alerts keep the row, without the report link.
  const alert = transformAlert('a1', { title: 'Flood', reportId: 'r2' }, ctx);
  assert.equal(alert.skip, null);
  assert.equal(alert.row.report_id, null);
  assert.ok(alert.warnings.some((w) => /report r2 not migrated; report_id set to null/.test(w)));
  assert.equal(transformAlert('a2', { title: 'Flood', reportId: 'r1' }, ctx).row.report_id, R1);

  // Overrides and verifications need the report (report_id is not null).
  assert.match(transformVerificationOverride('o1', { reportId: 'r2', validatorId: 'alice', action: 'approved' }, ctx).skip, /report r2/);
  assert.match(transformVerification('v1', { reportId: 'r2', verifierId: 'alice' }, ctx).skip, /report r2/);

  // Dry run (no id set): unchanged resolver.
  const resolve = (id) => id;
  assert.equal(existingReportResolver(resolve, null), resolve);
});

/** Fake client: alerts.update().in() fails for any id batch containing a "bad" id. */
function fakeAlerts(bad, { throws = false } = {}) {
  const active = new Set();
  const calls = [];
  return {
    active,
    calls,
    from(table) {
      assert.equal(table, 'alerts');
      return {
        update(patch) {
          assert.deepEqual(patch, { is_active: true });
          return {
            async in(col, ids) {
              calls.push(ids);
              if (ids.some((id) => bad.has(id))) {
                if (throws) throw new Error('network down');
                return { data: null, error: { message: 'permission denied' } };
              }
              ids.forEach((id) => active.add(id));
              return { data: null, error: null };
            },
          };
        },
      };
    },
  };
}

test('reactivateAlerts warns per failing alert and carries on', async () => {
  const entries = [
    { sourceId: 'fa1', row: { id: 'a1', is_active: true } },
    { sourceId: 'fa2', row: { id: 'a2', is_active: true } },
    { sourceId: 'fa3', row: { id: 'a3', is_active: false } },
    { sourceId: 'fa4', row: { id: 'a4', is_active: true } },
  ];
  const sb = fakeAlerts(new Set(['a2']));
  const warnings = [];
  const done = await reactivateAlerts(sb, entries, (id, reason) => warnings.push([id, reason]));
  assert.equal(done, 2);
  assert.deepEqual([...sb.active].sort(), ['a1', 'a4']);
  assert.deepEqual(warnings, [['fa2', 're-activation failed: permission denied; alert left inactive']]);
  assert.deepEqual(sb.calls[0], ['a1', 'a2', 'a4'], 'inactive alerts are not touched');

  const thrown = [];
  assert.equal(await reactivateAlerts(fakeAlerts(new Set(['a1']), { throws: true }), entries, (id, r) => thrown.push(id)), 2);
  assert.deepEqual(thrown, ['fa1']);
});
