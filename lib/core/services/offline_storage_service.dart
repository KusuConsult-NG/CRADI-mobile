import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'package:climate_app/core/services/hive_encryption_service.dart';
import 'package:climate_app/core/services/backend.dart';
import 'package:climate_app/core/utils/error_handler.dart'
    show ValidationException;
import 'package:climate_app/core/l10n/l10n.dart';

/// Thrown when an online submission could not reach the server and the
/// payload was saved to the offline sync queue instead. The data is safe and
/// will be uploaded automatically; UIs should treat this as "saved".
class OfflineQueuedException implements Exception {
  const OfflineQueuedException([this.message = _defaultMessage]);

  /// Shown to the user (resolved in the current language).
  final LocalizedText message;

  static String _defaultMessage(AppLocalizations l) => l.offlineSavedWillSync;

  @override
  String toString() => message(englishL10n);
}

/// True for connectivity failures worth retrying later (no network, DNS,
/// timeouts, dropped connections, auth refresh that could not reach the
/// server).
bool isTransientNetworkError(Object error) =>
    error is SocketException ||
    error is TimeoutException ||
    error is HandshakeException ||
    error is http.ClientException ||
    // The backend's own retryable failures; the adapter knows which.
    isBackendTransient(error);

/// True when the server rejected the payload and retrying cannot succeed:
/// a permanent Postgres error, a storage upload refused with a 4xx status
/// (e.g. file too large, wrong type, not permitted — but not a timeout,
/// conflict or rate limit), or an image that can't be processed.
bool isPermanentSyncError(Object error) =>
    isBackendPermanent(error) || error is ImageEncodingException;

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

  /// Save a draft report. [userId] (the signed-in author) is stored so the
  /// draft is only ever uploaded as that user.
  ///
  /// An online submission interrupted while uploading photos passes its
  /// [reportId] and the [imageStoragePaths] (aligned with [imagePaths]) it
  /// was uploading to, so the sync reuses both: no duplicate report and no
  /// orphaned photos.
  Future<String> saveDraft({
    String? userId,
    String? reportId,
    List<String>? imageStoragePaths,
    required String hazardType,
    required String severity,
    required String locationDetails,
    String? ward,
    String? lga,
    String? state,
    double? latitude,
    double? longitude,
    String? description,
    DateTime? reportDateTime,
    List<String>? imagePaths,
  }) async {
    _ensureInitialized();

    // Check if we've reached the max draft limit
    if (_draftsBox!.length >= _maxDrafts) {
      throw ValidationException((l) => l.offlineDraftLimit(_maxDrafts));
    }

    final draftId = DateTime.now().millisecondsSinceEpoch.toString();
    final persistedImages = await _persistImages(imagePaths);
    final draft = {
      'id': draftId,
      'userId': userId,
      'hazardType': hazardType,
      'severity': severity,
      'locationDetails': locationDetails,
      'ward': ward,
      'lga': lga,
      'state': state,
      // Unknown coordinates stay null (never 0,0 — that is in the ocean).
      'latitude': latitude,
      'longitude': longitude,
      'description': description ?? '',
      'reportDateTime': (reportDateTime ?? DateTime.now())
          .toUtc()
          .toIso8601String(),
      'imagePaths': persistedImages,
      'reportId': ?reportId,
      // Only while still aligned with the stored images (a photo that
      // vanished meanwhile is dropped by _persistImages).
      if (imageStoragePaths != null &&
          imageStoragePaths.length == persistedImages.length)
        'imageStoragePaths': imageStoragePaths,
      'createdAt': DateTime.now().toIso8601String(),
      'status': 'draft',
    };

    await _draftsBox!.put(draftId, draft);
    developer.log('Draft saved: $draftId', name: 'OfflineStorageService');

    return draftId;
  }

  /// Get all drafts (empty before [initialize] has completed).
  List<Map<String, dynamic>> getAllDrafts() {
    if (!isInitialized) return [];

    return _draftsBox!.values
        .map((draft) => Map<String, dynamic>.from(draft))
        .toList()
      ..sort(
        (a, b) =>
            b['createdAt'].toString().compareTo(a['createdAt'].toString()),
      );
  }

  /// Author of a draft; null for drafts saved by older builds, whose owner
  /// is unknown.
  static String? draftOwner(Map draft) {
    final owner = draft['userId'];
    return owner is String && owner.isNotEmpty ? owner : null;
  }

  /// Drafts shown to [userId]: their own, plus ownerless (legacy) drafts
  /// that the user may submit as their own or discard.
  List<Map<String, dynamic>> getDraftsFor(String? userId) =>
      getAllDrafts().where((d) {
        final owner = draftOwner(d);
        return owner == null || owner == userId;
      }).toList();

  /// Whether [draft] may be uploaded automatically for [userId]: only the
  /// author's own drafts, never ownerless ones (the author is unknown on a
  /// shared device) nor drafts the server refused permanently.
  static bool isAutoSyncableDraft(Map draft, String userId) =>
      draftOwner(draft) == userId && draft['status'] != statusRejected;

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
    final storedPaths = draft?['imagePaths'];
    if (storedPaths is List) {
      // Entries written by an older build may not all be strings.
      final paths = storedPaths.whereType<String>();
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
  ///
  /// Callers pass the raw report map (with optional 'docId',
  /// 'collection'/'collectionId').  We extract the meta keys and
  /// wrap the remaining payload under a 'data' key so that
  /// [syncPendingReports] can reliably read it.
  Future<void> addToSyncQueue(Map<String, dynamic> report) async {
    _ensureInitialized();

    final queueId = DateTime.now().millisecondsSinceEpoch.toString();

    // Pull out meta keys that syncPendingReports uses directly
    final docId = report.remove('docId') as String?;
    final collection =
        (report.remove('collection') ??
                report.remove('collectionId') ??
                'reports')
            as String;

    final queueItem = {
      'data': report, // row payload (app field names)
      'docId': docId,
      'collection': collection,
      'createdAt': report['createdAt'] ?? DateTime.now().toIso8601String(),
      'queueId': queueId,
      'addedToQueueAt': DateTime.now().toIso8601String(),
      'retryCount': 0,
      'status': 'pending',
    };

    await _syncQueueBox!.put(queueId, queueItem);
    developer.log(
      'Added to sync queue: $queueId (collection: $collection)',
      name: 'OfflineStorageService',
    );
  }

  /// Queue item status for a payload the server refused permanently (RLS,
  /// constraint violations). Such items are never retried automatically;
  /// the user can retry or discard them from the offline screen.
  static const String statusRejected = 'rejected';

  /// Owner (report author) of a queue item, when recorded.
  static String? _itemOwner(Map item) {
    final data = item['data'];
    final owner = data is Map ? data['userId'] : item['userId'];
    return owner is String && owner.isNotEmpty ? owner : null;
  }

  /// Whether [item] may be shown to / synced for [userId]. Items of another
  /// account are hidden, also when nobody is signed in ([userId] null):
  /// only ownerless (legacy) items are visible then.
  static bool belongsTo(Map item, String? userId) {
    final owner = _itemOwner(item);
    return owner == null || owner == userId;
  }

  /// A queue item's retry count, whatever shape it was stored in (an older
  /// build, or a JSON round-trip, can leave it as a double or a string).
  /// Anything unreadable counts as no retries yet.
  static int retryCountOf(Map item) {
    final raw = item['retryCount'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse('$raw') ?? 0;
  }

  /// Whether a queue item will not be retried automatically any more.
  static bool isTerminalFailure(Map item) =>
      item['status'] == statusRejected ||
      (item['status'] == 'failed' && retryCountOf(item) >= maxSyncAttempts);

  /// Unsynced queue items (pending, failed or rejected) belonging to
  /// [userId] (only ownerless items when null). Safe to call before
  /// [initialize].
  List<Map<String, dynamic>> getUnsyncedItems({String? userId}) {
    if (!isInitialized) return [];
    return getSyncQueue()
        .where((item) => item['status'] != 'synced')
        .where((item) => belongsTo(item, userId))
        .toList();
  }

  /// Items that will not sync without user action (rejected by the server
  /// or out of retries). Safe to call before [initialize].
  List<Map<String, dynamic>> getFailedSyncItems({String? userId}) =>
      getUnsyncedItems(userId: userId).where(isTerminalFailure).toList();

  /// Removes a queue item (e.g. a permanently rejected submission the user
  /// chose to discard).
  Future<void> discardQueueItem(String queueId) async {
    _ensureInitialized();
    await _syncQueueBox!.delete(queueId);
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

  /// The retry count after a failed attempt: unchanged when the attempt
  /// does not count (transient network failure).
  static int nextRetryCount(int previous, {required bool countsAsRetry}) =>
      countsAsRetry ? previous + 1 : previous;

  /// Whether a sync failure should consume one of the item's retries.
  static bool failureCountsAsRetry(Object error) =>
      !isTransientNetworkError(error) && !isRateLimited(error);

  /// Mark queue item as failed.
  ///
  /// When [countsAsRetry] is false (a transient network failure: the device
  /// is offline / the server unreachable) the retry budget is not consumed,
  /// so an item is never given up on just because the phone was offline.
  Future<void> markAsFailed(
    String queueId,
    String error, {
    bool countsAsRetry = true,
  }) async {
    _ensureInitialized();

    final item = _syncQueueBox!.get(queueId);
    if (item != null) {
      final retryCount = nextRetryCount(
        retryCountOf(item),
        countsAsRetry: countsAsRetry,
      );
      final updated = Map<String, dynamic>.from(item)
        ..['status'] = 'failed'
        ..['retryCount'] = retryCount
        ..['lastError'] = error
        ..['lastAttemptAt'] = DateTime.now().toIso8601String();

      await _syncQueueBox!.put(queueId, updated);
      developer.log(
        'Marked as failed: $queueId (retry: $retryCount)',
        name: 'OfflineStorageService',
      );
    }
  }

  /// Mark a queue item as permanently rejected by the server; it is kept
  /// (visible on the offline screen) but no longer retried automatically.
  Future<void> markAsRejected(String queueId, String error) async {
    _ensureInitialized();

    final item = _syncQueueBox!.get(queueId);
    if (item != null) {
      final updated = Map<String, dynamic>.from(item)
        ..['status'] = statusRejected
        ..['lastError'] = error
        ..['lastAttemptAt'] = DateTime.now().toIso8601String();
      await _syncQueueBox!.put(queueId, updated);
      developer.log(
        'Marked as rejected (permanent): $queueId',
        name: 'OfflineStorageService',
      );
    }
  }

  /// Retry failed queue item (resets its attempt counter).
  Future<void> retryQueueItem(String queueId) async {
    _ensureInitialized();

    final item = _syncQueueBox!.get(queueId);
    if (item != null) {
      final updated = Map<String, dynamic>.from(item)
        ..['status'] = 'pending'
        ..['retryCount'] = 0;

      await _syncQueueBox!.put(queueId, updated);
      developer.log(
        'Retrying queue item: $queueId',
        name: 'OfflineStorageService',
      );
    }
  }

  /// Maximum number of attempts for a queued item before it is skipped.
  static const int maxSyncAttempts = 5;

  /// In-flight sync, used as a re-entrancy guard so that concurrent triggers
  /// (reconnect, dashboard open, manual sync) never process the queue twice.
  Future<Map<String, int>>? _syncInFlight;

  /// Sync all pending (and previously failed) queue items to Supabase.
  ///
  /// This is the single implementation of queue syncing. Concurrent calls
  /// share the same in-flight run. Items that have failed
  /// [maxSyncAttempts] times, items the server rejected permanently and
  /// items queued by another account are skipped.
  ///
  /// Returns a map with `synced`, `failed` and `rejected` counts.
  Future<Map<String, int>> syncPendingReports() {
    return _syncInFlight ??= _doSyncPendingReports().whenComplete(() {
      _syncInFlight = null;
    });
  }

  Future<Map<String, int>> _doSyncPendingReports() async {
    final currentUserId = backend.isConfigured ? backend.currentUserId : null;
    if (!isInitialized) {
      developer.log(
        'syncPendingReports: not initialized, skipping',
        name: 'OfflineStorageService',
      );
      return {'synced': 0, 'failed': 0, 'rejected': 0};
    }
    if (currentUserId == null) {
      // RLS stamps rows with auth.uid(); nothing can sync signed out.
      return {'synced': 0, 'failed': 0, 'rejected': 0};
    }

    final pending = _syncQueueBox!.values
        .where(
          (item) =>
              (item['status'] == 'pending' || item['status'] == 'failed') &&
              retryCountOf(item) < maxSyncAttempts &&
              // Items queued by another account would be refused by RLS
              // (and must never be attributed to this user).
              belongsTo(item, currentUserId),
        )
        .toList();

    if (pending.isEmpty) {
      developer.log(
        'syncPendingReports: no pending items',
        name: 'OfflineStorageService',
      );
      return {'synced': 0, 'failed': 0, 'rejected': 0};
    }

    developer.log(
      'syncPendingReports: syncing ${pending.length} items',
      name: 'OfflineStorageService',
    );

    final db = backend;
    int successCount = 0;
    int failCount = 0;
    int rejectedCount = 0;

    for (final rawItem in pending) {
      final item = Map<String, dynamic>.from(rawItem);
      final queueId = item['queueId'] as String? ?? '';
      if (queueId.isEmpty) continue;

      try {
        final collection =
            (item['collection'] ?? item['collectionId'] ?? 'reports') as String;
        final Map<String, dynamic> data;
        if (item['data'] is Map) {
          // Current format: the row payload is wrapped under 'data'.
          data = Map<String, dynamic>.from(item['data'] as Map);
        } else {
          // Legacy flat format: strip queue-meta keys (including the queue
          // item's own 'status', which is not the report status).
          data = Map<String, dynamic>.from(item)
            ..removeWhere(
              (k, _) => const {
                'queueId',
                'addedToQueueAt',
                'retryCount',
                'status',
                'lastError',
                'lastAttemptAt',
                'syncedAt',
                'collection',
                'collectionId',
                'docId',
              }.contains(k),
            );
        }
        data
          ..remove('collection')
          ..remove('collectionId')
          ..remove('docId');
        stampForSync(collection, data);

        // With a known id, upsert idempotently (a row that already exists
        // was synced by an earlier attempt and is left untouched);
        // otherwise insert a new row.
        final docId = item['docId'] as String?;
        if (docId != null && docId.isNotEmpty) {
          await db.upsertDocument(
            collectionId: collection,
            documentId: docId,
            data: data,
            ignoreDuplicates: true,
          );
        } else {
          await db.createDocument(collectionId: collection, data: data);
        }

        await markAsSynced(queueId);
        successCount++;
      } on Exception catch (e) {
        if (isDuplicate(e)) {
          // Already inserted by an earlier attempt.
          await markAsSynced(queueId);
          successCount++;
          continue;
        }
        if (isPermanentSyncError(e)) {
          await markAsRejected(queueId, backendDiagnosticOf(e) ?? e.toString());
          rejectedCount++;
        } else {
          await markAsFailed(
            queueId,
            e.toString(),
            countsAsRetry: failureCountsAsRetry(e),
          );
          failCount++;
        }
        developer.log(
          'syncPendingReports: failed item $queueId: $e',
          name: 'OfflineStorageService',
        );
      }
    }

    // Cleanup synced entries
    if (successCount > 0) await clearSyncedItems();

    developer.log(
      'syncPendingReports: $successCount/${pending.length} synced successfully',
      name: 'OfflineStorageService',
    );
    return {
      'synced': successCount,
      'failed': failCount,
      'rejected': rejectedCount,
    };
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
      'data': guides.map((g) => _sanitizeForHive(g)).toList(),
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Cache user profile
  Future<void> cacheUserProfile(Map<String, dynamic> profile) async {
    _ensureInitialized();
    await _contentCacheBox!.put('user_profile', {
      'data': _sanitizeForHive(profile),
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Get cached user profile
  Map<String, dynamic>? getCachedUserProfile() {
    _ensureInitialized();
    final cached = _contentCacheBox!.get('user_profile');
    if (cached != null && cached['data'] is Map) {
      if (_isCacheStale(cached)) {
        _contentCacheBox!.delete('user_profile');
        return null;
      }
      return Map<String, dynamic>.from(cached['data'] as Map);
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

  /// Get cached guides.
  ///
  /// Served regardless of age and never deleted on read: this is the
  /// offline fallback, and guides rarely change, so an old copy is far
  /// better than none. The cache is refreshed whenever the guides are
  /// fetched online (see KnowledgeProvider.fetchGuides).
  ///
  /// Returns null when nothing was ever cached. An empty list means the
  /// server had no guides at the last successful fetch.
  List<Map<String, dynamic>>? getCachedGuides() {
    _ensureInitialized();
    final cached = _contentCacheBox!.get('guides');
    if (cached != null && cached['data'] is List) {
      return (cached['data'] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return null;
  }

  /// Cache alerts
  Future<void> cacheAlerts(List<Map<String, dynamic>> alerts) async {
    _ensureInitialized();
    await _contentCacheBox!.put('alerts', {
      'data': alerts.map((a) => _sanitizeForHive(a)).toList(),
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Get cached alerts
  List<Map<String, dynamic>> getCachedAlerts() {
    _ensureInitialized();
    final cached = _contentCacheBox!.get('alerts');
    if (cached != null && cached['data'] is List) {
      if (_isCacheStale(cached)) {
        _contentCacheBox!.delete('alerts');
        return [];
      }
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
      'data': verifications.map((v) => _sanitizeForHive(v)).toList(),
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Get cached verifications
  List<Map<String, dynamic>> getCachedVerifications() {
    _ensureInitialized();
    final cached = _contentCacheBox!.get('verifications');
    if (cached != null && cached['data'] is List) {
      if (_isCacheStale(cached)) {
        _contentCacheBox!.delete('verifications');
        return [];
      }
      return (cached['data'] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  /// Returns true when a cached entry is older than [maxAge] (default 24 hours).
  bool _isCacheStale(Map entry, {Duration maxAge = const Duration(hours: 24)}) {
    final raw = entry['timestamp'];
    if (raw == null) return true;
    final cached = raw is DateTime ? raw : DateTime.tryParse('$raw');
    if (cached == null) return true;
    // A device clock that has moved backwards makes the difference
    // negative; that is never "stale", so cached content keeps serving.
    return DateTime.now().difference(cached) > maxAge;
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
    final rejected = _syncQueueBox!.values
        .where((item) => item['status'] == statusRejected)
        .length;

    return {
      'totalDrafts': _draftsBox!.length,
      'maxDrafts': _maxDrafts,
      'pendingSync': pending,
      'failedSync': failed,
      'rejectedSync': rejected,
      'syncedItems': synced,
      'totalQueue': _syncQueueBox!.length,
    };
  }

  /// Closes the hive boxes
  Future<void> close() async {
    await _draftsBox?.close();
    await _syncQueueBox?.close();
    await _contentCacheBox?.close();
    developer.log('Offline storage disposed', name: 'OfflineStorageService');
  }

  /// Sanitizes maps before sending them to hive.
  ///
  /// Hive can only store primitives, lists and maps of those. DateTimes are
  /// converted to ISO strings and anything else that Hive cannot serialize
  /// is dropped.
  Map<String, dynamic> _sanitizeForHive(Map<dynamic, dynamic> data) {
    final Map<String, dynamic> sanitized = {};
    data.forEach((key, value) {
      final converted = _sanitizeValue(value);
      if (converted != _unsupported) sanitized[key.toString()] = converted;
    });
    return sanitized;
  }

  static const Object _unsupported = Object();

  Object? _sanitizeValue(Object? value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is DateTime) return value.toIso8601String();
    if (value is Map) return _sanitizeForHive(value);
    if (value is List) {
      return value.map(_sanitizeValue).where((e) => e != _unsupported).toList();
    }
    // Anything else cannot be stored in Hive.
    return _unsupported;
  }
}

/// What the queue adds to a row on its way out, by collection.
///
/// Both of these used to be written inline in the sync loop, and the
/// second was written for every collection:
///
///  - `status` is forced to `pending` because a new report may only be
///    inserted pending; the server would refuse anything else.
///  - `syncedAt` is a column **`reports` has and nothing else does**.
///    Appwrite refuses a field a collection does not declare — a 400
///    `document_invalid_structure` — which this queue classifies as
///    permanent and answers by marking the item rejected. So stamping it
///    on every collection meant the first queued write of anything but a
///    report would be thrown away instead of retried, and a field
///    agent's queued work is the one thing here that cannot be
///    recreated.
///
/// `createdAt` and `updatedAt` are the server's and are not sent.
///
/// Pulled out of the loop so it can be tested without Hive and without a
/// backend: it is the whole of the decision, and the loop does nothing
/// else to the payload.
@visibleForTesting
void stampForSync(String collection, Map<String, dynamic> data) {
  if (collection != 'reports') return;
  data['status'] = 'pending';
  data['syncedAt'] = DateTime.now();
}
