import assert from 'node:assert/strict';
import { describe, it, beforeEach } from 'node:test';

import write from '../src/write.js';
import { context, fakeAppwrite, profile } from './helpers.mjs';

const report = {
  op: 'create',
  collection: 'reports',
  documentId: 'r1',
  data: {
    hazardType: 'flood',
    title: 'Water over the road',
    description: 'Rising since dawn',
    state: 'Benue',
    lga: 'Makurdi',
    ward: 'North Bank I',
  },
};

describe('the write Function', () => {
  let fake;
  beforeEach(() => {
    fake = fakeAppwrite({ rows: { profiles: { u1: profile({ role: 'ewm' }) } } });
  });

  it('creates a report and stamps what the client may not choose', async () => {
    const ctx = context(report);
    await write(ctx);

    assert.equal(ctx.captured.status, 200);
    const stored = fake.store.reports.r1;
    assert.equal(stored.status, 'pending');
    assert.equal(stored.verificationCount, 0);
    assert.equal(stored.escalated, false);
    assert.equal(stored.userId, 'u1');
    // Denormalised at creation, because Appwrite cannot join to find it.
    assert.equal(stored.userName, 'Amina');
    assert.equal(stored.userRole, 'ewm');
  });

  it('refuses to let a client approve its own report', async () => {
    // Phase 4's third row, which is the one the whole write path exists
    // for: the client asks for approved/99/true and gets a success and a
    // document that says none of it.
    const ctx = context({
      ...report,
      data: {
        ...report.data,
        status: 'approved',
        verificationCount: 99,
        escalated: true,
        userId: 'somebody-else',
      },
    });
    await write(ctx);

    assert.equal(ctx.captured.status, 200);
    const stored = fake.store.reports.r1;
    assert.equal(stored.status, 'pending');
    assert.equal(stored.verificationCount, 0);
    assert.equal(stored.escalated, false);
    assert.equal(stored.userId, 'u1');
  });

  it('takes the caller from the header, never from the body', async () => {
    // The body is entirely under the client's control. The spike's
    // create-report accepted `payload.userId` as a fallback, which would
    // let any caller act as anyone.
    const ctx = context({ ...report, userId: 'admin-1' }, { userId: 'u1' });
    await write(ctx);
    assert.equal(fake.store.reports.r1.userId, 'u1');
  });

  it('refuses a caller with no session', async () => {
    const ctx = context(report, { userId: null });
    await write(ctx);
    assert.equal(ctx.captured.status, 401);
  });

  it('refuses a disabled account, in words the user will see', async () => {
    fake = fakeAppwrite({
      rows: { profiles: { u1: profile({ role: 'ewm', isDisabled: true }) } },
    });
    const ctx = context(report);
    await write(ctx);

    assert.equal(ctx.captured.status, 403);
    // No `type`: the client shows the server's own wording for a 4xx
    // that carries no slug, which is how this reaches a field agent.
    assert.equal(ctx.captured.body.type, undefined);
    assert.match(ctx.captured.body.message, /disabled/i);
  });

  it('refuses a ward that is not in the bundled list', async () => {
    const ctx = context({
      ...report,
      data: { ...report.data, ward: 'Nowhere In Particular' },
    });
    await write(ctx);
    assert.equal(ctx.captured.status, 400);
    assert.match(ctx.captured.body.message, /Unknown ward/);
  });

  it('refuses a collection it does not serve', async () => {
    const ctx = context({ ...report, collection: 'messages' });
    await write(ctx);
    assert.equal(ctx.captured.status, 403);
  });

  it('names the ward team in the ACL, not the people in it', async () => {
    // Phase 0's finding: the ACL names the team, so moving an agent
    // between wards is a membership change rather than a rewrite of
    // every document they can see.
    const ctx = context(report);
    await write(ctx);
    assert.deepEqual(fake.store.reports.r1.$permissions, [
      'read("user:u1")',
      'read("team:ward-benue-makurdi-north-bank-i")',
      'read("label:ewv")',
      'read("label:ewr")',
      'read("label:admin")',
    ]);
  });

  it('creates the ward team before the document that points at it', async () => {
    const ctx = context(report);
    await write(ctx);
    const teamCall = fake.calls.findIndex((c) => c.path.startsWith('/teams'));
    const rowCall = fake.calls.findIndex(
      (c) => c.path.includes('/tables/reports/rows') && c.method === 'POST',
    );
    assert.ok(teamCall >= 0 && teamCall < rowCall,
      'the team must exist first, or nobody in the ward can read the report');
  });

  it('answers a replay as a duplicate, not as a failure', async () => {
    await write(context(report));
    const second = context(report);
    await write(second);
    assert.equal(second.captured.status, 409);
  });
});

describe('votes', () => {
  const vote = {
    op: 'create',
    collection: 'verifications',
    documentId: 'v1',
    data: { reportId: 'r1', isConfirmed: true, comment: 'Seen it' },
  };

  it('takes the ward from the report, not from the voter', async () => {
    // The cross-collection check the old `verifications_insert` policy
    // made: an EWM must not vote on another ward's report by claiming it
    // is theirs.
    const fake = fakeAppwrite({
      rows: {
        profiles: { u1: profile({ role: 'ewm', name: 'Amina' }) },
        reports: {
          r1: { $id: 'r1', status: 'pending', state: 'Benue', lga: 'Makurdi', ward: 'North Bank I' },
        },
      },
    });
    const ctx = context({
      ...vote,
      data: { ...vote.data, state: 'Plateau', lga: 'Jos North', ward: 'Gangare' },
    });
    await write(ctx);

    assert.equal(ctx.captured.status, 200);
    assert.equal(fake.store.verifications.v1.ward, 'North Bank I');
    assert.equal(fake.store.verifications.v1.verifierId, 'u1');
    assert.equal(fake.store.verifications.v1.verifierName, 'Amina');
  });

  it('refuses a vote on a report that is no longer pending', async () => {
    fakeAppwrite({
      rows: {
        profiles: { u1: profile({ role: 'ewm' }) },
        reports: { r1: { $id: 'r1', status: 'approved', state: 'Benue', lga: 'Makurdi', ward: 'North Bank I' } },
      },
    });
    const ctx = context(vote);
    await write(ctx);
    assert.equal(ctx.captured.status, 409);
  });

  it('refuses a voter whose role may not vote', async () => {
    fakeAppwrite({
      rows: {
        profiles: { u1: profile({ role: 'user' }) },
        reports: { r1: { $id: 'r1', status: 'pending', state: 'Benue', lga: 'Makurdi', ward: 'North Bank I' } },
      },
    });
    const ctx = context(vote);
    await write(ctx);
    assert.equal(ctx.captured.status, 403);
  });
});

describe('profiles', () => {
  it('lets a user edit their own name', async () => {
    const fake = fakeAppwrite({ rows: { profiles: { u1: profile() } } });
    const ctx = context({
      op: 'update', collection: 'profiles', documentId: 'u1',
      data: { name: 'Amina B.' },
    });
    await write(ctx);
    assert.equal(ctx.captured.status, 200);
    assert.equal(fake.store.profiles.u1.name, 'Amina B.');
  });

  it('refuses a user approving themselves — loudly, not silently', async () => {
    // Ignoring the field would answer 200 and let them believe it worked.
    const fake = fakeAppwrite({ rows: { profiles: { u1: profile() } } });
    const ctx = context({
      op: 'update', collection: 'profiles', documentId: 'u1',
      data: { name: 'Amina', isApproved: true, role: 'admin' },
    });
    await write(ctx);

    assert.equal(ctx.captured.status, 403);
    assert.match(ctx.captured.body.message, /isApproved/);
    assert.equal(fake.store.profiles.u1.isApproved, true, 'unchanged from the fixture');
    assert.equal(fake.store.profiles.u1.role, 'user');
  });

  it('refuses a user editing somebody else', async () => {
    fakeAppwrite({ rows: { profiles: { u1: profile(), u2: profile({ $id: 'u2' }) } } });
    const ctx = context({
      op: 'update', collection: 'profiles', documentId: 'u2', data: { name: 'x' },
    });
    await write(ctx);
    assert.equal(ctx.captured.status, 403);
  });

  it('lets an admin set a role', async () => {
    const fake = fakeAppwrite({
      rows: { profiles: { u1: profile({ role: 'admin' }), u2: profile({ $id: 'u2' }) } },
    });
    const ctx = context({
      op: 'update', collection: 'profiles', documentId: 'u2',
      data: { role: 'ewm', isApproved: true },
    });
    await write(ctx);
    assert.equal(ctx.captured.status, 200);
    assert.equal(fake.store.profiles.u2.role, 'ewm');
  });
});

describe('updates', () => {
  it('refuses to move a report to another ward', async () => {
    const fake = fakeAppwrite({
      rows: {
        profiles: { u1: profile({ role: 'admin' }) },
        reports: { r1: { $id: 'r1', status: 'pending', state: 'Benue', lga: 'Makurdi', ward: 'North Bank I' } },
      },
    });
    const ctx = context({
      op: 'update', collection: 'reports', documentId: 'r1',
      data: { ward: 'Gangare' },
    });
    await write(ctx);

    assert.equal(ctx.captured.status, 403);
    assert.equal(fake.store.reports.r1.ward, 'North Bank I');
  });

  it('refuses a delete from a non-admin', async () => {
    fakeAppwrite({
      rows: {
        profiles: { u1: profile({ role: 'ewr' }) },
        reports: { r1: { $id: 'r1', status: 'pending' } },
      },
    });
    const ctx = context({ op: 'delete', collection: 'reports', documentId: 'r1' });
    await write(ctx);
    assert.equal(ctx.captured.status, 403);
  });
});
