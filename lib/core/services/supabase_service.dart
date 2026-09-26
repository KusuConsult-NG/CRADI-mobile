import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/core/services/rate_limiter.dart';

/// Central Supabase service — drop-in replacement for FirebaseService / AppwriteService.
///
/// Provides Auth (`supabase.auth`), Database (Postgres tables via PostgREST),
/// Realtime subscriptions, and Storage (`supabase.storage`).
///
/// Keeps the exact method signatures of FirebaseService so providers and screens
/// work without breaking.
class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  SupabaseClient get _client => Supabase.instance.client;
  final RateLimiter _rateLimiter = RateLimiter();

  // ───────────────────────── TABLE NAMES ──────────────────────────────
  static const String usersTable = 'profiles';
  static const String reportsTable = 'reports';
  static const String verificationsTable = 'verifications';
  static const String alertsTable = 'alerts';
  static const String chatsTable = 'chats';
  static const String messagesTable = 'messages';
  static const String contactsTable = 'emergency_contacts';
  static const String knowledgeTable = 'knowledge_base';
  static const String trustedDevicesTable = 'trusted_devices';
  static const String loginHistoryTable = 'login_history';

  // Storage buckets
  static const String profileImagesBucket = 'profile_images';
  static const String reportImagesBucket = 'report_images';

  // ───────────────────────────── AUTH ──────────────────────────────────────

  /// Stream emitting auth state changes
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  /// Get the currently signed-in Supabase user (null if signed out).
  User? getCurrentUser() => _client.auth.currentUser;

  /// Reload the current user's profile from the server.
  Future<User?> reloadCurrentUser() async {
    try {
      final res = await _client.auth.getUser();
      return res.user;
    } on Exception catch (e) {
      developer.log('reloadCurrentUser error: $e', name: 'SupabaseService');
      return null;
    }
  }

  /// Create a new user with email and password.
  Future<User> createAccount({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      final res = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'full_name': name},
      );

      final user = res.user;
      if (user == null) {
        throw const AuthException('User creation failed: No user returned');
      }

      developer.log('Account created: ${user.id}', name: 'SupabaseService');
      return user;
    } on AuthException catch (e) {
      developer.log(
        'createAccount error: ${e.message}',
        name: 'SupabaseService',
      );
      rethrow;
    }
  }

  /// Sign in with email and password with rate limiting.
  Future<User> createEmailPasswordSession({
    required String email,
    required String password,
  }) async {
    final rateLimitResult = await _rateLimiter.checkLoginAttempt();
    if (!rateLimitResult.allowed) {
      throw AuthException(rateLimitResult.userMessage);
    }

    try {
      final res = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );

      final user = res.user;
      if (user == null) {
        throw const AuthException('Login failed: Invalid credentials');
      }

      await _rateLimiter.resetLoginAttempts();
      developer.log(
        'Signed in successfully: ${user.id}',
        name: 'SupabaseService',
      );
      return user;
    } on AuthException catch (e) {
      await _rateLimiter.recordFailedLogin();
      developer.log('signIn error: ${e.message}', name: 'SupabaseService');
      rethrow;
    }
  }

  /// Sign out the current user.
  Future<void> logout() async {
    try {
      await _client.auth.signOut();
      developer.log('Signed out', name: 'SupabaseService');
    } catch (e) {
      developer.log('logout error: $e', name: 'SupabaseService');
      rethrow;
    }
  }

  /// Send password reset email.
  Future<void> createPasswordRecovery({required String email}) async {
    try {
      await _client.auth.resetPasswordForEmail(email.trim());
      developer.log('Password reset sent: $email', name: 'SupabaseService');
    } catch (e) {
      developer.log(
        'createPasswordRecovery error: $e',
        name: 'SupabaseService',
      );
      rethrow;
    }
  }

  /// Update password for the current user.
  Future<void> updatePassword({required String password}) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: password));
      developer.log('Password updated', name: 'SupabaseService');
    } catch (e) {
      developer.log('updatePassword error: $e', name: 'SupabaseService');
      rethrow;
    }
  }

  // ─────────────────────────── DATABASE (CRUD) ───────────────────────────

  /// Map legacy collection names to Supabase table names.
  String _mapCollection(String collectionId) {
    switch (collectionId) {
      case AppConfig.usersCollection:
        return usersTable;
      case AppConfig.reportsCollection:
        return reportsTable;
      case AppConfig.verificationsCollection:
        return verificationsTable;
      case AppConfig.alertsCollection:
        return alertsTable;
      case AppConfig.contactsCollection:
      case 'emergency_contacts':
        return contactsTable;
      case AppConfig.messagesCollection:
        return messagesTable;
      case AppConfig.knowledgeBaseCollection:
        return knowledgeTable;
      case AppConfig.trustedDevicesCollection:
        return trustedDevicesTable;
      case AppConfig.loginHistoryCollection:
        return loginHistoryTable;
      default:
        return collectionId;
    }
  }

  /// Create / insert a record in the database.
  Future<Map<String, dynamic>> createDocument({
    required String collectionId,
    required Map<String, dynamic> data,
    String? documentId,
    List<String>? permissions,
  }) async {
    try {
      final table = _mapCollection(collectionId);
      final payload = Map<String, dynamic>.from(data);
      if (documentId != null && documentId.isNotEmpty) {
        payload['id'] = documentId;
      }

      final res = await _client.from(table).insert(payload).select().single();
      final resultData = Map<String, dynamic>.from(res);
      resultData['\$id'] = resultData['id'];
      return resultData;
    } catch (e) {
      developer.log(
        'createDocument error in $collectionId: $e',
        name: 'SupabaseService',
      );
      rethrow;
    }
  }

  /// Get a single document by ID.
  Future<Map<String, dynamic>> getDocument({
    required String collectionId,
    required String documentId,
  }) async {
    try {
      final table = _mapCollection(collectionId);
      final res = await _client
          .from(table)
          .select()
          .eq('id', documentId)
          .single();
      final resultData = Map<String, dynamic>.from(res);
      resultData['\$id'] = resultData['id'];
      return resultData;
    } catch (e) {
      developer.log('getDocument error: $e', name: 'SupabaseService');
      rethrow;
    }
  }

  /// List documents with optional filters and limits.
  Future<List<Map<String, dynamic>>> listDocuments({
    required String collectionId,
    List<QueryFilter>? queries,
    int? limitCount,
  }) async {
    try {
      final table = _mapCollection(collectionId);
      dynamic builder = _client.from(table).select();

      if (queries != null) {
        for (final filter in queries) {
          builder = filter.applyToPostgrest(builder);
        }
      }

      if (limitCount != null) {
        builder = builder.limit(limitCount);
      }

      final res = await builder;
      final list = (res as List).map((row) {
        final map = Map<String, dynamic>.from(row as Map);
        map['\$id'] = map['id'];
        return map;
      }).toList();

      return list;
    } catch (e) {
      developer.log(
        'listDocuments error in $collectionId: $e',
        name: 'SupabaseService',
      );
      rethrow;
    }
  }

  /// Count documents matching [queries].
  Future<int> countDocuments({
    required String collectionId,
    List<QueryFilter>? queries,
  }) async {
    try {
      final table = _mapCollection(collectionId);
      dynamic builder = _client.from(table).select();

      if (queries != null) {
        for (final filter in queries) {
          builder = filter.applyToPostgrest(builder);
        }
      }

      final res = await builder.count(CountOption.exact);
      return res.count;
    } on Exception catch (e) {
      developer.log('countDocuments error: $e', name: 'SupabaseService');
      return 0;
    }
  }

  /// Update an existing document by ID.
  Future<Map<String, dynamic>> updateDocument({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    try {
      final table = _mapCollection(collectionId);
      final payload = Map<String, dynamic>.from(data)
        ..remove('id')
        ..remove('\$id');
      payload['updated_at'] = DateTime.now().toUtc().toIso8601String();

      final res = await _client
          .from(table)
          .update(payload)
          .eq('id', documentId)
          .select()
          .single();

      final resultData = Map<String, dynamic>.from(res);
      resultData['\$id'] = resultData['id'];
      return resultData;
    } catch (e) {
      developer.log('updateDocument error: $e', name: 'SupabaseService');
      rethrow;
    }
  }

  /// Delete a document by ID.
  Future<void> deleteDocument({
    required String collectionId,
    required String documentId,
  }) async {
    try {
      final table = _mapCollection(collectionId);
      await _client.from(table).delete().eq('id', documentId);
    } catch (e) {
      developer.log('deleteDocument error: $e', name: 'SupabaseService');
      rethrow;
    }
  }

  /// Subscribe to changes on a table (Realtime).
  Stream<List<Map<String, dynamic>>> subscribeToCollection({
    required String collectionId,
    List<QueryFilter>? queries,
  }) {
    final table = _mapCollection(collectionId);
    return _client
        .from(table)
        .stream(primaryKey: ['id'])
        .map(
          (rows) => rows.map((r) {
            final map = Map<String, dynamic>.from(r);
            map['\$id'] = map['id'];
            return map;
          }).toList(),
        );
  }

  // ─────────────────────────── STORAGE ─────────────────────────────────────

  /// Upload file from bytes with automatic compression.
  Future<String> uploadFile({
    required String bucketId,
    required String filePath,
    required List<int> fileBytes,
    String? fileId,
  }) async {
    try {
      final name = fileId ?? '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final storagePath = '$filePath/$name';

      final compressed = await FlutterImageCompress.compressWithList(
        Uint8List.fromList(fileBytes),
        minWidth: 1920,
        minHeight: 1920,
        quality: 85,
        format: CompressFormat.jpeg,
      );
      final uploadData = compressed.isNotEmpty
          ? compressed
          : Uint8List.fromList(fileBytes);

      await _client.storage
          .from(bucketId)
          .uploadBinary(
            storagePath,
            uploadData,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );

      return _client.storage.from(bucketId).getPublicUrl(storagePath);
    } catch (e) {
      developer.log('uploadFile error: $e', name: 'SupabaseService');
      rethrow;
    }
  }

  /// Upload file directly from a File object.
  Future<String> uploadFileFromPath({
    required String storagePath,
    required File file,
    String? contentType,
  }) async {
    try {
      final bucket = storagePath.startsWith('profile_images')
          ? profileImagesBucket
          : reportImagesBucket;
      final cleanPath = storagePath.replaceFirst('$bucket/', '');

      final compressed = await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        minWidth: 1920,
        minHeight: 1920,
        quality: 85,
        format: CompressFormat.jpeg,
      );

      final bytes = compressed ?? await file.readAsBytes();

      await _client.storage
          .from(bucket)
          .uploadBinary(
            cleanPath,
            bytes,
            fileOptions: FileOptions(
              contentType: contentType ?? 'image/jpeg',
              upsert: true,
            ),
          );

      return _client.storage.from(bucket).getPublicUrl(cleanPath);
    } catch (e) {
      developer.log('uploadFileFromPath error: $e', name: 'SupabaseService');
      rethrow;
    }
  }

  /// Delete a file from storage.
  Future<void> deleteFile({required String storagePath}) async {
    try {
      final parts = storagePath.split('/');
      final bucket = parts.first;
      final path = parts.sublist(1).join('/');
      await _client.storage.from(bucket).remove([path]);
    } catch (e) {
      developer.log('deleteFile error: $e', name: 'SupabaseService');
      rethrow;
    }
  }

  /// Test connectivity to Supabase.
  Future<bool> ping() async {
    try {
      await _client.from('profiles').select('id').limit(1);
      return true;
    } on Exception catch (e) {
      developer.log('ping failed: $e', name: 'SupabaseService');
      return false;
    }
  }
}

// ────────────────────────── QUERY FILTER DSL ─────────────────────────────────

abstract class QueryFilter {
  dynamic applyToPostgrest(dynamic builder);
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
  dynamic applyToPostgrest(dynamic builder) {
    if (isEqualTo != null) return builder.eq(field, isEqualTo);
    if (isNotEqualTo != null) return builder.neq(field, isNotEqualTo);
    if (isGreaterThan != null) return builder.gt(field, isGreaterThan);
    if (isLessThan != null) return builder.lt(field, isLessThan);
    if (arrayContains != null) return builder.contains(field, [arrayContains]);
    return builder;
  }
}

class OrderByFilter extends QueryFilter {
  final String field;
  final bool descending;

  OrderByFilter(this.field, {this.descending = false});

  @override
  dynamic applyToPostgrest(dynamic builder) {
    return builder.order(field, ascending: !descending);
  }
}

class LimitFilter extends QueryFilter {
  final int limit;
  LimitFilter(this.limit);

  @override
  dynamic applyToPostgrest(dynamic builder) {
    return builder.limit(limit);
  }
}

class SQuery {
  SQuery._();
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

/// Compatibility alias so existing code using FQuery works directly with SupabaseService
typedef FQuery = SQuery;
