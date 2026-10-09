import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import auth from '../src/auth.js';
import { context, fakeAppwrite } from './helpers.mjs';

const call = async (body, opts) => {
  const ctx = context(body, { userId: null, ...opts });
  await auth(ctx);
  return ctx.captured;
};

describe('registration', () => {
  it('creates the account and the profile, and sends a code', async () => {
    const fake = fakeAppwrite();
    const out = await call({
      action: 'signUp',
      email: ' Amina@Example.COM ',
      password: 'Password1!',
      metadata: { name: 'Amina', role: 'ewm', ward: 'North Bank I' },
    });

    assert.equal(out.status, 200);
    // No session: the user types the emailed code next.
    assert.deepEqual(out.body, {});
    assert.equal(fake.users[0].email, 'amina@example.com');

    const profile = Object.values(fake.store.profiles)[0];
    assert.equal(profile.name, 'Amina');
    // The requested role is recorded and grants nothing.
    assert.equal(profile.role, 'ewm');
    assert.equal(profile.isApproved, false);
    assert.equal(profile.isVerified, false);

    // One call that mints and mails, not a mint plus a Messaging send.
    assert.ok(fake.calls.some((c) => c.path === '/account/tokens/email' && c.method === 'POST'));
  });

  it('never lets the client decide its own approval', async () => {
    const fake = fakeAppwrite();
    await call({
      action: 'signUp',
      email: 'a@b.com',
      password: 'Password1!',
      metadata: { name: 'A', role: 'admin', isApproved: true, isDisabled: false },
    });
    const profile = Object.values(fake.store.profiles)[0];
    assert.equal(profile.isApproved, false);
  });

  it('answers a duplicate address as one', async () => {
    fakeAppwrite({ users: [{ $id: 'u1', email: 'a@b.com' }] });
    const out = await call({
      action: 'signUp', email: 'a@b.com', password: 'Password1!', metadata: {},
    });
    assert.equal(out.status, 409);
    assert.equal(out.body.type, 'user_already_exists');
  });

  it('refuses something that is not an address', async () => {
    fakeAppwrite();
    const out = await call({
      action: 'signUp', email: 'not-an-address', password: 'x', metadata: {},
    });
    assert.equal(out.status, 400);
  });

  it('reports a code that was minted but not delivered', async () => {
    // Silence here leaves the user waiting for a code that will never
    // arrive, which reads to them as the app being broken.
    fakeAppwrite({
      fail: { '/account/tokens/email': { status: 500, body: { message: 'smtp down' } } },
    });
    const out = await call({
      action: 'signUp', email: 'a@b.com', password: 'Password1!', metadata: {},
    });
    assert.equal(out.status, 502);
  });
});

describe('recovery does not say who exists', () => {
  it('answers the same for a known and an unknown address', async () => {
    fakeAppwrite({ users: [{ $id: 'u1', email: 'known@b.com' }] });
    const known = await call({ action: 'sendRecoveryCode', email: 'known@b.com' });

    fakeAppwrite({ users: [] });
    const unknown = await call({ action: 'sendRecoveryCode', email: 'nobody@b.com' });

    assert.equal(known.status, unknown.status);
    assert.deepEqual(known.body, unknown.body);
  });

  it('never lets the minted code reach the log or the response', async () => {
    // New hazard with `/account/tokens/email`: called with an API key it
    // answers with the `secret` it just mailed. The old mint did too, but
    // the code then had to travel through this Function into an email
    // body, so a stray log line was plausible. It no longer needs to be
    // touched at all — and the fake returns one so this cannot pass
    // vacuously.
    fakeAppwrite({ users: [{ $id: 'u1', email: 'known@b.com' }] });
    const ctx = context(
      { action: 'sendRecoveryCode', email: 'known@b.com' },
      { userId: null },
    );
    await auth(ctx);

    assert.equal(ctx.captured.status, 200);
    assert.ok(
      !JSON.stringify(ctx.captured.body).includes('251152'),
      `the code is in the response: ${JSON.stringify(ctx.captured.body)}`,
    );
    assert.ok(
      !ctx.logs.some((l) => l.includes('251152')),
      `the code is in the log: ${JSON.stringify(ctx.logs)}`,
    );
  });

  it('logs why the mail failed, and still tells the caller nothing', async () => {
    fakeAppwrite({
      users: [{ $id: 'u1', email: 'known@b.com' }],
      fail: {
        '/account/tokens/email': {
          status: 400,
          body: { message: 'mail server refused the sender', type: 'general_smtp_disabled' },
        },
      },
    });
    // Its own context: the reason is in the log, and that is the point —
    // every reason Appwrite can give answers the caller identically, so
    // the log is the only place the difference survives.
    const ctx = context(
      { action: 'sendRecoveryCode', email: 'known@b.com' },
      { userId: null },
    );
    await auth(ctx);

    assert.equal(ctx.captured.status, 502);
    assert.ok(!JSON.stringify(ctx.captured.body).includes('mail server'));
    assert.ok(
      ctx.logs.some(
        (l) => l.includes('recovery email send failed: 400')
          && l.includes('mail server refused the sender'),
      ),
      `reason not logged: ${JSON.stringify(ctx.logs)}`,
    );
  });

  it('mints nothing for an address with no account', async () => {
    const fake = fakeAppwrite({ users: [] });
    await call({ action: 'sendRecoveryCode', email: 'nobody@b.com' });
    // Not merely "no mail sent": `/account/tokens/email` CREATES an
    // account for an address it does not know, so reaching it at all
    // would leave a passwordless account behind AND leak that the
    // address was new. Never calling it is the property under test.
    assert.equal(fake.calls.filter((c) => c.path === '/account/tokens/email').length, 0);
  });

  it('and the resend is just as quiet', async () => {
    const fake = fakeAppwrite({ users: [] });
    const out = await call({ action: 'resendSignUpCode', email: 'nobody@b.com' });
    assert.equal(out.status, 200);
    assert.equal(fake.calls.filter((c) => c.path === '/account/tokens/email').length, 0);
  });
});

describe('redeeming a typed code', () => {
  it('returns a session the client can set, not a user id', async () => {
    // Handing out a userId in exchange for an address would be an
    // enumeration oracle, which is the whole reason the exchange happens
    // server-side.
    fakeAppwrite({ users: [{ $id: 'u1', email: 'a@b.com' }] });
    const out = await call({ action: 'verifySignUp', email: 'a@b.com', code: '251152' });

    assert.equal(out.status, 200);
    assert.equal(out.body.sessionSecret, 'session-secret');
  });

  it('marks the address verified, but only after the code proved it', async () => {
    const fake = fakeAppwrite({ users: [{ $id: 'u1', email: 'a@b.com' }] });
    await call({ action: 'verifySignUp', email: 'a@b.com', code: '251152' });

    const verify = fake.calls.findIndex((c) => c.path === '/users/u1/verification');
    const session = fake.calls.findIndex((c) => c.path === '/account/sessions/token');
    assert.ok(session >= 0 && session < verify,
      'the code must be redeemed before the address is trusted');
  });

  it('a recovery session is not a verification', async () => {
    const fake = fakeAppwrite({ users: [{ $id: 'u1', email: 'a@b.com' }] });
    await call({ action: 'verifyRecovery', email: 'a@b.com', code: '251152' });
    assert.ok(!fake.calls.some((c) => c.path === '/users/u1/verification'));
  });

  it('a wrong code and an unknown address read identically', async () => {
    fakeAppwrite({
      users: [{ $id: 'u1', email: 'a@b.com' }],
      fail: { '/account/sessions/token': { status: 401, body: { message: 'bad' } } },
    });
    const wrongCode = await call({ action: 'verifySignUp', email: 'a@b.com', code: '000000' });

    fakeAppwrite({ users: [] });
    const noAccount = await call({ action: 'verifySignUp', email: 'ghost@b.com', code: '251152' });

    assert.equal(wrongCode.status, 401);
    assert.deepEqual(wrongCode.body, noAccount.body);
  });

  it('fails loudly if the session comes back without a secret', async () => {
    // That means the API key was not attached or lost its scopes.
    // Returning a session the client cannot use would look like success.
    fakeAppwrite({
      users: [{ $id: 'u1', email: 'a@b.com' }],
      fail: { '/account/sessions/token': { status: 201, body: { $id: 's1' } } },
    });
    const out = await call({ action: 'verifySignUp', email: 'a@b.com', code: '251152' });
    assert.equal(out.status, 500);
  });
});

describe('setting a password after recovery', () => {
  it('sets it for the caller, from the header', async () => {
    const fake = fakeAppwrite();
    const out = await call(
      { action: 'setPassword', password: 'Password1!', userId: 'somebody-else' },
      { userId: 'u1' },
    );
    assert.equal(out.status, 200);
    const patch = fake.calls.find((c) => c.path.endsWith('/password'));
    assert.equal(patch.path, '/users/u1/password');
  });

  it('refuses without a session', async () => {
    fakeAppwrite();
    const out = await call({ action: 'setPassword', password: 'Password1!' });
    assert.equal(out.status, 401);
  });

  it('refuses a short password with the condition the app understands', async () => {
    fakeAppwrite();
    const out = await call({ action: 'setPassword', password: 'short' }, { userId: 'u1' });
    assert.equal(out.status, 400);
    assert.equal(out.body.type, 'general_password_weak');
  });
});

describe('the throttle that used to be a dashboard setting', () => {
  it('refuses a fourth code inside the window', async () => {
    const recent = new Date().toISOString();
    fakeAppwrite({
      users: [{ $id: 'u1', email: 'a@b.com' }],
      fail: {
        '/users/u1/tokens': {
          status: 200,
          body: {
            tokens: [
              { $createdAt: recent }, { $createdAt: recent }, { $createdAt: recent },
            ],
          },
        },
      },
    });
    const out = await call({ action: 'resendSignUpCode', email: 'a@b.com' });
    assert.equal(out.status, 429);
    assert.equal(out.body.type, 'general_rate_limit_exceeded');
  });

  it('ignores codes older than the window', async () => {
    const old = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    fakeAppwrite({
      users: [{ $id: 'u1', email: 'a@b.com' }],
      fail: {
        '/users/u1/tokens': {
          status: 200,
          body: { tokens: [{ $createdAt: old }, { $createdAt: old }, { $createdAt: old }] },
        },
      },
    });
    const out = await call({ action: 'resendSignUpCode', email: 'a@b.com' });
    assert.equal(out.status, 200);
  });
});

describe('the envelope', () => {
  it('refuses an unknown action rather than doing nothing quietly', async () => {
    fakeAppwrite();
    const out = await call({ action: 'deleteEverything' });
    assert.equal(out.status, 400);
  });

  it('refuses a body that is not JSON', async () => {
    fakeAppwrite();
    const ctx = context({}, { userId: null });
    ctx.req.bodyRaw = 'not json';
    await auth(ctx);
    assert.equal(ctx.captured.status, 400);
  });
});

/**
 * A registration that half-succeeds.
 *
 * The account and the profile are two writes with no transaction
 * between them. If the second fails the first has already happened,
 * and an account with no profile is worse than no account at all:
 * every rule in the system reads the profile, so the user can do
 * nothing — and registering again answers "This account is already
 * registered. Please login.", which is a dead end only an
 * administrator with console access can open.
 */
describe('a registration that fails halfway', () => {
  it('removes the account when the profile cannot be written', async () => {
    const fake = fakeAppwrite({
      fail: {
        'POST /tables/profiles/rows': {
          status: 500,
          body: { message: 'storage is down', type: 'general_unknown' },
        },
      },
    });
    const out = await call({
      action: 'signUp',
      email: 'amina@example.com',
      password: 'Password1!',
      metadata: { name: 'Amina' },
    });

    assert.notEqual(out.status, 200);
    // The address is free again, which is the whole point.
    assert.deepEqual(fake.users, []);
    assert.ok(
      fake.calls.some((c) => c.method === 'DELETE' && /^\/users\/[^/]+$/.test(c.path)),
      'the account was deleted',
    );
    // And no code was sent for an account that no longer exists.
    assert.ok(!fake.calls.some((c) => c.path === '/account/tokens/email'));
  });

  it('lets the address be registered again afterwards', async () => {
    // The failure this is really about. One fake across both attempts,
    // so the second really is retrying against the first one's
    // leftovers — a fresh fake would reset the account list and assert
    // nothing.
    const fake = fakeAppwrite({
      fail: {
        'POST /tables/profiles/rows': { status: 500, body: { message: 'down' }, times: 1 },
      },
    });
    const first = await call({ action: 'signUp', email: 'a@b.com', password: 'Password1!' });
    assert.notEqual(first.status, 200);

    const retry = await call({ action: 'signUp', email: 'a@b.com', password: 'Password1!' });
    assert.equal(retry.status, 200, JSON.stringify(retry.body));
    assert.equal(fake.users.length, 1);
    assert.equal(Object.keys(fake.store.profiles ?? {}).length, 1);
  });

  it('reports the write that failed, not the cleanup', async () => {
    // A rollback that itself fails must not replace the real reason.
    const fake = fakeAppwrite({
      fail: {
        'POST /tables/profiles/rows': { status: 500, body: { message: 'storage is down' } },
        'DELETE /users/': { status: 500, body: { message: 'users is down too' } },
      },
    });
    // Its own context, because the warning is in the log rather than in
    // the response — which is the point: nothing the caller sees can
    // say this happened.
    const ctx = context(
      { action: 'signUp', email: 'a@b.com', password: 'Password1!' },
      { userId: null },
    );
    await auth(ctx);
    const out = ctx.captured;

    assert.notEqual(out.status, 200);
    assert.ok(!JSON.stringify(out.body).includes('users is down too'));
    // Orphaned for real now, so it has to be in the log for a person:
    // nothing else in the system will ever mention this account again.
    assert.equal(fake.users.length, 1, 'the account is still there');
    assert.ok(
      ctx.logs.some((l) => /WARNING: account .* has no profile/.test(l)),
      `no warning logged: ${JSON.stringify(ctx.logs)}`,
    );
  });
});
