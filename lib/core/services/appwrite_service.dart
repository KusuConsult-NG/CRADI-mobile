import 'package:climate_app/core/config/app_config.dart';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'dart:async';
import 'dart:developer' as developer;
import 'package:climate_app/core/services/rate_limiter.dart';

/// Global Appwrite client instance
final Client client = Client()
    .setProject(AppConfig.appwriteProjectId)
    .setEndpoint(AppConfig.appwriteEndpoint);

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

  // Session refresh state
  Timer? _sessionRefreshTimer;
  bool _isRefreshing = false;

  // Database and Collection IDs
  static const String databaseId = AppConfig.appwriteDatabaseId;
  static const String usersCollectionId = AppConfig.usersCollection;
  static const String reportsCollectionId = AppConfig.reportsCollection;
  static const String chatsCollectionId = AppConfig.chatsCollection;
  static const String messagesCollectionId = AppConfig.messagesCollection;
  static const String contactsCollectionId = AppConfig.contactsCollection;
  static const String trustedDevicesCollectionId = AppConfig.devicesCollection;
  static const String loginHistoryCollectionId =
      AppConfig.loginHistoryCollection;
  static const String knowledgeCollectionId = AppConfig.knowledgeBaseCollection;
  static const String alertsCollectionId = AppConfig.alertsCollection;

  // Storage Bucket IDs
  static const String profileImagesBucketId = AppConfig.storageBucketId;
  static const String reportImagesBucketId = AppConfig.storageBucketId;

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

  /// Send password recovery email
  Future<models.Token> createRecovery({required String email}) async {
    try {
      // URL to redirect user to after resetting password.
      // Handled by the mobile app via uni_links.
      const url = 'https://cradi.org/reset-password';
      return await _account.createRecovery(email: email, url: url);
    } catch (e) {
      developer.log('Create recovery error: $e', name: 'AppwriteService');
      rethrow;
    }
  }

  /// Execute password reset using secret from email link
  Future<models.Token> resetPassword({
    required String userId,
    required String secret,
    required String password,
  }) async {
    try {
      return await _account.updateRecovery(
        userId: userId,
        secret: secret,
        password: password,
      );
    } catch (e) {
      developer.log('Reset password error: $e', name: 'AppwriteService');
      rethrow;
    }
  }

  /// Send email verification
  Future<models.Token> createVerification() async {
    try {
      // URL to redirect user to after verifying email.
      // Handled by the mobile app via uni_links.
      const url = 'https://cradi.org/verify-email';
      return await _account.createEmailVerification(url: url);
    } catch (e) {
      developer.log('Create verification error: $e', name: 'AppwriteService');
      rethrow;
    }
  }

  /// Verify email using the secret from the link
  Future<models.Token> updateVerification({
    required String userId,
    required String secret,
  }) async {
    try {
      return await _account.updateVerification(userId: userId, secret: secret);
    } on AppwriteException catch (e) {
      developer.log('Update verification error: $e', name: 'AppwriteService');
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

  /// Get current session
  Future<models.Session?> getCurrentSession() async {
    try {
      return await _account.getSession(sessionId: 'current');
    } on AppwriteException catch (e) {
      developer.log('Get session error: $e', name: 'AppwriteService');
      return null;
    }
  }

  /// Check if session needs refresh and refresh if necessary
  Future<bool> refreshSessionIfNeeded() async {
    if (_isRefreshing) {
      developer.log(
        'Session refresh already in progress',
        name: 'AppwriteService',
      );
      return false;
    }

    try {
      _isRefreshing = true;
      final session = await getCurrentSession();

      if (session == null) {
        developer.log('No active session to refresh', name: 'AppwriteService');
        return false;
      }

      final expiry = DateTime.parse(session.expire);
      final now = DateTime.now();
      final timeUntilExpiry = expiry.difference(now);

      // Refresh if less than 5 minutes remaining
      if (timeUntilExpiry.inMinutes < 5 && timeUntilExpiry.inSeconds > 0) {
        developer.log(
          'Refreshing session (expires in ${timeUntilExpiry.inMinutes} minutes)',
          name: 'AppwriteService',
        );

        // Update session to extend it
        await _account.updateSession(sessionId: 'current');

        developer.log(
          'Session refreshed successfully',
          name: 'AppwriteService',
        );
        return true;
      }

      return false;
    } on AppwriteException catch (e) {
      if (e.code == 401 || e.code == 403) {
        developer.log(
          'Session expired or unauthorized: ${e.message}',
          name: 'AppwriteService',
        );
        // Session is invalid, caller should handle logout
        return false;
      }
      developer.log('Session refresh error: $e', name: 'AppwriteService');
      return false;
    } finally {
      _isRefreshing = false;
    }
  }

  /// Start automatic session monitoring
  void startSessionMonitoring() {
    _sessionRefreshTimer?.cancel();

    // Check session every 2 minutes
    _sessionRefreshTimer = Timer.periodic(const Duration(minutes: 2), (
      _,
    ) async {
      await refreshSessionIfNeeded();
    });

    developer.log('Session monitoring started', name: 'AppwriteService');
  }

  /// Stop session monitoring
  void stopSessionMonitoring() {
    _sessionRefreshTimer?.cancel();
    _sessionRefreshTimer = null;
    developer.log('Session monitoring stopped', name: 'AppwriteService');
  }

  /// Logout (delete current session)
  Future<void> logout() async {
    try {
      stopSessionMonitoring();
      await _account.deleteSession(sessionId: 'current');
    } catch (e) {
      developer.log('Logout error: $e', name: 'AppwriteService');
      rethrow;
    }
  }

  /// Logout from all sessions
  Future<void> logoutAll() async {
    try {
      stopSessionMonitoring();
      await _account.deleteSessions();
    } catch (e) {
      developer.log('Logout all error: $e', name: 'AppwriteService');
      rethrow;
    }
  }

  /// Execute API call with automatic session refresh and error handling
  Future<T> executeWithAuth<T>(Future<T> Function() apiCall) async {
    try {
      // Try to refresh session if needed before API call
      await refreshSessionIfNeeded();

      // Execute the API call
      return await apiCall();
    } on AppwriteException catch (e) {
      // Handle authentication errors
      if (e.code == 401) {
        developer.log(
          'Unauthorized (401): Session expired - ${e.message}',
          name: 'AppwriteService',
        );
        stopSessionMonitoring();
        throw Exception('SESSION_EXPIRED');
      } else if (e.code == 403) {
        developer.log(
          'Forbidden (403): Insufficient permissions - ${e.message}',
          name: 'AppwriteService',
        );
        throw Exception('PERMISSION_DENIED');
      }

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
