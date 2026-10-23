/**
 * Pins the two ACL sets apart, with the reasoning.
 *
 * `copy-tables.mjs` stamps `migrate.mjs`'s permissions on `profiles`, `reports`
 * and `verifications` — the ones written to reproduce the Postgres RLS — while
 * the `client` Function stamps `policy.js`'s `RULES` on a row created after the
 * cutover. Those are not the same set, so a migrated row is readable by more
 * roles than a new one.
 *
 * That is a real inconsistency and somebody has to decide about it. This exists
 * so the decision is forced rather than drifted into: the difference is written
 * down here, and changing either side fails until it is written down again.
 *
 * Narrowing access during a cutover is not the migration's call, which is why it
 * is this way round and not the other.
 */
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { RULES, VALIDATED_STATUSES } from '../../../functions/cradi/src/lib/policy.js';
import { lgaLabel } from '../../../functions/cradi/src/lib/appwrite.js';
import {
  profilePermissions,
  reportPermissions,
  verificationPermissions,
} from './migrate.mjs';
import { TABLES, coerce } from './copy-tables.mjs';

const ROW = {
  id: 'u1',
  user_id: 'u1',
  verifier_id: 'v1',
  state: 'Benue',
  lga: 'Makurdi',
  ward: 'North Bank I',
};

/** Just the labels, which is where the two sets differ. */
const labels = (acl) =>
  acl
    .map((p) => /^read\("label:([^"]+)"\)$/.exec(p)?.[1])
    .filter(Boolean)
    .sort();

describe('the migration ACL against the one the Function stamps', () => {
  test('profiles: the migration grants the roles profiles_select did', () => {
    const migrated = labels(profilePermissions(ROW));
    const created = labels(RULES.profiles.acl({ documentId: 'u1' }));
    assert.deepEqual(migrated, [
      'admin', 'ewr', 'ewv', 'ldpCoordinator', 'projectStaff',
    ]);
    assert.deepEqual(created, ['admin', 'techSupport']);
    // Plus the ward team, which `RULES.profiles` has no equivalent of: that is
    // how an `ewm` read their own ward's profiles.
    assert.ok(profilePermissions(ROW).some((p) => p.startsWith('read("team:')));
    assert.ok(!RULES.profiles.acl({ documentId: 'u1' }).some((p) => p.includes('team:')));
  });

  test('reports: the two sets now differ by scope, not by oversight', () => {
    // This test used to record the opposite: `created` was
    // `['admin', 'ewr', 'ewv']`, and the comment here said a report that
    // `ldpCoordinator` and `projectStaff` could decide but not read looked
    // "like an oversight rather than a decision". It was one, and it is
    // fixed — `reportAcl` now gives Project Staff every LGA by label and an
    // LDP Coordinator their own by a per-LGA label, per matrix 4.1.
    //
    // So the difference that remains is deliberate on both sides:
    //
    //   the migration  grants every staff role every report, because
    //                  narrowing access during a cutover is not its call
    //   the Function   grants the matrix's scopes, and `ewr` only once a
    //                  report is validated
    //
    // What closes it is `infra/appwrite/fix-report-permissions.mjs`, which
    // re-derives the stored ACL of every existing row from `reportAcl` —
    // including the rows this migration wrote. Until that has run against
    // the project, a migrated report is readable by more roles than a new
    // one, which is what this file exists to keep visible.
    const migrated = labels(reportPermissions(ROW));
    const created = labels(RULES.reports.acl({ data: ROW }));
    assert.deepEqual(migrated, [
      'admin', 'ewr', 'ewv', 'ldpCoordinator', 'projectStaff', 'techSupport',
    ]);
    assert.deepEqual(created, [
      'admin', 'ewv', lgaLabel(ROW.state, ROW.lga), 'projectStaff',
    ].sort());

    // The roles that may decide a report can now read it.
    assert.ok(created.includes('projectStaff'));
    assert.ok(created.includes(lgaLabel(ROW.state, ROW.lga)));

    // `techSupport` is the one role the migration grants and the Function
    // does not. Deliberate: it is absent from matrix 4.1 entirely, and
    // `isAdmin` already covers what it needs to *write*.
    assert.ok(migrated.includes('techSupport'));
    assert.ok(!created.includes('techSupport'));
  });

  test('reports: ewr and media wait for the report to be validated', () => {
    // The scope the migration cannot express at all, because an Appwrite
    // ACL is stored per row at creation and `status` changes afterwards.
    // `write.js` rewrites the permissions when it does.
    const pending = labels(RULES.reports.acl({ data: { ...ROW, status: 'pending' } }));
    assert.ok(!pending.includes('ewr'), pending.join());
    assert.ok(!pending.includes('media'), pending.join());

    for (const status of VALIDATED_STATUSES) {
      const validated = labels(RULES.reports.acl({ data: { ...ROW, status } }));
      assert.ok(validated.includes('ewr'), `${status}: ${validated.join()}`);
      assert.ok(validated.includes('media'), `${status}: ${validated.join()}`);
    }

    // And the migration grants `ewr` regardless, which is the other half of
    // why the reconciliation script has to run: it takes reach away as well
    // as granting it.
    assert.ok(labels(reportPermissions(ROW)).includes('ewr'));
  });

  test('verifications: the Function does not grant the verifier their own vote', () => {
    const migrated = verificationPermissions(ROW, ROW);
    const created = RULES.verifications.acl({ data: ROW });
    assert.ok(
      migrated.includes('read("user:v1")'),
      'the verifier could read their own vote under verifications_select',
    );
    assert.ok(!created.some((p) => p.startsWith('read("user:')));
  });

  test('every ACL the migration writes names a label Appwrite knows', () => {
    // An ACL naming a label nobody can hold is accepted in silence and grants
    // nobody anything — the quietest possible migration bug.
    const known = new Set([
      'ewm', 'ewv', 'ewr', 'ldpCoordinator', 'projectStaff', 'admin',
      'techSupport', 'approved',
    ]);
    for (const acl of [
      profilePermissions(ROW),
      reportPermissions(ROW),
      verificationPermissions(ROW, ROW),
    ]) {
      for (const label of labels(acl)) assert.ok(known.has(label), label);
    }
  });
});

describe('the table list', () => {
  test('profiles and reports are read before what depends on them', () => {
    const order = TABLES.map((t) => t.table);
    assert.ok(order.indexOf('profiles') < order.indexOf('reports'), order.join(','));
    assert.ok(order.indexOf('reports') < order.indexOf('verifications'), order.join(','));
  });

  test('every collection a user can read is in it', () => {
    // The gate reconciles 15 tables; these are the ones with rows to copy.
    for (const t of [
      'profiles', 'reports', 'verifications', 'alerts', 'authorities',
      'app_settings', 'scheduled_escalations', 'knowledge_base', 'news_links',
    ]) {
      assert.ok(TABLES.some((x) => x.table === t), `${t} is not copied`);
    }
  });
});

describe('coerce', () => {
  test('a timestamptz becomes ISO-8601, whether Date or string', () => {
    const when = new Date('2026-10-08T05:00:00.000Z');
    assert.equal(coerce(when, { type: 'datetime' }), '2026-10-08T05:00:00.000Z');
    assert.equal(
      coerce('2026-10-08T05:00:00Z', { type: 'datetime' }),
      '2026-10-08T05:00:00.000Z',
    );
  });

  test('jsonb becomes the string the plan stores', () => {
    assert.equal(coerce({ a: 1 }, { type: 'string', size: 64 }), '{"a":1}');
    assert.equal(coerce(3, { type: 'string', size: 64 }), '3');
  });

  test('a text[] becomes a string[]', () => {
    assert.deepEqual(
      coerce(['a', 'b'], { type: 'string', size: 8, array: true }),
      ['a', 'b'],
    );
  });

  test('null means leave the column unset', () => {
    assert.equal(coerce(null, { type: 'string', size: 8 }), null);
    assert.equal(coerce(undefined, { type: 'boolean' }), null);
  });

  test('a value too long for its column is refused, not truncated', () => {
    // Silently truncating migrated data is worse than refusing to write it.
    assert.throws(() => coerce('x'.repeat(10), { type: 'string', size: 4 }), /holds 4/);
  });
});
