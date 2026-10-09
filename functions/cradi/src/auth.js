/**
 * `auth` — every step that needs a server API key.
 *
 * Contract: docs/APPWRITE-FUNCTION-CONTRACTS.md.
 * Client: lib/core/services/appwrite/appwrite_auth_backend.dart.
 *
 * The whole design rests on a typed code, not a link:
 *
 *   POST /v1/account/tokens/email  {"userId": "...", "email": "..."}
 *     -> 201 {"userId": "...", "secret": "251152", "expire": "..."}
 *
 * A server-minted six-digit secret, which the user types and redeems for
 * a real session. That is what keeps the app's code screens instead of
 * rebuilding them as email links — and it deletes a class of bug this
 * project has already paid for once, because a design with no link in it
 * cannot send anybody to the wrong one.
 *
 * Phase 2 verified `POST /v1/users/{userId}/tokens` for this, which mints
 * a secret of any length and expiry we choose but does **not** send it —
 * delivery is the caller's. That half was Appwrite Messaging, which
 * refuses to send without an enabled provider, and project
 * 6ac51e70002ab6238fec has none: every reset failed with "We could not
 * send the code". `/account/tokens/email` mints *and* mails, through
 * Cloud's shared SMTP, so no provider is needed. See `sendCode`.
 */
import { Query, api, apiOrThrow, databaseId } from './lib/appwrite.js';
import {
  ErrorType,
  Refusal,
  handler,
  invalid,
  readJson,
  unauthorized,
} from './lib/http.js';

/**
 * Supabase threw this away per address and per project from a dashboard
 * setting. It is our code now, so it is written down: at most this many
 * codes to one address in this window.
 */
const MAX_CODES = 3;
const WINDOW_MS = 15 * 60 * 1000;

const ACTIONS = {
  signUp,
  resendSignUpCode,
  sendRecoveryCode,
  verifySignUp,
  verifyRecovery,
  setPassword,
};

export default handler(async (context) => {
  const payload = readJson(context.req);
  const action = ACTIONS[payload.action];
  if (!action) {
    throw invalid(`Unknown action: ${payload.action}`, ErrorType.argument);
  }
  return action(payload, context);
});

// ───────────────────────────── registration ─────────────────────────────

/**
 * Runs `step`, and deletes the account just created if it throws.
 *
 * Appwrite has no transaction across the account and its profile, so
 * this is the compensating write. A rollback that itself fails is
 * logged and swallowed: the caller's own failure is the one worth
 * reporting, and hiding it behind a cleanup error would say the
 * registration failed for the wrong reason.
 */
async function withAccountRollback(userId, log, step) {
  try {
    return await step();
  } catch (e) {
    try {
      // `api` answers with a result rather than throwing, so the status
      // has to be read. Without this check a 500 from the delete logged
      // "rolled back" for an account that is still there — a rollback
      // that reports success when it failed is worse than none.
      const removed = await api(`/users/${encodeURIComponent(userId)}`, { method: 'DELETE' });
      if (!removed.ok && removed.status !== 404) {
        throw new Error(`delete answered ${removed.status}`);
      }
      log(`rolled back account ${userId} after: ${e?.message ?? e}`);
    } catch (cleanup) {
      // Now it really is orphaned, and somebody has to know.
      log(
        `WARNING: account ${userId} has no profile and could not be removed ` +
          `(${cleanup?.message ?? cleanup}); it must be deleted by hand`,
      );
    }
    throw e;
  }
}

async function signUp({ email, password, metadata }, { log }) {
  const address = normaliseEmail(email);
  if (!address || !password) {
    throw invalid('An email and password are required', ErrorType.argument);
  }

  const created = await api('/users', {
    method: 'POST',
    body: { userId: 'unique()', email: address, password, name: metadata?.name ?? '' },
  });
  if (created.status === 409) {
    throw new Refusal(409, 'This account is already registered. Please login.',
      ErrorType.userExists);
  }
  if (created.status === 400) {
    throw new Refusal(400, created.body?.message ?? 'That email was refused',
      ErrorType.argument);
  }
  if (!created.ok) throw new Error(`user create failed: ${created.status}`);

  const userId = created.body.$id;

  // The profile is Function-written for the reason Phase 1 gives: role,
  // approval and ward are the inputs to every other rule in the system.
  // `role` here is a *request* — it grants nothing until an admin
  // approves — and `isApproved` starts false whatever the client sent.
  //
  // Wrapped, because the account above already exists. A profile write
  // that fails leaves an account nobody can use and nobody can replace:
  // every rule reads the profile, and registering again answers "This
  // account is already registered. Please login." — so the address is
  // spent and the only way out is an administrator with console access.
  // Undoing the account turns that dead end back into a retry.
  await withAccountRollback(userId, log, () =>
    apiOrThrow(`/tablesdb/${databaseId()}/tables/profiles/rows`, {
      method: 'POST',
      body: {
        rowId: userId,
        data: {
          name: metadata?.name ?? '',
          role: metadata?.role ?? 'user',
          phone: metadata?.phone ?? '',
          state: metadata?.state ?? '',
          lga: metadata?.lga ?? '',
          ward: metadata?.ward ?? '',
          address: metadata?.address ?? '',
          isApproved: false,
          isVerified: false,
          isDisabled: false,
        },
        permissions: [
          `read("user:${userId}")`,
          'read("label:admin")',
          'read("label:techSupport")',
        ],
      },
    }),
  );

  await sendCode(userId, address, 'signUp', log);
  log(`registered ${userId}`);
  // No session: the user types the emailed code next.
  return {};
}

async function resendSignUpCode({ email }, { log }) {
  const address = normaliseEmail(email);
  const user = await findByEmail(address);
  // Same silence as recovery: resending to an address nobody registered
  // must not say so.
  if (user) await sendCode(user.$id, address, 'signUp', log);
  return {};
}

// ───────────────────────────── recovery ─────────────────────────────────

async function sendRecoveryCode({ email }, { log }) {
  const address = normaliseEmail(email);
  const user = await findByEmail(address);

  // Phase 2, risk 3: Appwrite's own recovery endpoint deliberately does
  // not reveal whether an address exists, and ours must not either. Mint
  // nothing, send nothing, answer the same.
  if (user) {
    await sendCode(user.$id, address, 'recovery', log);
  } else {
    log('recovery requested for an address with no account');
  }
  return {};
}

// ───────────────────────────── redemption ───────────────────────────────

/**
 * Why the exchange happens here and not in the client.
 *
 * `POST /account/sessions/token` needs a `userId`, and the client has only
 * the address the user typed. Handing a client a `userId` in exchange for
 * an address is an account-enumeration oracle — ask for a hundred
 * addresses, see which answer. So this takes the address *and* the code
 * together, resolves the user itself, and returns the session.
 *
 * An unknown address and a wrong code answer identically, and the lookup
 * runs before the redemption either way so the two take the same shape.
 */
async function redeem(email, code) {
  const address = normaliseEmail(email);
  if (!code) throw badCode();
  const user = await findByEmail(address);
  if (!user) throw badCode();

  // Creating a session with an API key returns the session `secret`,
  // which is what the client sets. Without the key the secret comes back
  // empty and the session is unusable from here.
  const session = await api('/account/sessions/token', {
    method: 'POST',
    body: { userId: user.$id, secret: String(code).trim() },
  });
  if (!session.ok) throw badCode();
  if (!session.body?.secret) {
    // The API key was not attached, or the deployment lost its scopes.
    // Failing loudly beats returning a session the client cannot use.
    throw new Error('session created without a secret — check the API key');
  }
  return { user, session: session.body };
}

const badCode = () =>
  new Refusal(401, 'That code is invalid or has expired.', ErrorType.invalidToken);

async function verifySignUp({ email, code }, { log }) {
  const { user, session } = await redeem(email, code);
  // Only now: the code proved the address.
  await api(`/users/${user.$id}/verification`, {
    method: 'PATCH',
    body: { emailVerification: true },
  });
  log(`verified ${user.$id}`);
  return { sessionSecret: session.secret, userId: user.$id };
}

async function verifyRecovery({ email, code }, { log }) {
  const { user, session } = await redeem(email, code);
  // Deliberately does *not* set emailVerification: this session exists
  // only for the password change that follows it, and the client signs
  // out afterwards whether or not that change succeeds.
  log(`recovery session for ${user.$id}`);
  return { sessionSecret: session.secret, userId: user.$id };
}

// ───────────────────────────── password ─────────────────────────────────

async function setPassword({ password }, { req, log }) {
  // The caller's own id, from the header Appwrite sets — never from the
  // body, which the client controls entirely.
  const userId = req.headers['x-appwrite-user-id'];
  if (!userId) throw unauthorized('That reset session has expired.');
  if (!password || String(password).length < 8) {
    throw new Refusal(400,
      'Password is too weak. Use at least 8 characters with letters, numbers and symbols.',
      ErrorType.weakPassword);
  }

  const updated = await api(`/users/${userId}/password`, {
    method: 'PATCH',
    body: { password },
  });
  if (updated.status === 400) {
    throw new Refusal(400, updated.body?.message ?? 'That password was refused',
      ErrorType.weakPassword);
  }
  if (!updated.ok) throw new Error(`password update failed: ${updated.status}`);
  log(`password set for ${userId}`);
  return {};
}

// ───────────────────────────── helpers ──────────────────────────────────

function normaliseEmail(email) {
  const address = String(email ?? '').trim().toLowerCase();
  if (!address.includes('@')) {
    throw invalid('Please enter a valid email address', ErrorType.argument);
  }
  return address;
}

async function findByEmail(email) {
  const found = await api(
    `/users?queries[]=${encodeURIComponent(Query.equal('email', email))}` +
      `&queries[]=${encodeURIComponent(Query.limit(1))}`,
  );
  if (!found.ok) throw new Error(`user lookup failed: ${found.status}`);
  return found.body?.users?.[0] ?? null;
}

/**
 * Has Appwrite mint a typed code and mail it.
 *
 * `POST /account/tokens/email` does both halves: it mints a six-digit
 * secret good for fifteen minutes and sends it through Appwrite Cloud's
 * shared SMTP server, which every project has. Nothing needs configuring.
 *
 * It replaced a pairing that read better and did not work: mint with
 * `POST /users/{id}/tokens`, then post the code to
 * `/messaging/messages/email` with our own subject and body. That kept
 * the template in version control, which is worth something — this
 * project shipped a bug once because a provider dashboard said eight
 * digits and the app's copy said six. But Messaging is bring-your-own
 * provider: it refuses to send without an enabled one, and project
 * 6ac51e70002ab6238fec has none, so every reset answered "We could not
 * send the code". A generic mail that arrives beats a well-worded one
 * that does not.
 *
 * What moved to the console: the wording. Messaging → Templates → OTP,
 * and it is one template for both a registration code and a reset code,
 * where this function used to send two different ones. `kind` now only
 * reaches the log.
 *
 * What did not move: the length and the expiry. Appwrite's defaults are
 * six digits and fifteen minutes, which is exactly what the old mint
 * asked for, so no screen or string in the app changes.
 *
 * **Only ever call this for an address that already has an account.**
 * Appwrite *creates* one when the address is unknown, which would turn a
 * reset request for a stranger's address into a new passwordless account
 * — and hand an enumeration oracle to anyone willing to read the
 * difference. Both callers resolve the user first and stay silent when
 * there is none. For an address that does exist, Appwrite ignores the
 * `userId` below in favour of that address's own account; it is sent
 * because the endpoint requires it.
 */
async function sendCode(userId, email, kind, log) {
  await assertNotFlooding(userId);

  const sent = await api('/account/tokens/email', {
    method: 'POST',
    body: { userId, email },
  });
  if (!sent.ok) {
    // The mail was not sent. Say so: a silent success here leaves the
    // user waiting for a code that will never come, which reads to them
    // as the app being broken.
    //
    // The reason goes to the log, because the refusal cannot carry it —
    // the caller sees one sentence whichever of Appwrite's reasons it
    // was, and that sameness is deliberate.
    //
    // `status`, `type` and `message` only, never the whole body. Called
    // with an API key this endpoint returns the minted `secret`, so a
    // body dump would write live reset codes into the execution log.
    log(
      `${kind} email send failed: ${sent.status}`
        + (sent.body?.type ? ` ${sent.body.type}` : '')
        + (sent.body?.message ? `: ${sent.body.message}` : ''),
    );
    throw new Refusal(502,
      'We could not send the code. Please try again in a moment.',
      null);
  }
  log(`${kind} code sent to ${userId}`);
}

/**
 * The per-address throttle that used to be a Supabase project setting.
 *
 * Counted from the tokens Appwrite already stores for the user, so there
 * is no state of our own to keep consistent.
 *
 * **Unverified against a live project since `sendCode` moved to
 * `/account/tokens/email`.** This reads `GET /users/{id}/tokens`, which
 * listed the tokens the old `POST /users/{id}/tokens` minted. An email
 * token is a token on the same user and should be listed too, but that
 * has not been checked. If it is not, this window never fills and the
 * throttle quietly stops throttling — Appwrite's own rate limit on
 * `/account/tokens/email` still applies, so the failure mode is a
 * different error message, not an open door. Worth confirming by asking
 * for two codes and reading the list.
 */
async function assertNotFlooding(userId) {
  const tokens = await api(`/users/${userId}/tokens`);
  if (!tokens.ok) return; // never block a sign-up on the throttle's own failure
  const since = Date.now() - WINDOW_MS;
  const recent = (tokens.body?.tokens ?? []).filter(
    (t) => Date.parse(t.$createdAt) >= since,
  );
  if (recent.length >= MAX_CODES) {
    throw new Refusal(429,
      'Too many codes requested. Please wait a few minutes before trying again.',
      ErrorType.rateLimited);
  }
}
