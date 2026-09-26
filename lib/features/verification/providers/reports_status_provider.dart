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
import 'package:climate_app/core/constants/hazards.dart';
import 'package:climate_app/core/utils/error_handler.dart';

export 'package:climate_app/core/services/offline_storage_service.dart'
    show OfflineQueuedException;

/// Thrown when a verification is refused by business rules (self-verification,
/// distance, not signed in). [message] is safe to show to the user.
class VerificationRefusedException implements Exception {
  const VerificationRefusedException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Page size used for report lists.
const int _pageSize = 20;

/// Parameters identifying one cached report list.
class _ListKey {
  const _ListKey(this.status, this.userId, this.excludeUserId);
  final ReportStatus? status;
  final String? userId;
  final String? excludeUserId;
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

  /// Last fetch error per key (null once a fetch succeeds).
  final Map<String, String> _errorMap = {};

  /// Monotonic request token per key; responses of superseded requests are
  /// dropped so a slow, older response never overwrites a newer one.
  final Map<String, int> _requestTokens = {};

  /// Parameters of every key that has been fetched (for refresh-all).
  final Map<String, _ListKey> _keyParams = {};

  /// Reports the signed-in user has already voted on (confirm or dispute).
  Set<String> _votedReportIds = {};
  String? _votesUserId;
  Future<void>? _votesInFlight;

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

  /// User-facing message of the last failed fetch for this list, or null.
  String? errorFor(
    ReportStatus? status, {
    String? userId,
    String? excludeUserId,
  }) => _errorMap[_getKey(status, userId, excludeUserId: excludeUserId)];

  /// Whether the signed-in user has already voted on [reportId]. Populated
  /// by [loadMyVotes] (called by [refreshReports]) and after each vote.
  bool hasVotedOn(String reportId) => _votedReportIds.contains(reportId);

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
      'hazardType': Hazard.canonicalName(hazardType),
      'severity': normalizeSeverity(severity) ?? severity,
      'status': 'pending',
      'submittedAt': DateTime.now().toUtc().toIso8601String(),
      'locationDetails': defaultLocation,
      'location': defaultLocation,
      'address': defaultLocation,
      'ward': ward,
      'lga': lga,
      'state': state,
      // Unknown coordinates are stored as null, never 0,0.
      'latitude': latitude,
      'longitude': longitude,
      'imageUrls': <String>[],
      'type': 'verification_request',
    };
    // Client-generated id so an offline retry is idempotent.
    final docId = const Uuid().v4();

    try {
      await _db
          .createDocument(
            collectionId: AppConfig.reportsCollection,
            documentId: docId,
            data: data,
          )
          .timeout(const Duration(seconds: 10));
      developer.log('Verification request submitted online');
    } on Exception catch (e) {
      // Only connectivity failures are queued; the server refusing the
      // payload (RLS, constraints) would fail again on every retry.
      if (!isTransientNetworkError(e)) rethrow;
      developer.log('Online submission failed, queuing offline: $e');
      await _offlineStorage.addToSyncQueue({
        ...data,
        'docId': docId,
        'collectionId': AppConfig.reportsCollection,
      });
      throw const OfflineQueuedException(
        'Offline: request saved and will sync when you are back online.',
      );
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> refreshReports({String? excludeUserId, String? userId}) async {
    await Future.wait([
      loadMyVotes(force: true),
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

  /// Re-fetches (first page of) every list that has been loaded, e.g. after
  /// a vote or a status change moved reports between lists.
  Future<void> refreshLoadedLists() {
    return Future.wait(
      _keyParams.values.map(
        (k) => fetchReports(
          status: k.status,
          userId: k.userId,
          excludeUserId: k.excludeUserId,
        ),
      ),
    );
  }

  /// Loads the ids of reports the signed-in user already voted on (one
  /// query, cached per user). Failures leave the previous set in place.
  Future<void> loadMyVotes({bool force = false}) {
    final uid = SupabaseService.isReady ? _db.currentUserId : null;
    if (uid == null) {
      _votedReportIds = {};
      _votesUserId = null;
      return Future.value();
    }
    if (!force && _votesUserId == uid) return Future.value();
    return _votesInFlight ??= _loadMyVotes(uid).whenComplete(() {
      _votesInFlight = null;
    });
  }

  Future<void> _loadMyVotes(String uid) async {
    try {
      final ids = <String>{};
      const page = 500;
      var offset = 0;
      while (true) {
        final rows = await _db.listDocuments(
          collectionId: AppConfig.verificationsCollection,
          queries: [FQuery.equal('verifierId', uid)],
          limitCount: page,
          offset: offset,
        );
        for (final r in rows) {
          final id = r['reportId'];
          if (id is String) ids.add(id);
        }
        if (rows.length < page) break;
        offset += rows.length;
      }
      _votedReportIds = ids;
      _votesUserId = uid;
      notifyListeners();
    } on Exception catch (e) {
      developer.log(
        'Could not load own verifications: $e',
        name: 'ReportsStatusProvider',
      );
    }
  }

  /// Loads every page of a list (up to [maxRows]) so screens that filter
  /// client-side see all rows, not only the first page.
  Future<void> fetchAllPages({
    ReportStatus? status,
    String? userId,
    String? excludeUserId,
    int maxRows = 1000,
  }) async {
    await fetchReports(
      status: status,
      userId: userId,
      excludeUserId: excludeUserId,
    );
    while (hasMore(status, userId: userId, excludeUserId: excludeUserId) &&
        errorFor(status, userId: userId, excludeUserId: excludeUserId) ==
            null &&
        getReports(
              status,
              userId: userId,
              excludeUserId: excludeUserId,
            ).length <
            maxRows) {
      final before = getReports(
        status,
        userId: userId,
        excludeUserId: excludeUserId,
      ).length;
      await fetchReports(
        loadMore: true,
        status: status,
        userId: userId,
        excludeUserId: excludeUserId,
      );
      final after = getReports(
        status,
        userId: userId,
        excludeUserId: excludeUserId,
      ).length;
      if (after <= before) break; // no progress (superseded or empty)
    }
  }

  Future<void> fetchReports({
    bool loadMore = false,
    ReportStatus? status,
    String? userId,
    String? excludeUserId,
  }) async {
    final key = _getKey(status, userId, excludeUserId: excludeUserId);
    _keyParams[key] = _ListKey(status, userId, excludeUserId);

    if (loadMore &&
        ((_hasMoreMap[key] == false) || (_loadingMap[key] == true))) {
      return;
    }

    // Existing rows stay visible until the new page arrives.
    final token = (_requestTokens[key] ?? 0) + 1;
    _requestTokens[key] = token;
    bool isCurrent() => _requestTokens[key] == token;

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

      final zoneQueries = userId == null ? _zoneQueries() : <QueryFilter>[];

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

      final offset = loadMore ? (_offsetMap[key] ?? 0) : 0;
      int? total;
      List<Map<String, dynamic>> docs;
      try {
        if (!loadMore) {
          total = await _db.countDocuments(
            collectionId: AppConfig.reportsCollection,
            queries: queries,
          );
        }
        docs = await _db.listDocuments(
          collectionId: AppConfig.reportsCollection,
          queries: queries,
          limitCount: _pageSize,
          offset: offset,
        );
      } on Exception catch (primaryError) {
        if (zoneQueries.isEmpty || isTransientNetworkError(primaryError)) {
          rethrow;
        }
        // ── DEFENSIVE FALLBACK ──────────────────────────────────────
        // If the zone-filtered query fails, retry WITHOUT the zone filter
        // so the user still sees reports rather than an empty screen.
        developer.log(
          'Primary query failed for key=$key: $primaryError; '
          'retrying without zone filter',
          name: 'ReportsStatusProvider',
        );
        final fallbackQueries = <QueryFilter>[
          ...baseQueries,
          FQuery.orderDesc('submittedAt'),
        ];
        if (!loadMore) {
          total = await _db.countDocuments(
            collectionId: AppConfig.reportsCollection,
            queries: fallbackQueries,
          );
        }
        docs = await _db.listDocuments(
          collectionId: AppConfig.reportsCollection,
          queries: fallbackQueries,
          limitCount: _pageSize,
          offset: offset,
        );
      }

      final newReports = await Future.wait(docs.map(_toReport));
      if (!isCurrent()) return; // superseded by a newer request

      developer.log(
        'fetchReports key=$key returned ${docs.length} docs',
        name: 'ReportsStatusProvider',
      );

      if (total != null) _totalCounts[key] = total;
      _hasMoreMap[key] = docs.length >= _pageSize;
      _reportsMap[key] = loadMore
          ? [...(_reportsMap[key] ?? []), ...newReports]
          : newReports;
      _offsetMap[key] = offset + docs.length;
      _errorMap.remove(key);
    } on Exception catch (e, stack) {
      developer.log(
        'Error fetching reports for key=$key: $e',
        name: 'ReportsStatusProvider',
        error: e,
        stackTrace: stack,
      );
      if (isCurrent()) {
        _errorMap[key] = isTransientNetworkError(e)
            ? 'Could not reach the server. Check your connection and retry.'
            : ErrorHandler.getUserMessage(e);
      }
    } finally {
      if (isCurrent()) {
        _loadingMap[key] = false;
        notifyListeners();
      }
    }
  }

  /// Monitoring-zone filter for staff-wide lists.
  List<QueryFilter> _zoneQueries() {
    final zone = _profileProvider?.monitoringZone;
    if (zone == null) return const [];
    final lower = zone.toLowerCase();
    if (lower.contains('all zone')) return const [];
    if (lower.contains('state')) {
      return [FQuery.equal('state', zone.replaceAll(' State', '').trim())];
    }
    if (zone.contains(',')) {
      return [FQuery.equal('lga', zone.split(',').first.trim())];
    }
    if (MVPLocationsData.getAllStates().any((s) => s.toLowerCase() == lower)) {
      return [FQuery.equal('state', zone)];
    }
    developer.log(
      'Skipping zone filter for unrecognized zone "$zone"',
      name: 'ReportsStatusProvider',
    );
    return const [];
  }

  /// Maps a `reports` document to a display-ready [VerificationReport].
  Future<VerificationReport> _toReport(Map<String, dynamic> data) async {
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
  }

  /// Loads a single report by id (deep links / notification taps).
  /// Returns null when it does not exist or is not readable.
  Future<VerificationReport?> fetchReportById(String reportId) async {
    try {
      final data = await _db.getDocument(
        collectionId: AppConfig.reportsCollection,
        documentId: reportId,
      );
      return await _toReport({...data, 'id': data['id'] ?? reportId});
    } on DocumentNotFoundException catch (_) {
      return null;
    } on Exception catch (_) {
      // Offline / transient failure: fall back to an already-loaded copy.
      for (final list in _reportsMap.values) {
        for (final r in list) {
          if (r.id == reportId) return r;
        }
      }
      rethrow;
    }
  }

  /// All report rows readable by the user (optionally one status), newest
  /// first, paged through in full (capped at [maxRows]).
  Future<List<Map<String, dynamic>>> fetchAllReportRows({
    ReportStatus? status,
    int maxRows = 10000,
  }) async {
    const page = 500;
    final rows = <Map<String, dynamic>>[];
    while (rows.length < maxRows) {
      final docs = await _db.listDocuments(
        collectionId: AppConfig.reportsCollection,
        queries: [
          if (status != null) FQuery.equal('status', status.name),
          FQuery.orderDesc('submittedAt'),
        ],
        limitCount: page,
        offset: rows.length,
      );
      rows.addAll(docs);
      if (docs.length < page) break;
    }
    return rows;
  }

  Future<List<VerificationReport>> getAllReports() async {
    try {
      final docs = await fetchAllReportRows();
      return await Future.wait(
        docs.map((d) => _toReport({...d, 'id': d['id'] ?? d['\$id']})),
      );
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
    String? comment,
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
      comment: comment,
    );
    if (result['alreadyVoted'] == true) {
      _votedReportIds = {..._votedReportIds, reportId};
      notifyListeners();
    }
    if (result['success'] != true) {
      throw VerificationRefusedException(
        (result['message'] ?? result['error'] ?? 'Verification failed')
            .toString(),
      );
    }
    _votedReportIds = {..._votedReportIds, reportId};
    notifyListeners();
  }

  /// Casts a confirming peer vote.
  Future<void> verifyReport(
    String reportId, {
    String? userId,
    String? comment,
  }) async {
    try {
      await _submitVerificationAsCurrentUser(
        reportId,
        isConfirmed: true,
        userId: userId,
        comment: comment,
      );
      // One peer vote only: the verifications_after_insert trigger moves
      // the report to 'verified' once the confirmation threshold is met.
      developer.log('Report confirmation recorded: $reportId');
      unawaited(refreshLoadedLists());
    } on Exception catch (e) {
      developer.log('Error verifying report: $e');
      rethrow;
    }
  }

  /// Casts a disputing peer vote. This does NOT reject the report; only
  /// senior staff can do that (see [staffRejectReport]).
  Future<void> disputeReport(
    String reportId, {
    String? userId,
    String? comment,
  }) async {
    try {
      await _submitVerificationAsCurrentUser(
        reportId,
        isConfirmed: false,
        userId: userId,
        comment: comment,
      );
      developer.log('Report dispute recorded: $reportId');
      unawaited(refreshLoadedLists());
    } on Exception catch (e) {
      developer.log('Error disputing report: $e');
      rethrow;
    }
  }

  /// Legacy name for [disputeReport] (a peer "reject" vote).
  Future<void> rejectReport(String reportId, {String? userId}) =>
      disputeReport(reportId, userId: userId);

  /// Senior staff approval (the database audits the decision).
  Future<void> approveReport(String reportId) async {
    try {
      await PeerVerificationService().manualValidation(
        reportId: reportId,
        isApproved: true,
      );
      developer.log('Report approved: $reportId');
      unawaited(refreshLoadedLists());
    } on Exception catch (e) {
      developer.log('Error approving report: $e');
      rethrow;
    }
  }

  /// Senior staff rejection with a reason (the database audits it and
  /// refuses it for roles that may not reject, or for one's own report).
  Future<void> staffRejectReport(
    String reportId, {
    required String reason,
  }) async {
    try {
      await PeerVerificationService().manualValidation(
        reportId: reportId,
        isApproved: false,
        reason: reason,
      );
      developer.log('Report rejected by staff: $reportId');
      unawaited(refreshLoadedLists());
    } on Exception catch (e) {
      developer.log('Error rejecting report: $e');
      rethrow;
    }
  }

  /// Reopens a report (senior staff / admin): the `reopen_report` RPC clears
  /// its peer votes, sets it back to pending and reschedules escalation.
  Future<void> moveBackToPending(String reportId) async {
    try {
      await _db.client.rpc('reopen_report', params: {'p_report_id': reportId});
      developer.log('Report reopened: $reportId');
      // Votes were cleared, including the user's own.
      _votedReportIds = {..._votedReportIds}..remove(reportId);
      unawaited(refreshLoadedLists());
    } on Exception catch (e) {
      developer.log('Error reopening report: $e');
      rethrow;
    }
  }

  /// CSV columns of [generateCSVReport].
  static const List<String> csvHeader = [
    'ID',
    'Hazard',
    'Severity',
    'Status',
    'Submitted At (UTC)',
    'State',
    'LGA',
    'Ward',
    'Location',
    'Latitude',
    'Longitude',
    'Reporter',
    'Verifications',
    'Description',
  ];

  /// Escapes one CSV field (RFC 4180): fields containing a comma, quote,
  /// CR or LF are quoted and quotes are doubled. Fields that a spreadsheet
  /// would evaluate as a formula are prefixed with an apostrophe.
  static String csvEscape(Object? value) {
    var s = value?.toString() ?? '';
    if (s.isNotEmpty &&
        '=+-@\t\r'.contains(s[0]) &&
        double.tryParse(s) == null) {
      s = "'$s";
    }
    if (s.contains(RegExp(r'[",\r\n]'))) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  /// Builds CSV text (CRLF line endings) from report rows.
  static String buildCsv(List<Map<String, dynamic>> rows) {
    final buffer = StringBuffer()
      ..write(csvHeader.map(csvEscape).join(','))
      ..write('\r\n');
    for (final d in rows) {
      final submitted = parseTimestamp(d['submittedAt'])?.toUtc();
      final fields = [
        d['id'] ?? d['\$id'],
        Hazard.labelFor(d['hazardType']),
        normalizeSeverity(d['severity']) ?? d['severity'],
        d['status'],
        submitted?.toIso8601String(),
        d['state'],
        d['lga'],
        d['ward'],
        d['locationDetails'] ?? d['location'],
        d['latitude'],
        d['longitude'],
        d['reporterName'],
        d['verificationCount'],
        d['description'],
      ];
      buffer
        ..write(fields.map(csvEscape).join(','))
        ..write('\r\n');
    }
    return buffer.toString();
  }

  /// CSV export of all readable reports (optionally one status), newest
  /// first.
  Future<String> generateCSVReport(ReportStatus? filterStatus) async {
    final rows = await fetchAllReportRows(status: filterStatus);
    return buildCsv(rows);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _formatTitle(String hazardType) => Hazard.titleFor(hazardType);

  String _getIconName(String? hazardType) => Hazard.iconKeyFor(hazardType);

  String _getIconColor(Object? severity) =>
      // Tolerates canonical ('high') and legacy ('High Severity') values.
      SeverityColors.nameFor(normalizeSeverity(severity));

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
