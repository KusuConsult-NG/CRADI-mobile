import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:appwrite/appwrite.dart' as aw;
import 'package:appwrite/enums.dart' show ExecutionMethod;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_image_compress/flutter_image_compress.dart';

import 'package:climate_app/core/services/appwrite/appwrite_config.dart';
import 'package:climate_app/core/services/appwrite/appwrite_documents.dart';
import 'package:climate_app/core/services/appwrite/appwrite_errors.dart';
import 'package:climate_app/core/services/appwrite/appwrite_queries.dart';
import 'package:climate_app/core/services/data_backend.dart';
import 'package:climate_app/core/utils/image_url_resolver.dart';

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

  /// A second client, used only for the websocket.
  ///
  /// Separate because Appwrite refuses a request that carries both a JWT
  /// and a session — `user_jwt_and_cookie_set`, 403 — so the JWT the
  /// socket needs cannot live on the client the REST calls use. This one
  /// carries the JWT and nothing else; `_client` keeps the session.
  aw.Client? _realtimeClient;

  aw.Client get _rtClient {
    final existing = _realtimeClient;
    if (existing != null) return existing;
    // `setEndpoint` derives the websocket URL itself, so the explicit
    // one is copied only when the caller overrode it — which a
    // self-hosted stack that publishes realtime on its own port does.
    final made = aw.Client()
        .setEndpoint(_client.endPoint)
        .setProject(_client.config['project'] ?? AppwriteConfig.projectId);
    final realtime = _client.endPointRealtime;
    if (realtime != null) made.setEndPointRealtime(realtime);
    return _realtimeClient = made;
  }

  aw.Realtime get _rt => _realtime ??= aw.Realtime(_rtClient);

  /// How long a minted realtime JWT is asked to live.
  ///
  /// Appwrite's maximum is an hour; shorter is safer and the refresh
  /// below is cheap.
  static const Duration _jwtLifetime = Duration(minutes: 15);

  /// Re-minted this long before expiry, so a socket that reconnects
  /// never picks up a token that is about to lapse.
  static const Duration _jwtRenewBefore = Duration(minutes: 3);

  DateTime? _jwtExpiresAt;
  Timer? _jwtTimer;

  /// Gives the websocket a credential it will actually send.
  ///
  /// `realtime_io` builds its handshake headers from exactly two places:
  /// the SDK's cookie jar, and `x-appwrite-jwt`. It never sends the
  /// session header that `Client.setSession` sets. CRADI establishes its
  /// session from a server-minted secret — the typed-code flow in
  /// `AppwriteAuthBackend._establish` — so no cookie is ever stored, and
  /// without this every subscription connects as a guest.
  ///
  /// The failure that causes is silent and easy to miss: the socket
  /// opens, the server accepts the channel, the initial page still loads
  /// because that goes over REST with the session header, and then no
  /// event for a document permissioned to `user:<id>` ever arrives. It
  /// looks exactly like a quiet collection.
  Future<void> _authenticateRealtime() async {
    if (_userId == null) return; // A guest has nothing to prove.
    final expires = _jwtExpiresAt;
    if (expires != null &&
        expires.isAfter(DateTime.now().add(_jwtRenewBefore))) {
      return;
    }
    await _mintRealtimeJwt();
  }

  Future<void> _mintRealtimeJwt() async {
    try {
      final jwt = await _account.createJWT(duration: _jwtLifetime.inSeconds);
      _rtClient.setJWT(jwt.jwt);
      // `setJWT` stores the token as `config['jWT']`, but
      // `realtime_io._getWebSocket` reads `config['jwt']` when it builds
      // the handshake headers — so on SDK 27 the socket never sends what
      // `setJWT` set. Writing the key realtime actually reads is the
      // whole fix; drop this when the SDK spells them the same.
      _rtClient.config['jwt'] = jwt.jwt;
      _jwtExpiresAt = DateTime.now().add(_jwtLifetime);
      _jwtTimer?.cancel();
      // Kept fresh in the background, because the SDK re-reads the stored
      // JWT only when it rebuilds the socket — on a reconnect, which is
      // precisely when an expired one would lock the stream out for good.
      _jwtTimer = Timer(_jwtLifetime - _jwtRenewBefore, () {
        unawaited(_mintRealtimeJwt());
      });
    } on aw.AppwriteException {
      // Leave whatever token is already set. A stale one still beats
      // none, and the next subscribe tries again.
    }
  }

  /// Stops the background JWT refresh. Call when signing out.
  void stopRealtimeAuth() {
    _jwtTimer?.cancel();
    _jwtTimer = null;
    _jwtExpiresAt = null;
  }

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

  /// The realtime channel for a collection, or for one document.
  ///
  /// A subscription to a channel the server does not publish fails
  /// *silently* — the socket connects, the server accepts the channel,
  /// and no event ever arrives. Appwrite 1.8 published only
  /// `databases.<db>.…`, so the SDK's `tablesdb.<db>.…` matched nothing.
  /// From 1.9 the server publishes each event under all three spellings
  /// (`tablesdb.…rows`, `databases.…rows`, `databases.…documents`), so
  /// the SDK's builder is right for every server it targets. The local
  /// stack is pinned to 1.9.6 for that reason; see
  /// `infra/appwrite/local/docker-compose.yml`.
  static aw.Channel _channelFor(String collectionId, [String? documentId]) =>
      aw.Channel.tablesdb(
        AppwriteConfig.databaseId,
      ).table(collectionId).row(documentId);

  @override
  Stream<List<Map<String, dynamic>>> subscribeToCollection({
    required String collectionId,
    List<QueryFilter>? queries,
  }) {
    if (!isConfigured) return const Stream.empty();
    final plan = DocumentPlan.build(queries);
    final channel = _channelFor(collectionId);

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

      await _authenticateRealtime();
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
    final channel = _channelFor(collectionId, documentId);

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

      await _authenticateRealtime();
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
      fileId: fileIdFor(storagePath),
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
      fileId: fileIdFor(storagePath),
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
  ///
  /// Capped at [_maxOwnIdLength], not Appwrite's 36, to leave room for
  /// [thumbFileIdFor]'s suffix — see [thumbUrlFor] for why a thumbnail's
  /// id has to be derivable from its photo's.
  static String fileIdFor(String storagePath) {
    final cleaned = storagePath.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
    final digest = _fnv1a64(storagePath);
    if (cleaned.length <= _maxOwnIdLength) {
      return cleaned.startsWith(RegExp(r'[._-]'))
          ? 'f${cleaned.substring(1)}'
          : cleaned;
    }
    // 17 characters of prefix + '-' + 16 hex = 34.
    final prefix = cleaned.substring(0, _maxOwnIdLength - 17);
    final head = prefix.startsWith(RegExp(r'[._-]'))
        ? 'f${prefix.substring(1)}'
        : prefix;
    return '$head-$digest';
  }

  /// Appwrite's limit on a file id.
  static const int _maxIdLength = 36;

  /// What [fileIdFor] may use, leaving [_thumbIdSuffix] room to fit.
  static const int _maxOwnIdLength = _maxIdLength - _thumbIdSuffix.length;

  /// Marks a thumbnail's id as belonging to the photo it was cut from.
  ///
  /// `-` and `_` are both legal in an Appwrite id and both occur inside
  /// a derived id, so this is not a delimiter that can be parsed back
  /// out — it does not need to be. Only one direction is ever needed:
  /// photo id -> thumbnail id.
  static const String _thumbIdSuffix = '-t';

  /// The id of the thumbnail cut from the file at [fileId].
  static String thumbFileIdFor(String fileId) => '$fileId$_thumbIdSuffix';

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
    required String fileId,
    required aw.InputFile file,
    required bool upsert,
  }) async {
    // The uploader's own rules. Buckets grant `read("any")` because the
    // image loader sends no credential; these add the owner-only rights
    // on top, so an avatar can be replaced by the person it belongs to
    // and by nobody else. The evidence bucket has `fileSecurity` off, so
    // it ignores these and stays write-once — which is intended.
    final owner = _userId;
    final permissions = owner == null
        ? null
        : [
            aw.Permission.read(aw.Role.any()),
            aw.Permission.update(aw.Role.user(owner)),
            aw.Permission.delete(aw.Role.user(owner)),
          ];
    try {
      await _storage.createFile(
        bucketId: bucketId,
        fileId: fileId,
        file: file,
        permissions: permissions,
      );
    } on aw.AppwriteException catch (e) {
      final duplicate = classifyAppwriteFailure(e) == BackendFailure.duplicate;
      if (!duplicate) rethrow;
      if (!upsert) rethrow;
      // Appwrite has no replace: delete then create. A failure between the
      // two loses the old file, which is why this only runs when the
      // caller asked for an overwrite.
      await _storage.deleteFile(bucketId: bucketId, fileId: fileId);
      await _storage.createFile(
        bucketId: bucketId,
        fileId: fileId,
        file: file,
        permissions: permissions,
      );
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

  /// A thumbnail is stored under its photo's id plus a suffix.
  ///
  /// Not under `thumbStoragePath`'s name, which is what Supabase uses:
  /// Appwrite addresses a file by a 36-character id that is a *digest*
  /// of the path, and a digest cannot be inverted — so a thumbnail named
  /// by path would be unreachable from the photo's URL, which is all the
  /// display code has. Keying the id off the photo's id keeps the
  /// "derived by convention, nothing persisted" property that
  /// `reports.imageUrls` relies on.
  ///
  /// The object still carries the `_thumb.jpg` filename, so it is
  /// recognisable in the console.
  @override
  Future<String> uploadThumbnailFromPath({
    required String bucketId,
    required String storagePath,
    required File file,
    int maxDimension = 320,
    int quality = 60,
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
      fileId: thumbFileIdFor(fileIdFor(storagePath)),
      file: aw.InputFile.fromBytes(
        bytes: compressed,
        filename: _filename(ImageUrlResolver.thumbStoragePath(storagePath)),
        contentType: 'image/jpeg',
      ),
      upsert: false,
    );
  }

  @override
  String? thumbUrlFor(String url) => thumbUrlForUrl(url);

  /// [url] with its file id swapped for its thumbnail's.
  ///
  /// Rewrites the URL that was given rather than rebuilding one from
  /// config, so the endpoint, the `project` query that `/view` is
  /// refused without, and anything else already on it all survive.
  @visibleForTesting
  static String? thumbUrlForUrl(String url) {
    final parsed = _parseFileUrl(url);
    if (parsed == null) return null;
    if (parsed.fileId.endsWith(_thumbIdSuffix)) return url;
    return parsed.rewritten(url, fileId: thumbFileIdFor(parsed.fileId));
  }

  /// Appwrite renders a smaller copy itself, through `/preview`.
  ///
  /// Off unless `APPWRITE_IMAGE_TRANSFORMS` is set at build time, because
  /// image transformations are a plan-gated feature on Cloud: asking for
  /// one where it is not included answers with an error rather than the
  /// image, and an image that does not load is worse than a large one
  /// that does. Self-hosted has no such limit.
  @override
  String displayUrl(String url, {int? width, int? quality}) =>
      AppwriteConfig.imageTransformsEnabled
      ? previewUrlFor(url, width: width, quality: quality)
      : url;

  /// [url] served by `/preview` at [width] / [quality], or unchanged when
  /// it is not one of this backend's file URLs or nothing was asked for.
  @visibleForTesting
  static String previewUrlFor(String url, {int? width, int? quality}) {
    final wanted = <String>[
      if (width != null && width > 0) 'width=$width',
      if (quality != null && quality > 0) 'quality=$quality',
    ];
    if (wanted.isEmpty) return url;
    final parsed = _parseFileUrl(url);
    if (parsed == null || parsed.action != 'view') return url;
    final asPreview = parsed.rewritten(url, action: 'preview');
    return '$asPreview${asPreview.contains('?') ? '&' : '?'}'
        '${wanted.join('&')}';
  }

  /// The bucket and file of one of this backend's own file URLs, or null.
  ///
  /// Deliberately narrow: an admin-set knowledge-base image on a third
  /// party's site, a `data:` URI, a leftover Supabase URL and a local
  /// path all have to come back null and be left alone.
  static _FileUrl? _parseFileUrl(String url) {
    final match = RegExp(
      r'/storage/buckets/([^/]+)/files/([^/?#]+)/(view|preview)(?=[/?#]|$)',
    ).firstMatch(url);
    if (match == null) return null;
    return _FileUrl(
      bucketId: match.group(1)!,
      fileId: match.group(2)!,
      action: match.group(3)!,
      start: match.start,
      end: match.end,
    );
  }

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

/// Where the bucket, file and action sit inside one of this backend's
/// file URLs, so a rewrite can replace a part in place and leave the
/// endpoint and query untouched.
class _FileUrl {
  const _FileUrl({
    required this.bucketId,
    required this.fileId,
    required this.action,
    required this.start,
    required this.end,
  });

  final String bucketId;
  final String fileId;

  /// `view` or `preview`.
  final String action;

  /// Where the matched `/storage/buckets/.../files/.../<action>` segment
  /// sits in the URL. Dart's `RegExpMatch` has no per-group offsets, so
  /// the segment is rebuilt whole and spliced back in.
  final int start;
  final int end;

  String rewritten(String url, {String? fileId, String? action}) =>
      url.replaceRange(
        start,
        end,
        '/storage/buckets/$bucketId/files/${fileId ?? this.fileId}'
        '/${action ?? this.action}',
      );
}
