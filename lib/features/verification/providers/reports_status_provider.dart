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
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

export 'package:climate_app/core/services/offline_storage_service.dart'
    show OfflineQueuedException;

/// Thrown when a verification is refused by business rules (self-verification,
/// distance, not signed in). [message] is safe to show to the user.
class VerificationRefusedException implements Exception {
  const VerificationRefusedException(
    this.message, {
    this.noLongerPending = false,
    this.alreadyVoted = false,
  });
  final String message;

  /// The user has already voted on this report.
  final bool alreadyVoted;

  /// The report is no longer pending (already verified / rejected), so
  /// voting on it is pointless.
  final bool noLongerPending;

  @override
  String toString() => message;
}

/// User-facing message for a failed report action (vote, approve, reject,
/// reopen): the database's curated refusals are shown as such, everything
/// else goes through [ErrorHandler].
String reportActionErrorMessage(Object error, {String context = 'Report'}) {
  if (error is VerificationRefusedException) return error.message;
  if (error is DocumentNotFoundException) {
    return 'You do not have permission to change this report, '
        'or it no longer exists.';
  }
  if (error is PostgrestException) {
    switch (error.code) {
      case '22023':
        return 'This report is already pending.';
      case 'P0002':
        return 'This report no longer exists.';
      case '42501':
      case 'PGRST301':
        // Trigger refusals carry a readable reason; RLS denials do not.
        final msg = error.message;
        return msg.isNotEmpty && !msg.toLowerCase().contains('row-level')
            ? msg
            : 'You do not have permission to change this report.';
    }
  }
  return ErrorHandler.handleError(error, context: context);
}

/// Page size used for report lists.
const int _pageSize = 20;

/// Page size used by [ReportsStatusProvider.fetchAllPages].
const int _bulkPageSize = 250;

/// Parameters identifying one cached report list.
class _ListKey {
  const _ListKey(this.status, this.userId, this.excludeUserId, this.pageSize);
  final ReportStatus? status;
  final String? userId;
  final String? excludeUserId;
  final int pageSize;
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

  /// Lists a screen loaded with [fetchAllPages]; refreshes reload them fully
  /// so a first-page refresh can't truncate them.
  final Set<String> _allPagesKeys = {};
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

  /// Incremented by [clearUserData]; responses started before it are
  /// dropped.
  int _userGen = 0;

  /// Changes whenever [clearUserData] dropped the cached lists: screens
  /// that load their own lists (e.g. every page of "My Reports") compare it
  /// to reload them.
  int get userDataGeneration => _userGen;

  /// Rows fetched for the "To Verify" list: pending reports are filtered
  /// client-side (already voted, ward / LGA eligibility), so one page of
  /// the default size could leave the list empty while more exist.
  static const int toVerifyPageSize = 200;

  /// Monitoring-zone column filters: "Benue State" → state, "Makurdi,
  /// Benue" (LGA, State) → LGA and state, a bare state name → state.
  /// Empty when there is no zone, "All Zones" or an unrecognized zone.
  @visibleForTesting
  static Map<String, String> zoneFilterFor(String? zone) {
    final z = zone?.trim();
    if (z == null || z.isEmpty) return const {};
    final lower = z.toLowerCase();
    if (lower.contains('all zone')) return const {};
    // Column filters are case-sensitive equality: known names are mapped to
    // their stored spelling ("benue" → "Benue").
    String canonicalState(String v) {
      final name = v
          .replaceAll(RegExp(r'\s+state$', caseSensitive: false), '')
          .trim();
      return MVPLocationsData.getAllStates().firstWhere(
        (s) => s.toLowerCase() == name.toLowerCase(),
        orElse: () => name,
      );
    }

    if (z.contains(',')) {
      final parts = z.split(',');
      final state = canonicalState(parts.last.trim());
      final rawLga = parts.first.trim();
      final lga = rawLga.isEmpty
          ? rawLga
          : MVPLocationsData.findLGA(
                  rawLga,
                  state: state.isEmpty ? null : state,
                )?.name ??
                rawLga;
      return {
        if (lga.isNotEmpty) 'lga': lga,
        if (state.isNotEmpty) 'state': state,
      };
    }
    if (lower.endsWith(' state')) return {'state': canonicalState(z)};
    final state = canonicalState(z);
    if (MVPLocationsData.getAllStates().contains(state)) {
      return {'state': state};
    }
    return const {};
  }

  /// Drops every cached list, count, vote and error, e.g. on sign-out or
  /// before another account signs in on a shared device.
  void clearUserData() {
    _userGen++;
    // Bump (not reset) the request tokens so in-flight responses are dropped.
    _requestTokens.updateAll((_, token) => token + 1);
    _reportsMap.clear();
    _offsetMap.clear();
    _hasMoreMap.clear();
    _loadingMap.clear();
    _allPagesKeys.clear();
    _totalCounts.clear();
    _errorMap.clear();
    _keyParams.clear();
    _votedReportIds = {};
    _votesUserId = null;
    _votesInFlight = null;
    notifyListeners();
  }

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
      _refreshList(null, userId: userId, excludeUserId: excludeUserId),
      _refreshList(
        ReportStatus.pending,
        userId: userId,
        excludeUserId: excludeUserId,
      ),
      // The "To Verify" list of the signed-in user.
      if (userId == null && excludeUserId == null) fetchToVerify(),
      _refreshList(
        ReportStatus.verified,
        userId: userId,
        excludeUserId: excludeUserId,
      ),
      _refreshList(
        ReportStatus.approved,
        userId: userId,
        excludeUserId: excludeUserId,
      ),
      _refreshList(
        ReportStatus.rejected,
        userId: userId,
        excludeUserId: excludeUserId,
      ),
    ]);
  }

  /// First page, or every page for lists loaded with [fetchAllPages].
  Future<void> _refreshList(
    ReportStatus? status, {
    String? userId,
    String? excludeUserId,
    int? pageSize,
  }) {
    final key = _getKey(status, userId, excludeUserId: excludeUserId);
    if (_allPagesKeys.contains(key)) {
      return fetchAllPages(
        status: status,
        userId: userId,
        excludeUserId: excludeUserId,
      );
    }
    return fetchReports(
      status: status,
      userId: userId,
      excludeUserId: excludeUserId,
      pageSize: pageSize ?? _pageSize,
    );
  }

  /// Re-fetches (first page of) every list that has been loaded, e.g. after
  /// a vote or a status change moved reports between lists.
  Future<void> refreshLoadedLists() {
    return Future.wait(
      _keyParams.values.map(
        (k) => _refreshList(
          k.status,
          userId: k.userId,
          excludeUserId: k.excludeUserId,
          pageSize: k.pageSize,
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
    late final Future<void> load;
    load = _votesInFlight ??= _loadMyVotes(uid).whenComplete(() {
      if (identical(_votesInFlight, load)) _votesInFlight = null;
    });
    return load;
  }

  Future<void> _loadMyVotes(String uid) async {
    final gen = _userGen;
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
      if (gen != _userGen) return;
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
    _allPagesKeys.add(_getKey(status, userId, excludeUserId: excludeUserId));
    await fetchReports(
      status: status,
      userId: userId,
      excludeUserId: excludeUserId,
      pageSize: _bulkPageSize,
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
        pageSize: _bulkPageSize,
      );
      final after = getReports(
        status,
        userId: userId,
        excludeUserId: excludeUserId,
      ).length;
      if (after <= before) break; // no progress (superseded or empty)
    }
  }

  /// Pending reports not submitted by the signed-in user (the "To Verify"
  /// list, read with [toVerifyReports]), with a larger page than the
  /// default lists.
  Future<void> fetchToVerify() {
    final uid = SupabaseService.isReady ? _db.currentUserId : null;
    if (uid == null) return Future.value();
    return fetchReports(
      status: ReportStatus.pending,
      excludeUserId: uid,
      pageSize: toVerifyPageSize,
    );
  }

  /// Rows loaded by [fetchToVerify] for [uid], without reports the user
  /// already voted on.
  List<VerificationReport> toVerifyReports(String? uid) => getReports(
    ReportStatus.pending,
    excludeUserId: uid,
  ).where((r) => !hasVotedOn(r.id)).toList();

  Future<void> fetchReports({
    bool loadMore = false,
    ReportStatus? status,
    String? userId,
    String? excludeUserId,
    int pageSize = _pageSize,
  }) async {
    final key = _getKey(status, userId, excludeUserId: excludeUserId);
    _keyParams[key] = _ListKey(status, userId, excludeUserId, pageSize);

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
        // IS DISTINCT FROM: reports of deleted reporters (user_id NULL)
        // are still listed.
        baseQueries.add(FQuery.distinctFrom('userId', excludeUserId));
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
          limitCount: pageSize,
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
          limitCount: pageSize,
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
      _hasMoreMap[key] = docs.length >= pageSize;
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
    final filter = zoneFilterFor(zone);
    if (filter.isEmpty && zone != null && zone.trim().isNotEmpty) {
      developer.log(
        'Skipping zone filter for zone "$zone"',
        name: 'ReportsStatusProvider',
      );
    }
    return [for (final e in filter.entries) FQuery.equal(e.key, e.value)];
  }

  /// Maps a `reports` document to a display-ready [VerificationReport].
  Future<VerificationReport> _toReport(Map<String, dynamic> data) async {
    final reportStatus = _parseStatus(data['status']);

    // reporter_name is set by the database on insert (from the reporter's
    // profile). Other users' profiles are not generally readable, so it is
    // never looked up client-side.
    final storedName = (data['reporterName'] as String?)?.trim();
    final reporterName = (storedName != null && storedName.isNotEmpty)
        ? storedName
        : 'Community Report';

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
    if (result['noLongerPending'] == true) {
      // The report moved on (verified / rejected): refresh stale lists.
      unawaited(refreshLoadedLists());
    }
    if (result['success'] != true) {
      throw VerificationRefusedException(
        (result['message'] ?? result['error'] ?? 'Verification failed')
            .toString(),
        noLongerPending: result['noLongerPending'] == true,
        alreadyVoted: result['alreadyVoted'] == true,
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
  /// senior staff can do that (see [staffRejectReport]). A [comment]
  /// explaining the dispute is required, so staff can act on it.
  Future<void> disputeReport(
    String reportId, {
    String? userId,
    String? comment,
  }) async {
    if (comment == null || comment.trim().isEmpty) {
      throw const VerificationRefusedException(
        'Please explain why you dispute this report.',
      );
    }
    try {
      await _submitVerificationAsCurrentUser(
        reportId,
        isConfirmed: false,
        userId: userId,
        comment: comment.trim(),
      );
      developer.log('Report dispute recorded: $reportId');
      unawaited(refreshLoadedLists());
    } on Exception catch (e) {
      developer.log('Error disputing report: $e');
      rethrow;
    }
  }

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
