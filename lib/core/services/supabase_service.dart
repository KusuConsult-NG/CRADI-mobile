import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// Aliased as well, because `StorageException` is also the name of this
// app's own neutral type in error_handler.dart, and an unqualified
// reference is ambiguous.
import 'package:supabase_flutter/supabase_flutter.dart'
    as sb
    show StorageException;

import 'package:climate_app/core/utils/image_url_resolver.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/core/services/data_backend.dart';
import 'package:climate_app/core/services/supabase_mapping.dart';

export 'package:climate_app/core/services/data_backend.dart';

/// Persists the Supabase session (incl. refresh token) in the platform
/// keystore/keychain instead of SharedPreferences. The biometric lock reuses
/// this session; no password is ever stored on the device.
class SecureSessionStorage extends LocalStorage {
  const SecureSessionStorage();

  static const String _key = 'supabase_session';
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() => _storage.containsKey(key: _key);

  @override
  Future<String?> accessToken() => _storage.read(key: _key);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _key, value: persistSessionString);
}

/// Central data service backed by Supabase (Postgres + Storage + Realtime).
///
/// Exposes a document-style API: maps use camelCase keys and carry the
/// primary key as `$id`.
/// Conversion to snake_case rows happens here, at the boundary (see
/// `supabase_mapping.dart`).
class SupabaseService implements DataBackend {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  /// Set once [initialize] succeeds. Everything else is inert until then so
  /// widgets/providers can be constructed in tests without a backend.
  static bool isReady = false;

  @override
  bool get isConfigured => isReady;

  /// Initialise the Supabase client. Called once from `main()`.
  static Future<void> initialize() async {
    installErrorVocabulary();
    if (isReady) return;
    if (!AppConfig.isSupabaseConfigured) {
      developer.log(
        'SUPABASE_URL / SUPABASE_ANON_KEY not provided '
        '(use --dart-define-from-file=env.json). Backend disabled.',
        name: 'SupabaseService',
      );
      return;
    }
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        localStorage: SecureSessionStorage(),
      ),
    );
    isReady = true;
  }

  /// The Supabase client. Throws [BackendNotConfiguredException] (an
  /// [Exception], so ordinary `on Exception` handlers cope) before
  /// [initialize] has succeeded.
  SupabaseClient get client {
    if (!isReady) throw const BackendNotConfiguredException();
    return Supabase.instance.client;
  }

  // ───────────────────────────── AUTH ──────────────────────────────────────

  GoTrueClient get auth => client.auth;

  /// Emits on every sign-in / sign-out / token refresh / user update.
  Stream<AuthState> get authStateChanges =>
      isReady ? auth.onAuthStateChange : const Stream<AuthState>.empty();

  /// The signed-in user, or null.
  User? getCurrentUser() => isReady ? auth.currentUser : null;

  @override
  String? get currentUserId => getCurrentUser()?.id;

  /// The current access token (JWT) for calling the Railway backend.
  @override
  String? get accessToken => isReady ? auth.currentSession?.accessToken : null;

  /// Fetch the latest user record from the auth server.
  Future<User?> reloadCurrentUser() async {
    if (!isReady) return null;
    final res = await auth.getUser();
    return res.user;
  }

  /// Sign out (also revokes the refresh token server-side).
  Future<void> logout() async {
    if (!isReady) return;
    try {
      await auth.signOut();
    } on AuthException catch (e) {
      developer.log('logout error: ${e.message}', name: 'SupabaseService');
      // Local session is cleared by signOut even when revocation fails.
    }
  }

  // ─────────────────────────── DATABASE ────────────────────────────────────

  String _table(String collectionId) => SupabaseSchema.table(collectionId);

  PostgrestFilterBuilder<T> _applyFilters<T>(
    PostgrestFilterBuilder<T> builder,
    List<ColumnFilter> filters,
  ) {
    var b = builder;
    for (final f in filters) {
      final v = f.value;
      switch (f.op) {
        case FilterOp.eq:
          b = v == null ? b.isFilter(f.column, null) : b.eq(f.column, v);
        case FilterOp.neq:
          b = v == null ? b.not(f.column, 'is', null) : b.neq(f.column, v);
        case FilterOp.distinctFrom:
          b = v == null
              ? b.not(f.column, 'is', null)
              : b.or('${f.column}.is.null,${f.column}.neq.${_orValue(v)}');
        case FilterOp.gt:
          b = b.gt(f.column, v!);
        case FilterOp.lt:
          b = b.lt(f.column, v!);
        case FilterOp.inList:
          // PostgREST `in.(…)`; an empty list matches nothing.
          b = b.inFilter(f.column, v is List ? v : [v]);
        case FilterOp.contains:
          b = b.contains(f.column, v is List ? v : [v]);
      }
    }
    return b;
  }

  /// Quotes a value for a PostgREST `or=(...)` filter (reserved
  /// characters such as `,` `.` `(` `)` would otherwise split it).
  static String _orValue(Object value) =>
      '"${value.toString().replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

  /// Create a row. [documentId] sets the primary key (must be a UUID for
  /// uuid-keyed tables); otherwise the database generates one.
  @override
  Future<Map<String, dynamic>> createDocument({
    required String collectionId,
    required Map<String, dynamic> data,
    String? documentId,
  }) async {
    final table = _table(collectionId);
    final row = toRow(table, data);
    if (documentId != null && documentId.isNotEmpty) {
      row[SupabaseSchema.primaryKey(table)] = documentId;
    }
    final result = await client.from(table).insert(row).select().single();
    developer.log(
      'Row created in $table: ${result[SupabaseSchema.primaryKey(table)]}',
      name: 'SupabaseService',
    );
    return fromRow(table, result);
  }

  /// Insert-or-update by primary key. With [ignoreDuplicates] an existing row
  /// is left untouched (idempotent replay) and null may be returned.
  @override
  Future<Map<String, dynamic>?> upsertDocument({
    required String collectionId,
    required Map<String, dynamic> data,
    String? documentId,
    bool ignoreDuplicates = false,
  }) async {
    final table = _table(collectionId);
    final pk = SupabaseSchema.primaryKey(table);
    final row = toRow(table, data);
    if (documentId != null && documentId.isNotEmpty) row[pk] = documentId;
    final result = await client
        .from(table)
        .upsert(row, onConflict: pk, ignoreDuplicates: ignoreDuplicates)
        .select();
    if (result.isEmpty) return null;
    return fromRow(table, result.first);
  }

  /// Get one row by primary key. Throws [DocumentNotFoundException].
  @override
  Future<Map<String, dynamic>> getDocument({
    required String collectionId,
    required String documentId,
  }) async {
    final table = _table(collectionId);
    final row = await client
        .from(table)
        .select()
        .eq(SupabaseSchema.primaryKey(table), documentId)
        .maybeSingle();
    if (row == null) throw DocumentNotFoundException(table, documentId);
    return fromRow(table, row);
  }

  /// List rows matching [queries]. Pagination is offset based: pass the
  /// number of rows already loaded as [offset].
  @override
  Future<List<Map<String, dynamic>>> listDocuments({
    required String collectionId,
    List<QueryFilter>? queries,
    int? limitCount,
    int offset = 0,
    RelatedFields? related,
  }) async {
    if (related != null) {
      try {
        return await _listDocuments(
          collectionId,
          queries,
          limitCount,
          offset,
          related,
        );
      } on Exception catch (e) {
        // The embed is best-effort by contract: a relationship that is not
        // exposed must degrade to plain documents, not fail the read.
        developer.log(
          'Embed of ${related.alias} failed, loading plain documents: $e',
          name: 'SupabaseService',
        );
      }
    }
    return _listDocuments(collectionId, queries, limitCount, offset, null);
  }

  Future<List<Map<String, dynamic>>> _listDocuments(
    String collectionId,
    List<QueryFilter>? queries,
    int? limitCount,
    int offset,
    RelatedFields? related,
  ) async {
    final plan = QueryPlan.build(collectionId, queries);
    PostgrestTransformBuilder<List<Map<String, dynamic>>> q = _applyFilters(
      client.from(plan.table).select(selectionFor(related)),
      plan.filters,
    );
    for (final o in plan.orders) {
      q = q.order(o.column, ascending: o.ascending);
    }
    final limit = limitCount ?? plan.limit;
    if (limit != null) {
      q = q.range(offset, offset + limit - 1);
    } else if (offset > 0) {
      q = q.range(offset, offset + 999);
    }
    final rows = await q;
    return rows.map((r) => fromRow(plan.table, r)).toList();
  }

  /// PostgREST's projection for [related] — an embedded resource named for
  /// the foreign key, so the join is one round trip under the same RLS as
  /// the base rows. Null selects every column.
  @visibleForTesting
  static String selectionFor(RelatedFields? related) {
    if (related == null) return '*';
    final table = SupabaseSchema.table(related.collectionId);
    final fk = camelToSnake(related.foreignKey);
    final fields = related.fields.map(camelToSnake).join(', ');
    return '*, ${related.alias}:$table!$fk($fields)';
  }

  /// Count rows matching [queries] (ordering/limit are ignored).
  /// Exact row count, swallowing failures as 0.
  ///
  /// Right for a badge beside a menu item, wrong for a figure somebody acts
  /// on: a dashboard that cannot reach the backend should say so rather than
  /// report nothing to do. Callers that need the difference use
  /// [countDocumentsOrThrow].
  @override
  Future<int> countDocuments({
    required String collectionId,
    List<QueryFilter>? queries,
  }) async {
    try {
      return await countDocumentsOrThrow(
        collectionId: collectionId,
        queries: queries,
      );
    } on Exception catch (e) {
      developer.log('countDocuments error: $e', name: 'SupabaseService');
      return 0;
    }
  }

  /// Exact row count, letting failures reach the caller.
  @override
  Future<int> countDocumentsOrThrow({
    required String collectionId,
    List<QueryFilter>? queries,
    Duration timeout = const Duration(seconds: 10),
  }) {
    final plan = QueryPlan.build(collectionId, queries);
    return _applyFilters(
      client.from(plan.table).count(CountOption.exact),
      plan.filters,
    ).timeout(timeout);
  }

  /// Partial update. Throws [DocumentNotFoundException] when no row was
  /// updated (missing, or not permitted by RLS).
  @override
  Future<Map<String, dynamic>> updateDocument({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    final table = _table(collectionId);
    final row = toRow(table, data);
    final result = await client
        .from(table)
        .update(row)
        .eq(SupabaseSchema.primaryKey(table), documentId)
        .select()
        .maybeSingle();
    if (result == null) throw DocumentNotFoundException(table, documentId);
    return fromRow(table, result);
  }

  /// Delete a row. Throws [DocumentNotFoundException] when nothing was
  /// deleted (missing, or refused by RLS — which reports no error).
  @override
  Future<void> deleteDocument({
    required String collectionId,
    required String documentId,
  }) async {
    final table = _table(collectionId);
    final deleted = await client
        .from(table)
        .delete()
        .eq(SupabaseSchema.primaryKey(table), documentId)
        .select();
    if (deleted.isEmpty) throw DocumentNotFoundException(table, documentId);
  }

  /// Realtime list of rows matching [queries].
  ///
  /// Supabase streams accept a single server-side filter, one order and a
  /// limit. The server filter is only ever an equality on an immutable
  /// column (see [QueryPlan.streamServerFilter]); every filter, the full
  /// ordering and the limit are (re)applied on the client.
  @override
  Stream<List<Map<String, dynamic>>> subscribeToCollection({
    required String collectionId,
    List<QueryFilter>? queries,
  }) {
    if (!isReady) return const Stream.empty();
    final plan = QueryPlan.build(collectionId, queries);
    final pk = SupabaseSchema.primaryKey(plan.table);
    final base = client.from(plan.table).stream(primaryKey: [pk]);

    final serverFilter = plan.streamServerFilter;
    SupabaseStreamBuilder source = serverFilter == null
        ? base
        : base.eq(serverFilter.column, serverFilter.value!);
    final order = plan.streamServerOrder;
    if (order != null) {
      source = source.order(order.column, ascending: order.ascending);
    }
    final serverLimit = plan.streamServerLimit;
    if (serverLimit != null) source = source.limit(serverLimit);

    return source.map((rows) {
      final filtered = rows.where(plan.matches).toList();
      plan.sort(filtered);
      final limit = plan.limit;
      final limited = limit != null && filtered.length > limit
          ? filtered.sublist(0, limit)
          : filtered;
      return limited.map((r) => fromRow(plan.table, r)).toList();
    });
  }

  /// Realtime view of a single row (null when it does not exist).
  @override
  Stream<Map<String, dynamic>?> subscribeToDocument({
    required String collectionId,
    required String documentId,
  }) {
    if (!isReady) return const Stream.empty();
    final table = _table(collectionId);
    final pk = SupabaseSchema.primaryKey(table);
    return client
        .from(table)
        .stream(primaryKey: [pk])
        .eq(pk, documentId)
        .map((rows) => rows.isEmpty ? null : fromRow(table, rows.first));
  }

  // ─────────────────────────── STORAGE ─────────────────────────────────────
  // Buckets are public-read; object paths must start with the uploader's
  // user id (enforced by storage RLS).
  //
  // Evidence (report-images) can't be overwritten: there is no update
  // policy, so those uploads use upsert: false. Their paths are
  // deterministic per report + index, so an object that already exists
  // (a retried upload) is treated as uploaded.
  //
  // Metadata: images are re-encoded by flutter_image_compress, whose
  // keepExif defaults to false, so EXIF (incl. GPS) is dropped. Bytes that
  // can't be re-encoded are never uploaded as-is (see [uploadFileFromPath]).

  /// Upload image bytes (re-encoded as JPEG, max 1920px @ 85%, without
  /// EXIF metadata) and return the public URL.
  @override
  Future<String> uploadFile({
    required String bucketId,
    required String storagePath,
    required List<int> fileBytes,
    bool upsert = false,
  }) async {
    final compressed = await FlutterImageCompress.compressWithList(
      Uint8List.fromList(fileBytes),
      minWidth: 1920,
      minHeight: 1920,
      quality: 85,
      format: CompressFormat.jpeg,
      keepExif: false, // strip EXIF, incl. GPS position
    );
    if (compressed.isEmpty) throw ImageEncodingException();
    return _uploadBytes(
      bucketId,
      storagePath,
      compressed,
      'image/jpeg',
      upsert: upsert,
    );
  }

  /// Upload an image file and return its public URL. The image is always
  /// re-encoded as JPEG (by default max 1920px @ 85%, overridable with
  /// [maxDimension] / [quality] so the same path can produce a thumbnail)
  /// without EXIF metadata (camera GPS position, device details); an image
  /// that can't be re-encoded is refused rather than uploaded with its
  /// metadata.
  @override
  Future<String> uploadFileFromPath({
    required String bucketId,
    required String storagePath,
    required File file,
    String? contentType,
    bool upsert = false,
    int maxDimension = 1920,
    int quality = 85,
  }) async {
    final compressed = await FlutterImageCompress.compressWithFile(
      file.absolute.path,
      minWidth: maxDimension,
      minHeight: maxDimension,
      quality: quality,
      format: CompressFormat.jpeg,
      keepExif: false, // strip EXIF, incl. GPS position
    );
    if (compressed == null || compressed.isEmpty) {
      throw ImageEncodingException();
    }
    return _uploadBytes(
      bucketId,
      storagePath,
      compressed,
      'image/jpeg',
      upsert: upsert,
    );
  }

  /// Image MIME type from a file extension (the buckets only accept
  /// images); unknown extensions default to `image/jpeg`.
  static String imageMimeTypeForPath(String path) {
    final dot = path.lastIndexOf('.');
    final ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
    return switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'heif' => 'image/heif',
      _ => 'image/jpeg',
    };
  }

  Future<String> _uploadBytes(
    String bucketId,
    String storagePath,
    Uint8List bytes,
    String contentType, {
    required bool upsert,
  }) async {
    final bucket = client.storage.from(bucketId);
    try {
      await bucket.uploadBinary(
        storagePath,
        bytes,
        fileOptions: FileOptions(contentType: contentType, upsert: upsert),
      );
    } on StorageException catch (e) {
      // Deterministic path already uploaded by an earlier attempt.
      if (upsert || !isStorageDuplicate(e)) rethrow;
      developer.log(
        '$bucketId/$storagePath already exists; reusing it',
        name: 'SupabaseService',
      );
    }
    final url = bucket.getPublicUrl(storagePath);
    developer.log(
      'Uploaded ${bytes.length ~/ 1024}KB to $bucketId/$storagePath',
      name: 'SupabaseService',
    );
    return url;
  }

  /// Supabase addresses an object by its path, and the path is a
  /// verbatim suffix of the public URL — so the `_thumb.jpg` sibling is
  /// recoverable from the URL alone, and nothing has to be stored.
  @override
  Future<String> uploadThumbnailFromPath({
    required String bucketId,
    required String storagePath,
    required File file,
    int maxDimension = 320,
    int quality = 60,
  }) => uploadFileFromPath(
    bucketId: bucketId,
    storagePath: ImageUrlResolver.thumbStoragePath(storagePath),
    file: file,
    maxDimension: maxDimension,
    quality: quality,
  );

  @override
  String? thumbUrlFor(String url) => ImageUrlResolver.thumbUrlFor(url);

  /// Supabase Storage serves an object as stored; there is no resize.
  /// The thumbnail uploaded beside the photo is the only smaller copy,
  /// and `thumbUrlFor` is what reaches it.
  @override
  String displayUrl(String url, {int? width, int? quality}) => url;

  @override
  Future<void> deleteFile({
    required String bucketId,
    required String storagePath,
  }) async {
    await client.storage.from(bucketId).remove([storagePath]);
  }

  /// A `SECURITY DEFINER` function, called over PostgREST's RPC endpoint.
  /// Appwrite runs these as Functions instead — see Phase 4.
  @override
  Future<void> callOperation(
    String name, {
    Map<String, dynamic>? params,
  }) async {
    await client.rpc(name, params: params);
  }

  /// Connectivity check against the database.
  @override
  Future<bool> ping() async {
    if (!isReady) return false;
    try {
      await client.from(AppConfig.appSettingsCollection).select('key').limit(1);
      return true;
    } on Exception catch (e) {
      developer.log('ping failed: $e', name: 'SupabaseService');
      return false;
    }
  }

  /// True when [error] is a row-level-security / privilege failure.
  static bool isPermissionDenied(Object error) =>
      error is PostgrestException &&
      (error.code == '42501' || error.code == 'PGRST301');

  /// True when the database refused a write for exceeding a per-user rate
  /// limit (errcode 54000; e.g. chat messages per minute, reports per
  /// hour). Its message is user-facing; retrying later can succeed.
  /// Teaches `backend_failure.dart` how THIS backend reports refusals.
  ///
  /// Separate from [initialize] and callable on its own, because the call
  /// sites are pure functions — `isPermanentSyncError`, `reportActionError`,
  /// the submission failure map — that tests exercise with a hand-built
  /// exception and no live client. Registering only inside [initialize]
  /// looked tidier and quietly made every one of those classifications
  /// answer "unknown" under test, which is how five existing tests caught
  /// it.
  ///
  /// When an Appwrite adapter arrives it installs its own vocabulary here
  /// instead, and those same tests assert Appwrite's codes.
  static void installErrorVocabulary() {
    registerBackendFailureClassifier(_classifyPostgrest);
    registerBackendMessageReader(_postgrestMessage);
    registerBackendTransientPredicate(_isTransient);
    registerBackendPermanentPredicate(_isPermanent);
    registerBackendDiagnosticReader(_postgrestDiagnostic);
  }

  /// Postgres' refusal vocabulary, as the migrations use it.
  ///
  /// These codes are chosen deliberately in the SQL, not inherited: `42501`
  /// is what 41 separate guards raise to mean "refused", and `54000` is the
  /// chat rate limit. See `backend_failure.dart` for why this mapping exists
  /// in one place rather than at each call site.
  static BackendFailure _classifyPostgrest(Object error) {
    if (error is! PostgrestException) return BackendFailure.unknown;
    switch (error.code) {
      case '42501':
      case 'PGRST301':
        return BackendFailure.refused;
      case '54000':
        return BackendFailure.rateLimited;
      case 'P0002':
        return BackendFailure.notFound;
      case '22023':
        return BackendFailure.invalidState;
      case '23505':
        return BackendFailure.duplicate;
      case '23514':
      case '23503':
        return BackendFailure.constraint;
      default:
        return BackendFailure.unknown;
    }
  }

  /// The server's wording, when a person wrote it.
  ///
  /// Two cases qualify. The rate limit ("You are sending messages too
  /// quickly") is written in the migration for a reader. A trigger refusal
  /// carries the reason the guard gives, which is more use than "not
  /// permitted" — but a bare RLS denial does not: PostgREST fills that in
  /// with "new row violates row-level security policy…", which tells a field
  /// agent nothing. Distinguishing them means recognising that sentence, and
  /// that is Postgres-specific knowledge, so it lives here rather than at the
  /// call site that shows the message.
  static String? _postgrestMessage(Object error) {
    if (error is! PostgrestException) return null;
    final message = error.message;
    if (message.isEmpty) return null;
    switch (error.code) {
      case '54000':
        return message;
      case '42501':
      case 'PGRST301':
        return message.toLowerCase().contains('row-level') ? null : message;
      default:
        return null;
    }
  }

  /// Postgres codes that fail the same way on every retry: permissions,
  /// constraint and type violations, unknown columns. Moved here from
  /// `offline_storage_service.dart`, which had no business knowing them —
  /// this set decides whether a queued field report is retried or dropped.
  static const Set<String> _permanentPostgresCodes = {
    '42501', // insufficient_privilege / RLS
    '23502', // not_null_violation
    '23503', // foreign_key_violation
    '23514', // check_violation
    '22P02', // invalid_text_representation
    '22001', // string_data_right_truncation
    '22007', // invalid_datetime_format
    '42703', // undefined_column
    'PGRST204', // unknown column in payload
  };

  /// An auth refresh that could not reach the server. Transport failures
  /// (socket, DNS, timeout) are recognised without the adapter's help.
  static bool _isTransient(Object error) =>
      error is AuthRetryableFetchException;

  /// A refusal retrying cannot change: a permanent Postgres code, or a
  /// storage upload rejected 4xx — but not a timeout, conflict or rate
  /// limit, each of which may succeed next time.
  static bool _isPermanent(Object error) {
    if (error is PostgrestException) {
      return _permanentPostgresCodes.contains(error.code);
    }
    if (error is sb.StorageException) {
      final status = int.tryParse(error.statusCode ?? '');
      return status != null &&
          status >= 400 &&
          status < 500 &&
          !const {408, 409, 429}.contains(status);
    }
    return false;
  }

  /// Everything the server said, for the rejection record.
  static String? _postgrestDiagnostic(Object error) =>
      error is PostgrestException ? error.message : null;

  static bool isRateLimited(Object error) =>
      backendFailureOf(error) == BackendFailure.rateLimited;

  /// True when a storage upload failed because the object already exists.
  static bool isStorageDuplicate(Object error) =>
      error is StorageException &&
      (error.statusCode == '409' ||
          error.error?.toLowerCase() == 'duplicate' ||
          error.message.toLowerCase().contains('already exists'));

  /// True when [error] is a unique-constraint violation.
  static bool isUniqueViolation(Object error) =>
      error is PostgrestException && error.code == '23505';
}
