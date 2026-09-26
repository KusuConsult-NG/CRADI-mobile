import 'dart:async';

import 'package:flutter/material.dart';
import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/core/services/offline_storage_service.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'dart:developer' as developer;
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:climate_app/core/l10n/l10n.dart';

class AlertsProvider extends ChangeNotifier {
  final SupabaseService _db = SupabaseService();
  final OfflineStorageService _offlineStorage = OfflineStorageService();

  List<Map<String, dynamic>> _alerts = [];
  bool _isLoading = false;

  /// Last load failure, resolved in the current language by the UI.
  LocalizedText? _error;

  List<Map<String, dynamic>> get alerts => _alerts;
  bool get isLoading => _isLoading;
  LocalizedText? get error => _error;

  /// Realtime feed of the alerts table, so broadcasts and dismissals show
  /// up without a manual refresh. Bound to the signed-in user it was
  /// started for.
  StreamSubscription<List<Map<String, dynamic>>>? _realtimeSub;
  String? _realtimeUid;

  AlertsProvider() {
    fetchAlerts();
  }

  /// Most active alerts the list keeps.
  static const int maxAlerts = 50;

  /// Realtime query: the newest rows by created_at with a server-side limit.
  ///
  /// `is_active` is mutable, so it must not be a stream filter: a filtered
  /// stream never learns that a row stopped matching, and any client-side
  /// filter disables the server-side limit (see
  /// [QueryPlan.streamServerLimit]), which would download every historical
  /// alert on each subscribe. Inactive rows are dropped on the client
  /// ([_isActive]); the window is wider than [maxAlerts] so a few dismissed
  /// alerts do not push active ones out of it.
  @visibleForTesting
  static final List<QueryFilter> realtimeQuery = [
    FQuery.orderDesc('createdAt'),
    FQuery.limit(maxAlerts * 2),
  ];

  /// (Re)starts the realtime feed for the signed-in user; stops it when
  /// nobody is signed in. Safe to call repeatedly.
  void _ensureRealtime() {
    final uid = _db.currentUserId;
    if (uid == null) {
      stopRealtime();
      return;
    }
    if (_realtimeSub != null && _realtimeUid == uid) return;
    stopRealtime();
    _realtimeUid = uid;
    _realtimeSub = _db
        .subscribeToCollection(
          collectionId: AppConfig.alertsCollection,
          queries: realtimeQuery,
        )
        .listen(
          (rows) {
            // Another account signed in meanwhile: its own feed takes over.
            if (_db.currentUserId != uid) return;
            _alerts = activeAlerts(rows);
            _error = null;
            notifyListeners();
            unawaited(_cache(_alerts));
          },
          onError: (Object e) {
            ErrorHandler.logError(e, context: 'AlertsProvider.realtime');
            // Resubscribed by the next fetchAlerts (e.g. reopening Alerts).
            stopRealtime();
          },
          onDone: () {
            if (_realtimeUid == uid) {
              _realtimeSub = null;
              _realtimeUid = null;
            }
          },
        );
  }

  /// Stops the realtime feed (sign-out / dispose).
  void stopRealtime() {
    final sub = _realtimeSub;
    _realtimeSub = null;
    _realtimeUid = null;
    if (sub != null) unawaited(sub.cancel());
  }

  @override
  void dispose() {
    stopRealtime();
    super.dispose();
  }

  Future<void> _cache(List<Map<String, dynamic>> alerts) async {
    // Caching is best-effort: a cache failure (e.g. HiveError, which is an
    // Error rather than an Exception) must never prevent alerts loading.
    try {
      await _offlineStorage.cacheAlerts(alerts);
    } on Object catch (e) {
      ErrorHandler.logError(e, context: 'AlertsProvider.cacheAlerts');
    }
  }

  static bool _isActive(Map<String, dynamic> a) {
    final v = a['isActive'] ?? a['is_active'];
    return v != false;
  }

  /// The active alerts among realtime [rows] (newest first), capped at
  /// [maxAlerts].
  @visibleForTesting
  static List<Map<String, dynamic>> activeAlerts(
    List<Map<String, dynamic>> rows,
  ) => rows.where(_isActive).take(maxAlerts).toList();

  /// Whether [alert] targets a user in [lga] of [state] (alerts for 'All'
  /// with no target state reach everyone).
  ///
  /// LGA names repeat across states (Obi is in Benue and in Nasarawa), so
  /// alerts carry `target_state` too:
  ///  * no target state (legacy alerts): `target_lga` is matched by exact
  ///    (case-insensitive) name in any state;
  ///  * a target state: the user's [state] must match as well, and a
  ///    `target_lga` of 'All' means every LGA of that state.
  /// A user whose state is unknown never matches a state-targeted alert.
  static bool targetsLga(
    Map<String, dynamic> alert,
    String? lga, {
    String? state,
  }) {
    String norm(Object? v) => (v ?? '').toString().trim().toLowerCase();
    final target = norm(alert['targetLga'] ?? alert['target_lga'] ?? 'All');
    final targetState = norm(alert['targetState'] ?? alert['target_state']);
    if (targetState.isNotEmpty && norm(state) != targetState) return false;
    if (target.isEmpty || target == 'all') return true;
    final mine = norm(lga);
    return mine.isNotEmpty && mine == target;
  }

  /// Where [alert] is addressed, for display: "Obi, Benue", "Benue" (every
  /// LGA of the state), "Obi" (legacy, no state), or null for everyone.
  static String? targetLabel(Map<String, dynamic> alert) {
    String? str(Object? v) {
      final s = v?.toString().trim();
      return s == null || s.isEmpty ? null : s;
    }

    final lga = str(alert['targetLga'] ?? alert['target_lga']);
    final state = str(alert['targetState'] ?? alert['target_state']);
    final allLgas = lga == null || lga.toLowerCase() == 'all';
    if (state == null) return allLgas ? null : lga;
    return allLgas ? state : '$lga, $state';
  }

  /// Active alerts addressed to [lga] in [state], to all of [state], or to
  /// everyone.
  List<Map<String, dynamic>> alertsForLga(String? lga, {String? state}) =>
      _alerts.where((a) => targetsLga(a, lga, state: state)).toList();

  Future<void> fetchAlerts() async {
    // Alerts are only readable when signed in: a fetch before sign-in would
    // return nothing and overwrite the offline cache with an empty list.
    // The sign-in hook in main.dart fetches again once a session exists.
    if (_db.currentUserId == null) {
      stopRealtime();
      return;
    }
    _ensureRealtime();
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final documents = await _db.listDocuments(
        collectionId: AppConfig.alertsCollection,
        queries: [
          FQuery.equal('isActive', true),
          FQuery.orderDesc('createdAt'),
        ],
        limitCount: maxAlerts,
      );

      _alerts = documents.where(_isActive).toList();

      // Caching is best-effort: a cache failure (e.g. HiveError, which is an
      // Error rather than an Exception) must never prevent alerts loading.
      try {
        await _offlineStorage.cacheAlerts(_alerts);
      } on Object catch (e) {
        ErrorHandler.logError(e, context: 'AlertsProvider.cacheAlerts');
      }

      developer.log(
        'Fetched ${_alerts.length} alerts and cached',
        name: 'AlertsProvider',
      );
    } on Exception catch (e) {
      ErrorHandler.logError(e, context: 'AlertsProvider.fetchAlerts');
      _error = (l) => l.alertsLoadError;

      List<Map<String, dynamic>> cached = const [];
      try {
        cached = _offlineStorage.getCachedAlerts().where(_isActive).toList();
      } on Object catch (_) {
        // Cache unavailable (not initialized or unreadable); ignore.
      }
      if (cached.isNotEmpty) {
        _alerts = cached;
        _error = null;
        developer.log(
          'Loaded ${_alerts.length} alerts from cache',
          name: 'AlertsProvider',
        );
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Loads one alert by id (deep links / notification taps). Returns null
  /// when it does not exist or is not readable.
  Future<Map<String, dynamic>?> fetchAlertById(String alertId) async {
    try {
      return await _db.getDocument(
        collectionId: AppConfig.alertsCollection,
        documentId: alertId,
      );
    } on DocumentNotFoundException catch (_) {
      return null;
    } on Exception catch (_) {
      // Offline / transient failure: fall back to the loaded or cached list.
      List<Map<String, dynamic>> known = _alerts;
      if (known.isEmpty) {
        try {
          known = _offlineStorage.getCachedAlerts();
        } on Object catch (_) {}
      }
      for (final a in known) {
        if ((a['id'] ?? a[r'$id'])?.toString() == alertId) return a;
      }
      rethrow;
    }
  }
}
