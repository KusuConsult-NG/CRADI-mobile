/// What the backend refused, in terms the app can act on.
///
/// Feature code used to branch on Postgres SQLSTATEs — `22023`, `P0002`,
/// `42501`, `54000` — read off a `PostgrestException`. Those codes are not
/// incidental: the migrations raise them deliberately, 41 times for `42501`
/// alone, as the guards' way of saying "refused". So the app's business logic
/// was reading the database engine's error vocabulary directly, and six files
/// imported `supabase_flutter` for no other reason.
///
/// That coupling is the real one. Swapping the backend does not merely change
/// which client library is imported; it changes who raises these refusals
/// (an Appwrite Function rather than a trigger) and what they are called. So
/// the vocabulary is named here, once, in terms of what happened rather than
/// which engine said so.
///
/// Whichever backend is active registers a classifier at startup. Feature
/// code imports this file and nothing from any vendor SDK.
library;

/// The kinds of refusal the app distinguishes. Anything else is [unknown],
/// which callers must treat as a generic failure rather than guessing.
enum BackendFailure {
  /// A guard refused the write. Postgres `42501`; an Appwrite Function
  /// would answer 403. The most common refusal in this system by far.
  refused,

  /// Too many requests, too quickly. Postgres `54000`, raised by the chat
  /// rate limit. The server's own message is worth showing for this one.
  rateLimited,

  /// The row the operation needed does not exist. Postgres `P0002`.
  notFound,

  /// The row exists but is not in a state that allows this — a report that
  /// is no longer pending, say. Postgres `22023`.
  invalidState,

  /// Uniqueness violated. Postgres `23505`.
  duplicate,

  /// A CHECK or foreign key rejected the values. Postgres `23514` / `23503`.
  constraint,

  /// Not a refusal this app knows how to describe.
  unknown,
}

/// Maps a backend-specific error onto [BackendFailure].
typedef BackendFailureClassifier = BackendFailure Function(Object error);

BackendFailureClassifier _classifier = _unclassified;

BackendFailure _unclassified(Object error) => BackendFailure.unknown;

/// Installed once, at startup, by the active backend adapter.
///
/// Not a constructor argument because the call sites are pure functions that
/// turn an error into a message (`reportActionError`, and the submission
/// failure map in `ReportingProvider`). Threading a service through those
/// would be a worse seam than this one.
void registerBackendFailureClassifier(BackendFailureClassifier classifier) {
  _classifier = classifier;
}

/// Restores the default, so one test's classifier cannot leak into the next.
void resetBackendFailureClassifier() {
  _classifier = _unclassified;
}

/// What the backend refused, or [BackendFailure.unknown].
BackendFailure backendFailureOf(Object error) => _classifier(error);

/// The server's own wording, when there is one worth showing.
///
/// Only [BackendFailure.rateLimited] currently shows it: "You are sending
/// messages too quickly" is written in the migration, is not localised, and
/// is more useful than a generic failure line. Everything else goes through
/// the dictionary.
typedef BackendMessageReader = String? Function(Object error);

BackendMessageReader _messageReader = (_) => null;

void registerBackendMessageReader(BackendMessageReader reader) {
  _messageReader = reader;
}

void resetBackendMessageReader() {
  _messageReader = (_) => null;
}

String? backendMessageOf(Object error) => _messageReader(error);

// ───────────────────────── retryability ──────────────────────────────────
//
// Whether a queued write is worth retrying is backend knowledge, and it is
// the most consequential kind in this app: `isPermanentSyncError` decides
// whether a field agent's queued report is tried again or marked rejected
// and never sent. Expressed as Postgres SQLSTATEs and storage HTTP statuses,
// that policy would silently mean something different on another backend —
// and the failure mode is a dropped report, which nobody sees.
//
// The transport-level half (no socket, DNS, timeout) is backend-neutral and
// stays where it is. Only the server's own verdict is delegated here.

typedef BackendErrorPredicate = bool Function(Object error);

BackendErrorPredicate _transient = _never;
BackendErrorPredicate _permanent = _never;

bool _never(Object error) => false;

/// The backend's own transient failures — an auth refresh that could not
/// reach the server, and anything else only the adapter can recognise.
void registerBackendTransientPredicate(BackendErrorPredicate predicate) {
  _transient = predicate;
}

/// The backend's own permanent refusals: retrying cannot change the answer.
void registerBackendPermanentPredicate(BackendErrorPredicate predicate) {
  _permanent = predicate;
}

void resetBackendRetryPredicates() {
  _transient = _never;
  _permanent = _never;
}

bool isBackendTransient(Object error) => _transient(error);

bool isBackendPermanent(Object error) => _permanent(error);

/// The server's raw text, for a record a person will read while debugging.
///
/// Distinct from [backendMessageOf], which is deliberately narrow: that one
/// answers "is there wording here worth showing a field agent?", and is null
/// for most refusals. This one answers "what exactly did the server say?",
/// and is what the offline queue stores against a rejected report.
BackendMessageReader _diagnosticReader = (error) => null;

void registerBackendDiagnosticReader(BackendMessageReader reader) {
  _diagnosticReader = reader;
}

void resetBackendDiagnosticReader() {
  _diagnosticReader = (error) => null;
}

String? backendDiagnosticOf(Object error) => _diagnosticReader(error);
