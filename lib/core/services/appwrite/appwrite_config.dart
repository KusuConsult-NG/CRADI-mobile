/// Build-time configuration for the Appwrite backend, and the one piece of
/// policy the client has to know: which collections it may write directly.
library;

import 'package:climate_app/core/constants/app_config.dart';

class AppwriteConfig {
  AppwriteConfig._();

  // Supplied at build time, like the Supabase values:
  //   flutter run --dart-define-from-file=env.json
  //
  // The endpoint carries the region (`https://fra.cloud.appwrite.io/v1` is
  // Frankfurt). Which region is lawful under the NDPA is still open, and is
  // the reason nothing here has been pointed at a real project yet.
  static const String endpoint = String.fromEnvironment('APPWRITE_ENDPOINT');
  static const String projectId = String.fromEnvironment('APPWRITE_PROJECT_ID');
  static const String databaseId = String.fromEnvironment(
    'APPWRITE_DATABASE_ID',
    defaultValue: 'cradi',
  );

  static bool get isConfigured => endpoint.isNotEmpty && projectId.isNotEmpty;

  // ─────────────────────── Functions ──────────────────────────────────────
  //
  // Phase 2 and Phase 4: every write the database used to guard with a
  // trigger, and every auth step that needs a server API key.

  /// The write path for collections the client may not write. Takes
  /// `{op, collection, documentId, data}` and answers with the document —
  /// the generalisation of Phase 4's `create-report`.
  static const String writeFunctionId = String.fromEnvironment(
    'APPWRITE_FN_WRITE',
    defaultValue: 'write',
  );

  /// Registration, code resends and recovery: the three steps that mint a
  /// typed token with a server key and send our own mail.
  static const String authFunctionId = String.fromEnvironment(
    'APPWRITE_FN_AUTH',
    defaultValue: 'auth',
  );

  /// Named server-side operations — the RPCs. Today that is `reopen_report`.
  static const String operationFunctionId = String.fromEnvironment(
    'APPWRITE_FN_OPERATION',
    defaultValue: 'operation',
  );

  // ─────────────────────── Write policy ───────────────────────────────────

  /// Collections the client writes directly, under a document ACL.
  ///
  /// The complement of Phase 1's collection map: everything *not* listed
  /// here is Function-written, because its rule is something an ACL cannot
  /// express — a cross-collection check, a column the client must not
  /// choose, or a role gate.
  ///
  /// Keeping the list this way round is deliberate. A collection added
  /// later and forgotten defaults to **going through the Function**, which
  /// fails safe; the other way round it would default to a direct write
  /// the server then has to refuse.
  static const Set<String> clientWritableCollections = {
    AppConfig.contactsCollection, // pure owner rule
    AppConfig.messagesCollection, // owner + label:approved
    AppConfig.trustedDevicesCollection, // pure owner rule
    AppConfig.loginHistoryCollection, // append-only, owner-stamped
    AppConfig.ndpaConsentsCollection, // append-only, owner-stamped
  };

  static bool isClientWritable(String collectionId) =>
      clientWritableCollections.contains(collectionId);
}
