import 'package:flutter/material.dart';
import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/core/services/peer_verification_service.dart';
import 'package:climate_app/features/verification/models/verification_report_model.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'dart:async';
import 'dart:developer' as developer;
import 'package:climate_app/core/services/offline_storage_service.dart';
import 'package:climate_app/features/profile/providers/profile_provider.dart';
import 'package:climate_app/core/data/mvp_locations_data.dart';

class ReportsStatusProvider extends ChangeNotifier {
  final SupabaseService _supabase = SupabaseService();
  final OfflineStorageService _offlineStorage = OfflineStorageService();
  ProfileProvider? _profileProvider;

  ReportsStatusProvider({ProfileProvider? profileProvider}) {
    _profileProvider = profileProvider;
  }

  void updateContext(ProfileProvider? profileProvider) {
    _profileProvider = profileProvider;
    // Don't auto-fetch here as it might trigger rebuild loops. Allow UI to pull.
  }

  bool _isSubmitting = false;
  bool get isSubmitting => _isSubmitting;

  final Map<String, List<VerificationReport>> _reportsMap = {};
  final Map<String, String?> _lastDocMap = {};
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
      'user_id': userId,
      'description': description,
      'hazard_type': hazardType,
      'severity': severity,
      'status': 'pending',
      'submitted_at': DateTime.now().toUtc().toIso8601String(),
      'location_description': defaultLocation,
      'ward': ward,
      'lga': lga,
      'state': state,
      'latitude': latitude ?? 0.0,
      'longitude': longitude ?? 0.0,
      'image_urls': <String>[],
      'verification_count': 0,
    };

    try {
      developer.log('Checking network connectivity for submission...');
      await _supabase
          .createDocument(collectionId: AppConfig.reportsCollection, data: data)
          .timeout(const Duration(seconds: 10));
      developer.log('Verification request submitted online');
    } on Exception catch (e) {
      developer.log('Online submission failed, queuing offline: $e');
      try {
        await _offlineStorage.addToSyncQueue({
          ...data,
          'type': 'verification_request',
          'collectionId': AppConfig.reportsCollection,
        });
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

  Future<void> refreshReports({String? excludeUserId, String? userId}) async {
    await Future.wait([
      fetchReports(status: null, excludeUserId: excludeUserId, userId: userId),
      fetchReports(
        status: ReportStatus.pending,
        excludeUserId: excludeUserId,
        userId: userId,
      ),
      fetchReports(
        status: ReportStatus.verified,
        excludeUserId: excludeUserId,
        userId: userId,
      ),
      fetchReports(
        status: ReportStatus.approved,
        excludeUserId: excludeUserId,
        userId: userId,
      ),
      fetchReports(
        status: ReportStatus.rejected,
        excludeUserId: excludeUserId,
        userId: userId,
      ),
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
      // Build base filters
      final baseQueries = <QueryFilter>[];
      if (status != null) {
        baseQueries.add(SQuery.equal('status', status.name));
      }
      if (userId != null) {
        baseQueries.add(SQuery.equal('user_id', userId));
      }
      if (excludeUserId != null) {
        baseQueries.add(SQuery.notEqual('user_id', excludeUserId));
      }

      // Build zone filter
      final zoneQueries = <QueryFilter>[];
      if (userId == null && _profileProvider?.monitoringZone != null) {
        final zone = _profileProvider!.monitoringZone!;
        if (zone.toLowerCase().contains('all zone')) {
          // No filter needed
        } else if (zone.toLowerCase().contains('state')) {
          zoneQueries.add(SQuery.equal('state', zone.replaceAll(' State', '')));
        } else if (zone.contains(',')) {
          final lgaName = zone.split(',').first.trim();
          zoneQueries.add(SQuery.equal('lga', lgaName));
        } else if (MVPLocationsData.getAllStates().any(
          (s) => s.toLowerCase() == zone.toLowerCase(),
        )) {
          zoneQueries.add(SQuery.equal('state', zone));
        } else {
          developer.log(
            'Skipping zone filter for unrecognized zone "$zone"',
            name: 'ReportsStatusProvider',
          );
        }
      }

      final queries = <QueryFilter>[
        ...baseQueries,
        ...zoneQueries,
        SQuery.orderDesc('submitted_at'),
      ];

      developer.log(
        'fetchReports key=$key, filters=${queries.length}, '
        'status=${status?.name}, userId=$userId, '
        'zone=${zoneQueries.isNotEmpty ? "active" : "none"}',
        name: 'ReportsStatusProvider',
      );

      List<Map<String, dynamic>> docs;
      try {
        if (!loadMore) {
          _totalCounts[key] = await _supabase.countDocuments(
            collectionId: AppConfig.reportsCollection,
            queries: queries,
          );
        }
        docs = await _supabase.listDocuments(
          collectionId: AppConfig.reportsCollection,
          queries: queries,
          limitCount: 20,
        );
      } on Exception catch (primaryError) {
        developer.log(
          '⚠️ Primary query failed for key=$key: $primaryError\n'
          '   Retrying without zone filter as fallback...',
          name: 'ReportsStatusProvider',
        );

        final fallbackQueries = <QueryFilter>[
          ...baseQueries,
          SQuery.orderDesc('submitted_at'),
        ];

        if (!loadMore) {
          _totalCounts[key] = await _supabase.countDocuments(
            collectionId: AppConfig.reportsCollection,
            queries: fallbackQueries,
          );
        }
        docs = await _supabase.listDocuments(
          collectionId: AppConfig.reportsCollection,
          queries: fallbackQueries,
          limitCount: 20,
        );

        developer.log(
          '✅ Fallback query returned ${docs.length} docs for key=$key',
          name: 'ReportsStatusProvider',
        );
      }

      developer.log(
        'fetchReports key=$key returned ${docs.length} docs',
        name: 'ReportsStatusProvider',
      );

      if (docs.length < 20) {
        _hasMoreMap[key] = false;
      }

      final newReports = await Future.wait(
        docs.map((data) async {
          final reportStatus = _parseStatus(data['status']);

          String reporterName = 'Community Report';
          if (data['user_id'] != null) {
            try {
              final userDoc = await _supabase.getDocument(
                collectionId: AppConfig.usersCollection,
                documentId: data['user_id'] as String,
              );
              final n = userDoc['full_name'] as String?;
              if (n != null && n.trim().isNotEmpty) {
                reporterName = n;
              }
            } on Exception catch (_) {}
          }

          return VerificationReport(
            id: data['id'] as String? ?? data['\$id'] as String? ?? '',
            title: _formatTitle(data['hazard_type'] ?? 'Unknown Hazard'),
            type: data['hazard_type'] ?? 'Unknown',
            reporter: reporterName,
            location: data['location_description'] ?? 'Unknown Location',
            time: _formatTimeAgo(data['submitted_at']),
            status: reportStatus,
            iconName: _getIconName(data['hazard_type']),
            iconColor: _getIconColor(data['severity']),
            bgIconColor: '${_getIconColor(data['severity'])}_50',
          );
        }),
      );

      if (loadMore) {
        _reportsMap[key] = [...(_reportsMap[key] ?? []), ...newReports];
      } else {
        _reportsMap[key] = newReports;
      }

      // Store last doc ID for pagination cursor
      if (docs.isNotEmpty) {
        _lastDocMap[key] = docs.last['id'] as String?;
      }
    } on Exception catch (e, stack) {
      developer.log(
        'Error fetching reports for key=$key: $e',
        name: 'ReportsStatusProvider',
        error: e,
        stackTrace: stack,
      );
    } finally {
      _loadingMap[key] = false;
      notifyListeners();
    }
  }

  Future<List<VerificationReport>> getAllReports() async {
    try {
      final docs = await _supabase.listDocuments(
        collectionId: AppConfig.reportsCollection,
        limitCount: 100,
      );
      return docs.map((data) {
        return VerificationReport(
          id: data['\$id'] as String? ?? '',
          title: _formatTitle(data['hazard_type'] ?? 'Unknown'),
          type: data['hazard_type'] ?? 'Unknown',
          reporter: 'Community Report',
          location: data['location_description'] ?? 'Unknown',
          time: _formatTimeAgo(data['submitted_at']),
          status: _parseStatus(data['status']),
          iconName: _getIconName(data['hazard_type']),
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
      await _supabase.updateDocument(
        collectionId: AppConfig.reportsCollection,
        documentId: reportId,
        data: {'status': 'verified'},
      );
      developer.log('Report verified: $reportId');
      notifyListeners();
      fetchReports(status: ReportStatus.pending);
      fetchReports(status: ReportStatus.verified);
    } on Exception catch (e) {
      developer.log('Error verifying report: $e');
      rethrow;
    }
  }

  Future<void> approveReport(String reportId) async {
    try {
      await _supabase.updateDocument(
        collectionId: AppConfig.reportsCollection,
        documentId: reportId,
        data: {'status': 'approved'},
      );
      developer.log('Report approved: $reportId');
      notifyListeners();
      fetchReports(status: ReportStatus.verified);
      fetchReports(status: ReportStatus.approved);
    } on Exception catch (e) {
      developer.log('Error approving report: $e');
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
      await _supabase.updateDocument(
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
      await _supabase.updateDocument(
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
      case 'verified':
      case 'acknowledged':
      case 'validated':
        return ReportStatus.verified;
      case 'approved':
      case 'resolved':
        return ReportStatus.approved;
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

    final diff = DateTime.now().difference(dateTime);
    if (diff.isNegative || diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}
