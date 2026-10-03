import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import drain, { processOne } from '../src/drain.js';
import reconcile from '../src/reconcile.js';
import { createHandlers } from '../src/lib/handlers.js';
import { PermanentEventError, eventId } from '../src/lib/outbox.js';
import { context, fakeAppwrite, profile } from './helpers.mjs';

const outboxDoc = (over = {}) => ({
  $id: 'e1',
  eventType: 'report_created',
  payload: JSON.stringify({ reportId: 'r1' }),
  attempts: 0,
  availableAt: '2020-01-01T00:00:00.000Z',
  processedAt: null,
  ...over,
});

const report = (over = {}) => ({
  $id: 'r1',
  status: 'pending',
  userId: 'reporter',
  state: 'Benue',
  lga: 'Makurdi',
  ward: 'North Bank I',
  hazardType: 'flood',
  ...over,
});

const world = (over = {}) => ({
  rows: {
    notification_outbox: { e1: outboxDoc() },
    reports: { r1: report() },
    profiles: {
      m1: profile({ $id: 'm1', role: 'ewm', lga: 'Makurdi', ward: 'North Bank I' }),
    },
    app_settings: {},
    ...over,
  },
});

describe('the drain', () => {
  it('claims, notifies and marks processed', async () => {
    const fake = fakeAppwrite(world());
    const ctx = context({});
    await drain(ctx);

    assert.equal(ctx.captured.body.claimed, 1);
    assert.equal(ctx.captured.body.processed, 1);
    assert.ok(fake.store.notification_outbox.e1.processedAt);

    const push = fake.calls.find((c) => c.path === '/messaging/messages/push');
    assert.deepEqual(push.body.users, ['m1']);
    assert.equal(push.body.messageId, 'outbox-e1-verifiers');
  });

  it('never asks a verifier to verify their own report', async () => {
    const fake = fakeAppwrite(
      world({
        reports: { r1: report({ userId: 'm1' }) },
      }),
    );
    await drain(context({}));
    const push = fake.calls.find((c) => c.path === '/messaging/messages/push');
    assert.deepEqual(push?.body?.users ?? [], []);
  });

  it('leaves out an unapproved or disabled recipient', async () => {
    const fake = fakeAppwrite(
      world({
        profiles: {
          m1: profile({ $id: 'm1', role: 'ewm', lga: 'Makurdi', ward: 'North Bank I', isApproved: false }),
          m2: profile({ $id: 'm2', role: 'ewm', lga: 'Makurdi', ward: 'North Bank I', isDisabled: true }),
          m3: profile({ $id: 'm3', role: 'ewm', lga: 'Makurdi', ward: 'North Bank I' }),
        },
      }),
    );
    await drain(context({}));
    const push = fake.calls.find((c) => c.path === '/messaging/messages/push');
    assert.deepEqual(push.body.users, ['m3']);
  });

  it('does not announce a decision that has since been changed', async () => {
    // The event may be minutes old; retries back off. Announcing
    // "approved" after it was rejected is worse than announcing nothing.
    const fake = fakeAppwrite(
      world({
        notification_outbox: {
          e1: outboxDoc({
            eventType: 'report_status_changed',
            payload: JSON.stringify({
              reportId: 'r1', oldStatus: 'pending', newStatus: 'approved',
            }),
          }),
        },
        reports: { r1: report({ status: 'rejected' }) },
      }),
    );
    await drain(context({}));
    assert.match(fake.store.notification_outbox.e1.note, /stale/);
    assert.ok(!fake.calls.some((c) => c.path === '/messaging/messages/push'));
  });

  it('two overlapping runs cannot double-send', async () => {
    // There is no atomic claim. What stands in for it is Appwrite
    // refusing a duplicate messageId with 409 — the single property this
    // whole design leans on.
    const fake = fakeAppwrite(world());
    await drain(context({}));

    // Pretend the document came back due before the first run marked it.
    fake.store.notification_outbox.e1.processedAt = null;
    fake.store.notification_outbox.e1.availableAt = '2020-01-01T00:00:00.000Z';
    const second = context({});
    await drain(second);

    assert.equal(second.captured.body.processed, 1);
    assert.equal(fake.sentMessages['outbox-e1-verifiers'], 1,
      'the second send must be refused by the server, not duplicated');
  });

  it('a failed event keeps its claim and comes back later', async () => {
    const fake = fakeAppwrite(
      world({ notification_outbox: { e1: outboxDoc({ payload: 'not json' }) } }),
    );
    const ctx = context({});
    await drain(ctx);

    // A bad payload can never succeed, so it is marked processed rather
    // than retried eight times.
    assert.equal(ctx.captured.body.processed, 1);
    assert.ok(fake.store.notification_outbox.e1.processedAt);
    assert.match(fake.store.notification_outbox.e1.note, /not JSON/);
  });

  it('marks an unknown event type processed instead of retrying forever', async () => {
    const fake = fakeAppwrite(
      world({ notification_outbox: { e1: outboxDoc({ eventType: 'something_new' }) } }),
    );
    await drain(context({}));
    assert.equal(fake.store.notification_outbox.e1.note, 'unknown event');
    assert.ok(fake.store.notification_outbox.e1.processedAt);
  });

  it('records a retryable failure without marking it done', async () => {
    const handlers = {
      report_created: () => {
        throw new Error('push outage');
      },
    };
    const fake = fakeAppwrite(world());
    const outcome = await processOne(outboxDoc({ attempts: 1 }), handlers);

    assert.equal(outcome, 'failed');
    assert.equal(fake.store.notification_outbox.e1.processedAt, null);
    assert.match(fake.store.notification_outbox.e1.note, /push outage/);
  });

  it('a permanent failure is not retried', async () => {
    const handlers = {
      report_created: () => {
        throw new PermanentEventError('payload: reportId missing');
      },
    };
    const fake = fakeAppwrite(world());
    assert.equal(await processOne(outboxDoc(), handlers), 'processed');
    assert.ok(fake.store.notification_outbox.e1.processedAt);
  });
});

describe('an approval', () => {
  const approved = () =>
    world({
      notification_outbox: {
        e1: outboxDoc({
          eventType: 'report_status_changed',
          payload: JSON.stringify({
            reportId: 'r1', oldStatus: 'pending', newStatus: 'approved',
          }),
        }),
      },
      reports: { r1: report({ status: 'approved' }) },
      profiles: { reporter: profile({ $id: 'reporter' }) },
    });

  it('tells the reporter and broadcasts to the right LGA topic', async () => {
    const fake = fakeAppwrite(approved());
    await drain(context({}));

    const pushes = fake.calls.filter((c) => c.path === '/messaging/messages/push');
    assert.equal(pushes.length, 2);
    assert.deepEqual(pushes[0].body.users, ['reporter']);
    // Obi exists in both Benue and Nasarawa, so an LGA topic is scoped
    // by state or it addresses the wrong people entirely.
    assert.deepEqual(pushes[1].body.topics, ['lga-benue-makurdi']);
  });

  it('a push outage does not stop the SMS, and the event still retries', async () => {
    const fake = fakeAppwrite(approved());
    let smsCalls = 0;
    const handlers = createHandlers({
      sms: async () => {
        smsCalls += 1;
        return { sent: 1 };
      },
    });
    // Make every push fail.
    const realFetch = globalThis.fetch;
    globalThis.fetch = async (url, init) =>
      String(url).endsWith('/messaging/messages/push')
        ? new Response(JSON.stringify({ message: 'down' }), { status: 503 })
        : realFetch(url, init);

    const outcome = await processOne(
      { ...outboxDoc({ eventType: 'report_status_changed' }),
        payload: JSON.stringify({ reportId: 'r1', oldStatus: 'pending', newStatus: 'approved' }) },
      handlers,
    );

    assert.equal(smsCalls, 1, 'the authority SMS must not wait on push');
    assert.equal(outcome, 'failed', 'and the event must still retry');
    assert.equal(fake.store.notification_outbox.e1.processedAt, null);
  });
});

describe('the reconciling sweep', () => {
  it('finds a report whose event Function never ran, and enqueues it', async () => {
    // The loss Phase 6 named: in Postgres the outbox row was written in
    // the same transaction as the report. Here the event Function runs
    // after the commit and can simply not happen.
    const fake = fakeAppwrite({
      rows: { reports: { r1: report() }, alerts: {}, verifications: {}, notification_outbox: {} },
    });
    const ctx = context({});
    await reconcile(ctx);

    assert.equal(ctx.captured.body.missing, 1);
    assert.equal(ctx.captured.body.enqueued, 1);
    assert.ok(fake.store.notification_outbox[eventId('report_created', 'r1')]);
    // A gap means an event Function failed silently. That is worth
    // somebody's attention even though the sweep repaired it.
    assert.match(ctx.captured.error ?? '', /had no report_created/);
  });

  it('leaves a report whose event did happen alone', async () => {
    const fake = fakeAppwrite({
      rows: {
        reports: { r1: report() },
        alerts: {},
        verifications: {},
        notification_outbox: { [eventId('report_created', 'r1')]: outboxDoc() },
      },
    });
    const ctx = context({});
    await reconcile(ctx);

    assert.equal(ctx.captured.body.missing, 0);
    assert.equal(Object.keys(fake.store.notification_outbox).length, 1);
  });

  it('does not invent work the trigger would never have created', async () => {
    // A confirmation owes no event; only a dispute does. The sweep must
    // apply the same rule or it manufactures notifications.
    const fake = fakeAppwrite({
      rows: {
        reports: {}, alerts: {},
        verifications: { v1: { $id: 'v1', reportId: 'r1', isConfirmed: true } },
        notification_outbox: {},
      },
    });
    const ctx = context({});
    await reconcile(ctx);
    assert.equal(ctx.captured.body.missing, 0);
    assert.equal(Object.keys(fake.store.notification_outbox).length, 0);
  });

  it('reports a quiet run, so a sweep that stopped running is visible', async () => {
    // "0 missing" is the evidence it ran. A sweep that silently dies
    // looks exactly like a system with no gaps.
    fakeAppwrite({ rows: { reports: {}, alerts: {}, verifications: {} } });
    const ctx = context({});
    await reconcile(ctx);
    assert.deepEqual(ctx.captured.body, {
      checked: 0, missing: 0, enqueued: 0,
      countsChecked: 0, countsRepaired: 0, verified: 0,
    });
  });

  it('repairs a report whose confirmations were never counted', async () => {
    // `write.js` stores the vote and the count in two calls. Stopping
    // between them leaves a report with the votes to be verified sitting
    // at pending until it escalates — which is the failure worth a
    // second look every five minutes.
    const fake = fakeAppwrite({
      rows: {
        reports: { r1: report({ status: 'pending', verificationCount: 0 }) },
        alerts: {},
        verifications: {
          v1: { $id: 'v1', reportId: 'r1', isConfirmed: true, verifierId: 'a' },
          v2: { $id: 'v2', reportId: 'r1', isConfirmed: true, verifierId: 'b' },
        },
        notification_outbox: {},
        app_settings: {},
      },
    });
    const ctx = context({});
    await reconcile(ctx);

    assert.equal(ctx.captured.body.countsRepaired, 1);
    assert.equal(ctx.captured.body.verified, 1);
    assert.equal(fake.store.reports.r1.verificationCount, 2);
    assert.equal(fake.store.reports.r1.status, 'verified');
    assert.equal(fake.store.reports.r1.autoValidated, true);
    assert.equal(fake.store.reports.r1.previousStatus, 'pending');
    assert.match(ctx.captured.error ?? '', /stored 0 confirmations and has 2/);
  });

  it('leaves a report whose count is already right alone', async () => {
    const fake = fakeAppwrite({
      rows: {
        reports: { r1: report({ status: 'pending', verificationCount: 1 }) },
        alerts: {},
        verifications: { v1: { $id: 'v1', reportId: 'r1', isConfirmed: true, verifierId: 'a' } },
        notification_outbox: { [eventId('report_created', 'r1')]: { $id: 'x' } },
        app_settings: {},
      },
    });
    const ctx = context({});
    await reconcile(ctx);

    assert.equal(ctx.captured.body.countsChecked, 1);
    assert.equal(ctx.captured.body.countsRepaired, 0);
    assert.equal(fake.store.reports.r1.status, 'pending');
  });

  it('verifies a report whose count is right but whose flip never happened', async () => {
    // The other half of the same two-call write: `write.js` stored the
    // count and stopped before the status. The count then matches the
    // votes, so the sweep used to `continue` and walk straight past the
    // report it exists to rescue — it sat at pending with the votes to
    // be verified until it escalated.
    const fake = fakeAppwrite({
      rows: {
        reports: { r1: report({ status: 'pending', verificationCount: 2 }) },
        alerts: {},
        verifications: {
          v1: { $id: 'v1', reportId: 'r1', isConfirmed: true, verifierId: 'a' },
          v2: { $id: 'v2', reportId: 'r1', isConfirmed: true, verifierId: 'b' },
        },
        notification_outbox: { [eventId('report_created', 'r1')]: { $id: 'x' } },
        app_settings: {},
      },
    });
    const ctx = context({});
    await reconcile(ctx);

    // Nothing to repair — the count was already right — and the report
    // is verified all the same.
    assert.equal(ctx.captured.body.countsRepaired, 0);
    assert.equal(ctx.captured.body.verified, 1);
    assert.equal(fake.store.reports.r1.status, 'verified');
    assert.equal(fake.store.reports.r1.autoValidated, true);
  });

  it('does not reopen a decided report, however many votes it has', async () => {
    // A report approved by an admin is not pending, so the sweep never
    // looks at it — and if it did, the flip is a compare-and-set.
    const fake = fakeAppwrite({
      rows: {
        reports: { r1: report({ status: 'approved', verificationCount: 0 }) },
        alerts: {},
        verifications: {
          v1: { $id: 'v1', reportId: 'r1', isConfirmed: true, verifierId: 'a' },
          v2: { $id: 'v2', reportId: 'r1', isConfirmed: true, verifierId: 'b' },
        },
        notification_outbox: {},
        app_settings: {},
      },
    });
    const ctx = context({});
    await reconcile(ctx);

    assert.equal(ctx.captured.body.countsChecked, 0);
    assert.equal(fake.store.reports.r1.status, 'approved');
  });
});
