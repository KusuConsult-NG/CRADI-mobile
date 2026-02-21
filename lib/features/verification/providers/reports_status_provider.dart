import 'package:flutter/material.dart';
import 'package:climate_app/core/services/appwrite_service.dart';
import 'package:climate_app/core/services/peer_verification_service.dart';
import 'package:climate_app/features/verification/models/verification_report_model.dart';
import 'dart:async';
import 'dart:developer' as developer;
import 'package:appwrite/appwrite.dart';

import 'package:climate_app/core/services/offline_storage_service.dart';

class ReportsStatusProvider extends ChangeNotifier {
  final AppwriteService _appwrite = AppwriteService();
  final OfflineStorageService _offlineStorage = OfflineStorageService();

  // Global loading state for submissions
  bool _isSubmitting = false;
  bool get isSubmitting => _isSubmitting;

  // State maps for different tabs/statuses
  final Map<String, List<VerificationReport>> _reportsMap = {};
  final Map<String, String?> _cursors = {};
  final Map<String, bool> _hasMoreMap = {};
  final Map<String, bool> _loadingMap = {};
  final Map<String, int> _totalCounts = {};

  // Getters for specific status
  List<VerificationReport> getReports(
    ReportStatus? status, {
    String? userId,
    String? excludeUserId,
  }) =>
      _reportsMap[_getKey(status, userId, excludeUserId: excludeUserId)] ?? [];
  bool hasMore(ReportStatus? status, {String? userId, String? excludeUserId}) =>
      _hasMoreMap[_getKey(status, userId, excludeUserId: excludeUserId)] ??
      true;
  bool isLoading(
    ReportStatus? status, {
    String? userId,
    String? excludeUserId,
  }) =>
      _loadingMap[_getKey(status, userId, excludeUserId: excludeUserId)] ??
      false;
  int getTotal(ReportStatus? status, {String? userId, String? excludeUserId}) =>
      _totalCounts[_getKey(status, userId, excludeUserId: excludeUserId)] ?? 0;

  String _getKey(
    ReportStatus? status,
    String? userId, {
    String? excludeUserId,
  }) =>
      '${status?.name ?? 'all'}_${userId ?? 'all'}_excl_${excludeUserId ?? 'none'}';

  /// Submit a verification request (supports offline)
  Future<void> submitVerificationRequest({
    required String hazardType,
    required String severity,
    required String description,
    required String userId,
    String? locationDetails,
    double? latitude,
    double? longitude,
  }) async {
    _isSubmitting = true; // Use global submitting state
    notifyListeners();

    final data = {
      'userId': userId,
      'description': description,
      'hazardType': hazardType,
      'severity': severity,
      'status': 'pending',
      'submittedAt': DateTime.now().toIso8601String(),
      'locationDetails': locationDetails ?? 'User Requested Verification',
      'latitude': latitude ?? 0.0,
      'longitude': longitude ?? 0.0,
      'isAlert':
          severity.toLowerCase() == 'critical' ||
          severity.toLowerCase() == 'high',
      'verificationCount': 0,
    };

    try {
      // Try online submission first
      await _appwrite.createDocument(
        collectionId: AppwriteService.reportsCollectionId,
        data: data,
      );
      developer.log('Verification request submitted online');
    } on Exception catch (e) {
      developer.log('Online submission failed, queuing offline: $e');
      // If failed (likely offline), add to sync queue
      try {
        await _offlineStorage.addToSyncQueue({
          ...data,
          'type':
              'verification_request', // Tag for sync worker to know how to handle
          'collectionId': AppwriteService.reportsCollectionId,
        });
        // We rethrow a specific exception so UI can show "Saved to Sync Queue" message
        throw AppwriteException(
          'Connection failed. Request saved to offline queue.',
          0,
          'offline_queued',
        );
      } catch (queueError) {
        // If even offline storage fails
        developer.log('Failed to save to offline queue: $queueError');
        rethrow;
      }
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> refreshReports({String? excludeUserId}) async {
    // Refresh all lists
    await fetchReports(status: null, excludeUserId: excludeUserId);
    await fetchReports(
      status: ReportStatus.pending,
      excludeUserId: excludeUserId,
    );
    await fetchReports(
      status: ReportStatus.acknowledged,
      excludeUserId: excludeUserId,
    );
    await fetchReports(
      status: ReportStatus.resolved,
      excludeUserId: excludeUserId,
    );
    await fetchReports(
      status: ReportStatus.rejected,
      excludeUserId: excludeUserId,
    );
  }

  /// Fetch reports with pagination
  Future<void> fetchReports({
    bool loadMore = false,
    ReportStatus? status,
    String? userId,
    String? excludeUserId,
  }) async {
    final key = _getKey(status, userId, excludeUserId: excludeUserId);

    if (loadMore) {
      if ((_hasMoreMap[key] == false) || (_loadingMap[key] == true)) return;
    } else {
      _hasMoreMap[key] = true;
      _cursors[key] = null;
      _reportsMap[key] = [];
    }

    _loadingMap[key] = true;
    notifyListeners();

    try {
      final List<String> queries = [
        Query.orderDesc('\$createdAt'),
        Query.limit(20),
      ];

      if (status != null) {
        String appwriteStatus;
        switch (status) {
          case ReportStatus.pending:
            appwriteStatus = 'pending';
            break;
          case ReportStatus.acknowledged:
            appwriteStatus = 'acknowledged';
            break;
          case ReportStatus.resolved:
            appwriteStatus = 'resolved';
            break;
          case ReportStatus.rejected:
            appwriteStatus = 'rejected';
            break;
        }
        queries.add(Query.equal('status', appwriteStatus));
      }

      if (userId != null) {
        queries.add(Query.equal('userId', userId));
      }

      if (excludeUserId != null) {
        queries.add(Query.notEqual('userId', excludeUserId));
      }

      if (loadMore && _cursors[key] != null) {
        queries.add(Query.cursorAfter(_cursors[key]!));
      }

      final docs = await _appwrite.listDocuments(
        collectionId: AppwriteService.reportsCollectionId,
        queries: queries,
      );

      _totalCounts[key] = docs.total;

      if (docs.documents.length < 20) {
        _hasMoreMap[key] = false;
      }

      final newReports = docs.documents.map((doc) {
        final data = doc.data;
        final status = _parseStatus(data['status']);
        return VerificationReport(
          id: doc.$id,
          title: _formatTitle(data['hazardType'] ?? 'Unknown Hazard'),
          type: data['hazardType'] ?? 'Unknown',
          reporter: 'Community Report',
          location: data['locationDetails'] ?? 'Unknown Location',
          time: _formatTimeAgo(data['submittedAt']),
          status: status,
          iconName: _getIconName(data['hazardType']),
          iconColor: _getIconColor(data['severity']),
          bgIconColor: '${_getIconColor(data['severity'])}_50',
        );
      }).toList();

      if (loadMore) {
        if (_reportsMap[key] == null) _reportsMap[key] = [];
        _reportsMap[key]!.addAll(newReports);
      } else {
        _reportsMap[key] = newReports;
      }

      if (docs.documents.isNotEmpty) {
        _cursors[key] = docs.documents.last.$id;
      } else {
        _hasMoreMap[key] = false;
      }
    } on Exception catch (e) {
      developer.log('Error fetching reports: $e');
    } finally {
      _loadingMap[key] = false;
      notifyListeners();
    }
  }

  /// Get all reports (for CSV export)
  Future<List<VerificationReport>> getAllReports() async {
    try {
      final docs = await _appwrite.listDocuments(
        collectionId: AppwriteService.reportsCollectionId,
      );

      return docs.documents.map((doc) {
        final data = doc.data;
        final status = _parseStatus(data['status']);

        return VerificationReport(
          id: doc.$id,
          title: _formatTitle(data['hazardType'] ?? 'Unknown'),
          type: data['hazardType'] ?? 'Unknown',
          reporter: 'Community Report',
          location: data['locationDetails'] ?? 'Unknown',
          time: _formatTimeAgo(data['submittedAt']),
          status: status,
          iconName: _getIconName(data['hazardType']),
          iconColor: _getIconColor(data['severity']),
          bgIconColor: '${_getIconColor(data['severity'])}_50',
        );
      }).toList();
    } on Exception catch (e) {
      developer.log('Error fetching all reports: $e');
      return [];
    }
  }

  /// Verify a report (move to acknowledged)
  Future<void> verifyReport(String reportId, {String? userId}) async {
    try {
      // Create verification record via PeerVerificationService
      await PeerVerificationService().submitVerification(
        reportId: reportId,
        userId: userId ?? 'system_admin',
        isConfirmed: true,
      );

      // Status update is handled inside `submitVerification` based on `minimumConfirmations`
      // But if we want to forcibly acknowledge it here as an admin action:
      await _appwrite.updateDocument(
        collectionId: AppwriteService.reportsCollectionId,
        documentId: reportId,
        data: {'status': 'acknowledged'},
      );

      developer.log('Report verified: $reportId');
      notifyListeners();
      // Refresh relevant lists
      fetchReports(status: ReportStatus.pending);
      fetchReports(status: ReportStatus.acknowledged);
    } on Exception catch (e) {
      developer.log('Error verifying report: $e');
      rethrow;
    }
  }

  /// Resolve a report (mark as resolved)
  Future<void> resolveReport(String reportId) async {
    try {
      await _appwrite.updateDocument(
        collectionId: AppwriteService.reportsCollectionId,
        documentId: reportId,
        data: {'status': 'resolved'},
      );
      developer.log('Report resolved: $reportId');
      notifyListeners();
      // Refresh relevant lists
      fetchReports(status: ReportStatus.acknowledged);
      fetchReports(status: ReportStatus.resolved);
    } on Exception catch (e) {
      developer.log('Error resolving report: $e');
      rethrow;
    }
  }

  /// Reject a report
  Future<void> rejectReport(String reportId, {String? userId}) async {
    try {
      // Create verification record via PeerVerificationService
      await PeerVerificationService().submitVerification(
        reportId: reportId,
        userId: userId ?? 'system_admin',
        isConfirmed: false,
      );

      // Force status update to rejected
      await _appwrite.updateDocument(
        collectionId: AppwriteService.reportsCollectionId,
        documentId: reportId,
        data: {'status': 'rejected'},
      );

      developer.log('Report rejected: $reportId');
      notifyListeners();
      // Refresh relevant lists
      fetchReports(status: ReportStatus.pending);
      fetchReports(status: ReportStatus.rejected);
    } on Exception catch (e) {
      developer.log('Error rejecting report: $e');
      rethrow;
    }
  }

  /// Move report back to pending (reopen)
  Future<void> moveBackToPending(String reportId) async {
    try {
      await _appwrite.updateDocument(
        collectionId: AppwriteService.reportsCollectionId,
        documentId: reportId,
        data: {'status': 'pending'},
      );
      developer.log('Report moved back to pending: $reportId');
      notifyListeners();
      // Refresh relevant lists (rough approximation, ideally we know source status)
      refreshReports();
    } on Exception catch (e) {
      developer.log('Error moving report to pending: $e');
      rethrow;
    }
  }

  /// Generate CSV report
  Future<String> generateCSVReport(ReportStatus? filterStatus) async {
    final reports = await getAllReports();
    final filteredReports = filterStatus != null
        ? reports.where((r) => r.status == filterStatus).toList()
        : reports;

    final buffer = StringBuffer();
    buffer.writeln(
      'ID,Title,Type,Reporter,Location,Time,Status,Verified Date,Resolved Date',
    );

    for (final report in filteredReports) {
      buffer.write('${report.id},');
      buffer.write('"${report.title}",');
      buffer.write('${report.type},');
      buffer.write('"${report.reporter}",');
      buffer.write('"${report.location}",');
      buffer.write('${report.time},');
      buffer.write(report.status.displayName);
      buffer.writeln();
    }

    return buffer.toString();
  }

  // Helper methods
  String _formatTitle(String hazardType) {
    switch (hazardType.toLowerCase()) {
      case 'flood':
        return 'Flood Alert';
      case 'drought':
        return 'Drought Warning';
      case 'extreme temperature':
        return 'Temperature Extreme';
      case 'high winds':
        return 'High Wind Alert';
      case 'erosion':
        return 'Erosion Report';
      case 'wildfire':
        return 'Wildfire Report';
      case 'crop disease':
        return 'Crop Disease';
      default:
        return hazardType;
    }
  }

  String _getIconName(String? hazardType) {
    switch (hazardType?.toLowerCase()) {
      case 'flood':
        return 'water';
      case 'drought':
        return 'water_drop';
      case 'wildfire':
        return 'local_fire_department';
      case 'crop disease':
        return 'pest_control';
      default:
        return 'warning';
    }
  }

  String _getIconColor(String? severity) {
    switch (severity?.toLowerCase()) {
      case 'low severity':
        return 'green';
      case 'medium severity':
        return 'orange';
      case 'high severity':
        return 'orange';
      case 'critical severity':
        return 'red';
      default:
        return 'orange';
    }
  }

  ReportStatus _parseStatus(String? status) {
    switch (status?.toLowerCase()) {
      case 'pending':
        return ReportStatus.pending;
      case 'acknowledged':
        return ReportStatus.acknowledged;
      case 'resolved':
        return ReportStatus.resolved;
      case 'rejected':
        return ReportStatus.rejected;
      default:
        return ReportStatus.pending;
    }
  }

  String _formatTimeAgo(dynamic timestamp) {
    if (timestamp == null) return 'Unknown';

    DateTime dateTime;
    if (timestamp is String) {
      try {
        dateTime = DateTime.parse(timestamp);
      } on Exception {
        return 'Unknown';
      }
    } else if (timestamp is DateTime) {
      dateTime = timestamp;
    } else {
      return 'Unknown';
    }

    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${(difference.inDays / 7).floor()}w ago';
    }
  }
}
