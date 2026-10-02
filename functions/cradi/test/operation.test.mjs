import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import operation from '../src/operation.js';
import { context, fakeAppwrite, profile } from './helpers.mjs';

const reopen = { operation: 'reopen_report', params: { p_report_id: 'r1' } };

const world = (role) => ({
  rows: {
    profiles: { u1: profile({ role }) },
    reports: {
      r1: { $id: 'r1', status: 'approved', escalated: true, verificationCount: 3 },
    },
    verifications: {
      v1: { $id: 'v1', reportId: 'r1' },
      v2: { $id: 'v2', reportId: 'r1' },
    },
  },
});

const call = async (body, userId = 'u1') => {
  const ctx = context(body, { userId });
  await operation(ctx);
  return ctx.captured;
};

describe('reopen_report', () => {
  it('clears the votes and sets the report back to pending', async () => {
    const fake = fakeAppwrite(world('ewr'));
    const out = await call(reopen);

    assert.equal(out.status, 200);
    assert.deepEqual(Object.keys(fake.store.verifications), []);
    assert.equal(fake.store.reports.r1.status, 'pending');
    assert.equal(fake.store.reports.r1.verificationCount, 0);
    assert.equal(fake.store.reports.r1.escalated, false);
    assert.equal(fake.store.reports.r1.reopenedBy, 'u1');
  });

  it('clears the votes before reopening, not after', async () => {
    // Appwrite has no transaction. Interrupted this way the report is
    // still closed with some votes cleared, which running it again
    // fixes. The other order leaves a reopened report carrying stale
    // votes, and it re-escalates immediately on a count that is no
    // longer true.
    const fake = fakeAppwrite(world('ewr'));
    await call(reopen);

    const lastDelete = fake.calls.map((c) => c.method).lastIndexOf('DELETE');
    const patch = fake.calls.findIndex(
      (c) => c.method === 'PATCH' && c.path.includes('/tables/reports/rows/r1'),
    );
    assert.ok(lastDelete >= 0 && lastDelete < patch);
  });

  it('is refused for a role that may not reopen', async () => {
    const fake = fakeAppwrite(world('ewm'));
    const out = await call(reopen);
    assert.equal(out.status, 403);
    // And nothing was touched on the way to the refusal.
    assert.equal(Object.keys(fake.store.verifications).length, 2);
    assert.equal(fake.store.reports.r1.status, 'approved');
  });

  it('is allowed for an admin', async () => {
    fakeAppwrite(world('admin'));
    assert.equal((await call(reopen)).status, 200);
  });

  it('is refused for a disabled reviewer', async () => {
    fakeAppwrite({
      rows: {
        profiles: { u1: profile({ role: 'ewr', isDisabled: true }) },
        reports: { r1: { $id: 'r1', status: 'approved' } },
      },
    });
    const out = await call(reopen);
    assert.equal(out.status, 403);
  });

  it('refuses a caller with no session', async () => {
    fakeAppwrite(world('ewr'));
    const out = await call(reopen, null);
    assert.equal(out.status, 401);
  });

  it('answers not-found for a report that is gone', async () => {
    fakeAppwrite({ rows: { profiles: { u1: profile({ role: 'ewr' }) } } });
    const out = await call(reopen);
    assert.equal(out.status, 404);
  });

  it('refuses a missing report id rather than reopening nothing', async () => {
    fakeAppwrite(world('ewr'));
    const out = await call({ operation: 'reopen_report', params: {} });
    assert.equal(out.status, 400);
  });

  it('refuses an operation it does not have', async () => {
    fakeAppwrite(world('admin'));
    const out = await call({ operation: 'drop_everything' });
    assert.equal(out.status, 400);
  });
});
