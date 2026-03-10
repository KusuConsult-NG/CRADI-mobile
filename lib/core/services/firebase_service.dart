import 'dart:developer' as developer;
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/core/services/rate_limiter.dart';
import 'package:climate_app/firebase_options.dart';

/// Central Firebase service — replaces AppwriteService.
///
/// Provides Auth (FirebaseAuth), Database (Firestore), and Storage (FirebaseStorage).
/// All public methods mirror the old AppwriteService surface so call-sites need
/// minimal changes.
class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal() {
    // Enable Firestore offline persistence — critical for intermittent connectivity
    // (Nigeria average mobile: ~15 Mbps but with high latency + frequent drops)
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final RateLimiter _rateLimiter = RateLimiter();

  // ───────────────────────── COLLECTION NAMES ──────────────────────────────

  static const String usersCollectionId = AppConfig.usersCollection;
  static const String reportsCollectionId = AppConfig.reportsCollection;
  static const String chatsCollectionId = AppConfig.chatsCollection;
  static const String messagesCollectionId = AppConfig.messagesCollection;
  static const String contactsCollectionId = AppConfig.contactsCollection;
  static const String trustedDevicesCollectionId =
      AppConfig.trustedDevicesCollection;
  static const String loginHistoryCollectionId =
      AppConfig.loginHistoryCollection;
  static const String knowledgeCollectionId = AppConfig.knowledgeBaseCollection;
  static const String alertsCollectionId = AppConfig.alertsCollection;
  static const String verificationsCollectionId =
      AppConfig.verificationsCollection;

  // Storage buckets (mirrored as paths in Firebase Storage)
  static const String profileImagesBucketId = 'profile_images';
  static const String reportImagesBucketId = 'report_images';

  // ───────────────────────────── AUTH ──────────────────────────────────────

  /// Stream that emits whenever the auth state changes.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Get the currently signed-in Firebase user (null if signed out).
  User? getCurrentUser() => _auth.currentUser;

  /// Reload the current user's Firebase profile from the server.
  Future<User?> reloadCurrentUser() async {
    try {
      await _auth.currentUser?.reload();
      return _auth.currentUser;
    } on FirebaseAuthException catch (e) {
      developer.log(
        'reloadCurrentUser error: ${e.message}',
        name: 'FirebaseService',
      );
      return null;
    }
  }

  /// Create a new user with email and password. Returns the Firebase [User].
  Future<User> createAccount({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await credential.user?.updateDisplayName(name);
      developer.log(
        'Account created: ${credential.user!.uid}',
        name: 'FirebaseService',
      );
      return credential.user!;
    } on FirebaseAuthException catch (e) {
      developer.log(
        'createAccount error: ${e.code} – ${e.message}',
        name: 'FirebaseService',
      );
      rethrow;
    }
  }

  /// Creates a new session strictly mapping to standard logic.
  /// Modified to use Firebase REST API to completely bypass strict
  /// Google Play Services cached Integrity blocks on Android devices.
  Future<User> createEmailPasswordSession({
    required String email,
    required String password,
  }) async {
    final rateLimitResult = await _rateLimiter.checkLoginAttempt();
    if (!rateLimitResult.allowed) {
      throw FirebaseAuthException(
        code: 'rate-limited',
        message: rateLimitResult.userMessage,
      );
    }

    try {
      // STEP 1: REST API
      http.Response signInRes;
      try {
        final apiKey = DefaultFirebaseOptions.currentPlatform.apiKey;
        final verifyUrl = Uri.parse(
          'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$apiKey',
        );

        signInRes = await http.post(
          verifyUrl,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email.trim(),
            'password': password,
            'returnSecureToken': true,
          }),
        );
      } catch (e) {
        throw FirebaseAuthException(
          code: 'unknown',
          message: 'STEP 1 FAILED (REST API Network): $e',
        );
      }

      final signInData = jsonDecode(signInRes.body);

      if (signInRes.statusCode != 200) {
        final errMessage = signInData['error']?['message'] ?? 'UNKNOWN_ERROR';
        if (errMessage.contains('EMAIL_NOT_FOUND')) {
          throw FirebaseAuthException(code: 'user-not-found');
        }
        if (errMessage.contains('INVALID_PASSWORD')) {
          throw FirebaseAuthException(code: 'wrong-password');
        }
        if (errMessage.contains('INVALID_LOGIN_CREDENTIALS')) {
          throw FirebaseAuthException(code: 'invalid-credential');
        }
        if (errMessage.contains('INVALID_EMAIL')) {
          throw FirebaseAuthException(code: 'invalid-email');
        }
        if (errMessage.contains('TOO_MANY_ATTEMPTS_TRY_LATER')) {
          throw FirebaseAuthException(code: 'too-many-requests');
        }
        if (errMessage.contains('USER_DISABLED')) {
          throw FirebaseAuthException(code: 'user-disabled');
        }
        throw FirebaseAuthException(
          code: 'unknown',
          message: 'STEP 1 FAILED (REST API Auth): $errMessage',
        );
      }

      final idToken = signInData['idToken'];

      // STEP 2: Cloud Function
      http.Response sfRes;
      try {
        final sfUrl = Uri.parse(
          'https://us-central1-ewer-8f788.cloudfunctions.net/mintCustomToken',
        );

        sfRes = await http.post(
          sfUrl,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
          },
        );
      } catch (e) {
        throw FirebaseAuthException(
          code: 'unknown',
          message: 'STEP 2 FAILED (Cloud Function Network): $e',
        );
      }

      final sfData = jsonDecode(sfRes.body);

      if (sfRes.statusCode != 200 || sfData['customToken'] == null) {
        throw FirebaseAuthException(
          code: 'unknown',
          message:
              'STEP 2 FAILED (Cloud Function Logic): ${sfData['error'] ?? 'Unknown Check'}',
        );
      }

      final customToken = sfData['customToken'];

      // STEP 3: SDK signInWithCustomToken
      UserCredential credential;
      try {
        credential = await _auth.signInWithCustomToken(customToken);
      } catch (e) {
        throw FirebaseAuthException(
          code: 'unknown',
          message: 'STEP 3 FAILED (Native SDK Custom Token): $e',
        );
      }

      await _rateLimiter.resetLoginAttempts();
      developer.log(
        'Signed in smoothly via REST fallback: ${credential.user!.uid}',
        name: 'FirebaseService',
      );
      return credential.user!;
    } on FirebaseAuthException catch (e) {
      final isCredentialError =
          e.code == 'wrong-password' ||
          e.code == 'user-not-found' ||
          e.code == 'invalid-credential' ||
          e.code == 'invalid-email';
      if (isCredentialError) {
        await _rateLimiter.recordFailedLogin();
      }
      developer.log(
        'signIn error [credential=$isCredentialError]: ${e.code} – ${e.message}',
        name: 'FirebaseService',
      );
      rethrow;
    }
  }

  /// Sign out the current user.
  Future<void> logout() async {
    try {
      // Clear Firestore offline persistence before signing out.
      // This prevents cached listeners from replaying on next app boot with
      // a stale/missing auth token, which causes PERMISSION_DENIED errors.
      try {
        await _db.clearPersistence();
        developer.log('Firestore cache cleared', name: 'FirebaseService');
      } on Exception catch (e) {
        developer.log(
          'clearPersistence failed (non-fatal): $e',
          name: 'FirebaseService',
        );
      }
      await _auth.signOut();
      developer.log('Signed out', name: 'FirebaseService');
    } on FirebaseAuthException catch (e) {
      developer.log('logout error: ${e.message}', name: 'FirebaseService');
      rethrow;
    }
  }

  /// Send a password reset email.
  Future<void> createRecovery({required String email}) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      developer.log(
        'createRecovery error: ${e.message}',
        name: 'FirebaseService',
      );
      rethrow;
    }
  }

  /// Send email verification to the current user.
  Future<void> sendEmailVerification() async {
    try {
      await _auth.currentUser?.sendEmailVerification();
    } on FirebaseAuthException catch (e) {
      developer.log(
        'sendEmailVerification error: ${e.message}',
        name: 'FirebaseService',
      );
      rethrow;
    }
  }

  /// Token auto-refreshes; this is a no-op kept for API compatibility.
  bool get isRefreshing => false;

  /// No-op: Firebase tokens refresh automatically. Kept for compatibility.
  void startSessionMonitoring() {
    developer.log(
      'startSessionMonitoring: Firebase auto-refreshes tokens, no-op.',
      name: 'FirebaseService',
    );
  }

  /// No-op: Firebase tokens refresh automatically. Kept for compatibility.
  void stopSessionMonitoring() {}

  /// Execute an API call with automatic FirebaseAuth error handling.
  Future<T> executeWithAuth<T>(Future<T> Function() apiCall) async {
    try {
      return await apiCall();
    } on FirebaseAuthException catch (e) {
      developer.log(
        'executeWithAuth FirebaseAuthException: ${e.code}',
        name: 'FirebaseService',
      );
      if (e.code == 'user-token-expired' ||
          e.code == 'user-not-found' ||
          e.code == 'invalid-user-token') {
        throw Exception('SESSION_EXPIRED');
      }
      rethrow;
    } on FirebaseException catch (e) {
      developer.log(
        'executeWithAuth FirebaseException: ${e.code}',
        name: 'FirebaseService',
      );
      if (e.code == 'permission-denied') {
        throw Exception('PERMISSION_DENIED');
      }
      rethrow;
    }
  }

  // ─────────────────────────── FIRESTORE ───────────────────────────────────

  /// Get a Firestore collection reference.
  CollectionReference<Map<String, dynamic>> collection(String collectionId) =>
      _db.collection(collectionId);

  /// Create a document. If [documentId] is null, Firestore auto-generates one.
  Future<Map<String, dynamic>> createDocument({
    required String collectionId,
    required Map<String, dynamic> data,
    String? documentId,
    // permissions param is a no-op (handled by Firestore security rules)
    List<String>? permissions,
  }) async {
    try {
      final ts = FieldValue.serverTimestamp();
      final payload = {...data, 'createdAt': ts, 'updatedAt': ts};

      DocumentReference<Map<String, dynamic>> ref;
      if (documentId != null && documentId.isNotEmpty) {
        ref = _db.collection(collectionId).doc(documentId);
        await ref.set(payload);
      } else {
        ref = await _db.collection(collectionId).add(payload);
      }

      final snapshot = await ref.get();
      final resultData = snapshot.data() ?? {};
      resultData['\$id'] = ref.id;
      developer.log(
        'Document created: ${ref.id} in $collectionId',
        name: 'FirebaseService',
      );
      return resultData;
    } on FirebaseException catch (e) {
      developer.log(
        'createDocument error: ${e.message}',
        name: 'FirebaseService',
      );
      rethrow;
    }
  }

  /// Get a single document by ID. Returns a map with `\$id` injected.
  Future<Map<String, dynamic>> getDocument({
    required String collectionId,
    required String documentId,
  }) async {
    try {
      final snapshot = await _db.collection(collectionId).doc(documentId).get();
      if (!snapshot.exists) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'not-found',
          message: 'Document $documentId not found in $collectionId',
        );
      }
      final data = snapshot.data() ?? {};
      data['\$id'] = snapshot.id;
      return data;
    } on FirebaseException catch (e) {
      developer.log('getDocument error: ${e.message}', name: 'FirebaseService');
      rethrow;
    }
  }

  /// List documents matching [queries]. Returns a list of maps each with `\$id`.
  ///
  /// [queries] is a list of [QueryFilter] objects (see below).
  Future<List<Map<String, dynamic>>> listDocuments({
    required String collectionId,
    List<QueryFilter>? queries,
    int? limitCount,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _db.collection(collectionId);

      if (queries != null) {
        for (final filter in queries) {
          query = filter.apply(query);
        }
      }

      if (limitCount != null) {
        query = query.limit(limitCount);
      }

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snapshot = await query.get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['\$id'] = doc.id;
        data['\$snapshot'] = doc;
        return data;
      }).toList();
    } on FirebaseException catch (e) {
      developer.log(
        'listDocuments error: ${e.message}',
        name: 'FirebaseService',
      );
      rethrow;
    }
  }

  /// Update specific fields in a document (partial update).
  Future<Map<String, dynamic>> updateDocument({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    try {
      final payload = {...data, 'updatedAt': FieldValue.serverTimestamp()};
      await _db.collection(collectionId).doc(documentId).update(payload);
      developer.log(
        'Document updated: $documentId in $collectionId',
        name: 'FirebaseService',
      );
      return await getDocument(
        collectionId: collectionId,
        documentId: documentId,
      );
    } on FirebaseException catch (e) {
      developer.log(
        'updateDocument error: ${e.message}',
        name: 'FirebaseService',
      );
      rethrow;
    }
  }

  /// Delete a document by ID.
  Future<void> deleteDocument({
    required String collectionId,
    required String documentId,
  }) async {
    try {
      await _db.collection(collectionId).doc(documentId).delete();
      developer.log(
        'Document deleted: $documentId in $collectionId',
        name: 'FirebaseService',
      );
    } on FirebaseException catch (e) {
      developer.log(
        'deleteDocument error: ${e.message}',
        name: 'FirebaseService',
      );
      rethrow;
    }
  }

  /// Subscribe to a Firestore collection with optional filters.
  /// Returns a [Stream] of document lists. Replaces Appwrite Realtime.
  Stream<List<Map<String, dynamic>>> subscribeToCollection({
    required String collectionId,
    List<QueryFilter>? queries,
  }) {
    Query<Map<String, dynamic>> query = _db.collection(collectionId);
    if (queries != null) {
      for (final filter in queries) {
        query = filter.apply(query);
      }
    }
    return query.snapshots().map(
      (snapshot) => snapshot.docs.map((doc) {
        final data = doc.data();
        data['\$id'] = doc.id;
        return data;
      }).toList(),
    );
  }

  /// Subscribe to a single document.
  Stream<Map<String, dynamic>?> subscribeToDocument({
    required String collectionId,
    required String documentId,
  }) {
    return _db.collection(collectionId).doc(documentId).snapshots().map((
      snapshot,
    ) {
      if (!snapshot.exists) return null;
      final data = snapshot.data()!;
      data['\$id'] = snapshot.id;
      return data;
    });
  }

  // ─────────────────────────── STORAGE ─────────────────────────────────────

  /// Upload bytes to Firebase Storage with automatic JPEG compression.
  /// Images are compressed to max 1920px, 85% quality before upload.
  Future<String> uploadFile({
    required String bucketId,
    required String filePath,
    required List<int> fileBytes,
    String? fileId,
  }) async {
    try {
      final name = fileId ?? '${DateTime.now().millisecondsSinceEpoch}';
      final ref = _storage.ref('$bucketId/$name');

      // Compress image bytes before upload (reduces 3-10MB photos to ~200-500KB)
      final compressed = await FlutterImageCompress.compressWithList(
        Uint8List.fromList(fileBytes),
        minWidth: 1920,
        minHeight: 1920,
        quality: 85,
        format: CompressFormat.jpeg,
      );
      final data = compressed.isNotEmpty
          ? compressed
          : Uint8List.fromList(fileBytes);

      final uploadTask = await ref.putData(
        data,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final url = await uploadTask.ref.getDownloadURL();
      developer.log(
        'File uploaded (original: ${fileBytes.length ~/ 1024}KB, compressed: ${data.length ~/ 1024}KB): $url',
        name: 'FirebaseService',
      );
      return url;
    } on FirebaseException catch (e) {
      developer.log('uploadFile error: ${e.message}', name: 'FirebaseService');
      rethrow;
    }
  }

  /// Upload a file from a [File] object with automatic image compression.
  Future<String> uploadFileFromPath({
    required String storagePath,
    required File file,
    String? contentType,
  }) async {
    try {
      final ref = _storage.ref(storagePath);
      final isImage = contentType?.startsWith('image/') ?? true;

      if (isImage) {
        // Compress image before upload — reduces 3-10MB photos to ~200-500KB
        final compressed = await FlutterImageCompress.compressWithFile(
          file.absolute.path,
          minWidth: 1920,
          minHeight: 1920,
          quality: 85,
          format: CompressFormat.jpeg,
        );
        if (compressed != null && compressed.isNotEmpty) {
          final uploadTask = await ref.putData(
            compressed,
            SettableMetadata(contentType: 'image/jpeg'),
          );
          final url = await uploadTask.ref.getDownloadURL();
          developer.log(
            'File compressed+uploaded (${compressed.length ~/ 1024}KB): $url',
            name: 'FirebaseService',
          );
          return url;
        }
      }

      // Fallback: upload original if not image or compression failed
      final metadata = contentType != null
          ? SettableMetadata(contentType: contentType)
          : null;
      final uploadTask = await ref.putFile(file, metadata);
      final url = await uploadTask.ref.getDownloadURL();
      developer.log('File uploaded from path: $url', name: 'FirebaseService');
      return url;
    } on FirebaseException catch (e) {
      developer.log(
        'uploadFileFromPath error: ${e.message}',
        name: 'FirebaseService',
      );
      rethrow;
    }
  }

  /// Delete a file from Firebase Storage by its full storage path.
  Future<void> deleteFile({required String storagePath}) async {
    try {
      await _storage.ref(storagePath).delete();
    } on FirebaseException catch (e) {
      developer.log('deleteFile error: ${e.message}', name: 'FirebaseService');
      rethrow;
    }
  }

  /// Test connectivity to Firebase.
  Future<bool> ping() async {
    try {
      await _db.collection('_ping').limit(1).get();
      return true;
    } on Exception catch (e) {
      developer.log('ping failed: $e', name: 'FirebaseService');
      return false;
    }
  }
}

// ────────────────────────── QUERY FILTER DSL ─────────────────────────────────
// Replaces Appwrite's Query.equal(), Query.notEqual(), etc.

abstract class QueryFilter {
  Query<Map<String, dynamic>> apply(Query<Map<String, dynamic>> query);
}

class WhereFilter extends QueryFilter {
  final String field;
  final dynamic isEqualTo;
  final dynamic isNotEqualTo;
  final dynamic isGreaterThan;
  final dynamic isLessThan;
  final dynamic arrayContains;

  WhereFilter(
    this.field, {
    this.isEqualTo,
    this.isNotEqualTo,
    this.isGreaterThan,
    this.isLessThan,
    this.arrayContains,
  });

  @override
  Query<Map<String, dynamic>> apply(Query<Map<String, dynamic>> query) {
    if (isEqualTo != null) {
      return query.where(field, isEqualTo: isEqualTo);
    }
    if (isNotEqualTo != null) {
      return query.where(field, isNotEqualTo: isNotEqualTo);
    }
    if (isGreaterThan != null) {
      return query.where(field, isGreaterThan: isGreaterThan);
    }
    if (isLessThan != null) {
      return query.where(field, isLessThan: isLessThan);
    }
    if (arrayContains != null) {
      return query.where(field, arrayContains: arrayContains);
    }
    return query;
  }
}

class OrderByFilter extends QueryFilter {
  final String field;
  final bool descending;

  OrderByFilter(this.field, {this.descending = false});

  @override
  Query<Map<String, dynamic>> apply(Query<Map<String, dynamic>> query) =>
      query.orderBy(field, descending: descending);
}

class LimitFilter extends QueryFilter {
  final int limit;
  LimitFilter(this.limit);

  @override
  Query<Map<String, dynamic>> apply(Query<Map<String, dynamic>> query) =>
      query.limit(limit);
}

// Convenience helpers matching Appwrite's Query static methods
class FQuery {
  FQuery._();
  static WhereFilter equal(String field, dynamic value) =>
      WhereFilter(field, isEqualTo: value);
  static WhereFilter notEqual(String field, dynamic value) =>
      WhereFilter(field, isNotEqualTo: value);
  static WhereFilter greaterThan(String field, dynamic value) =>
      WhereFilter(field, isGreaterThan: value);
  static WhereFilter lessThan(String field, dynamic value) =>
      WhereFilter(field, isLessThan: value);
  static WhereFilter contains(String field, dynamic value) =>
      WhereFilter(field, arrayContains: value);
  static OrderByFilter orderDesc(String field) =>
      OrderByFilter(field, descending: true);
  static OrderByFilter orderAsc(String field) =>
      OrderByFilter(field, descending: false);
  static LimitFilter limit(int n) => LimitFilter(n);
}
