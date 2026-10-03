import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import operation from '../src/operation.js';
import { eventsFor } from '../src/on-write.js';
import { context, fakeAppwrite, profile } from './helpers.mjs';

/**
 * An outbox payload as `on-write.js` actually writes one.
 *
 * Built from the producer rather than typed out. These fixtures used to
 * say `report_id`, which nothing in the system emits — so the supersede
 * loop's own `report_id` comparison matched them and the tests passed
 * against a loop that, in production, superseded nothing.
 */
const payloadFor = (event, doc) =>
  JSON.stringify(eventsFor(event, doc)[0].payload);

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
    assert.equal(fake.store.reports.r1.updatedBy, 'u1');
  });

  it('clears every field the old decision left behind', async () => {
    // Resetting only the status and the vote count leaves a report that
    // is pending again while still carrying a rejection reason and a
    // verification timestamp — which is what the Postgres function went
    // out of its way to avoid.
    const fake = fakeAppwrite({
      rows: {
        profiles: { u1: profile({ role: 'ewr' }) },
        reports: {
          r1: {
            $id: 'r1', status: 'rejected', userId: 'someone-else',
            verificationCount: 3, verifiedAt: '2026-01-01T00:00:00.000Z',
            autoValidated: true, approvedAt: '2026-01-01T00:00:00.000Z',
            rejectedAt: '2026-01-02T00:00:00.000Z',
            rejectionReason: 'Not credible',
            escalated: true, escalatedAt: '2026-01-02T00:00:00.000Z',
            escalationReason: 'Timed out', escalationStatus: 'processed',
          },
        },
      },
    });
    assert.equal((await call(reopen)).status, 200);

    const r = fake.store.reports.r1;
    for (const key of [
      'verifiedAt', 'approvedAt', 'rejectedAt', 'rejectionReason',
      'escalatedAt', 'escalationReason',
    ]) {
      assert.equal(r[key], null, `${key} should be cleared`);
    }
    assert.equal(r.autoValidated, false);
    assert.equal(r.escalationStatus, 'pending');
    assert.ok(
      new Date(r.escalationScheduledAt).getTime() > Date.now(),
      'a fresh escalation deadline, in the future',
    );
  });

  it('refuses a report that is already pending', async () => {
    // Reopening a live report would wipe votes that are still being cast.
    const fake = fakeAppwrite({
      rows: {
        profiles: { u1: profile({ role: 'ewr' }) },
        reports: { r1: { $id: 'r1', status: 'pending' } },
        verifications: { v1: { $id: 'v1', reportId: 'r1' } },
      },
    });
    const out = await call(reopen);
    assert.equal(out.status, 400);
    assert.equal(Object.keys(fake.store.verifications).length, 1);
  });

  it('refuses a non-admin reopening their own report', async () => {
    // Otherwise a reviewer clears their own rejection.
    const fake = fakeAppwrite({
      rows: {
        profiles: { u1: profile({ role: 'ewr' }) },
        reports: { r1: { $id: 'r1', status: 'rejected', userId: 'u1' } },
      },
    });
    const out = await call(reopen);
    assert.equal(out.status, 403);
    assert.equal(fake.store.reports.r1.status, 'rejected');
  });

  it('lets an admin reopen their own report', async () => {
    fakeAppwrite({
      rows: {
        profiles: { u1: profile({ role: 'admin' }) },
        reports: { r1: { $id: 'r1', status: 'rejected', userId: 'u1' } },
      },
    });
    assert.equal((await call(reopen)).status, 200);
  });

  it('allows every role the Postgres function allowed', async () => {
    // An earlier port had only `ewr` and admin, which silently refused
    // the three roles that do most of the reviewing.
    for (const role of ['ewv', 'ewr', 'ldp_coordinator', 'project_staff']) {
      fakeAppwrite(world(role));
      assert.equal((await call(reopen)).status, 200, `${role} may reopen`);
    }
  });

  it('supersedes the events the old decision queued', async () => {
    // Delivered after the reopen they would tell the ward a report was
    // disputed or decided when it has just gone back to pending.
    const fake = fakeAppwrite({
      rows: {
        profiles: { u1: profile({ role: 'ewr' }) },
        reports: { r1: { $id: 'r1', status: 'approved' } },
        notification_outbox: {
          e1: {
            $id: 'e1', eventType: 'report_disputed', processedAt: null,
            payload: payloadFor(
              'databases.cradi.tables.verifications.rows.v9.create',
              { $id: 'v9', reportId: 'r1', isConfirmed: false },
            ),
          },
          e2: {
            $id: 'e2', eventType: 'report_disputed', processedAt: null,
            payload: payloadFor(
              'databases.cradi.tables.verifications.rows.v8.create',
              { $id: 'v8', reportId: 'other', isConfirmed: false },
            ),
          },
        },
      },
    });
    assert.equal((await call(reopen)).status, 200);

    assert.ok(fake.store.notification_outbox.e1.processedAt, 'superseded');
    assert.equal(
      fake.store.notification_outbox.e1.note,
      'superseded by reopen',
    );
    assert.equal(
      fake.store.notification_outbox.e2.processedAt,
      null,
      "another report's events are left alone",
    );
  });

  it('queues a fresh event so the ward hears it is live again', async () => {
    const fake = fakeAppwrite(world('ewr'));
    assert.equal((await call(reopen)).status, 200);

    const queued = Object.values(fake.store.notification_outbox ?? {}).filter(
      (e) => e.eventType === 'report_created' && !e.processedAt,
    );
    assert.equal(queued.length, 1);
    // `reportId`, the key the `report_created` handler reads. With
    // `report_id` the handler raised PermanentEventError and the event
    // was dropped, so nobody was told the report was live again.
    assert.deepEqual(JSON.parse(queued[0].payload), {
      reportId: 'r1',
      reopened: true,
    });
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
