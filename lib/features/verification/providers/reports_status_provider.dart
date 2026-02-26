import 'package:flutter/material.dart';
import 'package:climate_app/core/services/firebase_service.dart';
import 'package:climate_app/core/services/peer_verification_service.dart';
import 'package:climate_app/features/verification/models/verification_report_model.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'dart:async';
import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:climate_app/core/services/offline_storage_service.dart';

class ReportsStatusProvider extends ChangeNotifier {
  final FirebaseService _firebase = FirebaseService();
  final OfflineStorageService _offlineStorage = OfflineStorageService();

  bool _isSubmitting = false;
  bool get isSubmitting => _isSubmitting;

  final Map<String, List<VerificationReport>> _reportsMap = {};
  final Map<String, DocumentSnapshot?> _lastDocMap = {};
  final Map<String, bool> _hasMoreMap = {};
  final Map<String, bool> _loadingMap = {};
  final Map<String, int> _totalCounts = {};

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

  Future<void> submitVerificationRequest({
    required String hazardType,
    required String severity,
    required String description,
    required String userId,
    required String state,
    required String lga,
    required String ward,
    String? locationDetails,
    double? latitude,
    double? longitude,
  }) async {
    _isSubmitting = true;
    notifyListeners();

    final defaultLocation = locationDetails ?? 'User Requested Verification';
    final data = {
      'userId': userId,
      'description': description,
      'hazardType': hazardType,
      'severity': severity,
      'status': 'pending',
      'submittedAt': DateTime.now().toIso8601String(),
      'locationDetails': defaultLocation,
      'location': defaultLocation,
      'address': defaultLocation,
      'ward': ward,
      'lga': lga,
      'state': state,
      'latitude': latitude ?? 0.0,
      'longitude': longitude ?? 0.0,
      'imageUrls': [],
      'isAlert':
          severity.toLowerCase() == 'critical' ||
          severity.toLowerCase() == 'high',
      'verificationCount': 0,
    };

    try {
      await _firebase.createDocument(
        collectionId: AppConfig.reportsCollection,
        data: data,
      );
      developer.log('Verification request submitted online');
    } on FirebaseException catch (e) {
      developer.log('Online submission failed, queuing offline: $e');
      try {
        await _offlineStorage.addToSyncQueue({
          ...data,
          'type': 'verification_request',
          'collectionId': AppConfig.reportsCollection,
        });
        // Re-throw with offline indicator for UI
        throw Exception('Connection failed. Request saved to offline queue.');
      } on Exception catch (queueError) {
        developer.log('Failed to save to offline queue: $queueError');
        rethrow;
      }
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> refreshReports({String? excludeUserId}) async {
    await Future.wait([
      fetchReports(status: null, excludeUserId: excludeUserId),
      fetchReports(status: ReportStatus.pending, excludeUserId: excludeUserId),
      fetchReports(
        status: ReportStatus.acknowledged,
        excludeUserId: excludeUserId,
      ),
      fetchReports(status: ReportStatus.resolved, excludeUserId: excludeUserId),
      fetchReports(status: ReportStatus.rejected, excludeUserId: excludeUserId),
    ]);
  }

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
      _lastDocMap[key] = null;
      _reportsMap[key] = [];
    }

    _loadingMap[key] = true;
    notifyListeners();

    try {
      final queries = <QueryFilter>[FQuery.orderDesc('\$createdAt')];

      if (status != null) {
        queries.add(FQuery.equal('status', status.name));
      }
      if (userId != null) {
        queries.add(FQuery.equal('userId', userId));
      }
      if (excludeUserId != null) {
        queries.add(FQuery.notEqual('userId', excludeUserId));
      }

      final docs = await _firebase.listDocuments(
        collectionId: AppConfig.reportsCollection,
        queries: queries,
        limitCount: 20,
      );

      if (docs.length < 20) {
        _hasMoreMap[key] = false;
      }

      final newReports = docs.map((data) {
        final reportStatus = _parseStatus(data['status']);
        return VerificationReport(
          id: data['\$id'] as String? ?? '',
          title: _formatTitle(data['hazardType'] ?? 'Unknown Hazard'),
          type: data['hazardType'] ?? 'Unknown',
          reporter: 'Community Report',
          location: data['locationDetails'] ?? 'Unknown Location',
          time: _formatTimeAgo(data['submittedAt']),
          status: reportStatus,
          iconName: _getIconName(data['hazardType']),
          iconColor: _getIconColor(data['severity']),
          bgIconColor: '${_getIconColor(data['severity'])}_50',
        );
      }).toList();

      if (loadMore) {
        _reportsMap[key] = [...(_reportsMap[key] ?? []), ...newReports];
      } else {
        _reportsMap[key] = newReports;
      }

      // Store pagination cursor
      if (docs.isNotEmpty) {
        _lastDocMap[key] =
            null; // FirebaseService.listDocuments handles internally
      }
    } on Exception catch (e) {
      developer.log('Error fetching reports: $e');
    } finally {
      _loadingMap[key] = false;
      notifyListeners();
    }
  }

  Future<List<VerificationReport>> getAllReports() async {
    try {
      final docs = await _firebase.listDocuments(
        collectionId: AppConfig.reportsCollection,
        limitCount: 100, // Safety cap — no unbounded reads
      );
      return docs.map((data) {
        return VerificationReport(
          id: data['\$id'] as String? ?? '',
          title: _formatTitle(data['hazardType'] ?? 'Unknown'),
          type: data['hazardType'] ?? 'Unknown',
          reporter: 'Community Report',
          location: data['locationDetails'] ?? 'Unknown',
          time: _formatTimeAgo(data['submittedAt']),
          status: _parseStatus(data['status']),
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

  Future<void> verifyReport(String reportId, {String? userId}) async {
    try {
      await PeerVerificationService().submitVerification(
        reportId: reportId,
        userId: userId ?? 'system_admin',
        isConfirmed: true,
      );
      await _firebase.updateDocument(
        collectionId: AppConfig.reportsCollection,
        documentId: reportId,
        data: {'status': 'acknowledged'},
      );
      developer.log('Report verified: $reportId');
      notifyListeners();
      fetchReports(status: ReportStatus.pending);
      fetchReports(status: ReportStatus.acknowledged);
    } on Exception catch (e) {
      developer.log('Error verifying report: $e');
      rethrow;
    }
  }

  Future<void> resolveReport(String reportId) async {
    try {
      await _firebase.updateDocument(
        collectionId: AppConfig.reportsCollection,
        documentId: reportId,
        data: {'status': 'resolved'},
      );
      developer.log('Report resolved: $reportId');
      notifyListeners();
      fetchReports(status: ReportStatus.acknowledged);
      fetchReports(status: ReportStatus.resolved);
    } on Exception catch (e) {
      developer.log('Error resolving report: $e');
      rethrow;
    }
  }

  Future<void> rejectReport(String reportId, {String? userId}) async {
    try {
      await PeerVerificationService().submitVerification(
        reportId: reportId,
        userId: userId ?? 'system_admin',
        isConfirmed: false,
      );
      await _firebase.updateDocument(
        collectionId: AppConfig.reportsCollection,
        documentId: reportId,
        data: {'status': 'rejected'},
      );
      developer.log('Report rejected: $reportId');
      notifyListeners();
      fetchReports(status: ReportStatus.pending);
      fetchReports(status: ReportStatus.rejected);
    } on Exception catch (e) {
      developer.log('Error rejecting report: $e');
      rethrow;
    }
  }

  Future<void> moveBackToPending(String reportId) async {
    try {
      await _firebase.updateDocument(
        collectionId: AppConfig.reportsCollection,
        documentId: reportId,
        data: {'status': 'pending'},
      );
      developer.log('Report moved back to pending: $reportId');
      notifyListeners();
      refreshReports();
    } on Exception catch (e) {
      developer.log('Error moving to pending: $e');
      rethrow;
    }
  }

  Future<String> generateCSVReport(ReportStatus? filterStatus) async {
    final reports = await getAllReports();
    final filtered = filterStatus != null
        ? reports.where((r) => r.status == filterStatus).toList()
        : reports;
    final buffer = StringBuffer();
    buffer.writeln('ID,Title,Type,Reporter,Location,Time,Status');
    for (final r in filtered) {
      buffer.writeln(
        '${r.id},"${r.title}",${r.type},"${r.reporter}","${r.location}",${r.time},${r.status.displayName}',
      );
    }
    return buffer.toString();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

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
    } else if (timestamp is Timestamp) {
      dateTime = timestamp.toDate();
    } else if (timestamp is DateTime) {
      dateTime = timestamp;
    } else {
      return 'Unknown';
    }

    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}
