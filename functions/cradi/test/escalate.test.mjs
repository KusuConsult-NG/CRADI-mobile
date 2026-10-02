import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import escalate, {
  MAX_ATTEMPTS,
  failedAttempts,
  processEscalation,
  recordFailure,
  retryDelayMs,
} from '../src/escalate.js';
import { ESCALATION_REASON, DISPUTE_REASON } from '../src/lib/notifications.js';
import { context, fakeAppwrite, profile } from './helpers.mjs';

const esc = (over = {}) => ({
  $id: 'e1',
  reportId: 'r1',
  escalateAt: '2020-01-01T00:00:00.000Z',
  status: 'pending',
  reason: null,
  ...over,
});

const report = (over = {}) => ({
  $id: 'r1',
  status: 'pending',
  escalated: false,
  escalationReason: null,
  userId: 'reporter',
  lga: 'Makurdi',
  ward: 'North Bank I',
  ...over,
});

describe('backoff bookkeeping', () => {
  it('reads the attempt out of the reason, which is where it lives', () => {
    // scheduled_escalations has no attempts column — it did not have one
    // in Postgres either.
    assert.equal(failedAttempts('attempt 3: boom'), 3);
    assert.equal(failedAttempts('Already escalated: something'), 0);
    assert.equal(failedAttempts(null), 0);
  });

  it('doubles to an hour and no further', () => {
    assert.deepEqual(
      [1, 2, 3, 4, 5, 6, 7].map((a) => retryDelayMs(a) / 60_000),
      [1, 2, 4, 8, 16, 32, 60],
    );
  });

  it('pushes escalateAt forward so a failing row leaves the queue head', async () => {
    const fake = fakeAppwrite({ rows: { scheduled_escalations: { e1: esc() } } });
    const out = await recordFailure(esc(), 'smtp down');

    assert.deepEqual(out, { attempt: 1, gaveUp: false });
    const stored = fake.store.scheduled_escalations.e1;
    assert.match(stored.reason, /^attempt 1: smtp down/);
    assert.ok(Date.parse(stored.escalateAt) > Date.now());
    assert.equal(stored.status, 'pending');
  });

  it('gives up rather than retrying forever', async () => {
    const row = esc({ reason: `attempt ${MAX_ATTEMPTS - 1}: boom` });
    const fake = fakeAppwrite({ rows: { scheduled_escalations: { e1: row } } });
    const out = await recordFailure(row, 'boom again');

    assert.equal(out.gaveUp, true);
    assert.equal(fake.store.scheduled_escalations.e1.status, 'skipped');
  });
});

describe('processing one escalation', () => {
  it('marks the report escalated and notifies, leaving the status pending', async () => {
    const fake = fakeAppwrite({
      rows: {
        scheduled_escalations: { e1: esc() },
        reports: { r1: report() },
        profiles: {
          c1: profile({ $id: 'c1', role: 'ldp_coordinator', lga: 'Makurdi' }),
        },
      },
    });
    assert.equal(await processEscalation(esc()), 'processed');

    const stored = fake.store.reports.r1;
    assert.equal(stored.escalated, true);
    assert.equal(stored.escalationReason, ESCALATION_REASON);
    // The report stays pending: escalation is a flag, not a decision.
    assert.equal(stored.status, 'pending');
    assert.equal(fake.store.scheduled_escalations.e1.status, 'processed');

    const push = fake.calls.find((c) => c.path === '/messaging/messages/push');
    assert.ok(push, 'somebody has to be told');
    // The message id is what stands in for the lock Postgres had.
    assert.equal(push.body.messageId, 'escalation-e1');
  });

  it('never notifies the reporter about their own report', async () => {
    const fake = fakeAppwrite({
      rows: {
        scheduled_escalations: { e1: esc() },
        reports: { r1: report({ userId: 'c1' }) },
        profiles: { c1: profile({ $id: 'c1', role: 'ldp_coordinator', lga: 'Makurdi' }) },
      },
    });
    await processEscalation(esc());
    const push = fake.calls.find((c) => c.path === '/messaging/messages/push');
    assert.deepEqual(push?.body?.users ?? [], []);
  });

  it('skips a report that is no longer pending', async () => {
    const fake = fakeAppwrite({
      rows: {
        scheduled_escalations: { e1: esc() },
        reports: { r1: report({ status: 'approved' }) },
      },
    });
    assert.equal(await processEscalation(esc()), 'skipped');
    assert.match(fake.store.scheduled_escalations.e1.reason, /approved/);
    assert.ok(!fake.calls.some((c) => c.path === '/messaging/messages/push'));
  });

  it('skips a report a dispute already escalated and announced', async () => {
    const fake = fakeAppwrite({
      rows: {
        scheduled_escalations: { e1: esc() },
        reports: { r1: report({ escalated: true, escalationReason: DISPUTE_REASON }) },
      },
    });
    assert.equal(await processEscalation(esc()), 'skipped');
    assert.ok(!fake.calls.some((c) => c.path === '/messaging/messages/push'));
  });

  it('retries its own earlier failure, because the push is idempotent', async () => {
    // Marked escalated by this cron on an attempt that then failed to
    // notify. The push carries the same message id, so re-sending is
    // refused by Appwrite rather than duplicated.
    const fake = fakeAppwrite({
      rows: {
        scheduled_escalations: { e1: esc({ reason: 'attempt 1: smtp down' }) },
        reports: {
          r1: report({ escalated: true, escalationReason: ESCALATION_REASON }),
        },
        profiles: { c1: profile({ $id: 'c1', role: 'ewr', lga: 'Makurdi' }) },
      },
    });
    assert.equal(await processEscalation(esc({ reason: 'attempt 1: smtp down' })), 'processed');
    assert.ok(fake.calls.some((c) => c.path === '/messaging/messages/push'));
  });

  it('skips an escalation whose report is gone', async () => {
    const fake = fakeAppwrite({ rows: { scheduled_escalations: { e1: esc() } } });
    assert.equal(await processEscalation(esc()), 'skipped');
    assert.match(fake.store.scheduled_escalations.e1.reason, /not found/i);
  });
});

describe('the run', () => {
  it('asks only for pending escalations that are due, oldest first', async () => {
    const fake = fakeAppwrite({ rows: { scheduled_escalations: {} } });
    const ctx = context({});
    await escalate(ctx);

    const list = fake.calls.find((c) => c.path.includes('scheduled_escalations'));
    const queries = decodeURIComponent(list.path);
    assert.match(queries, /equal.*status.*pending/);
    assert.match(queries, /lessThanEqual.*escalateAt/);
    assert.match(queries, /orderAsc.*escalateAt/);
    assert.deepEqual(ctx.captured.body, { due: 0, processed: 0, skipped: 0, failed: 0 });
  });

  it('one failure does not stop the batch', async () => {
    const fake = fakeAppwrite({
      rows: {
        scheduled_escalations: { e1: esc({ $id: 'e1', reportId: 'gone' }), e2: esc({ $id: 'e2' }) },
        reports: { r1: report() },
        profiles: { c1: profile({ $id: 'c1', role: 'ewr', lga: 'Makurdi' }) },
      },
    });
    const ctx = context({});
    await escalate(ctx);
    assert.equal(ctx.captured.body.due, 2);
    assert.equal(ctx.captured.body.processed, 1);
    assert.equal(ctx.captured.body.skipped, 1);
    assert.equal(fake.store.reports.r1.escalated, true);
  });
});
