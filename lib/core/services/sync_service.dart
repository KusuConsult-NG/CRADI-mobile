import 'package:climate_app/core/services/offline_queue_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'dart:developer' as developer;

/// Service for synchronizing offline queued data with Firebase
///
/// Processes queued reports and uploads them when connection is restored
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final OfflineQueueService _queueService = OfflineQueueService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  bool _isSyncing = false;
  int _syncProgress = 0;
  int _totalToSync = 0;

  /// Whether a sync is currently in progress
  bool get isSyncing => _isSyncing;

  /// Current sync progress (0-100)
  int get syncProgress =>
      _totalToSync > 0 ? ((_syncProgress / _totalToSync) * 100).round() : 0;

  /// Initialize the sync service
  Future<void> initialize() async {
    await _queueService.initialize();
    developer.log('SyncService initialized', name: 'SyncService');
  }

  /// Sync all queued items to Firebase
  ///
  /// Returns number of successfully synced items
  Future<int> syncAll() async {
    if (_isSyncing) {
      developer.log('Sync already in progress', name: 'SyncService');
      return 0;
    }

    _isSyncing = true;
    _syncProgress = 0;

    try {
      final queuedReports = _queueService.getQueuedReports();
      _totalToSync = queuedReports.length;

      if (_totalToSync == 0) {
        developer.log('No items to sync', name: 'SyncService');
        return 0;
      }

      developer.log(
        'Starting sync for $_totalToSync items',
        name: 'SyncService',
      );

      int successCount = 0;

      for (final report in queuedReports) {
        try {
          await _syncReport(report);
          successCount++;
          _syncProgress++;
        } on Exception catch (e) {
          developer.log(
            'Failed to sync report: $e',
            name: 'SyncService',
            error: e,
          );
          // Continue with next item even if one fails
        }
      }

      developer.log(
        'Sync complete: $successCount/$_totalToSync successful',
        name: 'SyncService',
      );

      return successCount;
    } finally {
      _isSyncing = false;
      _syncProgress = 0;
      _totalToSync = 0;
    }
  }

  /// Sync a single report to Firebase
  Future<void> _syncReport(Map<String, dynamic> report) async {
    final reportId = report['id'] as String?;
    if (reportId == null) {
      throw Exception('Report missing ID');
    }

    try {
      // 1. Upload photos if any
      final photos = report['photos'] as List<dynamic>?;
      final List<String> photoUrls = [];

      if (photos != null && photos.isNotEmpty) {
        for (final photoPath in photos) {
          if (photoPath is String) {
            final url = await _uploadPhoto(photoPath, reportId);
            if (url != null) {
              photoUrls.add(url);
            }
          }
        }
      }

      // 2. Update report data with photo URLs
      final reportData = Map<String, dynamic>.from(report);
      reportData['photoUrls'] = photoUrls;
      reportData['syncedAt'] = FieldValue.serverTimestamp();
      reportData.remove('photos'); // Remove local paths

      // 3. Upload report to Firestore
      await _firestore
          .collection('reports')
          .doc(reportId)
          .set(reportData, SetOptions(merge: true));

      // 4. Remove from offline queue
      await _queueService.removeFromQueue(reportId);

      developer.log(
        'Report synced successfully: $reportId',
        name: 'SyncService',
      );
    } on Exception catch (e) {
      developer.log(
        'Error syncing report $reportId: $e',
        name: 'SyncService',
        error: e,
      );
      rethrow;
    }
  }

  /// Upload a photo to Firebase Storage
  ///
  /// Returns the download URL or null if upload fails
  Future<String?> _uploadPhoto(String localPath, String reportId) async {
    try {
      final file = File(localPath);
      if (!await file.exists()) {
        developer.log('Photo file not found: $localPath', name: 'SyncService');
        return null;
      }

      final fileName = localPath.split('/').last;
      final ref = _storage
          .ref()
          .child('reports')
          .child(reportId)
          .child(fileName);

      await ref.putFile(file);
      final url = await ref.getDownloadURL();

      return url;
    } on Exception catch (e) {
      developer.log('Error uploading photo: $e', name: 'SyncService', error: e);
      return null;
    }
  }

  /// Check if there are items pending sync
  bool hasPendingItems() {
    return _queueService.pendingCount > 0;
  }

  /// Get count of pending items
  int get pendingCount => _queueService.pendingCount;
}
