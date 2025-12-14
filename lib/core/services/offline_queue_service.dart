import 'package:hive_flutter/hive_flutter.dart';
import 'dart:developer' as developer;

/// Service for queuing reports when offline
///
/// Stores reports locally using Hive and syncs to Firestore when connection restores.
/// This is a foundation - implement full sync logic as needed.
class OfflineQueueService {
  static final OfflineQueueService _instance = OfflineQueueService._internal();
  factory OfflineQueueService() => _instance;
  OfflineQueueService._internal();

  static const String _queueBoxName = 'offline_reports_queue';
  Box<Map<dynamic, dynamic>>? _queueBox;

  /// Initialize the offline queue
  Future<void> initialize() async {
    try {
      _queueBox = await Hive.openBox<Map<dynamic, dynamic>>(_queueBoxName);
      developer.log('Offline queue initialized', name: 'OfflineQueueService');
    } on Exception catch (e) {
      developer.log(
        'Error initializing queue: $e',
        name: 'OfflineQueueService',
      );
    }
  }

  /// Add a report to the offline queue
  Future<void> queueReport(Map<String, dynamic> reportData) async {
    if (_queueBox == null) {
      await initialize();
    }

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      await _queueBox!.put(timestamp, reportData);
      developer.log(
        'Report queued offline: $timestamp',
        name: 'OfflineQueueService',
      );
    } on Exception catch (e) {
      developer.log('Error queuing report: $e', name: 'OfflineQueueService');
      rethrow;
    }
  }

  /// Get all queued reports
  List<Map<String, dynamic>> getQueuedReports() {
    if (_queueBox == null) return [];

    return _queueBox!.values.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Remove a report from queue after successful sync
  Future<void> removeFromQueue(String key) async {
    try {
      await _queueBox?.delete(key);
      developer.log('Removed from queue: $key', name: 'OfflineQueueService');
    } on Exception catch (e) {
      developer.log(
        'Error removing from queue: $e',
        name: 'OfflineQueueService',
      );
    }
  }

  /// Get count of pending reports
  int get pendingCount => _queueBox?.length ?? 0;

  /// Clear all queued reports (use with caution)
  Future<void> clearQueue() async {
    try {
      await _queueBox?.clear();
      developer.log('Queue cleared', name: 'OfflineQueueService');
    } on Exception catch (e) {
      developer.log('Error clearing queue: $e', name: 'OfflineQueueService');
    }
  }

  // TODO: Implement sync logic
  // - Listen to connectivity changes
  // - Auto-sync when online
  // - Handle sync conflicts
  // - Retry failed syncs
}
