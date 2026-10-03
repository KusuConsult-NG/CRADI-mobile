/**
 * The typed-code auth flows, end to end.
 *
 *   source infra/appwrite/local/.env.local
 *   node infra/appwrite/local/e2e-auth.mjs
 *
 * Phase 2's whole design rests on one endpoint — a server-minted token
 * of any length we choose, so the app's six-digit code screens survive
 * instead of becoming email links. This exercises that for real: the
 * code has to arrive in an actual email, be typed back, and buy a
 * session.
 *
 * It also checks the property that is easy to lose and expensive to
 * lose: an address with no account must be indistinguishable from a
 * wrong code.
 */
import assert from 'node:assert/strict';

const EP = process.env.APPWRITE_ENDPOINT;
const PROJECT = process.env.APPWRITE_PROJECT_ID;
const KEY = process.env.APPWRITE_API_KEY;
const MAIL = process.env.MAILPIT ?? 'http://localhost:8025';

const admin = { 'content-type': 'application/json', 'x-appwrite-project': PROJECT, 'x-appwrite-key': KEY };
const anon = { 'content-type': 'application/json', 'x-appwrite-project': PROJECT };

const step = (m) => console.log(`\n── ${m}`);
const ok = (m) => console.log(`   ✓ ${m}`);

async function call(path, { method = 'GET', body, headers = admin } = {}) {
  const r = await fetch(`${EP}${path}`, {
    method, headers, body: body === undefined ? undefined : JSON.stringify(body),
  });
  const t = await r.text();
  let b = null;
  if (t) { try { b = JSON.parse(t); } catch { b = { message: t }; } }
  return { status: r.status, ok: r.ok, body: b };
}

/** Calls the auth Function and returns {status, body}. */
async function auth(payload, headers = anon) {
  const exec = await call('/functions/client/executions', {
    method: 'POST',
    headers,
    body: { body: JSON.stringify(payload), path: '/auth', async: false, method: 'POST' },
  });
  assert.ok(exec.ok, `execution refused: ${JSON.stringify(exec.body).slice(0, 200)}`);
  if (exec.body.status !== 'completed') {
    const seen = await call(`/functions/client/executions/${exec.body.$id}`);
    throw new Error(
      `auth(${payload.action}) ${exec.body.status}: ${(seen.body?.errors || '').slice(-400)}`,
    );
  }
  let parsed = {};
  try { parsed = JSON.parse(exec.body.responseBody || '{}'); } catch { /* empty */ }
  return { status: exec.body.responseStatusCode, body: parsed, id: exec.body.$id };
}

await fetch(`${MAIL}/api/v1/messages`, { method: 'DELETE' });

/**
 * The code out of the newest mail addressed to `address`.
 *
 * Two things here were assumptions that turned out wrong, and both are
 * worth stating because the app depends on them.
 *
 * Appwrite addresses a message to users via **Bcc**, not To, so a
 * recipient search on `to:` finds nothing even though the mail arrived.
 *
 * And the token is **not six digits**. `POST /users/{id}/tokens` with
 * `length: 6` mints six characters from an alphanumeric alphabet —
 * `fea844`, not `251152`. Phase 2 recorded a sample that happened to be
 * all digits and the whole design has said "6-digit code" since.
 */
async function codeFor(address) {
  for (let i = 0; i < 30; i++) {
    const list = await (await fetch(`${MAIL}/api/v1/messages?limit=50`)).json();
    const to = (m) =>
      [...(m.To ?? []), ...(m.Bcc ?? []), ...(m.Cc ?? [])].map((a) => a.Address);
    const found = (list.messages ?? []).find((m) => to(m).includes(address));
    if (found) {
      const full = await (await fetch(`${MAIL}/api/v1/message/${found.ID}`)).json();
      const text = `${full.Text ?? ''} ${found.Snippet ?? ''}`;
      const m = /code is ([A-Za-z0-9]{4,10})\b/.exec(text);
      if (m) return { code: m[1], subject: found.Subject, text };
    }
    await new Promise((r2) => setTimeout(r2, 1000));
  }
  return null;
}

const stamp = Date.now();
const email = `signup-${stamp}@example.test`;
const password = 'FirstPassword123!';

// ─── registration ─────────────────────────────────────────────────────
step('register — the Function creates the account, the profile and mails a code');
const signUp = await auth({
  action: 'signUp',
  email,
  password,
  metadata: {
    name: 'Typed Code User', role: 'ewm', phone: '08031234567',
    state: 'Benue', lga: 'Makurdi', ward: 'North Bank I', address: 'Somewhere',
  },
});
assert.equal(signUp.status, 200, JSON.stringify(signUp.body));
// No session yet: the user types the code next, as on Supabase.
assert.deepEqual(signUp.body, {});
ok('200, and no session returned');

step('the profile exists, requested role recorded, approval withheld');
const users = await call(
  `/users?queries[]=${encodeURIComponent(JSON.stringify({ method: 'equal', attribute: 'email', values: [email] }))}`,
);
assert.equal(users.body.users.length, 1, 'account not created');
const userId = users.body.users[0].$id;
const profile = await call(`/tablesdb/${process.env.APPWRITE_DATABASE_ID ?? 'cradi'}/tables/profiles/rows/${userId}`);
assert.ok(profile.ok, 'profile row missing');
assert.equal(profile.body.role, 'ewm', 'requested role recorded');
assert.equal(profile.body.isApproved, false, 'approval must not be self-granted');
assert.equal(profile.body.isVerified, false);
ok(`profile ${userId}: role=ewm isApproved=false`);

step('the code arrives by email');
const mail = await codeFor(email);
assert.ok(mail, 'no email arrived');
assert.match(mail.subject, /verification code/i);
assert.equal(mail.code.length, 6, 'six characters, as the Function asked for');
ok(`"${mail.subject}" -> ${mail.code}`);

step('a wrong code is refused');
const wrong = await auth({ action: 'verifySignUp', email, code: '000000' });
assert.equal(wrong.status, 401, JSON.stringify(wrong.body));
ok(`401 ${wrong.body.type ?? ''}`);

step('an address with no account is refused identically');
// Phase 2, risk 3: the response must not be an enumeration oracle.
const ghost = await auth({ action: 'verifySignUp', email: `ghost-${stamp}@example.test`, code: '000000' });
assert.equal(ghost.status, wrong.status);
assert.deepEqual(ghost.body, wrong.body, 'unknown address and wrong code must read the same');
ok(`identical: ${JSON.stringify(ghost.body)}`);

step('the real code buys a session');
const verified = await auth({ action: 'verifySignUp', email, code: mail.code });
assert.equal(verified.status, 200, JSON.stringify(verified.body));
assert.ok(verified.body.sessionSecret, 'no session secret returned');
ok('sessionSecret returned');

step('the session works, and the address is now verified');
const me = await call('/account', {
  headers: { ...anon, 'x-appwrite-session': verified.body.sessionSecret },
});
assert.ok(me.ok, `account: ${JSON.stringify(me.body).slice(0, 200)}`);
assert.equal(me.body.$id, userId);
assert.equal(me.body.emailVerification, true, 'verification not set');
ok(`signed in as ${me.body.$id}, emailVerification=true`);

// ─── recovery ─────────────────────────────────────────────────────────
step('recovery says nothing about who exists');
await fetch(`${MAIL}/api/v1/messages`, { method: 'DELETE' });
const known = await auth({ action: 'sendRecoveryCode', email });
const unknown = await auth({ action: 'sendRecoveryCode', email: `nobody-${stamp}@example.test` });
assert.equal(known.status, unknown.status);
assert.deepEqual(known.body, unknown.body);
ok(`both ${known.status} ${JSON.stringify(known.body)}`);

step('only the real address was mailed');
const recovery = await codeFor(email);
assert.ok(recovery, 'no recovery mail');
assert.match(recovery.subject, /reset code/i);
const everything = await (await fetch(`${MAIL}/api/v1/messages?limit=50`)).json();
const ghostMail = (everything.messages ?? []).filter((m) =>
  [...(m.To ?? []), ...(m.Bcc ?? []), ...(m.Cc ?? [])].some((a) =>
    a.Address.startsWith(`nobody-${stamp}`),
  ),
);
assert.equal(ghostMail.length, 0, 'mailed an address with no account');
ok(`"${recovery.subject}" -> ${recovery.code}; nothing sent to the unknown address`);

step('the recovery code sets a new password');
const recovered = await auth({ action: 'verifyRecovery', email, code: recovery.code });
assert.equal(recovered.status, 200, JSON.stringify(recovered.body));
const recoverySession = { ...anon, 'x-appwrite-session': recovered.body.sessionSecret };

// Before the real change, not after: setting a password revokes the
// sessions that could set it, so a second attempt on the same session
// is a 401 and tells you nothing about the policy.
const weak = await auth({ action: 'setPassword', password: 'short' }, recoverySession);
assert.equal(weak.status, 400, JSON.stringify(weak.body));
assert.equal(weak.body.type, 'general_password_weak');
ok(`a weak password is refused: 400 ${weak.body.type}`);

const set = await auth({ action: 'setPassword', password: 'SecondPassword456!' }, recoverySession);
assert.equal(set.status, 200, JSON.stringify(set.body));
ok('password changed through the recovery session');

step('the new password works and the old one does not');
const fresh = await call('/account/sessions/email', {
  method: 'POST', headers: anon, body: { email, password: 'SecondPassword456!' },
});
assert.ok(fresh.ok, `new password refused: ${JSON.stringify(fresh.body).slice(0, 150)}`);
const stale = await call('/account/sessions/email', {
  method: 'POST', headers: anon, body: { email, password },
});
assert.ok(!stale.ok, 'the old password still works');
assert.equal(stale.status, 401);
ok('new password accepted, old one 401');

console.log('\nAUTH END TO END: PASS');
