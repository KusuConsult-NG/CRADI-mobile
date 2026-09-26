import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/core/services/hive_encryption_service.dart';
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

        final granted = await OneSignal.Notifications.requestPermission(true);
        if (!granted) {
          developer.log(
            'User declined notification permissions',
            name: 'NotificationService',
          );
        }
      }

      _initialized = true;
      _updateUnreadCount();

      // A user signed in while we were initializing — identify them now.
      if (_userId != null) await _syncSignedInUser();

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
        title: n.title ?? 'New Alert',
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
    unawaited(
      _saveNotification(
        title: n.title ?? 'New Alert',
        body: n.body ?? '',
        data: data,
        isRead: true,
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
  /// Backend types: verification_request, report_status, validated_alert,
  /// admin_alert, escalation_auto (ids arrive as `report_id` / `alert_id`).
  /// Older camelCase keys and types are still understood.
  @visibleForTesting
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
      case 'escalation_auto':
      case 'report':
      case 'verification':
        return reportId.isNotEmpty ? '/report/$reportId' : '/reports-status';
      case 'validated_alert':
      case 'admin_alert':
      case 'alert':
        return alertId.isNotEmpty ? '/alert/$alertId' : '/alerts';
      case 'chat':
        return '/chat';
      default:
        return '/notifications';
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

  /// Call after a user signs in (from AuthProvider): identifies the device
  /// with the Supabase user id and sets targeting tags.
  Future<void> onUserSignedIn({
    required String userId,
    String? role,
    String? lga,
    String? state,
    String? ward,
    String? monitoringZone,
  }) async {
    _userId = userId;
    _baseTags = tagsFor(role: role, lga: lga, state: state, ward: ward);
    final profileZone = _profileProvider?.monitoringZone;
    _zone = (profileZone != null && profileZone.isNotEmpty)
        ? profileZone
        : monitoringZone;
    // If not yet initialized, initialize() will sync once it finishes.
    if (!_initialized) return;
    await _syncSignedInUser();
  }

  /// Call after the user signs out: detaches the device from the user so it
  /// stops receiving their targeted notifications.
  Future<void> onUserSignedOut() async {
    final wasSignedIn = _userId != null;
    _userId = null;
    _baseTags = const {};
    _zone = null;
    _appliedTags = const {};
    if (!_pushEnabled || !wasSignedIn) return;
    try {
      await OneSignal.logout();
    } on Exception catch (e) {
      developer.log('OneSignal logout error: $e', name: 'NotificationService');
    }
  }

  Future<void> _syncSignedInUser() async {
    final userId = _userId;
    if (!_pushEnabled || userId == null) return;
    try {
      await OneSignal.login(userId);
      await _applyTags();
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
    if (!_pushEnabled || _userId == null) return;
    try {
      await _applyTags();
    } on Exception catch (e) {
      developer.log('OneSignal tag error: $e', name: 'NotificationService');
    }
  }

  // ─────────────────────────── Local history ───────────────────────────────

  Future<void> _saveNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
    bool isRead = false,
  }) async {
    if (_notificationsBox == null) return;

    final id = DateTime.now().millisecondsSinceEpoch.toString();
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
