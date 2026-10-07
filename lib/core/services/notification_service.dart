import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:climate_app/core/providers/settings_provider.dart';
import 'package:climate_app/core/services/backend.dart' show registerPushTarget;
import 'package:climate_app/core/services/hive_encryption_service.dart';
import 'package:climate_app/core/services/supabase_mapping.dart'
    show parseTimestamp;
import 'package:climate_app/features/profile/providers/profile_provider.dart';

/// Push notifications via FCM + Appwrite Messaging topics.
///
/// The Appwrite drain Function decides who receives what: it publishes to
/// Appwrite Messaging topics (e.g. `role_field_agent`, `lga_ikeja`) that this
/// service subscribes the device to after sign-in. Appwrite Messaging relays
/// the message to FCM, which delivers it to the device.
///
/// FCM displays notifications itself (including in the foreground via the
/// background message handler); this service keeps a local history for the
/// in-app notifications screen and routes taps.
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

  /// Signed-in user state used to (re)compute topic subscriptions.
  String? _userId;
  Map<String, String> _baseTags = const {};
  String? _zone;
  Map<String, String> _appliedTags = const {};

  static const String _notificationsBoxName = 'notifications_history';
  Box<Map>? _notificationsBox;

  /// ValueNotifier for unread notification count
  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  /// Initialize FCM and the local notification history.
  ///
  /// [profileProvider] lets the service keep the `monitoring_zone` topic in
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

      // FCM setup — gracefully disabled when Firebase is not configured.
      try {
        final messaging = FirebaseMessaging.instance;
        final settings = await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: !SettingsProvider().pushNotifications,
        );
        _pushEnabled =
            settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;

        if (_pushEnabled) {
          // Foreground messages: record to history; FCM does not show a
          // heads-up by default in foreground, so we just log it.
          FirebaseMessaging.onMessage.listen(_onForegroundMessage);
          // Tapped from background / notification tray.
          FirebaseMessaging.onMessageOpenedApp.listen(_onMessageTapped);
          // Cold-start tap (app was terminated).
          final initial = await messaging.getInitialMessage();
          if (initial != null) _onMessageTapped(initial);
          // Token refresh: update Appwrite push target
          FirebaseMessaging.instance.onTokenRefresh.listen((token) {
            unawaited(syncPushTarget(token));
          });
        }
      } on Exception catch (e) {
        developer.log(
          'FCM setup error (push disabled): $e',
          name: 'NotificationService',
        );
        _pushEnabled = false;
      }

      _initialized = true;
      // The history belongs to one account; drop another account's.
      await _ensureHistoryOwner(_userId);
      _updateUnreadCount();

      // A user signed in while we were initializing — subscribe them now.
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

  /// Whether the OS notification permission is currently granted.
  bool get hasPushPermission => _pushEnabled;

  /// Whether push is set up on this device (FCM configured and initialised).
  bool get isPushAvailable => _pushEnabled;

  /// Requests OS notification permission. On Android 13+ this shows the
  /// system dialog the first time. [fallbackToSettings] is kept for API
  /// compatibility with callers; FCM handles the dialog itself.
  Future<void> requestPushPermission({required bool fallbackToSettings}) async {
    if (!_pushEnabled) return;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      _pushEnabled =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } on Exception catch (e) {
      developer.log(
        'Permission request error: $e',
        name: 'NotificationService',
      );
    }
  }

  /// Opts this device in/out of push (the Settings toggle).
  /// With FCM, opt-out is handled at the OS level — we simply skip
  /// subscribing to topics when the user disables push.
  Future<bool> setPushSubscribed(bool enabled) async {
    if (!_pushEnabled) return false;
    try {
      await FirebaseMessaging.instance.setAutoInitEnabled(enabled);
      if (enabled && _userId != null) {
        await _serialized(_syncSignedInUser);
      } else if (!enabled) {
        await _unsubscribeAllTopics();
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

  // ─────────────────────────── FCM callbacks ───────────────────────────────

  void _onForegroundMessage(RemoteMessage message) {
    final n = message.notification;
    developer.log(
      'Foreground message: ${n?.title}',
      name: 'NotificationService',
    );
    unawaited(
      _saveNotification(
        notificationId: message.messageId,
        title: n?.title ?? '',
        body: n?.body ?? '',
        data: message.data.isNotEmpty ? message.data : null,
      ),
    );
  }

  void _onMessageTapped(RemoteMessage message) {
    final n = message.notification;
    final data = Map<String, dynamic>.from(message.data);
    developer.log(
      'Notification tapped: ${n?.title} $data',
      name: 'NotificationService',
    );
    unawaited(
      recordOpenedNotification(
        notificationId: message.messageId,
        title: n?.title ?? '',
        body: n?.body ?? '',
        data: data,
      ),
    );
    if (_router == null) {
      _pendingNavigation = data;
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

  // ─────────────────────────── Identity & topics ───────────────────────────

  /// Sanitises a topic segment exactly as the backend does.
  @visibleForTesting
  static String sanitizeTag(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');

  /// Topic names for the signed-in user (empty values are omitted).
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

  /// FCM topic name for a given key/value pair (e.g. `role` + `field_agent`
  /// → `role_field_agent`).
  static String _topicFor(String key, String value) => '${key}_$value';

  /// All-users broadcast topic — every device subscribes on sign-in.
  static const String _allUsersTopic = 'all-users';

  /// FCM topic subscribe/unsubscribe calls run one at a time.
  Future<void> _opChain = Future<void>.value();

  Future<void> _serialized(Future<void> Function() op) {
    final next = _opChain.then((_) => op());
    _opChain = next.catchError((Object _) {});
    return next;
  }

  bool _tagsKnown = false;

  /// Call after a user signs in (from AuthProvider): subscribes the device to
  /// the user's Appwrite Messaging topics. With [updateTags] false (profile
  /// unavailable) only the all-users topic is subscribed.
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
    if (!_initialized) return;
    final sync = _serialized(_syncSignedInUser);
    if (!sameUser) await _ensureHistoryOwner(userId);
    await sync;
  }

  /// Call after the user signs out: unsubscribes all topics.
  Future<void> onUserSignedOut() async {
    final wasSignedIn = _userId != null;
    _userId = null;
    _baseTags = const {};
    _tagsKnown = false;
    _zone = null;
    // The token is the device's, not the account's: the next user on this
    // phone has the same one, and remembering it as registered would skip
    // registering *their* target and leave them with no push at all.
    _registeredToken = null;
    final logout = (!_pushEnabled || !wasSignedIn)
        ? Future<void>.value()
        : _serialized(() async {
            if (_userId != null) return; // new user signed in meanwhile
            try {
              await _unsubscribeAllTopics();
              _appliedTags = const {};
            } on Exception catch (e) {
              developer.log(
                'FCM topic unsubscribe error: $e',
                name: 'NotificationService',
              );
            }
          });
    if (_userId == null) await clearHistoryForSignOut();
    await logout;
  }

  Future<void> _syncSignedInUser() async {
    if (!_pushEnabled || _userId == null) return;
    try {
      // Subscribe to all-users first, then role/lga/state/ward/zone topics.
      await FirebaseMessaging.instance.subscribeToTopic(_allUsersTopic);
      if (_tagsKnown) await _applyTags();
    } on Exception catch (e) {
      developer.log(
        'FCM topic subscribe error: $e',
        name: 'NotificationService',
      );
    }
    // After the identity, because the server subscribes the target to the
    // topics of the profile it belongs to, and on Appwrite the session is
    // what says whose target this is.
    await syncPushTarget(await _pushToken());
  }

  /// How this device is registered for push on the active backend.
  @visibleForTesting
  Future<bool> Function(String token) pushTargetRegistrar = registerPushTarget;

  /// The last token handed to the registrar, so a repeated observer
  /// callback with an unchanged token costs nothing.
  String? _registeredToken;

  Future<String?> _pushToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } on Object catch (e) {
      developer.log('Push token read failed: $e', name: 'NotificationService');
      return null;
    }
  }

  /// Registers [token] as this device's push target on the backend.
  ///
  /// Quiet about the three ordinary reasons there is nothing to do — no
  /// user, no token yet, the same token as last time — and loud about a
  /// failure, which is the whole point: a push path that silently stops
  /// working looks exactly like one with nothing to deliver.
  ///
  /// It does not check [_pushEnabled]: a token is only ever produced by a
  /// OneSignal that did initialise, so the guard would say nothing the
  /// empty-token check does not — and it is what makes this reachable
  /// from a test, which cannot start the plugin.
  @visibleForTesting
  Future<void> syncPushTarget(String? token) async {
    final userId = _userId;
    if (userId == null) return;
    if (token == null || token.isEmpty) return;
    if (token == _registeredToken) return;
    try {
      if (await pushTargetRegistrar(token)) {
        _registeredToken = token;
        developer.log(
          'Push target registered for $userId',
          name: 'NotificationService',
        );
      }
    } on Object catch (e) {
      // Not recorded as registered, so the next sign-in or token change
      // tries again.
      developer.log(
        'Push target registration failed: $e',
        name: 'NotificationService',
      );
    }
  }

  Future<void> _applyTags() async {
    final tags = {..._baseTags, ...tagsFor(monitoringZone: _zone)};

    // Unsubscribe removed topics.
    final removed = _appliedTags.keys
        .where((k) => !tags.containsKey(k))
        .toList();
    for (final k in removed) {
      await FirebaseMessaging.instance.unsubscribeFromTopic(
        _topicFor(k, _appliedTags[k]!),
      );
    }

    // Subscribe new / changed topics.
    for (final entry in tags.entries) {
      final prev = _appliedTags[entry.key];
      if (prev == entry.value) continue;
      if (prev != null) {
        await FirebaseMessaging.instance.unsubscribeFromTopic(
          _topicFor(entry.key, prev),
        );
      }
      await FirebaseMessaging.instance.subscribeToTopic(
        _topicFor(entry.key, entry.value),
      );
    }
    _appliedTags = tags;
  }

  Future<void> _unsubscribeAllTopics() async {
    await FirebaseMessaging.instance.unsubscribeFromTopic(_allUsersTopic);
    for (final entry in _appliedTags.entries) {
      await FirebaseMessaging.instance.unsubscribeFromTopic(
        _topicFor(entry.key, entry.value),
      );
    }
    _appliedTags = const {};
  }

  /// Keep the monitoring_zone topic in sync with the ProfileProvider.
  void _onProfileChanged() {
    final provider = _profileProvider;
    if (provider == null || _userId == null || provider.isLoading) return;
    final zone = provider.monitoringZone;
    if (zone == _zone) return;
    _zone = zone;
    if (_initialized && _pushEnabled) unawaited(updateZoneSubscriptions());
  }

  /// Re-apply topic subscriptions after the user changes their monitoring zone.
  Future<void> updateZoneSubscriptions() async {
    if (!_pushEnabled || _userId == null || !_tagsKnown) return;
    await _serialized(() async {
      if (_userId == null || !_tagsKnown) return;
      try {
        await _applyTags();
      } on Exception catch (e) {
        developer.log(
          'FCM topic update error: $e',
          name: 'NotificationService',
        );
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
