/// The documents, streams and files the app needs from a backend.
///
/// Phase 5 took the *engine's error codes* out of feature code and Phase 5b
/// did the same for auth. Both left one thing behind: 22 files still named
/// `SupabaseService` by type, and four reached past it into the raw
/// PostgREST client to run an RPC or a join. So the vocabulary was clean
/// and the wiring was not — "swap the backend" still meant editing every
/// provider.
///
/// This is the type those files depend on instead. Nothing here is
/// Postgres-shaped: documents are maps, queries are [QueryFilter]s, and the
/// two operations that genuinely differ between engines (a server-side
/// procedure, and fields pulled in from a related collection) are named for
/// what they do rather than for how PostgREST spells them.
library;

import 'dart:io' show File;

import 'package:climate_app/core/services/supabase_mapping.dart'
    show QueryFilter;
import 'package:climate_app/core/utils/error_handler.dart' show SecureException;

// The failure vocabulary travels with the interface: a caller that reads
// documents also has to say what it does when one is refused.
export 'package:climate_app/core/services/backend_failure.dart';

// The query vocabulary travels with the interface, so a caller needs one
// import and names no backend to build a filter.
export 'package:climate_app/core/services/supabase_mapping.dart'
    show
        FQuery,
        QueryFilter,
        WhereFilter,
        FilterOp,
        OrderByFilter,
        LimitFilter,
        parseTimestamp;

/// Thrown by [DataBackend.getDocument], [DataBackend.updateDocument] and
/// [DataBackend.deleteDocument] when nothing matched — the document does
/// not exist, or the backend's own rules hide it. The two cases are
/// indistinguishable from the client by design, on both backends.
class DocumentNotFoundException implements Exception {
  const DocumentNotFoundException(this.collection, this.id);

  final String collection;
  final String id;

  @override
  String toString() =>
      'DocumentNotFoundException: $id not found in $collection';
}

/// Thrown when a picked image can't be re-encoded (so its metadata can't be
/// stripped); it is not uploaded.
class ImageEncodingException extends SecureException {
  ImageEncodingException() : super((l) => l.reportErrorPhotoProcessing);
}

/// Thrown when the backend is used before it was initialised — a missing
/// `env.json`, or a unit test with no server.
class BackendNotConfiguredException implements Exception {
  const BackendNotConfiguredException();

  @override
  String toString() =>
      'BackendNotConfiguredException: no backend is initialised '
      '(check the configuration passed with --dart-define-from-file).';
}

/// Fields to pull in from a related collection alongside each document.
///
/// Postgres does this with a PostgREST embed — one round trip, enforced by
/// the same RLS as the base rows. Appwrite cannot join at all; Phase 1 of
/// the migration denormalises the few fields this app embeds onto the
/// document itself.
///
/// So an adapter that cannot honour this **must return the plain documents
/// rather than fail**. Every caller already copes: the only use in the app
/// embeds a verifier's name and falls back to rows without it.
class RelatedFields {
  const RelatedFields({
    required this.alias,
    required this.collectionId,
    required this.foreignKey,
    required this.fields,
  });

  /// The key the related object is placed under in each document.
  final String alias;

  /// The collection the fields come from.
  final String collectionId;

  /// The field on the base document that points at it.
  final String foreignKey;

  /// Which of the related document's fields to include.
  final List<String> fields;
}

/// Everything the app's providers and services need from a backend.
///
/// Implemented by `SupabaseService` today. An Appwrite implementation is a
/// second file, not a second pass over the feature tree.
abstract interface class DataBackend {
  /// False until a backend has been configured and initialised. Everything
  /// else is inert until then, so providers can be built in tests without
  /// a server.
  bool get isConfigured;

  /// The signed-in user's id, or null.
  ///
  /// Auth belongs to [AuthBackend]; this is here because the data layer
  /// resolves "my documents" constantly and threading the auth backend
  /// through every service for one string is a worse seam than this.
  String? get currentUserId;

  /// A bearer token for calls this app makes outside the SDK.
  String? get accessToken;

  // ───────────────────────── documents ────────────────────────────────

  /// Creates a document. [documentId] sets the key; otherwise the backend
  /// generates one.
  Future<Map<String, dynamic>> createDocument({
    required String collectionId,
    required Map<String, dynamic> data,
    String? documentId,
  });

  /// Creates or replaces by key. With [ignoreDuplicates] an existing
  /// document is left untouched — an idempotent replay — and null may come
  /// back.
  Future<Map<String, dynamic>?> upsertDocument({
    required String collectionId,
    required Map<String, dynamic> data,
    String? documentId,
    bool ignoreDuplicates = false,
  });

  /// One document by key. Throws [DocumentNotFoundException].
  Future<Map<String, dynamic>> getDocument({
    required String collectionId,
    required String documentId,
  });

  /// Documents matching [queries]. Pagination is offset based: pass the
  /// number already loaded as [offset].
  ///
  /// [related] is best-effort — see [RelatedFields].
  Future<List<Map<String, dynamic>>> listDocuments({
    required String collectionId,
    List<QueryFilter>? queries,
    int? limitCount,
    int offset = 0,
    RelatedFields? related,
  });

  /// Exact count, swallowing failures as `0`.
  ///
  /// Right for a badge beside a menu item, wrong for a figure somebody acts
  /// on: a dashboard that cannot reach the backend should say so rather
  /// than report nothing to do. Use [countDocumentsOrThrow] where the
  /// difference matters.
  Future<int> countDocuments({
    required String collectionId,
    List<QueryFilter>? queries,
  });

  /// Exact count, letting failures reach the caller.
  Future<int> countDocumentsOrThrow({
    required String collectionId,
    List<QueryFilter>? queries,
    Duration timeout = const Duration(seconds: 10),
  });

  /// Partial update. Throws [DocumentNotFoundException] when nothing was
  /// updated — missing, or refused by the backend's own rules.
  Future<Map<String, dynamic>> updateDocument({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  });

  /// Deletes a document. Throws [DocumentNotFoundException] when nothing
  /// was deleted.
  Future<void> deleteDocument({
    required String collectionId,
    required String documentId,
  });

  /// A named operation the server runs for us.
  ///
  /// Postgres: a `SECURITY DEFINER` function called over RPC. Appwrite:
  /// a Function execution — which is where Phase 4 puts every write that
  /// a trigger used to guard.
  Future<void> callOperation(String name, {Map<String, dynamic>? params});

  // ───────────────────────── realtime ─────────────────────────────────

  /// Live list of documents matching [queries]. Empty when no backend is
  /// configured.
  Stream<List<Map<String, dynamic>>> subscribeToCollection({
    required String collectionId,
    List<QueryFilter>? queries,
  });

  /// Live view of one document; emits null once it is gone.
  Stream<Map<String, dynamic>?> subscribeToDocument({
    required String collectionId,
    required String documentId,
  });

  // ───────────────────────── files ────────────────────────────────────

  /// Uploads bytes and returns the URL to read them back.
  Future<String> uploadFile({
    required String bucketId,
    required String storagePath,
    required List<int> fileBytes,
    bool upsert = false,
  });

  /// Uploads a file from disk, compressing it on the way.
  Future<String> uploadFileFromPath({
    required String bucketId,
    required String storagePath,
    required File file,
    String? contentType,
    bool upsert = false,
    int maxDimension = 1920,
    int quality = 85,
  });

  /// Uploads the small thumbnail that belongs beside the image at
  /// [storagePath] — the **photo's** path, not the thumbnail's.
  ///
  /// The backend chooses where the thumbnail lands and under what name,
  /// because that is exactly the decision [thumbUrlFor] has to reverse.
  /// Supabase addresses an object by its path, so a `_thumb.jpg` sibling
  /// is recoverable from the URL; Appwrite addresses a file by a digest
  /// id, from which no path can be recovered, so it derives the
  /// thumbnail's id from the photo's instead. Neither convention
  /// survives being imposed by the caller.
  Future<String> uploadThumbnailFromPath({
    required String bucketId,
    required String storagePath,
    required File file,
    int maxDimension = 320,
    int quality = 60,
  });

  /// The thumbnail stored beside the image at [url], or null when there
  /// is none to derive — [url] was not written by this backend, or is
  /// already a thumbnail.
  ///
  /// A thumbnail that was never uploaded 404s, so callers keep [url] as
  /// a fallback rather than treating a non-null answer as a promise.
  String? thumbUrlFor(String url);

  /// [url], asked for at a smaller size.
  ///
  /// Returns [url] unchanged when the backend has no way to resize, or
  /// has one that is not configured — so this is a delivery
  /// optimisation and never a correctness requirement.
  String displayUrl(String url, {int? width, int? quality});

  Future<void> deleteFile({
    required String bucketId,
    required String storagePath,
  });

  /// Whether the backend is reachable right now.
  Future<bool> ping();
}
