/// Appwrite's refusals, in the app's two vocabularies.
///
/// The counterpart of `SupabaseService`'s GoTrue and PostgREST tables. Where
/// Postgres answers with SQLSTATEs and GoTrue with its own code strings,
/// Appwrite answers with an HTTP status and a `type` slug — and the slug is
/// the reliable half: statuses are reused across wildly different causes
/// (a 401 is both "wrong password" and "no session"), while `type` names
/// the condition.
///
/// So every mapping below reads `type` first and falls back to the status
/// only where Appwrite does not set one.
///
/// Slugs are from Appwrite's published error-type list. This file has not
/// been exercised against a live server; the risk that carries is that an
/// unlisted slug falls through to `unknown`, which is the safe direction —
/// the app shows a generic failure rather than the wrong specific one.
library;

import 'package:appwrite/appwrite.dart' show AppwriteException;

import 'package:climate_app/core/services/auth_backend.dart';
import 'package:climate_app/core/services/backend_failure.dart';

/// Which refusal, for the data layer.
BackendFailure classifyAppwriteFailure(Object error) {
  if (error is! AppwriteException) return BackendFailure.unknown;

  switch (error.type) {
    case 'user_unauthorized':
    case 'general_unauthorized_scope':
    case 'general_access_forbidden':
      return BackendFailure.refused;

    case 'general_rate_limit_exceeded':
      return BackendFailure.rateLimited;

    case 'document_not_found':
    case 'collection_not_found':
    case 'file_not_found':
    case 'general_not_found':
      return BackendFailure.notFound;

    case 'document_already_exists':
    case 'storage_file_already_exists':
      return BackendFailure.duplicate;

    // Not `duplicate`, which it was grouped with. Appwrite raises this
    // when the row moved under the writer, and the `write` Function
    // raises it when an `expect` clause matched nothing — "somebody did
    // something else", not "somebody already did this".
    //
    // The difference is not cosmetic: `isDuplicate` is how the offline
    // queue decides a queued item was already written, so a decision
    // that lost its optimistic lock was marked synced and dropped, and
    // the reviewer was told it had gone through.
    case 'document_update_conflict':
      return BackendFailure.invalidState;

    case 'document_invalid_structure':
    case 'attribute_value_invalid':
    case 'general_argument_invalid':
      return BackendFailure.constraint;
  }

  // A Function rejecting a write states the condition in its own body;
  // Phase 4's `create-report` answers 403 for a disabled account and 409
  // for a replay. Those arrive here with no `type`.
  switch (error.code) {
    case 401:
    case 403:
      return BackendFailure.refused;
    case 404:
      return BackendFailure.notFound;
    case 409:
      return BackendFailure.duplicate;
    case 429:
      return BackendFailure.rateLimited;
    // 400 is deliberately *not* mapped to `constraint`: Appwrite uses it
    // for malformed requests as well as rejected values, and treating a
    // client bug as a permanent data refusal would drop a queued report.
    default:
      return BackendFailure.unknown;
  }
}

/// The server's own wording, where it is worth showing somebody.
///
/// As narrow as the Postgres reader: a rate limit says how long to wait and
/// a Function's refusal says why, and those are written for a person.
/// Everything else goes through the app's dictionary.
String? appwriteMessage(Object error) {
  if (error is! AppwriteException) return null;
  final message = error.message?.trim();
  if (message == null || message.isEmpty) return null;
  final failure = classifyAppwriteFailure(error);
  if (failure == BackendFailure.rateLimited) return message;
  // A Function's own refusal — no `type`, a 4xx it chose — is written for
  // the user. Appwrite's generic messages are not.
  if (error.type == null && (error.code ?? 0) >= 400 && error.code! < 500) {
    return message;
  }
  return null;
}

/// Everything the server said, for the record stored against a rejected
/// report.
String? appwriteDiagnostic(Object error) => error is AppwriteException
    ? 'Appwrite ${error.code ?? 0} ${error.type ?? ''}: ${error.message ?? ''}'
          .trim()
    : null;

/// Worth retrying: the request never got an answer, or the answer was the
/// server's own temporary trouble.
bool isAppwriteTransient(Object error) {
  if (error is! AppwriteException) return false;
  final code = error.code ?? 0;
  if (code == 429 || code >= 500) return true;
  // The SDK reports transport failures as a 0-coded exception.
  return code == 0;
}

/// Retrying cannot change the answer, so a queued write must be abandoned
/// rather than tried forever.
///
/// Narrower than the Supabase predicate on purpose. Getting this wrong in
/// one direction retries a doomed report forever; in the other it throws a
/// field agent's report away. When in doubt the answer is "not permanent",
/// because a retry costs a request and a wrong `true` costs the report.
bool isAppwritePermanent(Object error) {
  if (error is! AppwriteException) return false;
  if (isAppwriteTransient(error)) return false;
  switch (classifyAppwriteFailure(error)) {
    case BackendFailure.refused:
    case BackendFailure.constraint:
      return true;
    case BackendFailure.duplicate:
      // A duplicate means the write already landed; retrying it forever is
      // pointless, and the queue treats "permanent" as "stop", not as
      // "failed".
      return true;
    case BackendFailure.notFound:
    case BackendFailure.invalidState:
    case BackendFailure.rateLimited:
    case BackendFailure.unknown:
      return false;
  }
}

// ───────────────────────────── auth ──────────────────────────────────────

/// Which condition, for the auth layer.
AuthFailure classifyAppwriteAuthFailure(Object error) {
  if (error is! AppwriteException) return AuthFailure.unknown;

  switch (error.type) {
    case 'user_invalid_credentials':
    case 'user_not_found':
      return AuthFailure.invalidCredentials;

    case 'user_unverified':
    case 'user_email_not_whitelisted':
      return AuthFailure.emailNotConfirmed;

    case 'user_already_exists':
    case 'user_email_already_exists':
    case 'user_phone_already_exists':
      return AuthFailure.accountExists;

    case 'user_blocked':
      return AuthFailure.accountBanned;

    case 'user_email_not_valid':
    case 'general_argument_invalid':
      return AuthFailure.invalidEmail;

    case 'user_auth_method_unsupported':
    case 'general_smtp_disabled':
      return AuthFailure.providerDisabled;

    case 'general_sms_disabled':
      return AuthFailure.deliveryFailed;

    case 'general_rate_limit_exceeded':
      return AuthFailure.rateLimited;

    case 'user_invalid_token':
      return AuthFailure.otpExpired;

    case 'password_recently_used':
    case 'password_personal_data':
    case 'general_password_weak':
      return AuthFailure.weakPassword;

    case 'user_password_mismatch':
      return AuthFailure.samePassword;

    case 'user_session_not_found':
    case 'user_jwt_invalid':
    case 'general_unauthorized_scope':
      return AuthFailure.sessionExpired;

    case 'user_challenge_required':
      return AuthFailure.reauthenticationNeeded;
  }

  switch (error.code) {
    case 0:
      return AuthFailure.network;
    case 401:
      return AuthFailure.invalidCredentials;
    case 409:
      return AuthFailure.accountExists;
    case 429:
      return AuthFailure.rateLimited;
    default:
      return (error.code ?? 0) >= 500
          ? AuthFailure.network
          : AuthFailure.unknown;
  }
}

/// Wraps an Appwrite failure as the app's own auth exception.
AuthBackendException toAuthBackendException(AppwriteException e) =>
    AuthBackendException(
      classifyAppwriteAuthFailure(e),
      code: e.type ?? '${e.code ?? 0}',
      message: e.message,
    );
