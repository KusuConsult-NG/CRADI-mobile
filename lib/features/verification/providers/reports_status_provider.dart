import 'package:flutter/material.dart';
import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/core/services/peer_verification_service.dart';
import 'package:climate_app/features/verification/models/verification_report_model.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'dart:async';
import 'dart:developer' as developer;
import 'package:uuid/uuid.dart';
import 'package:climate_app/core/services/offline_storage_service.dart';
import 'package:climate_app/features/profile/providers/profile_provider.dart';
import 'package:climate_app/core/data/mvp_locations_data.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart'
    show normalizeSeverity;

/// Thrown when a verification is refused by business rules (self-verification,
/// distance, not signed in). [message] is safe to show to the user.
class VerificationRefusedException implements Exception {
  const VerificationRefusedException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ReportsStatusProvider extends ChangeNotifier {
  final SupabaseService _db = SupabaseService();
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

  /// Offset-based pagination cursor: rows already loaded per key.
  final Map<String, int> _offsetMap = {};
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
      'submittedAt': DateTime.now().toUtc().toIso8601String(),
      'locationDetails': defaultLocation,
      'location': defaultLocation,
      'address': defaultLocation,
      'ward': ward,
      'lga': lga,
      'state': state,
      'latitude': latitude ?? 0.0,
      'longitude': longitude ?? 0.0,
      'imageUrls': <String>[],
      'type': 'verification_request',
    };
    // Client-generated id so an offline retry is idempotent.
    final docId = const Uuid().v4();

    try {
      developer.log('Checking network connectivity for submission...');
      await _db
          .createDocument(
            collectionId: AppConfig.reportsCollection,
            documentId: docId,
            data: data,
          )
          .timeout(const Duration(seconds: 10));
      developer.log('Verification request submitted online');
    } on Exception catch (e) {
      developer.log('Online submission failed, queuing offline: $e');
      try {
        await _offlineStorage.addToSyncQueue({
          ...data,
          'docId': docId,
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
      _offsetMap[key] = 0;
      _reportsMap[key] = [];
    }

    _loadingMap[key] = true;
    notifyListeners();

    try {
      // Build base filters (always needed)
      final baseQueries = <QueryFilter>[];
      if (status != null) {
        baseQueries.add(FQuery.equal('status', status.name));
      }
      if (userId != null) {
        baseQueries.add(FQuery.equal('userId', userId));
      }
      if (excludeUserId != null) {
        baseQueries.add(FQuery.notEqual('userId', excludeUserId));
      }

      // Build zone filter
      final zoneQueries = <QueryFilter>[];
      if (userId == null && _profileProvider?.monitoringZone != null) {
        final zone = _profileProvider!.monitoringZone!;
        if (zone.toLowerCase().contains('all zone')) {
          // "All Zones" — no filter needed
        } else if (zone.toLowerCase().contains('state')) {
          zoneQueries.add(FQuery.equal('state', zone.replaceAll(' State', '')));
        } else if (zone.contains(',')) {
          final lgaName = zone.split(',').first.trim();
          zoneQueries.add(FQuery.equal('lga', lgaName));
        } else if (MVPLocationsData.getAllStates().any(
          (s) => s.toLowerCase() == zone.toLowerCase(),
        )) {
          zoneQueries.add(FQuery.equal('state', zone));
        } else {
          developer.log(
            'Skipping zone filter for unrecognized zone "$zone"',
            name: 'ReportsStatusProvider',
          );
        }
      }

      // Combine: base + zone + orderBy
      final queries = <QueryFilter>[
        ...baseQueries,
        ...zoneQueries,
        FQuery.orderDesc('submittedAt'),
      ];

      developer.log(
        'fetchReports key=$key, filters=${queries.length}, '
        'status=${status?.name}, userId=$userId, '
        'zone=${zoneQueries.isNotEmpty ? "active" : "none"}',
        name: 'ReportsStatusProvider',
      );

      // Try the primary query (with zone filter)
      List<Map<String, dynamic>> docs;
      try {
        if (!loadMore) {
          _totalCounts[key] = await _db.countDocuments(
            collectionId: AppConfig.reportsCollection,
            queries: queries,
          );
        }
        docs = await _db.listDocuments(
          collectionId: AppConfig.reportsCollection,
          queries: queries,
          limitCount: 20,
          offset: loadMore ? (_offsetMap[key] ?? 0) : 0,
        );
      } on Exception catch (primaryError) {
        // ── DEFENSIVE FALLBACK ──────────────────────────────────────
        // If the zone-filtered query fails, retry WITHOUT the zone filter
        // so the user still sees reports rather than an empty screen.
        developer.log(
          '⚠️ Primary query failed for key=$key: $primaryError\n'
          '   Retrying without zone filter as fallback...',
          name: 'ReportsStatusProvider',
        );

        final fallbackQueries = <QueryFilter>[
          ...baseQueries,
          FQuery.orderDesc('submittedAt'),
        ];

        if (!loadMore) {
          _totalCounts[key] = await _db.countDocuments(
            collectionId: AppConfig.reportsCollection,
            queries: fallbackQueries,
          );
        }
        docs = await _db.listDocuments(
          collectionId: AppConfig.reportsCollection,
          queries: fallbackQueries,
          limitCount: 20,
          offset: loadMore ? (_offsetMap[key] ?? 0) : 0,
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

          // reporter_name is filled in by the database on insert; fall
          // back to the profile (readable by staff) for older rows.
          String reporterName = 'Community Report';
          final storedName = data['reporterName'] as String?;
          if (storedName != null && storedName.trim().isNotEmpty) {
            reporterName = storedName;
          } else if (data['userId'] != null) {
            try {
              final userDoc = await _db.getDocument(
                collectionId: AppConfig.usersCollection,
                documentId: data['userId'] as String,
              );
              final n = userDoc['name'] as String?;
              if (n != null && n.trim().isNotEmpty) reporterName = n;
            } on Exception catch (_) {}
          }

          // fromMap populates reporterId, coordinates, description,
          // severity, imageUrls, etc.; display fields are overridden below.
          return VerificationReport.fromMap(
            data,
            data['id'] as String? ?? data['\$id'] as String? ?? '',
          ).copyWith(
            title: _formatTitle(data['hazardType'] ?? 'Unknown Hazard'),
            type: data['hazardType'] ?? 'Unknown',
            reporter: reporterName,
            location: data['locationDetails'] ?? 'Unknown Location',
            time: _formatTimeAgo(data['submittedAt']),
            status: reportStatus,
            iconName: _getIconName(data['hazardType']),
            iconColor: _getIconColor(data['severity']),
            bgIconColor: '${_getIconColor(data['severity'])}_50',
            severity: normalizeSeverity(data['severity']),
          );
        }),
      );

      if (loadMore) {
        _reportsMap[key] = [...(_reportsMap[key] ?? []), ...newReports];
      } else {
        _reportsMap[key] = newReports;
      }

      // Advance pagination cursor
      _offsetMap[key] = (loadMore ? (_offsetMap[key] ?? 0) : 0) + docs.length;
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
      final docs = await _db.listDocuments(
        collectionId: AppConfig.reportsCollection,
        limitCount: 100, // Safety cap — no unbounded reads
      );
      return docs.map((data) {
        return VerificationReport.fromMap(
          data,
          data['\$id'] as String? ?? '',
        ).copyWith(
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

  /// Submits a verification as the signed-in user. Throws with the service's
  /// message when the verification is refused (e.g. self-verification or
  /// too far from the report).
  Future<void> _submitVerificationAsCurrentUser(
    String reportId, {
    required bool isConfirmed,
    String? userId,
  }) async {
    final uid = userId ?? _db.currentUserId;
    if (uid == null) {
      throw const VerificationRefusedException(
        'You must be signed in to verify reports.',
      );
    }
    final result = await PeerVerificationService().submitVerification(
      reportId: reportId,
      userId: uid,
      isConfirmed: isConfirmed,
    );
    if (result['success'] != true) {
      throw VerificationRefusedException(
        (result['message'] ?? result['error'] ?? 'Verification failed')
            .toString(),
      );
    }
  }

  Future<void> verifyReport(String reportId, {String? userId}) async {
    try {
      await _submitVerificationAsCurrentUser(
        reportId,
        isConfirmed: true,
        userId: userId,
      );
      // One peer vote only: the verifications_after_insert trigger moves
      // the report to 'verified' once the confirmation threshold is met.
      developer.log('Report confirmation recorded: $reportId');
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
      await _db.updateDocument(
        collectionId: AppConfig.reportsCollection,
        documentId: reportId,
        data: {'status': 'approved', 'approvedAt': DateTime.now()},
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
      await _submitVerificationAsCurrentUser(
        reportId,
        isConfirmed: false,
        userId: userId,
      );
      // A dispute is one peer vote; it does not change the report status.
      developer.log('Report dispute recorded: $reportId');
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
      await _db.updateDocument(
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

  String _getIconColor(Object? severity) {
    // Tolerates canonical ('high') and legacy ('High Severity') values.
    switch (normalizeSeverity(severity)) {
      case 'low':
        return 'green';
      case 'medium':
        return 'orange';
      case 'high':
        return 'orange';
      case 'critical':
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
      case 'acknowledged': // legacy compat
        return ReportStatus.verified;
      case 'approved':
      case 'validated': // legacy compat
      case 'resolved': // legacy compat
        return ReportStatus.approved;
      case 'rejected':
        return ReportStatus.rejected;
      default:
        return ReportStatus.pending;
    }
  }

  String _formatTimeAgo(dynamic timestamp) {
    if (timestamp == null) return 'Unknown';
    final dateTime = parseTimestamp(timestamp);
    if (dateTime == null) return 'Unknown';

    final diff = DateTime.now().difference(dateTime);
    if (diff.isNegative || diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}
