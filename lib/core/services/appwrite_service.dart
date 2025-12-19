import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'dart:developer' as developer;
import 'package:climate_app/core/services/rate_limiter.dart';

/// Global Appwrite client instance
final Client client = Client()
    .setProject("6941cdb400050e7249d5")
    .setEndpoint("https://fra.cloud.appwrite.io/v1");

/// Comprehensive Appwrite service for managing backend operations
class AppwriteService {
  static final AppwriteService _instance = AppwriteService._internal();

  factory AppwriteService() => _instance;

  AppwriteService._internal() {
    _account = Account(client);
    _databases = Databases(client);
    _storage = Storage(client);
    _realtime = Realtime(client);
  }

  late final Account _account;
  late final Databases _databases;
  late final Storage _storage;
  late final Realtime _realtime;
  final RateLimiter _rateLimiter = RateLimiter();

  // Database and Collection IDs (will be created in Appwrite Console)
  static const String databaseId = '6941e2c2003705bb5a25'; // Actual database ID
  static const String usersCollectionId = 'users';
  static const String reportsCollectionId = 'reports';
  static const String chatsCollectionId = 'chats';
  static const String messagesCollectionId = 'messages';
  static const String contactsCollectionId = 'emergency_contacts';
  static const String trustedDevicesCollectionId = 'trusted_devices';
  static const String loginHistoryCollectionId = 'login_history';
  static const String knowledgeCollectionId = 'knowledge_base';

  // Storage Bucket IDs (using existing bucket due to plan limit)
  static const String profileImagesBucketId =
      '6941e4e10034186aded8'; // Shared bucket for all images
  static const String reportImagesBucketId =
      '6941e4e10034186aded8'; // Shared bucket for all images

  /// Get the global client instance
  Client get appwriteClient => client;

  // ==================== AUTHENTICATION ====================

  /// Create account with email and password
  Future<models.User> createAccount({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      return await _account.create(
        userId: ID.unique(),
        email: email,
        password: password,
        name: name,
      );
    } catch (e) {
      developer.log('Create account error: $e', name: 'AppwriteService');
      rethrow;
    }
  }

  /// Login with email and password (with rate limiting)
  Future<models.Session> createEmailPasswordSession({
    required String email,
    required String password,
  }) async {
    // Check rate limit
    final rateLimitResult = await _rateLimiter.checkLoginAttempt();
    if (!rateLimitResult.allowed) {
      throw Exception(rateLimitResult.userMessage);
    }

    try {
      final session = await _account.createEmailPasswordSession(
        email: email,
        password: password,
      );

      // Reset on successful login
      await _rateLimiter.resetLoginAttempts();
      return session;
    } catch (e) {
      // Record failed attempt
      await _rateLimiter.recordFailedLogin();
      developer.log('Login error: $e', name: 'AppwriteService');

      rethrow;
    }
  }

  /// Create email token (Email OTP)
  Future<models.Token> createEmailToken({required String email}) async {
    try {
      return await _account.createEmailToken(userId: ID.unique(), email: email);
    } catch (e) {
      developer.log('Email token error: $e', name: 'AppwriteService');
      rethrow;
    }
  }

  /// Create email session (Verify Email OTP)
  Future<models.Session> verifyEmailOTP({
    required String userId,
    required String secret,
  }) async {
    try {
      return await _account.createSession(userId: userId, secret: secret);
    } catch (e) {
      developer.log('Email session error: $e', name: 'AppwriteService');
      rethrow;
    }
  }

  /// Create phone session (SMS OTP)
  Future<models.Token> createPhoneToken({required String phone}) async {
    try {
      return await _account.createPhoneToken(userId: ID.unique(), phone: phone);
    } catch (e) {
      developer.log('Phone token error: $e', name: 'AppwriteService');
      rethrow;
    }
  }

  /// Verify phone with OTP
  Future<models.Session> createPhoneSession({
    required String userId,
    required String secret,
  }) async {
    try {
      // ignore: deprecated_member_use
      return await _account.updatePhoneSession(userId: userId, secret: secret);
    } on Exception catch (e) {
      developer.log('Phone session error: $e', name: 'AppwriteService');
      rethrow;
    }
  }

  /// Get current user
  Future<models.User?> getCurrentUser() async {
    try {
      return await _account.get();
    } on Exception catch (e) {
      developer.log('Get user error: $e', name: 'AppwriteService');
      return null;
    }
  }

  /// Logout (delete current session)
  Future<void> logout() async {
    try {
      await _account.deleteSession(sessionId: 'current');
    } catch (e) {
      developer.log('Logout error: $e', name: 'AppwriteService');
      rethrow;
    }
  }

  /// Logout from all sessions
  Future<void> logoutAll() async {
    try {
      await _account.deleteSessions();
    } catch (e) {
      developer.log('Logout all error: $e', name: 'AppwriteService');
      rethrow;
    }
  }

  // ==================== DATABASE ====================

  /// Create a document in a collection
  Future<models.Document> createDocument({
    required String collectionId,
    required Map<String, dynamic> data,
    String? documentId,
    List<String>? permissions,
  }) async {
    try {
      // ignore: deprecated_member_use
      return await _databases.createDocument(
        databaseId: databaseId,
        collectionId: collectionId,
        documentId: documentId ?? ID.unique(),
        data: data,
        permissions: permissions,
      );
    } catch (e) {
      developer.log('Create document error: $e', name: 'AppwriteService');
      rethrow;
    }
  }

  /// Get a document by ID
  Future<models.Document> getDocument({
    required String collectionId,
    required String documentId,
  }) async {
    try {
      // ignore: deprecated_member_use
      return await _databases.getDocument(
        databaseId: databaseId,
        collectionId: collectionId,
        documentId: documentId,
      );
    } catch (e) {
      developer.log('Get document error: $e', name: 'AppwriteService');
      rethrow;
    }
  }

  /// List documents with optional queries
  Future<models.DocumentList> listDocuments({
    required String collectionId,
    List<String>? queries,
  }) async {
    try {
      // ignore: deprecated_member_use
      return await _databases.listDocuments(
        databaseId: databaseId,
        collectionId: collectionId,
        queries: queries,
      );
    } catch (e) {
      developer.log('List documents error: $e', name: 'AppwriteService');
      rethrow;
    }
  }

  /// Update a document
  Future<models.Document> updateDocument({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    try {
      // ignore: deprecated_member_use
      return await _databases.updateDocument(
        databaseId: databaseId,
        collectionId: collectionId,
        documentId: documentId,
        data: data,
      );
    } catch (e) {
      developer.log('Update document error: $e', name: 'AppwriteService');
      rethrow;
    }
  }

  /// Delete a document
  Future<void> deleteDocument({
    required String collectionId,
    required String documentId,
  }) async {
    try {
      // ignore: deprecated_member_use
      await _databases.deleteDocument(
        databaseId: databaseId,
        collectionId: collectionId,
        documentId: documentId,
      );
    } catch (e) {
      developer.log('Delete document error: $e', name: 'AppwriteService');
      rethrow;
    }
  }

  // ==================== STORAGE ====================

  /// Upload a file to storage
  Future<models.File> uploadFile({
    required String bucketId,
    required String filePath,
    required List<int> fileBytes,
    String? fileId,
  }) async {
    try {
      return await _storage.createFile(
        bucketId: bucketId,
        fileId: fileId ?? ID.unique(),
        file: InputFile.fromBytes(
          bytes: fileBytes,
          filename: filePath.split('/').last,
        ),
      );
    } catch (e) {
      developer.log('Upload file error: $e', name: 'AppwriteService');
      rethrow;
    }
  }

  /// Get file preview URL
  String getFilePreview({
    required String bucketId,
    required String fileId,
    int? width,
    int? height,
  }) {
    return '${client.endPoint}/storage/buckets/$bucketId/files/$fileId/preview?project=${client.config['project']}&width=${width ?? 400}&height=${height ?? 400}';
  }

  /// Get file view URL
  String getFileView({required String bucketId, required String fileId}) {
    return '${client.endPoint}/storage/buckets/$bucketId/files/$fileId/view?project=${client.config['project']}';
  }

  /// Delete a file
  Future<void> deleteFile({
    required String bucketId,
    required String fileId,
  }) async {
    try {
      await _storage.deleteFile(bucketId: bucketId, fileId: fileId);
    } catch (e) {
      developer.log('Delete file error: $e', name: 'AppwriteService');
      rethrow;
    }
  }

  // ==================== REALTIME ====================

  /// Subscribe to realtime updates
  RealtimeSubscription subscribe({
    required List<String> channels,
    required void Function(RealtimeMessage) callback,
  }) {
    final subscription = _realtime.subscribe(channels);
    subscription.stream.listen(callback);
    return subscription;
  }

  /// Test connection to Appwrite server
  Future<void> ping() async {
    try {
      await client.ping();
      developer.log('Appwrite ping successful!', name: 'AppwriteService');
    } catch (e) {
      developer.log('Appwrite ping failed: $e', name: 'AppwriteService');
      rethrow;
    }
  }
}
