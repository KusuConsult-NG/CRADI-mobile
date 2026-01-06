import 'package:hive_flutter/hive_flutter.dart';
import 'dart:developer' as developer;

/// Service for storing draft reports offline using Hive
/// Allows users to create reports without internet and sync later
class OfflineStorageService {
  static final OfflineStorageService _instance =
      OfflineStorageService._internal();
  factory OfflineStorageService() => _instance;
  OfflineStorageService._internal();

  static const String _draftsBoxName = 'draft_reports';
  static const String _syncQueueBoxName = 'sync_queue';
  static const int _maxDrafts = 50;

  Box<Map>? _draftsBox;
  Box<Map>? _syncQueueBox;

  /// Initialize Hive boxes for offline storage
  Future<void> initialize() async {
    try {
      _draftsBox = await Hive.openBox<Map>(_draftsBoxName);
      _syncQueueBox = await Hive.openBox<Map>(_syncQueueBoxName);
      developer.log(
        'Offline storage initialized. Drafts: ${_draftsBox!.length}, Queue: ${_syncQueueBox!.length}',
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
      'latitude': latitude ?? 0.0,
      'longitude': longitude ?? 0.0,
      'description': description ?? '',
      'reportDateTime':
          reportDateTime?.toIso8601String() ?? DateTime.now().toIso8601String(),
      'imagePaths': imagePaths ?? [],
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

    await _draftsBox!.delete(draftId);
    developer.log('Draft deleted: $draftId', name: 'OfflineStorageService');
  }

  /// Add report to sync queue (for reports that failed to submit)
  Future<void> addToSyncQueue(Map<String, dynamic> report) async {
    _ensureInitialized();

    final queueId = DateTime.now().millisecondsSinceEpoch.toString();
    final queueItem = {
      ...report,
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
    developer.log('All drafts cleared', name: 'OfflineStorageService');
  }

  /// Clear entire sync queue (use with caution!)
  Future<void> clearSyncQueue() async {
    _ensureInitialized();

    await _syncQueueBox!.clear();
    developer.log('Sync queue cleared', name: 'OfflineStorageService');
  }

  /// Check if storage is initialized
  bool get isInitialized => _draftsBox != null && _syncQueueBox != null;

  /// Ensure storage is initialized before operations
  void _ensureInitialized() {
    if (!isInitialized) {
      throw Exception(
        'OfflineStorageService not initialized. Call initialize() first.',
      );
    }
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
    developer.log('Offline storage disposed', name: 'OfflineStorageService');
  }
}
