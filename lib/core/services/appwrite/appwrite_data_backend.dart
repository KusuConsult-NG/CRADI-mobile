import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:appwrite/appwrite.dart' as aw;
import 'package:appwrite/enums.dart' show ExecutionMethod;
import 'package:flutter_image_compress/flutter_image_compress.dart';

import 'package:climate_app/core/services/appwrite/appwrite_config.dart';
import 'package:climate_app/core/services/appwrite/appwrite_documents.dart';
import 'package:climate_app/core/services/appwrite/appwrite_errors.dart';
import 'package:climate_app/core/services/appwrite/appwrite_queries.dart';
import 'package:climate_app/core/services/data_backend.dart';

/// [DataBackend] over Appwrite.
///
/// Two things make this shorter than the Postgres adapter and one makes it
/// longer.
///
/// Shorter: the collections carry the app's own field names (Phase 1), so
/// there is no row mapping; and there is no `select`, so a read is a read.
///
/// Longer: **most collections are not client-writable.** Phase 1 found that
/// 14 of 19 have a rule an ACL cannot express — a cross-collection check, a
/// column the client must not choose, a role gate — so their writes go
/// through a Function, which Phase 4 proved refuses a client that tries to
/// approve its own report. Which collections those are is
/// [AppwriteConfig.clientWritableCollections], and the default is the safe
/// one: a collection nobody listed goes through the Function.
///
/// **Status: not exercised against a server.** The pure parts — queries,
/// document mapping, the error table — are tested. Everything below that
/// needs a socket is written against the SDK and Phases 1–4's findings, and
/// is unverified until there is a project to point it at.
class AppwriteDataBackend implements DataBackend {
  AppwriteDataBackend({aw.Client? client})
    : _client = client ?? _defaultClient() {
    _tables = aw.TablesDB(_client);
    _storage = aw.Storage(_client);
    _functions = aw.Functions(_client);
    _account = aw.Account(_client);
  }

  static aw.Client _defaultClient() => aw.Client()
      .setEndpoint(AppwriteConfig.endpoint)
      .setProject(AppwriteConfig.projectId);

  final aw.Client _client;
  late final aw.TablesDB _tables;
  late final aw.Storage _storage;
  late final aw.Functions _functions;
  late final aw.Account _account;

  aw.Realtime? _realtime;
  aw.Realtime get _rt => _realtime ??= aw.Realtime(_client);

  /// Cached because `DataBackend.currentUserId` is synchronous and is read
  /// on nearly every query, while Appwrite only exposes the account over
  /// the network. Kept fresh by [refreshIdentity], which the auth adapter
  /// calls on every session change.
  String? _userId;

  /// Re-reads who is signed in. Null signs the cache out.
  void setCurrentUserId(String? id) => _userId = id;

  /// Asks the server who is signed in and caches it.
  Future<String?> refreshIdentity() async {
    try {
      final user = await _account.get();
      return _userId = user.$id;
    } on aw.AppwriteException {
      return _userId = null;
    }
  }

  @override
  bool get isConfigured => AppwriteConfig.isConfigured;

  @override
  String? get currentUserId => _userId;

  @override
  String? get accessToken => null;

  /// Installs this backend's error vocabulary — the Appwrite half of what
  /// `SupabaseService.installErrorVocabulary` does for Postgres.
  static void installErrorVocabulary() {
    registerBackendFailureClassifier(classifyAppwriteFailure);
    registerBackendMessageReader(appwriteMessage);
    registerBackendDiagnosticReader(appwriteDiagnostic);
    registerBackendTransientPredicate(isAppwriteTransient);
    registerBackendPermanentPredicate(isAppwritePermanent);
  }

  // ───────────────────────── documents ────────────────────────────────

  @override
  Future<Map<String, dynamic>> createDocument({
    required String collectionId,
    required Map<String, dynamic> data,
    String? documentId,
  }) async {
    final id = (documentId == null || documentId.isEmpty)
        ? aw.ID.unique()
        : documentId;

    if (!AppwriteConfig.isClientWritable(collectionId)) {
      return _write('create', collectionId, id, data);
    }
    final row = await _tables.createRow(
      databaseId: AppwriteConfig.databaseId,
      tableId: collectionId,
      rowId: id,
      data: toAppwriteData(data),
    );
    return fromAppwriteRow(row);
  }

  @override
  Future<Map<String, dynamic>?> upsertDocument({
    required String collectionId,
    required Map<String, dynamic> data,
    String? documentId,
    bool ignoreDuplicates = false,
  }) async {
    // `ignoreDuplicates` is the idempotent-replay path — the NDPA consent
    // write uses it. The row must be left exactly as it is, and the
    // contract the Postgres adapter set is to answer null. `upsertRow`
    // would overwrite, so this case deliberately does not use it.
    if (ignoreDuplicates) {
      try {
        return await createDocument(
          collectionId: collectionId,
          data: data,
          documentId: documentId,
        );
      } on aw.AppwriteException catch (e) {
        if (classifyAppwriteFailure(e) == BackendFailure.duplicate) {
          return null;
        }
        rethrow;
      }
    }

    final id = (documentId == null || documentId.isEmpty)
        ? aw.ID.unique()
        : documentId;
    if (!AppwriteConfig.isClientWritable(collectionId)) {
      return _write('upsert', collectionId, id, data);
    }
    final row = await _tables.upsertRow(
      databaseId: AppwriteConfig.databaseId,
      tableId: collectionId,
      rowId: id,
      data: toAppwriteData(data),
    );
    return fromAppwriteRow(row);
  }

  @override
  Future<Map<String, dynamic>> getDocument({
    required String collectionId,
    required String documentId,
  }) async {
    try {
      final row = await _tables.getRow(
        databaseId: AppwriteConfig.databaseId,
        tableId: collectionId,
        rowId: documentId,
      );
      return fromAppwriteRow(row);
    } on aw.AppwriteException catch (e) {
      // Appwrite answers 404 for "no such document" and for "you may not
      // read it" alike — the same conflation Postgres makes under RLS, and
      // the reason `DocumentNotFoundException` says nothing about which.
      if (classifyAppwriteFailure(e) == BackendFailure.notFound) {
        throw DocumentNotFoundException(collectionId, documentId);
      }
      rethrow;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> listDocuments({
    required String collectionId,
    List<QueryFilter>? queries,
    int? limitCount,
    int offset = 0,
    RelatedFields? related,
  }) async {
    if (related != null) {
      // Appwrite cannot join, and `DataBackend` says an adapter that
      // cannot must return the plain documents rather than fail. Phase 1
      // denormalises the one field the app embeds; until that lands, the
      // caller shows no verifier name, which is what it already does for a
      // profile it may not read.
      developer.log(
        'Appwrite cannot embed ${related.alias}; returning plain documents',
        name: 'AppwriteDataBackend',
      );
    }
    final page = await _tables.listRows(
      databaseId: AppwriteConfig.databaseId,
      tableId: collectionId,
      queries: buildAppwriteQueries(
        queries,
        limitCount: limitCount,
        offset: offset,
      ),
    );
    return page.rows.map(fromAppwriteRow).toList();
  }

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
      developer.log('countDocuments error: $e', name: 'AppwriteDataBackend');
      return 0;
    }
  }

  @override
  Future<int> countDocumentsOrThrow({
    required String collectionId,
    List<QueryFilter>? queries,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    // `total` is the count of documents matching the queries, independent
    // of the page size — so ask for the smallest page Appwrite allows and
    // read the total off it.
    final page = await _tables
        .listRows(
          databaseId: AppwriteConfig.databaseId,
          tableId: collectionId,
          queries: [...buildAppwriteQueries(queries), aw.Query.limit(1)],
          total: true,
        )
        .timeout(timeout);
    return page.total;
  }

  @override
  Future<Map<String, dynamic>> updateDocument({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    if (!AppwriteConfig.isClientWritable(collectionId)) {
      return _write('update', collectionId, documentId, data);
    }
    try {
      final row = await _tables.updateRow(
        databaseId: AppwriteConfig.databaseId,
        tableId: collectionId,
        rowId: documentId,
        data: toAppwriteData(data),
      );
      return fromAppwriteRow(row);
    } on aw.AppwriteException catch (e) {
      if (classifyAppwriteFailure(e) == BackendFailure.notFound) {
        throw DocumentNotFoundException(collectionId, documentId);
      }
      rethrow;
    }
  }

  @override
  Future<void> deleteDocument({
    required String collectionId,
    required String documentId,
  }) async {
    if (!AppwriteConfig.isClientWritable(collectionId)) {
      await _write('delete', collectionId, documentId, const {});
      return;
    }
    try {
      await _tables.deleteRow(
        databaseId: AppwriteConfig.databaseId,
        tableId: collectionId,
        rowId: documentId,
      );
    } on aw.AppwriteException catch (e) {
      if (classifyAppwriteFailure(e) == BackendFailure.notFound) {
        throw DocumentNotFoundException(collectionId, documentId);
      }
      rethrow;
    }
  }

  @override
  Future<void> callOperation(
    String name, {
    Map<String, dynamic>? params,
  }) async {
    await _execute(AppwriteConfig.operationFunctionId, {
      'operation': name,
      'params': params ?? const <String, dynamic>{},
    });
  }

  /// A write the client may not make directly.
  Future<Map<String, dynamic>> _write(
    String op,
    String collectionId,
    String documentId,
    Map<String, dynamic> data,
  ) async {
    final body = await _execute(AppwriteConfig.writeFunctionId, {
      'op': op,
      'collection': collectionId,
      'documentId': documentId,
      'data': toAppwriteData(data),
    });
    final document = body['document'];
    if (document is Map) {
      return fromAppwritePayload(Map<String, dynamic>.from(document));
    }
    // A delete answers with no document; a create or update that does is a
    // Function bug, and silently returning an empty map would make it look
    // like a successful write of nothing.
    if (op == 'delete') return const {};
    throw aw.AppwriteException(
      'The $op Function returned no document',
      502,
      'function_contract',
    );
  }

  /// Calls a Function synchronously and returns its JSON body.
  ///
  /// A Function that refuses a write answers with a 4xx *inside* a
  /// successful execution — the execution completed, the response did not.
  /// Turning that back into an [aw.AppwriteException] is what lets the rest
  /// of the app treat a Function refusal and a database refusal alike,
  /// which is the whole point of Phase 4.
  Future<Map<String, dynamic>> _execute(
    String functionId,
    Map<String, dynamic> payload,
  ) async {
    final execution = await _functions.createExecution(
      functionId: functionId,
      body: jsonEncode(payload),
      xasync: false,
      method: ExecutionMethod.pOST,
      headers: {'content-type': 'application/json'},
    );

    final status = execution.responseStatusCode;
    final body = _decode(execution.responseBody);

    if (status >= 400) {
      throw aw.AppwriteException(
        body['message']?.toString() ?? 'The request was refused',
        status,
        body['type']?.toString(),
        execution.responseBody,
      );
    }
    // An execution that never ran — a cold-start timeout, a crash — has no
    // response at all. It must not read as success.
    if (execution.status.name != 'completed') {
      throw aw.AppwriteException(
        'Function $functionId did not complete (${execution.status.name})',
        503,
        'function_incomplete',
        execution.errors,
      );
    }
    return body;
  }

  static Map<String, dynamic> _decode(String body) {
    if (body.isEmpty) return const {};
    try {
      final decoded = jsonDecode(body);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : {'value': decoded};
    } on FormatException {
      return {'message': body};
    }
  }

  // ───────────────────────── realtime ─────────────────────────────────

  @override
  Stream<List<Map<String, dynamic>>> subscribeToCollection({
    required String collectionId,
    List<QueryFilter>? queries,
  }) {
    if (!isConfigured) return const Stream.empty();
    final plan = DocumentPlan.build(queries);
    final channel = aw.Channel.tablesdb(
      AppwriteConfig.databaseId,
    ).table(collectionId).row();

    late StreamController<List<Map<String, dynamic>>> controller;
    aw.RealtimeSubscription? subscription;
    // Keyed by `$id` so an update replaces rather than duplicates — the
    // same reason the Postgres stream is keyed on the primary key.
    final byId = <String, Map<String, dynamic>>{};
    var closed = false;

    void emit() {
      if (closed) return;
      controller.add(plan.apply(byId.values));
    }

    Future<void> start() async {
      try {
        final initial = await listDocuments(
          collectionId: collectionId,
          queries: queries,
        );
        for (final doc in initial) {
          byId[doc[r'$id'].toString()] = doc;
        }
        emit();
      } on Exception catch (e, st) {
        if (!closed) controller.addError(e, st);
        return;
      }

      subscription = _rt.subscribe([channel]);
      subscription!.stream.listen(
        (message) {
          final doc = fromAppwritePayload(message.payload);
          final id = doc[r'$id']?.toString();
          if (id == null) return;
          if (message.events.any((e) => e.endsWith('.delete'))) {
            byId.remove(id);
          } else {
            byId[id] = doc;
          }
          emit();
        },
        onError: (Object e, StackTrace st) {
          if (!closed) controller.addError(e, st);
        },
      );
    }

    controller = StreamController<List<Map<String, dynamic>>>(
      onListen: () => unawaited(start()),
      onCancel: () async {
        closed = true;
        await subscription?.close();
      },
    );
    return controller.stream;
  }

  @override
  Stream<Map<String, dynamic>?> subscribeToDocument({
    required String collectionId,
    required String documentId,
  }) {
    if (!isConfigured) return const Stream.empty();
    final channel = aw.Channel.tablesdb(
      AppwriteConfig.databaseId,
    ).table(collectionId).row(documentId);

    late StreamController<Map<String, dynamic>?> controller;
    aw.RealtimeSubscription? subscription;
    var closed = false;

    Future<void> start() async {
      try {
        controller.add(
          await getDocument(collectionId: collectionId, documentId: documentId),
        );
      } on DocumentNotFoundException {
        // Not an error: the caller's contract is "null when it does not
        // exist", and a profile row can legitimately be missing while the
        // creating Function is still running.
        if (!closed) controller.add(null);
      } on Exception catch (e, st) {
        if (!closed) controller.addError(e, st);
        return;
      }

      subscription = _rt.subscribe([channel]);
      subscription!.stream.listen(
        (message) {
          if (message.events.any((e) => e.endsWith('.delete'))) {
            controller.add(null);
          } else {
            controller.add(fromAppwritePayload(message.payload));
          }
        },
        onError: (Object e, StackTrace st) {
          if (!closed) controller.addError(e, st);
        },
      );
    }

    controller = StreamController<Map<String, dynamic>?>(
      onListen: () => unawaited(start()),
      onCancel: () async {
        closed = true;
        await subscription?.close();
      },
    );
    return controller.stream;
  }

  // ───────────────────────── files ────────────────────────────────────

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
    );
    if (compressed.isEmpty) throw ImageEncodingException();
    return _put(
      bucketId: bucketId,
      storagePath: storagePath,
      file: aw.InputFile.fromBytes(
        bytes: compressed,
        filename: _filename(storagePath),
        contentType: 'image/jpeg',
      ),
      upsert: upsert,
    );
  }

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
    );
    if (compressed == null || compressed.isEmpty) {
      throw ImageEncodingException();
    }
    return _put(
      bucketId: bucketId,
      storagePath: storagePath,
      file: aw.InputFile.fromBytes(
        bytes: compressed,
        filename: _filename(storagePath),
        contentType: contentType ?? 'image/jpeg',
      ),
      upsert: upsert,
    );
  }

  /// Appwrite addresses files by id within a bucket, not by path, and an
  /// id is at most 36 characters.
  ///
  /// The app's storage paths are `<userId>/report_<timestamp>.jpg`, which
  /// is 60 characters with a UUID user id. Truncating to the last 36 was
  /// the obvious thing and is wrong: it keeps the whole filename and only
  /// the tail of the user id, so two agents whose ids end alike who
  /// photograph the same hazard in the same millisecond get the same id —
  /// and the second upload **overwrites the first's evidence** with no
  /// error anywhere. Unlikely, silent, and unrecoverable.
  ///
  /// So the id is a readable prefix plus a digest of the *whole* path: the
  /// prefix keeps it debuggable in the Appwrite console, the digest makes
  /// it one-to-one.
  static String fileIdFor(String storagePath) {
    final cleaned = storagePath.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
    final digest = _fnv1a64(storagePath);
    if (cleaned.length <= 36) {
      return cleaned.startsWith(RegExp(r'[._-]'))
          ? 'f${cleaned.substring(1)}'
          : cleaned;
    }
    // 19 characters of prefix + '-' + 16 hex = 36.
    final prefix = cleaned.substring(0, 19);
    final head = prefix.startsWith(RegExp(r'[._-]'))
        ? 'f${prefix.substring(1)}'
        : prefix;
    return '$head-$digest';
  }

  /// FNV-1a, 64-bit, as 16 hex characters.
  ///
  /// Not a security hash and does not need to be — it distinguishes paths
  /// the app itself generates. Written out rather than pulling in a crypto
  /// dependency for sixteen characters.
  static String _fnv1a64(String input) {
    var hash = BigInt.parse('cbf29ce484222325', radix: 16);
    final prime = BigInt.parse('100000001b3', radix: 16);
    final mask = BigInt.parse('ffffffffffffffff', radix: 16);
    for (final byte in utf8.encode(input)) {
      hash = (hash ^ BigInt.from(byte)) * prime & mask;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  static String _filename(String storagePath) =>
      storagePath.split('/').last.isEmpty
      ? 'upload.jpg'
      : storagePath.split('/').last;

  Future<String> _put({
    required String bucketId,
    required String storagePath,
    required aw.InputFile file,
    required bool upsert,
  }) async {
    final fileId = fileIdFor(storagePath);
    try {
      await _storage.createFile(bucketId: bucketId, fileId: fileId, file: file);
    } on aw.AppwriteException catch (e) {
      final duplicate = classifyAppwriteFailure(e) == BackendFailure.duplicate;
      if (!duplicate) rethrow;
      if (!upsert) rethrow;
      // Appwrite has no replace: delete then create. A failure between the
      // two loses the old file, which is why this only runs when the
      // caller asked for an overwrite.
      await _storage.deleteFile(bucketId: bucketId, fileId: fileId);
      await _storage.createFile(bucketId: bucketId, fileId: fileId, file: file);
    }
    return fileUrl(bucketId: bucketId, fileId: fileId);
  }

  /// The URL the app stores on a document and later renders.
  ///
  /// `/view` rather than `/preview`: preview transformations are a paid
  /// feature on Cloud and the app already compresses before upload.
  static String fileUrl({required String bucketId, required String fileId}) =>
      '${AppwriteConfig.endpoint}/storage/buckets/$bucketId/files/$fileId/view'
      '?project=${AppwriteConfig.projectId}';

  @override
  Future<void> deleteFile({
    required String bucketId,
    required String storagePath,
  }) => _storage.deleteFile(bucketId: bucketId, fileId: fileIdFor(storagePath));

  @override
  Future<bool> ping() async {
    if (!isConfigured) return false;
    try {
      await _tables.listRows(
        databaseId: AppwriteConfig.databaseId,
        tableId: 'app_settings',
        queries: [aw.Query.limit(1)],
      );
      return true;
    } on Exception catch (e) {
      developer.log('ping failed: $e', name: 'AppwriteDataBackend');
      return false;
    }
  }

  /// Exposed so the auth adapter can share this backend's client rather
  /// than opening a second connection with its own cookie jar.
  aw.Client get client => _client;
}
