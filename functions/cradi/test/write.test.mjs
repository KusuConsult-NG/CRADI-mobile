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

describe('the peer confirmation threshold', () => {
  const pending = {
    $id: 'r1', status: 'pending', verificationCount: 0,
    state: 'Benue', lga: 'Makurdi', ward: 'North Bank I',
  };
  const vote = (id, over = {}) => ({
    $id: id, reportId: 'r1', isConfirmed: true, verifierId: `v-${id}`, ...over,
  });
  const cast = (documentId, over = {}) =>
    context({
      op: 'create', collection: 'verifications', documentId,
      data: { reportId: 'r1', isConfirmed: true, comment: 'Seen it', ...over },
    });

  it('counts the confirmations onto the report', async () => {
    // `verifications_after_insert`, which had no Appwrite counterpart:
    // the vote was stored and nothing read it, so the count stayed 0.
    const fake = fakeAppwrite({
      rows: {
        profiles: { u1: profile({ role: 'ewm' }) },
        reports: { r1: { ...pending } },
        verifications: {},
        app_settings: { minimum_peer_confirmations: { $id: 'minimum_peer_confirmations', key: 'minimum_peer_confirmations', value: '3' } },
      },
    });
    const ctx = cast('v1');
    await write(ctx);

    assert.equal(ctx.captured.status, 200);
    assert.equal(fake.store.reports.r1.verificationCount, 1);
    // Below the threshold, so still pending.
    assert.equal(fake.store.reports.r1.status, 'pending');
  });

  it('verifies the report once the threshold is reached', async () => {
    const fake = fakeAppwrite({
      rows: {
        profiles: { u1: profile({ role: 'ewm' }) },
        reports: { r1: { ...pending, verificationCount: 1 } },
        verifications: { v1: vote('v1') },
        app_settings: {},
      },
    });
    const ctx = cast('v2');
    await write(ctx);

    assert.equal(ctx.captured.status, 200);
    const report = fake.store.reports.r1;
    assert.equal(report.verificationCount, 2, 'the default threshold is 2');
    assert.equal(report.status, 'verified');
    assert.equal(report.autoValidated, true);
    assert.equal(typeof report.verifiedAt, 'string');
    // So the event Function can tell this was a status change; Appwrite's
    // payload carries no "before".
    assert.equal(report.previousStatus, 'pending');
  });

  it('honours the configured threshold', async () => {
    const fake = fakeAppwrite({
      rows: {
        profiles: { u1: profile({ role: 'ewm' }) },
        reports: { r1: { ...pending, verificationCount: 2 } },
        verifications: { v1: vote('v1'), v2: vote('v2') },
        app_settings: { k: { $id: 'k', key: 'minimum_peer_confirmations', value: '3' } },
      },
    });
    await write(cast('v3'));

    assert.equal(fake.store.reports.r1.verificationCount, 3);
    assert.equal(fake.store.reports.r1.status, 'verified');
  });

  it('does not count a dispute toward the threshold', async () => {
    const fake = fakeAppwrite({
      rows: {
        profiles: { u1: profile({ role: 'ewm' }) },
        reports: { r1: { ...pending } },
        verifications: { v1: vote('v1', { isConfirmed: false }) },
        app_settings: {},
      },
    });
    await write(cast('v2', { isConfirmed: false }));

    assert.equal(fake.store.reports.r1.verificationCount, 0);
    assert.equal(fake.store.reports.r1.status, 'pending');
  });

  it('counts only this report\'s votes', async () => {
    const fake = fakeAppwrite({
      rows: {
        profiles: { u1: profile({ role: 'ewm' }) },
        reports: {
          r1: { ...pending },
          r2: { ...pending, $id: 'r2' },
        },
        verifications: { other: vote('other', { reportId: 'r2' }) },
        app_settings: {},
      },
    });
    await write(cast('v1'));

    assert.equal(fake.store.reports.r1.verificationCount, 1);
    assert.equal(fake.store.reports.r2.verificationCount, 0, 'untouched');
  });

  it('never overwrites a decision an admin already made', async () => {
    // The trigger's `where id = ... and status = 'pending'`: a report
    // approved while the votes were coming in stays approved.
    const fake = fakeAppwrite({
      rows: {
        profiles: { u1: profile({ role: 'ewm' }) },
        reports: { r1: { ...pending, status: 'pending' } },
        verifications: { v1: vote('v1'), v2: vote('v2') },
        app_settings: {},
      },
    });
    // The vote is accepted while the report is pending; the approval
    // lands between the vote being stored and the count being applied.
    const ctx = cast('v3');
    const original = globalThis.fetch;
    globalThis.fetch = async (url, init) => {
      const result = await original(url, init);
      if (String(url).includes('/verifications/rows') && init?.method === 'POST') {
        fake.store.reports.r1.status = 'approved';
      }
      return result;
    };
    await write(ctx);
    globalThis.fetch = original;

    assert.equal(ctx.captured.status, 200);
    assert.equal(fake.store.reports.r1.status, 'approved', 'the admin decision stands');
    assert.equal(fake.store.reports.r1.verificationCount, 3, 'but the count is still true');
  });

  it('recounts when a vote is deleted', async () => {
    const fake = fakeAppwrite({
      rows: {
        profiles: { u1: profile({ role: 'admin' }) },
        reports: { r1: { ...pending, verificationCount: 2 } },
        verifications: { v1: vote('v1'), v2: vote('v2') },
        app_settings: {},
      },
    });
    await write(context({ op: 'delete', collection: 'verifications', documentId: 'v2', data: {} }));

    assert.equal(fake.store.reports.r1.verificationCount, 1);
  });

  it('does not fail the vote when the count cannot be stored', async () => {
    // The vote is already written. Telling the verifier it failed would
    // have them send it again — into a unique index, which refuses it.
    const fake = fakeAppwrite({
      rows: {
        profiles: { u1: profile({ role: 'ewm' }) },
        reports: { r1: { ...pending } },
        verifications: {},
        app_settings: {},
      },
      fail: { 'PATCH /tables/reports/rows/r1': { status: 503, body: { message: 'upstream' } } },
    });
    const ctx = cast('v1');
    await write(ctx);

    assert.equal(ctx.captured.status, 200);
    assert.ok(fake.store.verifications.v1, 'the vote is stored');
    assert.match(ctx.logs.join('\n'), /WARNING: could not store verificationCount/);
  });
});

describe('a refusal from the database', () => {
  it('reaches the caller with the reason, not as a server fault', async () => {
    // Appwrite answers a bad payload with 400 and names the column:
    // `Invalid document structure: Unknown attribute: "updated_by"`.
    // Collapsing that into a 500 threw away the only useful part.
    const fake = fakeAppwrite({
      rows: { profiles: { u1: profile({ role: 'admin' }) } },
      fail: {
        '/tables/app_settings/rows': {
          status: 400,
          body: {
            message: 'Invalid document structure: Invalid value for "value": Value must be a valid string',
            type: 'document_invalid_structure',
          },
        },
      },
    });
    const ctx = context({
      op: 'upsert', collection: 'app_settings', documentId: 'escalation_timeout_minutes',
      data: { key: 'escalation_timeout_minutes', value: 47 },
    });
    await write(ctx);

    assert.equal(ctx.captured.status, 400);
    assert.match(ctx.captured.body.message, /Value must be a valid string/);
    assert.equal(fake.store.app_settings, undefined);
  });

  it('keeps a missing scope as a server fault, not the caller\'s', async () => {
    // A 403 here is this Function's own API key, not the payload. Saying
    // "missing scope" to a field agent is both confusing and a detail
    // they should not be handed.
    fakeAppwrite({
      rows: { profiles: { u1: profile({ role: 'admin' }) } },
      fail: {
        '/tables/news_links/rows': {
          status: 403,
          body: { message: 'app.cradi (role: applications) missing scope (documents.write)' },
        },
      },
    });
    const ctx = context({
      op: 'create', collection: 'news_links', documentId: 'n1',
      data: { title: 'A link', url: 'https://example.org/' },
    });
    await write(ctx);

    assert.equal(ctx.captured.status, 500);
    assert.doesNotMatch(JSON.stringify(ctx.captured.body), /missing scope/);
  });
});

describe('account labels', () => {
  const labelsOf = (fake, id) => fake.users.find((u) => u.$id === id)?.labels;

  it('gives a promoted admin the label their reads depend on', async () => {
    const fake = fakeAppwrite({
      rows: { profiles: { u1: profile({ role: 'admin' }), u2: profile({ $id: 'u2', role: 'user' }) } },
    });
    const ctx = context({
      op: 'update', collection: 'profiles', documentId: 'u2',
      data: { role: 'admin', isApproved: true },
    });
    await write(ctx);

    assert.equal(ctx.captured.status, 200);
    // Without this the row says admin, every `read("label:admin")` ACL
    // still refuses, and Appwrite answers the refusal with 200 and zero
    // rows — an empty panel and no error.
    assert.deepEqual(labelsOf(fake, 'u2'), ['admin', 'approved']);
  });

  it('spells a two-word role the way a label may be spelled', async () => {
    const fake = fakeAppwrite({
      rows: { profiles: { u1: profile({ role: 'admin' }), u2: profile({ $id: 'u2', role: 'user' }) } },
    });
    await write(context({
      op: 'update', collection: 'profiles', documentId: 'u2',
      data: { role: 'ldp_coordinator', isApproved: true },
    }));

    assert.deepEqual(labelsOf(fake, 'u2'), ['ldpCoordinator', 'approved']);
  });

  it('takes every label off a disabled account', async () => {
    const fake = fakeAppwrite({
      rows: {
        profiles: {
          u1: profile({ role: 'admin' }),
          u2: profile({ $id: 'u2', role: 'ewm', isApproved: true }),
        },
      },
    });
    await write(context({
      op: 'update', collection: 'profiles', documentId: 'u2', data: { isDisabled: true },
    }));

    assert.deepEqual(labelsOf(fake, 'u2'), []);
  });

  it('drops `approved` when approval is revoked', async () => {
    const fake = fakeAppwrite({
      rows: {
        profiles: {
          u1: profile({ role: 'admin' }),
          u2: profile({ $id: 'u2', role: 'ewm', isApproved: true }),
        },
      },
    });
    await write(context({
      op: 'update', collection: 'profiles', documentId: 'u2', data: { isApproved: false },
    }));

    assert.deepEqual(labelsOf(fake, 'u2'), ['ewm']);
  });

  it('leaves the account alone when the edit touches nothing labels depend on', async () => {
    const fake = fakeAppwrite({ rows: { profiles: { u1: profile({ role: 'ewm' }) } } });
    await write(context({
      op: 'update', collection: 'profiles', documentId: 'u1', data: { name: 'Amina B.' },
    }));

    assert.equal(labelsOf(fake, 'u1'), undefined);
    assert.equal(fake.calls.filter((c) => c.path.endsWith('/labels')).length, 0);
  });

  it('does not fail the write when the labels call does', async () => {
    // The row is already written; reporting a write that happened as one
    // that did not would be the worse answer. It is logged instead.
    const fake = fakeAppwrite({
      rows: { profiles: { u1: profile({ role: 'admin' }), u2: profile({ $id: 'u2' }) } },
      fail: { '/labels': { status: 401, body: { message: 'missing scope (users.write)' } } },
    });
    const ctx = context({
      op: 'update', collection: 'profiles', documentId: 'u2', data: { role: 'ewr', isApproved: true },
    });
    await write(ctx);

    assert.equal(ctx.captured.status, 200);
    assert.equal(fake.store.profiles.u2.role, 'ewr');
    assert.match(ctx.logs.join('\n'), /WARNING: profile u2 was updated but its account labels were not/);
  });
});

describe('authorities', () => {
  it('refuses a contact whose LGA names no state', async () => {
    const fake = fakeAppwrite({ rows: { profiles: { u1: profile({ role: 'admin' }) } } });
    const ctx = context({
      op: 'create', collection: 'authorities', documentId: 'a1',
      data: { name: 'Obi Desk', phone: '+2348031234567', coverageLga: 'Obi' },
    });
    await write(ctx);

    assert.equal(ctx.captured.status, 400);
    assert.match(ctx.captured.body.message, /must name its state/);
    assert.equal(fake.store.authorities?.a1, undefined);
  });

  it('refuses an edit that moves the LGA out of the stored state', async () => {
    // The patch alone looks fine — it is the row it would produce that is
    // wrong, so the check runs against current + patch.
    const fake = fakeAppwrite({
      rows: {
        profiles: { u1: profile({ role: 'admin' }) },
        authorities: {
          a1: { $id: 'a1', name: 'Obi Desk', phone: '+2348031234567', coverageState: 'Benue', coverageLga: 'Obi' },
        },
      },
    });
    const ctx = context({
      op: 'update', collection: 'authorities', documentId: 'a1',
      data: { coverageLga: 'Lafia' },
    });
    await write(ctx);

    assert.equal(ctx.captured.status, 400);
    assert.match(ctx.captured.body.message, /Unknown LGA/);
    assert.equal(fake.store.authorities.a1.coverageLga, 'Obi');
  });

  it('accepts the same LGA name in either of its states', async () => {
    const fake = fakeAppwrite({ rows: { profiles: { u1: profile({ role: 'admin' }) } } });
    for (const [documentId, coverageState] of [['a1', 'Benue'], ['a2', 'Nasarawa']]) {
      const ctx = context({
        op: 'create', collection: 'authorities', documentId,
        data: { name: 'Obi Desk', phone: '+2348031234567', coverageState, coverageLga: 'Obi' },
      });
      await write(ctx);
      assert.equal(ctx.captured.status, 200, coverageState);
      assert.equal(fake.store.authorities[documentId].coverageState, coverageState);
    }
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

describe('the optimistic lock', () => {
    const world = () => ({
        rows: {
            profiles: { admin1: profile({ role: 'admin' }) },
            reports: {
                r1: {
                    $id: 'r1',
                    status: 'pending',
                    userId: 'someone',
                    state: 'Benue',
                    lga: 'Makurdi',
                    ward: 'North Bank I',
                },
            },
        },
    });

    const decide = (expect) => ({
        op: 'update',
        collection: 'reports',
        documentId: 'r1',
        data: { status: 'approved' },
        ...(expect ? { expect } : {}),
    });

    it('applies the edit when the expected value still holds', async () => {
        const fake = fakeAppwrite(world());
        const ctx = context(decide({ status: 'pending' }), { userId: 'admin1' });
        await write(ctx);
        assert.equal(ctx.captured.status, 200);
        assert.equal(fake.store.reports.r1.status, 'approved');
    });

    it('refuses, and changes nothing, when it does not', async () => {
        // Somebody else decided the report while the card was on screen.
        const w = world();
        w.rows.reports.r1.status = 'rejected';
        const fake = fakeAppwrite(w);
        const ctx = context(decide({ status: 'pending' }), { userId: 'admin1' });
        await write(ctx);
        assert.equal(ctx.captured.status, 409);
        assert.equal(fake.store.reports.r1.status, 'rejected');
    });

    it('matches a null expectation', async () => {
        const fake = fakeAppwrite(world());
        const ctx = context(
            { ...decide({ status: 'pending', rejectionReason: null }) },
            { userId: 'admin1' },
        );
        await write(ctx);
        assert.equal(ctx.captured.status, 200);
        assert.equal(fake.store.reports.r1.status, 'approved');
    });

    it('is off unless asked for', async () => {
        const fake = fakeAppwrite(world());
        const ctx = context(decide(null), { userId: 'admin1' });
        await write(ctx);
        assert.equal(ctx.captured.status, 200);
        assert.equal(fake.store.reports.r1.status, 'approved');
    });

    it('pins a profile edit to the values the admin reviewed', async () => {
        const w = world();
        w.rows.profiles.u2 = profile({ role: 'user', lga: 'Makurdi', ward: 'North Bank I' });
        const fake = fakeAppwrite(w);
        const promote = (expected) => ({
            op: 'update',
            collection: 'profiles',
            documentId: 'u2',
            data: { role: 'ewm' },
            expect: expected,
        });

        const stale = context(promote({ role: 'ewr' }), { userId: 'admin1' });
        await write(stale);
        assert.equal(stale.captured.status, 409);
        assert.equal(fake.store.profiles.u2.role, 'user');

        const fresh = context(promote({ role: 'user' }), { userId: 'admin1' });
        await write(fresh);
        assert.equal(fresh.captured.status, 200);
        assert.equal(fake.store.profiles.u2.role, 'ewm');
    });
});

describe('deciding a report', () => {
    // `guard_report_update()`, carried over from Postgres. Each clause is a
    // different rule, so each gets its own case.
    const world = (role, overrides = {}) => ({
        rows: {
            profiles: { me: profile({ role }) },
            reports: {
                r1: {
                    $id: 'r1',
                    status: 'pending',
                    userId: 'someone-else',
                    severity: 'low',
                    state: 'Benue',
                    lga: 'Makurdi',
                    ward: 'North Bank I',
                    ...overrides,
                },
            },
        },
    });

    const edit = (data) => ({ op: 'update', collection: 'reports', documentId: 'r1', data });

    async function run(role, data, overrides) {
        const fake = fakeAppwrite(world(role, overrides));
        const ctx = context(edit(data), { userId: 'me' });
        await write(ctx);
        return { status: ctx.captured.status, row: fake.store.reports.r1, body: ctx.captured.body };
    }

    it('lets a reviewer approve, and actually writes the status', async () => {
        // The bug this covers: `status` is server-owned at creation, and
        // stripping it from updates too made every approval a silent no-op
        // that still answered 200.
        for (const role of ['ewv', 'ewr', 'ldp_coordinator', 'project_staff', 'admin']) {
            const { status, row } = await run(role, { status: 'approved' });
            assert.equal(status, 200, role);
            assert.equal(row.status, 'approved', role);
        }
    });

    it('refuses a role that may not decide', async () => {
        for (const role of ['user', 'ewm']) {
            const { status, row } = await run(role, { status: 'approved' });
            assert.equal(status, 403, role);
            assert.equal(row.status, 'pending', role);
        }
    });

    it('refuses deciding your own report unless you are an admin', async () => {
        const mine = { userId: 'me' };
        const refused = await run('ewr', { status: 'approved' }, mine);
        assert.equal(refused.status, 403);
        assert.equal(refused.row.status, 'pending');

        const allowed = await run('admin', { status: 'approved' }, mine);
        assert.equal(allowed.status, 200);
        assert.equal(allowed.row.status, 'approved');
    });

    it('keeps the peer tally out of reach', async () => {
        for (const data of [
            { verificationCount: 9 },
            { verifiedAt: '2026-01-01T00:00:00.000Z' },
            { autoValidated: true },
            { status: 'verified' },
        ]) {
            const { status } = await run('ewr', data);
            assert.equal(status, 403, JSON.stringify(data));
        }
        const { status } = await run('admin', { verificationCount: 9 });
        assert.equal(status, 200);
    });

    it('keeps ownership and escalation for admins', async () => {
        for (const data of [{ escalated: true }, { escalationStatus: 'processed' }]) {
            assert.equal((await run('ewr', data)).status, 403, JSON.stringify(data));
            assert.equal((await run('admin', data)).status, 200, JSON.stringify(data));
        }
    });

    it('re-derives isAlert from the severity, as the trigger did', async () => {
        const raised = await run('admin', { severity: 'critical' });
        assert.equal(raised.row.isAlert, true);

        const lowered = await run('admin', { severity: 'low' }, { severity: 'critical', isAlert: true });
        assert.equal(lowered.row.isAlert, false);
    });

    it('still refuses a claimed status at creation', async () => {
        // The create path must keep stripping it: `decidable` is about
        // updates only.
        const fake = fakeAppwrite({ rows: { profiles: { me: profile({ role: 'user' }) } } });
        const ctx = context(
            {
                op: 'create',
                collection: 'reports',
                documentId: 'r2',
                data: {
                    hazardType: 'flood',
                    description: 'x',
                    state: 'Benue',
                    lga: 'Makurdi',
                    ward: 'North Bank I',
                    severity: 'high',
                    status: 'approved',
                    verificationCount: 99,
                },
            },
            { userId: 'me' },
        );
        await write(ctx);
        assert.equal(ctx.captured.status, 200);
        assert.equal(fake.store.reports.r2.status, 'pending');
        assert.equal(fake.store.reports.r2.verificationCount, 0);
    });
});

/**
 * The rest of `guard_report_update()`, ported from `supabase/deploy/schema.sql`.
 *
 * These rules were in the Postgres trigger and not in the first port, so
 * the Function enforced about half of it. Each test below names the
 * `raise exception` it stands for; the wording is derived from the SQL,
 * not from the JavaScript, so a port that drifts fails here.
 */
describe('the rules the Postgres guard had and the port had not', () => {
  const pendingReport = (over = {}) => ({
    $id: 'r1',
    status: 'pending',
    userId: 'owner',
    hazardType: 'flood',
    description: 'Water over the road',
    state: 'Benue',
    lga: 'Makurdi',
    ward: 'North Bank I',
    ...over,
  });

  const world = (role, report = pendingReport(), rows = {}) =>
    fakeAppwrite({
      rows: {
        profiles: { u1: profile({ role }) },
        reports: { r1: report },
        ...rows,
      },
    });

  const patch = async (data, { role = 'ewr', userId = 'u1' } = {}) => {
    const ctx = context(
      { op: 'update', collection: 'reports', documentId: 'r1', data },
      { userId },
    );
    await write(ctx);
    return ctx.captured;
  };

  describe("'Use reopen_report() to move a report back to pending'", () => {
    it('refuses a bare status write back to pending', async () => {
      // Reopening clears the votes, reschedules escalation and
      // supersedes the queued notifications. A PATCH does none of that,
      // so a report reopened this way keeps the votes it was decided on
      // and re-escalates immediately on a count that is no longer true.
      const fake = world('ewr', pendingReport({ status: 'approved' }));
      const out = await patch({ status: 'pending' });

      assert.equal(out.status, 403);
      assert.match(out.body.message, /reopen/i);
      assert.equal(fake.store.reports.r1.status, 'approved');
    });

    it('refuses it for an admin too, who also has the operation', async () => {
      // Postgres refused this before it looked at the role.
      world('admin', pendingReport({ status: 'rejected' }));
      assert.equal((await patch({ status: 'pending' })).status, 403);
    });

    it('allows a write that leaves a pending report pending', async () => {
      // `pending → pending` is not a reopen, and an edit that happens to
      // resend the status must still go through.
      world('admin', pendingReport());
      assert.equal((await patch({ status: 'pending', severity: 'high' })).status, 200);
    });
  });

  describe("'Only the reporter can edit a report\\'s details'", () => {
    it('refuses a reviewer rewriting somebody else’s description', async () => {
      const fake = world('ewr', pendingReport({ userId: 'someone-else' }));
      const out = await patch({ description: 'Rewritten by a reviewer' });

      assert.equal(out.status, 403);
      assert.match(out.body.message, /reporter/i);
      assert.equal(fake.store.reports.r1.description, 'Water over the road');
    });

    it('lets the reporter edit their own pending report', async () => {
      world('user', pendingReport({ userId: 'u1' }));
      assert.equal((await patch({ description: 'Now knee deep' })).status, 200);
    });

    it('lets an admin edit anybody’s', async () => {
      world('admin', pendingReport({ userId: 'someone-else' }));
      assert.equal((await patch({ description: 'Corrected' })).status, 200);
    });
  });

  describe("'A report can only be edited while it is pending'", () => {
    it('refuses the reporter editing their own approved report', async () => {
      // A staff reporter passes the role check at any status, so this is
      // the only thing keeping a decided report from being rewritten
      // after the fact.
      const fake = world('ewr', pendingReport({ userId: 'u1', status: 'approved' }));
      const out = await patch({ description: 'Quietly changed after approval' });

      assert.equal(out.status, 403);
      assert.match(out.body.message, /pending/i);
      assert.equal(fake.store.reports.r1.description, 'Water over the road');
    });
  });

  describe("'A report cannot be edited after peers have voted on it'", () => {
    it('refuses an edit once a vote exists', async () => {
      const fake = world('user', pendingReport({ userId: 'u1' }), {
        verifications: { v1: { $id: 'v1', reportId: 'r1', isConfirmed: true } },
      });
      const out = await patch({ description: 'Changed under the voters' });

      assert.equal(out.status, 403);
      assert.match(out.body.message, /voted/i);
      assert.equal(fake.store.reports.r1.description, 'Water over the road');
    });

    it('counts a dispute as a vote', async () => {
      // A dispute is still somebody who read what is about to change.
      world('user', pendingReport({ userId: 'u1' }), {
        verifications: { v1: { $id: 'v1', reportId: 'r1', isConfirmed: false } },
      });
      assert.equal((await patch({ description: 'Changed' })).status, 403);
    });

    it('ignores votes cast on another report', async () => {
      world('user', pendingReport({ userId: 'u1' }), {
        verifications: { v1: { $id: 'v1', reportId: 'other', isConfirmed: true } },
      });
      assert.equal((await patch({ description: 'Changed' })).status, 200);
    });

    it('does not ask when the edit is a decision rather than content', async () => {
      // An approval is not a content edit, and a report being approved
      // has votes almost by definition.
      world('ewr', pendingReport({ userId: 'someone-else' }), {
        verifications: { v1: { $id: 'v1', reportId: 'r1', isConfirmed: true } },
      });
      assert.equal((await patch({ status: 'approved' })).status, 200);
    });
  });

  describe('the admin-only escalation fields the port had missed', () => {
    for (const field of ['escalationReason', 'escalationScheduledAt']) {
      it(`refuses a non-admin changing ${field}`, async () => {
        const fake = world('ewr', pendingReport({ userId: 'someone-else' }));
        const out = await patch({ [field]: '2030-01-01T00:00:00.000Z' });

        assert.equal(out.status, 403, field);
        assert.equal(fake.store.reports.r1[field], undefined);
      });
    }
  });

  describe('the decision columns follow the status, as the trigger made them', () => {
    it('clears the rejection when a report is approved', async () => {
      // Otherwise an approved report still carries the reason it was
      // turned down with, and the app shows both.
      const fake = world('ewr', pendingReport({
        userId: 'someone-else',
        status: 'rejected',
        rejectedAt: '2026-01-01T00:00:00.000Z',
        rejectionReason: 'Not credible',
      }));
      assert.equal((await patch({ status: 'approved' })).status, 200);

      const r = fake.store.reports.r1;
      assert.equal(r.rejectedAt, null);
      assert.equal(r.rejectionReason, null);
      assert.ok(r.approvedAt, 'approvedAt is stamped');
    });

    it('clears the approval when a report is rejected', async () => {
      const fake = world('ewr', pendingReport({
        userId: 'someone-else',
        status: 'approved',
        approvedAt: '2026-01-01T00:00:00.000Z',
      }));
      assert.equal((await patch({ status: 'rejected', rejectionReason: 'Duplicate' })).status, 200);

      assert.equal(fake.store.reports.r1.approvedAt, null);
      assert.ok(fake.store.reports.r1.rejectedAt);
    });

    it('keeps a timestamp the caller chose', async () => {
      // `coalesce(new.approved_at, now())`: the panel may send its own.
      const fake = world('admin', pendingReport({ userId: 'someone-else' }));
      await patch({ status: 'approved', approvedAt: '2026-05-05T05:05:00.000Z' });
      assert.equal(fake.store.reports.r1.approvedAt, '2026-05-05T05:05:00.000Z');
    });
  });
});

/**
 * `alerts_target_lga_needs_state`, on an update as well as a create.
 *
 * The CHECK constraint applied to every write. The port asserted it on
 * the create branch only, so an alert could be retargeted afterwards to
 * an LGA with no state — and two Nigerian states have an Obi.
 */
describe('an alert’s target is validated when it is edited', () => {
  const alert = {
    $id: 'a1',
    title: 'Flood warning',
    targetState: 'Benue',
    targetLga: 'Obi',
    createdBy: 'u1',
  };
  const edit = async (data) => {
    const ctx = context({ op: 'update', collection: 'alerts', documentId: 'a1', data });
    await write(ctx);
    return ctx.captured;
  };

  it('refuses an edit that drops the state from a targeted LGA', async () => {
    const fake = fakeAppwrite({
      rows: { profiles: { u1: profile({ role: 'admin' }) }, alerts: { a1: { ...alert } } },
    });
    const out = await edit({ targetState: '' });

    assert.equal(out.status, 400);
    assert.match(out.body.message, /state/i);
    assert.equal(fake.store.alerts.a1.targetState, 'Benue');
  });

  it('refuses a move to an LGA the new state does not have', async () => {
    fakeAppwrite({
      rows: { profiles: { u1: profile({ role: 'admin' }) }, alerts: { a1: { ...alert } } },
    });
    // Obi is in Benue and in Nasarawa; Makurdi is in neither but Benue.
    const out = await edit({ targetState: 'Nasarawa', targetLga: 'Makurdi' });
    assert.equal(out.status, 400);
  });

  it('checks the row as it will be, not the patch alone', async () => {
    // Resending only the LGA has to be validated against the state
    // already stored, or every partial edit would look stateless.
    const fake = fakeAppwrite({
      rows: { profiles: { u1: profile({ role: 'admin' }) }, alerts: { a1: { ...alert } } },
    });
    assert.equal((await edit({ targetLga: 'Gwer East' })).status, 200);
    assert.equal(fake.store.alerts.a1.targetLga, 'Gwer East');
  });

  it('still allows an alert aimed at every LGA', async () => {
    fakeAppwrite({
      rows: { profiles: { u1: profile({ role: 'admin' }) }, alerts: { a1: { ...alert } } },
    });
    assert.equal((await edit({ targetLga: 'all' })).status, 200);
  });
});
