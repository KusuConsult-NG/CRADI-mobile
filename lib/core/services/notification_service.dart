import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/core/providers/settings_provider.dart';
import 'package:climate_app/core/services/hive_encryption_service.dart';
import 'package:climate_app/core/services/supabase_mapping.dart'
    show parseTimestamp;
import 'package:climate_app/features/profile/providers/profile_provider.dart';

/// Push notifications via OneSignal.
///
/// The Railway backend decides who receives what: it targets devices by
/// external id (the Supabase user id, set with [OneSignal.login]) and by the
/// data tags set here (role / lga / state / ward / monitoring_zone). There are
/// no topic subscriptions or device tokens stored in the database.
///
/// OneSignal displays notifications itself (including in the foreground);
/// this service keeps a local history for the in-app notifications screen and
/// routes taps.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  bool _initialized = false;
  bool _pushEnabled = false;
  ProfileProvider? _profileProvider;

  GoRouter? _router;
  Map<String, dynamic>? _pendingNavigation;

  /// Set from main.dart so notification taps can navigate via GoRouter.
  /// A tap that arrived before the router existed (cold start) is replayed.
  GoRouter? get router => _router;
  set router(GoRouter? value) {
    _router = value;
    final pending = _pendingNavigation;
    if (value != null && pending != null) {
      _pendingNavigation = null;
      _handleNotificationNavigation(pending);
    }
  }

  /// In-flight initialization, so concurrent callers share one run.
  Future<void>? _initFuture;

  /// Signed-in user state used to (re)compute tags.
  String? _userId;
  Map<String, String> _baseTags = const {};
  String? _zone;
  Map<String, String> _appliedTags = const {};

  static const String _notificationsBoxName = 'notifications_history';
  Box<Map>? _notificationsBox;

  /// ValueNotifier for unread notification count
  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  /// Initialize OneSignal and the local notification history.
  ///
  /// [profileProvider] lets the service keep the `monitoring_zone` tag in
  /// sync when the user changes zone.
  Future<void> initialize({ProfileProvider? profileProvider}) async {
    if (profileProvider != null && profileProvider != _profileProvider) {
      _profileProvider?.removeListener(_onProfileChanged);
      _profileProvider = profileProvider;
      _profileProvider!.addListener(_onProfileChanged);
    }
    if (_initialized) return;
    _initFuture ??= _initialize().whenComplete(() {
      // Allow a retry if initialization did not complete (e.g. error).
      if (!_initialized) _initFuture = null;
    });
    return _initFuture;
  }

  Future<void> _initialize() async {
    try {
      final cipher = await HiveEncryptionService().getCipher();
      _notificationsBox = await Hive.openBox<Map>(
        _notificationsBoxName,
        encryptionCipher: cipher,
      );

      if (AppConfig.oneSignalAppId.isEmpty) {
        developer.log(
          'ONESIGNAL_APP_ID not set — push notifications disabled',
          name: 'NotificationService',
        );
      } else {
        await OneSignal.initialize(AppConfig.oneSignalAppId);
        OneSignal.Notifications.addForegroundWillDisplayListener(
          _onForegroundNotification,
        );
        OneSignal.Notifications.addClickListener(_onNotificationClicked);
        _pushEnabled = true;

        // Restore the user's Push Notifications setting.
        if (SettingsProvider().pushNotifications) {
          // Not awaited: the permission dialog can stay open indefinitely
          // and must not hold back initialization or identifying the user.
          // No "open Settings" fallback dialog here: that would nag on
          // every cold start once the user denied the OS prompt.
          unawaited(_restorePushSubscription());
        } else {
          unawaited(setPushSubscribed(false));
        }
      }

      _initialized = true;
      // The history belongs to one account; drop another account's.
      await _ensureHistoryOwner(_userId);
      _updateUnreadCount();

      // A user signed in while we were initializing — identify them now.
      if (_userId != null) await _serialized(_syncSignedInUser);

      developer.log(
        'Notifications initialized (push: $_pushEnabled)',
        name: 'NotificationService',
      );
    } on Exception catch (e) {
      developer.log(
        'Notification initialization error: $e',
        name: 'NotificationService',
      );
    }
  }

  /// Asks for the OS permission without the "open Settings" fallback, then
  /// undoes an earlier opt-out only when permission is granted: OneSignal's
  /// optIn() prompts on its own (with the Settings fallback), which would
  /// nag on every cold start after the user denied the OS prompt.
  Future<void> _restorePushSubscription() async {
    await requestPushPermission(fallbackToSettings: false);
    try {
      if (OneSignal.Notifications.permission &&
          OneSignal.User.pushSubscription.optedIn != true) {
        await setPushSubscribed(true);
      }
    } on Object catch (e) {
      developer.log(
        'Push opt-in restore failed: $e',
        name: 'NotificationService',
      );
    }
  }

  /// Whether the OS notification permission is currently granted.
  bool get hasPushPermission {
    if (!_pushEnabled) return false;
    try {
      return OneSignal.Notifications.permission;
    } on Object catch (_) {
      return false;
    }
  }

  /// Whether push is set up on this device (OneSignal configured and
  /// initialised).
  bool get isPushAvailable => _pushEnabled;

  /// Asks for the OS notification permission. [fallbackToSettings] offers
  /// to open the system settings when it was denied before; only use it for
  /// an explicit user action (the Settings toggle), not at startup.
  Future<void> requestPushPermission({required bool fallbackToSettings}) async {
    if (!_pushEnabled) return;
    try {
      final granted = await OneSignal.Notifications.requestPermission(
        fallbackToSettings,
      );
      if (!granted) {
        developer.log(
          'User declined notification permissions',
          name: 'NotificationService',
        );
      }
    } on Exception catch (e) {
      developer.log(
        'Permission request error: $e',
        name: 'NotificationService',
      );
    }
  }

  /// Opts this device in to / out of push (the Settings toggle). Opting in
  /// may show the OS permission prompt. Returns false when it failed.
  Future<bool> setPushSubscribed(bool enabled) async {
    if (!_pushEnabled) return false;
    try {
      if (enabled) {
        await OneSignal.User.pushSubscription.optIn();
      } else {
        await OneSignal.User.pushSubscription.optOut();
      }
      return true;
    } on Exception catch (e) {
      developer.log(
        'Push opt-${enabled ? 'in' : 'out'} error: $e',
        name: 'NotificationService',
      );
      return false;
    }
  }

  // ─────────────────────────── OneSignal callbacks ──────────────────────────

  void _onForegroundNotification(OSNotificationWillDisplayEvent event) {
    final n = event.notification;
    developer.log(
      'Foreground notification: ${n.title}',
      name: 'NotificationService',
    );
    // Let OneSignal display it; just record it in the history.
    unawaited(
      _saveNotification(
        notificationId: n.notificationId,
        // Empty: the history screen shows a localised default title.
        title: n.title ?? '',
        body: n.body ?? '',
        data: n.additionalData,
      ),
    );
  }

  void _onNotificationClicked(OSNotificationClickEvent event) {
    final n = event.notification;
    final data = n.additionalData ?? const <String, dynamic>{};
    developer.log(
      'Notification clicked: ${n.title} $data',
      name: 'NotificationService',
    );
    // A push received in the foreground is already in the history: mark
    // that entry read instead of recording a copy.
    unawaited(
      recordOpenedNotification(
        notificationId: n.notificationId,
        // Empty: the history screen shows a localised default title.
        title: n.title ?? '',
        body: n.body ?? '',
        data: data,
      ),
    );
    if (_router == null) {
      // Cold start: navigate once the router is injected.
      _pendingNavigation = Map<String, dynamic>.from(data);
      return;
    }
    _handleNotificationNavigation(data);
  }

  // ─────────────────────────── Navigation ──────────────────────────────────

  /// Maps a push payload (`additionalData`) to an app route.
  ///
  /// Backend types: verification_request, report_status, escalation,
  /// escalation_auto, validated_alert, admin_alert (ids arrive as
  /// `report_id` / `alert_id`). `validated_alert` carries the validated
  /// report's `report_id` and opens that report. Older camelCase keys and
  /// types are still understood.
  static String routeForData(Map<String, dynamic> data) {
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = data[k];
        if (v != null && v.toString().isNotEmpty) return v.toString();
      }
      return '';
    }

    final type = (data['type'] ?? 'alert').toString();
    final reportId = pick(['report_id', 'reportId', 'id']);
    final alertId = pick(['alert_id', 'alertId', 'id']);

    switch (type) {
      case 'verification_request':
      case 'report_status':
      case 'escalation':
      case 'escalation_auto':
      case 'report':
      case 'verification':
        return reportId.isNotEmpty ? '/report/$reportId' : '/reports-status';
      case 'validated_alert':
        final validatedReport = pick(['report_id', 'reportId']);
        if (validatedReport.isNotEmpty) return '/report/$validatedReport';
        return alertId.isNotEmpty ? '/alert/$alertId' : '/alerts';
      case 'admin_alert':
      case 'alert':
        return alertId.isNotEmpty ? '/alert/$alertId' : '/alerts';
      case 'chat':
        return '/chat';
      default:
        return '/notifications';
    }
  }

  /// A key identifying the *event* a notification is about, independent of
  /// how it reached the device.
  ///
  /// The push path and the in-app producers ([recordAlerts],
  /// [recordOwnReportStatuses]) both store their entry under this key, so a
  /// push that arrives after the app already recorded the same event (or the
  /// other way round) updates nothing and the user sees one entry, not two.
  /// Returns null for payloads with no identifiable subject; those fall back
  /// to the OneSignal notification id.
  static String? stableKeyFor(Map<String, dynamic>? data) {
    if (data == null) return null;
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = data[k];
        if (v != null && v.toString().isNotEmpty) return v.toString();
      }
      return '';
    }

    final type = (data['type'] ?? '').toString();
    switch (type) {
      case 'report_status':
        final id = pick(['report_id', 'reportId', 'id']);
        if (id.isEmpty) return null;
        // The status is part of the identity: pending → verified → approved
        // are three separate things that happened to the same report. The
        // backend sends it for every status the app produces an entry for
        // (see [reportStatuses]), so both paths build the same key.
        final status = (data['status'] ?? '').toString().trim().toLowerCase();
        return status.isEmpty
            ? 'report_status:$id'
            : 'report_status:$id:$status';
      case 'verification_request':
      case 'escalation':
      case 'escalation_auto':
      case 'validated_alert':
        final id = pick(['report_id', 'reportId', 'id']);
        return id.isEmpty ? null : '$type:$id';
      case 'admin_alert':
      case 'alert':
        final id = pick(['alert_id', 'alertId', 'id']);
        return id.isEmpty ? null : 'alert:$id';
      default:
        return null;
    }
  }

  void _handleNotificationNavigation(Map<String, dynamic> data) {
    final route = routeForData(data);
    developer.log('Notification nav → $route', name: 'NotificationService');
    final router = _router;
    if (router == null) {
      _pendingNavigation = data;
      return;
    }
    // Safe before auth is ready: the router's top-level redirect parks the
    // navigation on /splash?from=<route> (or /login?from=<route> while the
    // app is locked / signed out) and resumes it once the user may see it.
    router.go(route);
  }

  // ─────────────────────────── Identity & tags ─────────────────────────────

  /// Sanitises a tag value exactly as the backend does.
  @visibleForTesting
  static String sanitizeTag(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');

  /// Tags for the signed-in user (empty values are omitted).
  @visibleForTesting
  static Map<String, String> tagsFor({
    String? role,
    String? lga,
    String? state,
    String? ward,
    String? monitoringZone,
  }) {
    final raw = {
      'role': role,
      'lga': lga,
      'state': state,
      'ward': ward,
      'monitoring_zone': monitoringZone,
    };
    return {
      for (final e in raw.entries)
        if (e.value != null && e.value!.isNotEmpty)
          e.key: sanitizeTag(e.value!),
    };
  }

  /// OneSignal login / logout / tag calls run one at a time, in call order,
  /// so a logout for a previous user can never land after the login of the
  /// next one.
  Future<void> _opChain = Future<void>.value();

  Future<void> _serialized(Future<void> Function() op) {
    final next = _opChain.then((_) => op());
    _opChain = next.catchError((Object _) {});
    return next;
  }

  /// Whether [_baseTags] reflect the user's profile (false when the profile
  /// could not be loaded: the existing tags are left untouched).
  bool _tagsKnown = false;

  /// Call after a user signs in (from AuthProvider): identifies the device
  /// with the Supabase user id and sets targeting tags. With [updateTags]
  /// false (profile unavailable) only the identity is synced.
  Future<void> onUserSignedIn({
    required String userId,
    String? role,
    String? lga,
    String? state,
    String? ward,
    String? monitoringZone,
    bool updateTags = true,
  }) async {
    final sameUser = _userId == userId;
    _userId = userId;
    if (updateTags) {
      _baseTags = tagsFor(role: role, lga: lga, state: state, ward: ward);
      _tagsKnown = true;
    } else if (!sameUser) {
      _baseTags = const {};
      _tagsKnown = false;
    }
    final profileZone = _profileProvider?.monitoringZone;
    _zone = (profileZone != null && profileZone.isNotEmpty)
        ? profileZone
        : monitoringZone;
    // If not yet initialized, initialize() will sync once it finishes.
    if (!_initialized) return;
    final sync = _serialized(_syncSignedInUser);
    if (!sameUser) await _ensureHistoryOwner(userId);
    await sync;
  }

  /// Call after the user signs out: detaches the device from the user so it
  /// stops receiving their targeted notifications.
  Future<void> onUserSignedOut() async {
    final wasSignedIn = _userId != null;
    _userId = null;
    _baseTags = const {};
    _tagsKnown = false;
    _zone = null;
    // Queued before any await, so a sign-in that follows runs after it.
    final logout = (!_pushEnabled || !wasSignedIn)
        ? Future<void>.value()
        : _serialized(() async {
            // A new user signed in meanwhile: their login replaces the
            // identity; logging out now would detach them.
            if (_userId != null) return;
            _appliedTags = const {};
            try {
              await OneSignal.logout();
            } on Exception catch (e) {
              developer.log(
                'OneSignal logout error: $e',
                name: 'NotificationService',
              );
            }
          });
    // The next account on this device must not see this one's history
    // (unless that account already signed in meanwhile).
    if (_userId == null) await clearHistoryForSignOut();
    await logout;
  }

  Future<void> _syncSignedInUser() async {
    final userId = _userId;
    if (!_pushEnabled || userId == null) return;
    try {
      await OneSignal.login(userId);
      if (_tagsKnown) await _applyTags();
    } on Exception catch (e) {
      developer.log(
        'OneSignal login/tag error: $e',
        name: 'NotificationService',
      );
    }
  }

  Future<void> _applyTags() async {
    final tags = {..._baseTags, ...tagsFor(monitoringZone: _zone)};
    final removed = _appliedTags.keys
        .where((k) => !tags.containsKey(k))
        .toList();
    if (removed.isNotEmpty) await OneSignal.User.removeTags(removed);
    if (tags.isNotEmpty) await OneSignal.User.addTags(tags);
    _appliedTags = tags;
  }

  /// Keep the monitoring_zone tag in sync with the ProfileProvider.
  void _onProfileChanged() {
    final provider = _profileProvider;
    if (provider == null || _userId == null || provider.isLoading) return;
    final zone = provider.monitoringZone;
    if (zone == _zone) return;
    _zone = zone;
    if (_initialized && _pushEnabled) unawaited(updateZoneSubscriptions());
  }

  /// Re-apply tags after the user changes their monitoring zone.
  Future<void> updateZoneSubscriptions() async {
    if (!_pushEnabled || _userId == null || !_tagsKnown) return;
    await _serialized(() async {
      if (_userId == null || !_tagsKnown) return;
      try {
        await _applyTags();
      } on Exception catch (e) {
        developer.log('OneSignal tag error: $e', name: 'NotificationService');
      }
    });
  }

  // ─────────────────────────── Local history ───────────────────────────────

  /// SharedPreferences key holding the user id the history belongs to.
  static const String historyOwnerKey = 'notifications_history_owner';

  /// Uses [box] as the history box (tests only; the app opens an encrypted
  /// Hive box in [initialize]).
  @visibleForTesting
  void attachHistoryBoxForTesting(Box<Map> box) {
    _notificationsBox = box;
    _updateUnreadCount();
  }

  /// Signed-in user id for tests that bypass [onUserSignedIn].
  @visibleForTesting
  Future<void> setUserForTesting(String? userId) async {
    _userId = userId;
    if (userId == null) {
      await clearHistoryForSignOut();
    } else {
      await _ensureHistoryOwner(userId);
    }
  }

  /// Clears the history and its owner record (on sign-out).
  Future<void> clearHistoryForSignOut() async {
    try {
      await clearAll();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(historyOwnerKey);
      await _clearSeenState(prefs);
    } on Object catch (e) {
      developer.log('History clear error: $e', name: 'NotificationService');
    }
  }

  /// Clears the history when it was recorded for another account (e.g. the
  /// sign-out clear could not run because the box was not open yet), then
  /// records [userId] as its owner.
  Future<void> _ensureHistoryOwner(String? userId) async {
    if (userId == null || _notificationsBox == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final owner = prefs.getString(historyOwnerKey);
      if (owner == userId) return;
      await clearAll();
      // The producers' memory belongs to the previous account too: without
      // this the next user would be told about their predecessor's reports.
      await _clearSeenState(prefs);
      await prefs.setString(historyOwnerKey, userId);
    } on Object catch (e) {
      developer.log('History owner error: $e', name: 'NotificationService');
    }
  }

  // ───────────────────── In-app producers ──────────────────────────────
  //
  // The history must reflect what happened to this user whether or not a
  // push was delivered: push is optional (ONESIGNAL_APP_ID may be unset),
  // may be denied at the OS level, and never arrives for events that
  // happen while the app itself is the one watching the data. Everything
  // here is written straight to the local Hive box — no network call — so
  // it works offline, and every entry is keyed by [stableKeyFor] so a push
  // for the same event collapses onto it.

  /// SharedPreferences key holding what the producers have already seen.
  static const String seenStateKey = 'notifications_seen_state';

  /// The report statuses an entry is produced for. Kept identical to the
  /// backend's `REPORT_STATUSES`, so a push for the same change builds the
  /// same [stableKeyFor] key and does not add a second entry.
  static const Set<String> reportStatuses = {
    'pending',
    'verified',
    'approved',
    'rejected',
  };

  /// Most ids remembered per producer, so the record cannot grow forever.
  static const int _maxSeenEntries = 300;

  Map<String, dynamic>? _seenState;

  Future<Map<String, dynamic>> _loadSeenState() async {
    final cached = _seenState;
    if (cached != null) return cached;
    var state = <String, dynamic>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(seenStateKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) state = Map<String, dynamic>.from(decoded);
      }
    } on Object catch (e) {
      developer.log('Seen-state read error: $e', name: 'NotificationService');
    }
    return _seenState = state;
  }

  Future<void> _saveSeenState(Map<String, dynamic> state) async {
    _seenState = state;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(seenStateKey, jsonEncode(state));
    } on Object catch (e) {
      developer.log('Seen-state write error: $e', name: 'NotificationService');
    }
  }

  Future<void> _clearSeenState(SharedPreferences prefs) async {
    _seenState = null;
    await prefs.remove(seenStateKey);
  }

  /// Records an entry for every alert in [targetedAlerts] the user has not
  /// been told about yet.
  ///
  /// Callers pass alerts already narrowed to this user (see
  /// `AlertsProvider.alertsForLga`, which applies
  /// `AlertsProvider.targetsLga`); this service does not know the user's
  /// LGA.
  ///
  /// Only alerts *issued after* this account first called in are announced.
  /// That cut-off, rather than "an id I have not seen yet", is what keeps a
  /// backlog out of the history: the user's LGA is not yet known at the
  /// instant they sign in, so an alert can become targeted a moment later
  /// (or after they change their LGA) without being news to them. The id
  /// list is what makes repeated calls idempotent.
  Future<void> recordAlerts(List<Map<String, dynamic>> targetedAlerts) async {
    if (_notificationsBox == null) return;
    final state = await _loadSeenState();
    final seen = <String>[
      for (final v in (state['alerts'] as List?) ?? const []) v.toString(),
    ];
    final known = seen.toSet();
    final since = DateTime.tryParse((state['alertsSince'] ?? '').toString());

    final fresh = <Map<String, dynamic>>[];
    for (final alert in targetedAlerts) {
      final id = (alert['id'] ?? alert[r'$id'] ?? '').toString();
      if (id.isEmpty || !known.add(id)) continue;
      seen.add(id);
      final createdAt = parseTimestamp(
        alert['createdAt'] ?? alert['created_at'],
      );
      if (since != null && createdAt != null && createdAt.isAfter(since)) {
        fresh.add(alert);
      }
    }
    if (seen.length > _maxSeenEntries) {
      seen.removeRange(0, seen.length - _maxSeenEntries);
    }
    await _saveSeenState({
      ...state,
      'alerts': seen,
      'alertsSince':
          state['alertsSince'] ?? DateTime.now().toUtc().toIso8601String(),
    });

    for (final alert in fresh) {
      final id = (alert['id'] ?? alert[r'$id'] ?? '').toString();
      final severity = (alert['severity'] ?? '').toString();
      await _saveNotification(
        // Alert copy is authored text, not app UI, so it is stored as is;
        // an alert with no message falls back to a localised line on the
        // notifications screen.
        title: (alert['title'] ?? '').toString().trim(),
        body: (alert['message'] ?? alert['body'] ?? '').toString().trim(),
        data: {
          'type': 'admin_alert',
          'alert_id': id,
          if (severity.isNotEmpty) 'severity': severity,
          'source': 'in_app',
        },
      );
    }
  }

  /// Records an entry for every one of the user's own [reports] whose
  /// status changed since the last call.
  ///
  /// This also covers peer verification: a peer verifying or disputing a
  /// report is only visible to its author as the report moving to
  /// `verified` / `rejected`, so it needs no separate producer — and giving
  /// it one would put two entries in the history for one thing happening.
  ///
  /// Rows the producer has never seen (a report the user just filed) are
  /// only remembered, never announced.
  Future<void> recordOwnReportStatuses(
    List<Map<String, dynamic>> reports,
  ) async {
    if (_notificationsBox == null) return;
    final state = await _loadSeenState();
    final previous = <String, String>{
      for (final e in ((state['reports'] as Map?) ?? const {}).entries)
        e.key.toString(): e.value.toString(),
    };
    final seeded = state['reportsSeeded'] == true;

    final current = <String, String>{};
    final changed = <Map<String, dynamic>>[];
    for (final report in reports) {
      final id = (report['id'] ?? report[r'$id'] ?? '').toString();
      if (id.isEmpty) continue;
      final status = (report['status'] ?? '').toString().trim().toLowerCase();
      if (status.isEmpty) continue;
      if (current.length < _maxSeenEntries) current[id] = status;
      final was = previous[id];
      if (!seeded || was == null || was == status) continue;
      if (!reportStatuses.contains(status)) continue;
      changed.add(report);
    }
    await _saveSeenState({...state, 'reports': current, 'reportsSeeded': true});

    for (final report in changed) {
      final id = (report['id'] ?? report[r'$id'] ?? '').toString();
      final status = (report['status'] ?? '').toString().trim().toLowerCase();
      final hazard = (report['hazardType'] ?? report['hazard_type'] ?? '')
          .toString();
      await _saveNotification(
        // Empty: the notifications screen builds the text from the data
        // below in the user's current language.
        title: '',
        body: '',
        data: {
          'type': 'report_status',
          'report_id': id,
          'status': status,
          if (hazard.isNotEmpty) 'hazardType': hazard,
          'source': 'in_app',
        },
      );
    }
  }

  /// Drops the producers' memory (tests).
  @visibleForTesting
  Future<void> resetSeenStateForTesting() async {
    final prefs = await SharedPreferences.getInstance();
    await _clearSeenState(prefs);
  }

  /// Records a tapped push: marks its history entry (matched by the
  /// OneSignal [notificationId]) read, or adds it as read when it is not in
  /// the history yet (e.g. received while the app was in the background).
  @visibleForTesting
  Future<void> recordOpenedNotification({
    required String? notificationId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    final box = _notificationsBox;
    if (box == null) return;
    final key = stableKeyFor(data) ?? notificationId;
    if (key != null && key.isNotEmpty && box.containsKey(key)) {
      await markAsRead(key);
      return;
    }
    await _saveNotification(
      notificationId: notificationId,
      title: title,
      body: body,
      data: data,
      isRead: true,
    );
  }

  /// Adds a push to the history, keyed by its OneSignal [notificationId]
  /// when known (so the same push is never recorded twice).
  @visibleForTesting
  Future<void> saveNotificationForTesting({
    String? notificationId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) => _saveNotification(
    notificationId: notificationId,
    title: title,
    body: body,
    data: data,
  );

  Future<void> _saveNotification({
    String? notificationId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
    bool isRead = false,
  }) async {
    if (_notificationsBox == null) return;

    // Keyed by what happened, not by how it arrived, so a push and an
    // in-app producer for the same event share one entry.
    final id =
        stableKeyFor(data) ??
        ((notificationId != null && notificationId.isNotEmpty)
            ? notificationId
            : DateTime.now().millisecondsSinceEpoch.toString());
    // Already recorded (the same push delivered twice, or the in-app
    // producer got there first): keep that entry.
    if (_notificationsBox!.containsKey(id)) return;
    final notification = {
      'id': id,
      'title': title,
      'body': body,
      'data': data ?? {},
      'timestamp': DateTime.now().toIso8601String(),
      'isRead': isRead,
      'type': data?['type'] ?? 'system',
    };

    await _notificationsBox!.put(id, notification);
    _updateUnreadCount();
    await _evictOldNotifications();
  }

  /// Get all notifications from history
  List<Map<String, dynamic>> getNotifications() {
    if (_notificationsBox == null) return [];

    return _notificationsBox!.values
        .map((e) => Map<String, dynamic>.from(e))
        .toList()
      ..sort((a, b) => b['timestamp'].compareTo(a['timestamp']));
  }

  /// Mark a notification as read
  Future<void> markAsRead(String id) async {
    if (_notificationsBox == null) return;

    final notification = _notificationsBox!.get(id);
    if (notification != null) {
      final updated = Map<String, dynamic>.from(notification)
        ..['isRead'] = true;
      await _notificationsBox!.put(id, updated);
      _updateUnreadCount();
    }
  }

  /// Mark all notifications as read
  Future<void> markAllAsRead() async {
    if (_notificationsBox == null) return;

    for (final key in _notificationsBox!.keys) {
      final notification = _notificationsBox!.get(key);
      if (notification != null && notification['isRead'] == false) {
        final updated = Map<String, dynamic>.from(notification)
          ..['isRead'] = true;
        await _notificationsBox!.put(key, updated);
      }
    }
    _updateUnreadCount();
  }

  /// Clear all notifications
  Future<void> clearAll() async {
    if (_notificationsBox == null) return;
    await _notificationsBox!.clear();
    _updateUnreadCount();
  }

  /// Evict notifications older than 30 days and trim box to 200 entries.
  Future<void> _evictOldNotifications() async {
    if (_notificationsBox == null) return;

    const maxEntries = 200;
    const maxAge = Duration(days: 30);
    final cutoff = DateTime.now().subtract(maxAge);

    final staleKeys = _notificationsBox!.keys.where((key) {
      final n = _notificationsBox!.get(key);
      if (n == null) return true;
      final ts = DateTime.tryParse(n['timestamp']?.toString() ?? '');
      return ts != null && ts.isBefore(cutoff);
    }).toList();

    if (staleKeys.isNotEmpty) {
      await _notificationsBox!.deleteAll(staleKeys);
    }

    if (_notificationsBox!.length > maxEntries) {
      final sorted =
          _notificationsBox!.values
              .map((n) => Map<String, dynamic>.from(n))
              .toList()
            ..sort(
              (a, b) => a['timestamp'].toString().compareTo(
                b['timestamp'].toString(),
              ),
            );

      final toDelete = sorted
          .take(_notificationsBox!.length - maxEntries)
          .map((n) => n['id'] as String)
          .toList();

      await _notificationsBox!.deleteAll(toDelete);
    }
  }

  void _updateUnreadCount() {
    if (_notificationsBox == null) return;
    unreadCount.value = _notificationsBox!.values
        .where((n) => n['isRead'] == false)
        .length;
  }
}
