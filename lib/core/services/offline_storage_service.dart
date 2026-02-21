import 'package:hive_flutter/hive_flutter.dart';
import 'package:climate_app/core/services/hive_encryption_service.dart';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// Service for storing draft reports offline using Hive
/// Allows users to create reports without internet and sync later
/// All data is encrypted with AES-256 for security
class OfflineStorageService {
  static final OfflineStorageService _instance =
      OfflineStorageService._internal();
  factory OfflineStorageService() => _instance;
  OfflineStorageService._internal();

  static const String _draftsBoxName = 'draft_reports';
  static const String _syncQueueBoxName = 'sync_queue';
  static const String _contentCacheBoxName = 'content_cache';
  static const int _maxDrafts = 50;

  Box<Map>? _draftsBox;
  Box<Map>? _syncQueueBox;
  Box<Map>? _contentCacheBox;

  /// Initialize Hive boxes for offline storage with encryption
  Future<void> initialize() async {
    try {
      // Get encryption cipher
      final cipher = await HiveEncryptionService().getCipher();

      _draftsBox = await Hive.openBox<Map>(
        _draftsBoxName,
        encryptionCipher: cipher,
      );
      _syncQueueBox = await Hive.openBox<Map>(
        _syncQueueBoxName,
        encryptionCipher: cipher,
      );
      _contentCacheBox = await Hive.openBox<Map>(
        _contentCacheBoxName,
        encryptionCipher: cipher,
      );

      developer.log(
        'Offline storage initialized with AES-256 encryption. Drafts: ${_draftsBox!.length}, Queue: ${_syncQueueBox!.length}, Cache: ${_contentCacheBox!.length}',
        name: 'OfflineStorageService',
      );
    } on Exception catch (e) {
      developer.log(
        'Error initializing offline storage: $e',
        name: 'OfflineStorageService',
      );
      rethrow;
    }
  }

  /// Save a draft report
  Future<String> saveDraft({
    required String hazardType,
    required String severity,
    required String locationDetails,
    String? ward,
    String? lga,
    double? latitude,
    double? longitude,
    String? description,
    DateTime? reportDateTime,
    List<String>? imagePaths,
  }) async {
    _ensureInitialized();

    // Check if we've reached the max draft limit
    if (_draftsBox!.length >= _maxDrafts) {
      throw Exception('Maximum draft limit ($_maxDrafts) reached');
    }

    final draftId = DateTime.now().millisecondsSinceEpoch.toString();
    final draft = {
      'id': draftId,
      'hazardType': hazardType,
      'severity': severity,
      'locationDetails': locationDetails,
      'ward': ward,
      'lga': lga,
      'latitude': latitude ?? 0.0,
      'longitude': longitude ?? 0.0,
      'description': description ?? '',
      'reportDateTime':
          reportDateTime?.toIso8601String() ?? DateTime.now().toIso8601String(),
      'imagePaths': await _persistImages(imagePaths),
      'createdAt': DateTime.now().toIso8601String(),
      'status': 'draft',
    };

    await _draftsBox!.put(draftId, draft);
    developer.log('Draft saved: $draftId', name: 'OfflineStorageService');

    return draftId;
  }

  /// Get all drafts
  List<Map<String, dynamic>> getAllDrafts() {
    _ensureInitialized();

    return _draftsBox!.values
        .map((draft) => Map<String, dynamic>.from(draft))
        .toList()
      ..sort(
        (a, b) =>
            b['createdAt'].toString().compareTo(a['createdAt'].toString()),
      );
  }

  /// Get a specific draft by ID
  Map<String, dynamic>? getDraft(String draftId) {
    _ensureInitialized();

    final draft = _draftsBox!.get(draftId);
    return draft != null ? Map<String, dynamic>.from(draft) : null;
  }

  /// Update an existing draft
  Future<void> updateDraft(String draftId, Map<String, dynamic> updates) async {
    _ensureInitialized();

    final existing = _draftsBox!.get(draftId);
    if (existing == null) {
      throw Exception('Draft not found: $draftId');
    }

    final updated = Map<String, dynamic>.from(existing)..addAll(updates);
    await _draftsBox!.put(draftId, updated);

    developer.log('Draft updated: $draftId', name: 'OfflineStorageService');
  }

  /// Delete a draft
  Future<void> deleteDraft(String draftId) async {
    _ensureInitialized();
    final draft = _draftsBox!.get(draftId);

    // Delete associated persistent images
    if (draft != null && draft['imagePaths'] != null) {
      final paths = (draft['imagePaths'] as List).cast<String>();
      for (final imagePath in paths) {
        if (imagePath.contains('offline_images')) {
          try {
            final file = File(imagePath);
            if (await file.exists()) {
              await file.delete();
            }
          } on Exception catch (e) {
            developer.log(
              'Failed to clean up persistent image: $e',
              name: 'OfflineStorageService',
            );
          }
        }
      }
    }

    await _draftsBox!.delete(draftId);
    developer.log('Draft deleted: $draftId', name: 'OfflineStorageService');
  }

  /// Add report to sync queue (for reports that failed to submit)
  Future<void> addToSyncQueue(Map<String, dynamic> report) async {
    _ensureInitialized();

    final queueId = DateTime.now().millisecondsSinceEpoch.toString();
    final queueItem = {
      ...report,
      'createdAt': report['createdAt'] ?? DateTime.now().toIso8601String(),
      'queueId': queueId,
      'addedToQueueAt': DateTime.now().toIso8601String(),
      'retryCount': 0,
      'status': 'pending',
    };

    await _syncQueueBox!.put(queueId, queueItem);
    developer.log(
      'Added to sync queue: $queueId',
      name: 'OfflineStorageService',
    );
  }

  /// Get all items in sync queue
  List<Map<String, dynamic>> getSyncQueue() {
    _ensureInitialized();

    return _syncQueueBox!.values
        .map((item) => Map<String, dynamic>.from(item))
        .toList()
      ..sort(
        (a, b) => a['addedToQueueAt'].toString().compareTo(
          b['addedToQueueAt'].toString(),
        ),
      );
  }

  /// Get pending sync count
  int getPendingSyncCount() {
    _ensureInitialized();

    return _syncQueueBox!.values
        .where((item) => item['status'] == 'pending')
        .length;
  }

  /// Mark queue item as synced
  Future<void> markAsSynced(String queueId) async {
    _ensureInitialized();

    final item = _syncQueueBox!.get(queueId);
    if (item != null) {
      final updated = Map<String, dynamic>.from(item)
        ..['status'] = 'synced'
        ..['syncedAt'] = DateTime.now().toIso8601String();

      await _syncQueueBox!.put(queueId, updated);
      developer.log(
        'Marked as synced: $queueId',
        name: 'OfflineStorageService',
      );
    }
  }

  /// Mark queue item as failed
  Future<void> markAsFailed(String queueId, String error) async {
    _ensureInitialized();

    final item = _syncQueueBox!.get(queueId);
    if (item != null) {
      final retryCount = (item['retryCount'] as int?) ?? 0;
      final updated = Map<String, dynamic>.from(item)
        ..['status'] = 'failed'
        ..['retryCount'] = retryCount + 1
        ..['lastError'] = error
        ..['lastAttemptAt'] = DateTime.now().toIso8601String();

      await _syncQueueBox!.put(queueId, updated);
      developer.log(
        'Marked as failed: $queueId (retry: ${retryCount + 1})',
        name: 'OfflineStorageService',
      );
    }
  }

  /// Retry failed queue item
  Future<void> retryQueueItem(String queueId) async {
    _ensureInitialized();

    final item = _syncQueueBox!.get(queueId);
    if (item != null) {
      final updated = Map<String, dynamic>.from(item)..['status'] = 'pending';

      await _syncQueueBox!.put(queueId, updated);
      developer.log(
        'Retrying queue item: $queueId',
        name: 'OfflineStorageService',
      );
    }
  }

  /// Clear synced items from queue (cleanup)
  Future<void> clearSyncedItems() async {
    _ensureInitialized();

    final syncedKeys = _syncQueueBox!.values
        .where((item) => item['status'] == 'synced')
        .map((item) => item['queueId'] as String)
        .toList();

    await _syncQueueBox!.deleteAll(syncedKeys);
    developer.log(
      'Cleared ${syncedKeys.length} synced items',
      name: 'OfflineStorageService',
    );
  }

  /// Get draft count
  int getDraftCount() {
    _ensureInitialized();
    return _draftsBox!.length;
  }

  /// Clear all drafts (use with caution!)
  Future<void> clearAllDrafts() async {
    _ensureInitialized();
    await _draftsBox!.clear();

    // Clean up entire offline_images persistence directory
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final offlineImagesDir = Directory(
        path.join(appDir.path, 'offline_images'),
      );
      if (await offlineImagesDir.exists()) {
        await offlineImagesDir.delete(recursive: true);
      }
    } on Exception catch (e) {
      developer.log(
        'Failed to flush offline media directory: $e',
        name: 'OfflineStorageService',
      );
    }

    developer.log(
      'All drafts and offline images cleared',
      name: 'OfflineStorageService',
    );
  }

  /// Clear entire sync queue (use with caution!)
  Future<void> clearSyncQueue() async {
    _ensureInitialized();

    await _syncQueueBox!.clear();
    developer.log('Sync queue cleared', name: 'OfflineStorageService');
  }

  /// Check if storage is initialized
  bool get isInitialized =>
      _draftsBox != null && _syncQueueBox != null && _contentCacheBox != null;

  /// Ensure storage is initialized before operations
  void _ensureInitialized() {
    if (!isInitialized) {
      throw Exception(
        'OfflineStorageService not initialized. Call initialize() first.',
      );
    }
  }

  /// Helper to move volatile cache images to persistent application storage
  Future<List<String>> _persistImages(List<String>? volatilePaths) async {
    if (volatilePaths == null || volatilePaths.isEmpty) return [];

    final persistentPaths = <String>[];
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final persistentDir = Directory(path.join(appDir.path, 'offline_images'));

      if (!await persistentDir.exists()) {
        await persistentDir.create(recursive: true);
      }

      for (int i = 0; i < volatilePaths.length; i++) {
        final originalPath = volatilePaths[i];
        final originalFile = File(originalPath);

        if (await originalFile.exists()) {
          final extension = path.extension(originalPath);
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final newFileName = 'draft_img_${timestamp}_$i$extension';
          final newPath = path.join(persistentDir.path, newFileName);

          await originalFile.copy(newPath);
          persistentPaths.add(newPath);
        }
      }
    } on Exception catch (e) {
      developer.log(
        'Failed to persist images for offline draft: $e',
        name: 'OfflineStorageService',
      );
    }

    return persistentPaths.isNotEmpty ? persistentPaths : volatilePaths;
  }

  /// Cache guides details
  Future<void> cacheGuides(List<Map<String, dynamic>> guides) async {
    _ensureInitialized();
    await _contentCacheBox!.put('guides', {
      'data': guides,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Cache user profile
  Future<void> cacheUserProfile(Map<String, dynamic> profile) async {
    _ensureInitialized();
    await _contentCacheBox!.put('user_profile', {
      'data': profile,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Get cached user profile
  Map<String, dynamic>? getCachedUserProfile() {
    _ensureInitialized();
    final cached = _contentCacheBox!.get('user_profile');
    if (cached != null) {
      return Map<String, dynamic>.from(cached['data']);
    }
    return null;
  }

  /// Clear cached user profile
  Future<void> clearUserProfile() async {
    _ensureInitialized();
    await _contentCacheBox!.delete('user_profile');
    developer.log('Cleared cached user profile', name: 'OfflineStorageService');
  }

  /// Clear all user-specific data (profile, drafts, queue)
  /// Call this when logging out to prevent data leaks between users
  Future<void> clearUserData() async {
    _ensureInitialized();
    await clearUserProfile();
    await clearAllDrafts();
    await clearSyncQueue();
    developer.log(
      'All user data cleared (Profile, Drafts, Queue)',
      name: 'OfflineStorageService',
    );
  }

  /// Get cached guides
  List<Map<String, dynamic>> getCachedGuides() {
    _ensureInitialized();
    final cached = _contentCacheBox!.get('guides');
    if (cached != null && cached['data'] is List) {
      return (cached['data'] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  /// Cache alerts
  Future<void> cacheAlerts(List<Map<String, dynamic>> alerts) async {
    _ensureInitialized();
    await _contentCacheBox!.put('alerts', {
      'data': alerts,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Get cached alerts
  List<Map<String, dynamic>> getCachedAlerts() {
    _ensureInitialized();
    final cached = _contentCacheBox!.get('alerts');
    if (cached != null && cached['data'] is List) {
      return (cached['data'] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  /// Cache verifications
  Future<void> cacheVerifications(
    List<Map<String, dynamic>> verifications,
  ) async {
    _ensureInitialized();
    await _contentCacheBox!.put('verifications', {
      'data': verifications,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Get cached verifications
  List<Map<String, dynamic>> getCachedVerifications() {
    _ensureInitialized();
    final cached = _contentCacheBox!.get('verifications');
    if (cached != null && cached['data'] is List) {
      return (cached['data'] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  /// Get storage statistics
  Map<String, dynamic> getStats() {
    _ensureInitialized();

    final pending = _syncQueueBox!.values
        .where((item) => item['status'] == 'pending')
        .length;
    final failed = _syncQueueBox!.values
        .where((item) => item['status'] == 'failed')
        .length;
    final synced = _syncQueueBox!.values
        .where((item) => item['status'] == 'synced')
        .length;

    return {
      'totalDrafts': _draftsBox!.length,
      'maxDrafts': _maxDrafts,
      'pendingSync': pending,
      'failedSync': failed,
      'syncedItems': synced,
      'totalQueue': _syncQueueBox!.length,
    };
  }

  /// Close Hive boxes (call on app dispose)
  Future<void> dispose() async {
    await _draftsBox?.close();
    await _syncQueueBox?.close();
    await _contentCacheBox?.close();
    developer.log('Offline storage disposed', name: 'OfflineStorageService');
  }
}
