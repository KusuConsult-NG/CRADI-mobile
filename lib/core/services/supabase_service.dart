import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/core/services/supabase_mapping.dart';
import 'package:climate_app/core/utils/error_handler.dart' show SecureException;

export 'package:climate_app/core/services/supabase_mapping.dart'
    show
        FQuery,
        QueryFilter,
        WhereFilter,
        OrderByFilter,
        LimitFilter,
        parseTimestamp;

/// Thrown when a picked image can't be re-encoded (so its metadata can't be
/// stripped); it is not uploaded.
class ImageEncodingException extends SecureException {
  ImageEncodingException() : super((l) => l.reportErrorPhotoProcessing);
}

/// Thrown by [SupabaseService.getDocument] / [SupabaseService.updateDocument]
/// when no row matches (or RLS hides it).
class DocumentNotFoundException implements Exception {
  const DocumentNotFoundException(this.table, this.id);
  final String table;
  final String id;

  @override
  String toString() => 'DocumentNotFoundException: $id not found in $table';
}

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

/// Thrown when the backend is used before [SupabaseService.initialize]
/// succeeded (e.g. missing env.json, or in unit tests).
class BackendNotConfiguredException implements Exception {
  const BackendNotConfiguredException();

  @override
  String toString() =>
      'BackendNotConfiguredException: Supabase is not '
      'initialised (check SUPABASE_URL / SUPABASE_ANON_KEY).';
}

/// Central data service backed by Supabase (Postgres + Storage + Realtime).
///
/// Exposes a document-style API: maps use camelCase keys and carry the
/// primary key as `$id`.
/// Conversion to snake_case rows happens here, at the boundary (see
/// `supabase_mapping.dart`).
class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  /// Set once [initialize] succeeds. Everything else is inert until then so
  /// widgets/providers can be constructed in tests without a backend.
  static bool isReady = false;

  /// Initialise the Supabase client. Called once from `main()`.
  static Future<void> initialize() async {
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

  String? get currentUserId => getCurrentUser()?.id;

  /// The current access token (JWT) for calling the Railway backend.
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
  Future<List<Map<String, dynamic>>> listDocuments({
    required String collectionId,
    List<QueryFilter>? queries,
    int? limitCount,
    int offset = 0,
  }) async {
    final plan = QueryPlan.build(collectionId, queries);
    PostgrestTransformBuilder<List<Map<String, dynamic>>> q = _applyFilters(
      client.from(plan.table).select(),
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

  /// Count rows matching [queries] (ordering/limit are ignored).
  Future<int> countDocuments({
    required String collectionId,
    List<QueryFilter>? queries,
  }) async {
    try {
      final plan = QueryPlan.build(collectionId, queries);
      return await _applyFilters(
        client.from(plan.table).count(CountOption.exact),
        plan.filters,
      );
    } on Exception catch (e) {
      developer.log('countDocuments error: $e', name: 'SupabaseService');
      return 0;
    }
  }

  /// Partial update. Throws [DocumentNotFoundException] when no row was
  /// updated (missing, or not permitted by RLS).
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

  Future<void> deleteFile({
    required String bucketId,
    required String storagePath,
  }) async {
    await client.storage.from(bucketId).remove([storagePath]);
  }

  /// Connectivity check against the database.
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
  static bool isRateLimited(Object error) =>
      error is PostgrestException && error.code == '54000';

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
