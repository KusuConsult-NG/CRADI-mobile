/**
 * The response shapes the client adapters read.
 *
 * `lib/core/services/appwrite/appwrite_errors.dart` reads `type` first and
 * the status second, so a refusal that sets a recognised slug arrives at
 * the app as a named condition rather than a generic failure. Anything
 * unrecognised falls through to `unknown`, which shows a generic message —
 * the safe direction, but a worse one, so set a slug where one fits.
 */

/** Appwrite's own error type slugs, for the conditions these Functions raise. */
export const ErrorType = {
  unauthorized: 'user_unauthorized',
  forbidden: 'general_access_forbidden',
  notFound: 'document_not_found',
  duplicate: 'document_already_exists',
  // A write refused because the row moved under the caller, which is
  // not the same thing as a duplicate: the first is "somebody already
  // did this", the second is "somebody did something else". The client
  // branches on them differently — a duplicate is a replay to swallow,
  // a stale write is a refusal to show — so they cannot share a slug.
  staleWrite: 'document_update_conflict',
  invalid: 'document_invalid_structure',
  argument: 'general_argument_invalid',
  rateLimited: 'general_rate_limit_exceeded',
  invalidToken: 'user_invalid_token',
  userExists: 'user_already_exists',
  weakPassword: 'general_password_weak',
  samePassword: 'user_password_mismatch',
  sessionMissing: 'user_session_not_found',
  unverified: 'user_unverified',
  blocked: 'user_blocked',
};

/**
 * A refusal.
 *
 * Thrown rather than returned so a guard can stop a handler mid-way; the
 * entrypoint turns it into a response. A `type` of null is deliberate
 * where the message is written for the user: the client shows the server's
 * own wording for a 4xx that carries no slug, which is how "Your account
 * has been disabled" reaches a field agent intact.
 */
export class Refusal extends Error {
  constructor(status, message, type = null) {
    super(message);
    this.status = status;
    this.type = type;
  }
}

export const unauthorized = (m = 'Sign in to continue') =>
  new Refusal(401, m, ErrorType.unauthorized);
export const forbidden = (m) => new Refusal(403, m);
export const notFound = (m = 'Not found') =>
  new Refusal(404, m, ErrorType.notFound);
export const conflict = (m = 'Already exists', type = ErrorType.duplicate) =>
  new Refusal(409, m, type);
/** A 409 from an optimistic lock: the row changed, nothing was written. */
export const staleWrite = (m = 'That changed since you loaded it — reload and try again.') =>
  new Refusal(409, m, ErrorType.staleWrite);
export const invalid = (m, type = ErrorType.invalid) =>
  new Refusal(400, m, type);

/** Parses the request body, or refuses. */
export function readJson(req) {
  if (!req.bodyRaw) return {};
  try {
    const parsed = JSON.parse(req.bodyRaw);
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
      throw invalid('The request body must be an object', ErrorType.argument);
    }
    return parsed;
  } catch (e) {
    if (e instanceof Refusal) throw e;
    throw invalid('The request body is not JSON', ErrorType.argument);
  }
}

/**
 * The signed-in caller, from the header Appwrite sets.
 *
 * Never from the body. The client has no way to set this header and the
 * body is entirely under its control, so trusting a `userId` field would
 * hand every caller the ability to act as anyone — which is the one thing
 * moving these writes into a Function was for. The spike's `create-report`
 * accepted `payload.userId` as a fallback; that was fine for a spike and
 * is not fine here.
 */
export function callerId(req) {
  const id = req.headers['x-appwrite-user-id'];
  if (!id) throw unauthorized();
  return id;
}

/** Wraps a handler so every refusal leaves by the same door. */
export function handler(run) {
  return async (context) => {
    const { req, res, error } = context;
    try {
      const result = await run(context);
      return res.json(result ?? {}, 200);
    } catch (e) {
      if (e instanceof Refusal) {
        return res.json(
          { message: e.message, ...(e.type ? { type: e.type } : {}) },
          e.status,
        );
      }
      // An unexpected failure is the server's, not the caller's. 500 is
      // not in the client's permanent-failure set, so a queued write is
      // retried rather than thrown away over a bug here.
      error(`${req.path}: ${e?.stack ?? e}`);
      return res.json({ message: 'The server could not complete that' }, 500);
    }
  };
}
