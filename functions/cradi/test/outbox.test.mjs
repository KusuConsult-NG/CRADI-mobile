import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { backoffMs, eventId, enqueue, claim, MAX_ATTEMPTS } from '../src/lib/outbox.js';
import { eventsFor } from '../src/on-write.js';
import { messageId } from '../src/lib/messaging.js';
import { fakeAppwrite } from './helpers.mjs';

describe('outbox ids', () => {
  it('are readable while they fit', () => {
    assert.equal(eventId('alert_created', 'a1'), 'alert_created-a1');
  });

  it('keep the event type when they do not', () => {
    // The trap: a uuid key is already 36 characters, so trimming to the
    // last 36 would reduce every type on one report to the bare uuid.
    // `report_created` and `report_disputed` on the same report are two
    // different notifications and the second would be dropped as a
    // duplicate of the first.
    const uuid = '0199c0de-dead-beef-cafe-000000000001';
    const types = [
      'report_created',
      'report_disputed',
      'report_status_changed',
      'alert_created',
      'user_access_changed',
    ];
    const ids = types.map((t) => eventId(t, uuid));
    assert.equal(new Set(ids).size, types.length);
    for (const id of ids) assert.ok(id.length <= 36, id);
    assert.match(ids[0], /^report-created-/);
  });

  it('are stable, so a retry collides instead of notifying twice', () => {
    assert.equal(eventId('report_created', 'r1'), eventId('report_created', 'r1'));
  });
});

describe('backoff', () => {
  it('doubles and caps at an hour, as the SQL did', () => {
    // least(60, power(2, attempts)) minutes
    assert.deepEqual(
      [0, 1, 2, 3, 4, 5, 6, 7].map((a) => backoffMs(a) / 60_000),
      [1, 2, 4, 8, 16, 32, 60, 60],
    );
  });
});

describe('enqueue', () => {
  it('writes one document and reports a replay as a duplicate', async () => {
    const fake = fakeAppwrite();
    const first = await enqueue({
      eventType: 'report_created', key: 'r1', payload: { reportId: 'r1' },
    });
    assert.equal(first.duplicate, false);

    const second = await enqueue({
      eventType: 'report_created', key: 'r1', payload: { reportId: 'r1' },
    });
    assert.equal(second.duplicate, true);
    assert.equal(Object.keys(fake.store.notification_outbox).length, 1);
  });

  it('stores the payload as text, because a row has no sub-documents', async () => {
    const fake = fakeAppwrite();
    await enqueue({ eventType: 'alert_created', key: 'a1', payload: { alertId: 'a1' } });
    const doc = Object.values(fake.store.notification_outbox)[0];
    assert.equal(typeof doc.payload, 'string');
    assert.deepEqual(JSON.parse(doc.payload), { alertId: 'a1' });
  });
});

describe('claim', () => {
  const due = (over = {}) => ({
    $id: over.$id ?? 'e1',
    eventType: 'report_created',
    payload: '{}',
    attempts: 0,
    availableAt: '2020-01-01T00:00:00.000Z',
    processedAt: null,
    ...over,
  });

  it('bumps attempts and pushes availableAt forward', async () => {
    const fake = fakeAppwrite({ rows: { notification_outbox: { e1: due() } } });
    const claimed = await claim(10);

    assert.equal(claimed.length, 1);
    assert.equal(claimed[0].attempts, 1);
    const stored = fake.store.notification_outbox.e1;
    assert.equal(stored.attempts, 1);
    assert.ok(Date.parse(stored.availableAt) > Date.now());
  });

  it('claims before working, so a run that dies leaves work that comes back', async () => {
    // The claim is the first write. A crash after it means the document
    // reappears when its backoff expires rather than being retried
    // immediately forever.
    const fake = fakeAppwrite({ rows: { notification_outbox: { e1: due() } } });
    await claim(10);
    const writes = fake.calls.filter((c) => c.method === 'PATCH');
    assert.equal(writes.length, 1);
    assert.ok('attempts' in writes[0].body.data);
  });

  it('asks only for documents that are unprocessed, due and under the cap', async () => {
    fakeAppwrite({ rows: { notification_outbox: {} } });
    const fake = fakeAppwrite({ rows: { notification_outbox: {} } });
    await claim(10);
    const list = fake.calls.find((c) => c.method === 'GET');
    const queries = decodeURIComponent(list.path);
    assert.match(queries, /isNull.*processedAt/);
    assert.match(queries, /lessThanEqual.*availableAt/);
    assert.match(queries, new RegExp(`lessThan.*attempts.*${MAX_ATTEMPTS}`));
    assert.match(queries, /orderAsc.*availableAt/);
  });
});

describe('what a document event owes the outbox', () => {
  const E = 'tablesdb.cradi.tables.';

  it('matches the name Appwrite DELIVERS, not only the one it accepts', () => {
    // Subscribed as `...tables.reports.rows.*.create`; delivered as
    // `...collections.reports.documents.<id>.create`. Matching only the
    // first is silent — the Function logs a success and writes nothing.
    const delivered = `${E.replace('tables.', 'collections.')}`;
    assert.deepEqual(
      eventsFor('databases.cradi.collections.reports.documents.r1.create', { $id: 'r1' }),
      [{ eventType: 'report_created', key: 'r1', payload: { reportId: 'r1' } }],
    );
    assert.ok(delivered);
  });

  it('a new report owes one verification request', () => {
    assert.deepEqual(eventsFor(`${E}reports.rows.r1.create`, { $id: 'r1' }), [
      { eventType: 'report_created', key: 'r1', payload: { reportId: 'r1' } },
    ]);
  });

  it('a status change owes an announcement, keyed by the transition', () => {
    // Keyed by the report alone, pending->approved->rejected would
    // collapse into one notification and the rejection would never be
    // sent.
    const [event] = eventsFor(`${E}reports.rows.r1.update`, {
      $id: 'r1', previousStatus: 'pending', status: 'approved',
    });
    assert.equal(event.key, 'r1-pending-approved');

    const [second] = eventsFor(`${E}reports.rows.r1.update`, {
      $id: 'r1', previousStatus: 'approved', status: 'rejected',
    });
    assert.notEqual(eventId(event.eventType, event.key),
      eventId(second.eventType, second.key));
  });

  it('an edit that leaves the status alone owes nothing', () => {
    // Appwrite gives the document, not the change — without
    // `previousStatus` every touch would re-announce.
    assert.deepEqual(
      eventsFor(`${E}reports.rows.r1.update`, {
        $id: 'r1', previousStatus: 'pending', status: 'pending',
      }),
      [],
    );
    assert.deepEqual(
      eventsFor(`${E}reports.rows.r1.update`, { $id: 'r1', status: 'pending' }),
      [],
    );
  });

  it('only a dispute escalates; a confirmation owes nothing', () => {
    assert.equal(
      eventsFor(`${E}verifications.rows.v1.create`, {
        $id: 'v1', reportId: 'r1', isConfirmed: false,
      }).length,
      1,
    );
    assert.deepEqual(
      eventsFor(`${E}verifications.rows.v1.create`, {
        $id: 'v1', reportId: 'r1', isConfirmed: true,
      }),
      [],
    );
  });

  it('enabling and disabling an account are two events', () => {
    const [off] = eventsFor(`${E}profiles.rows.u1.update`, { $id: 'u1', isDisabled: true });
    const [on] = eventsFor(`${E}profiles.rows.u1.update`, { $id: 'u1', isDisabled: false });
    assert.notEqual(off.key, on.key);
  });

  it('an event nobody subscribed to owes nothing', () => {
    assert.deepEqual(eventsFor(`${E}contacts.rows.c1.create`, { $id: 'c1' }), []);
    assert.deepEqual(eventsFor('', {}), []);
  });
});

describe('message ids', () => {
  it('derive from the outbox event, which is what replaces the lock', () => {
    // Appwrite refuses a duplicate messageId with 409, so two
    // overlapping drains cannot double-send.
    assert.equal(messageId('outbox:e1:verifiers'), 'outbox-e1-verifiers');
  });

  it('stay inside 36 characters and stay distinct', () => {
    const a = messageId('outbox:0199c0de-dead-beef-cafe-000000000001:verifiers');
    const b = messageId('outbox:0199c0de-dead-beef-cafe-000000000001:reporter');
    assert.ok(a.length <= 36 && b.length <= 36);
    assert.notEqual(a, b);
  });
});
