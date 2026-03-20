import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:climate_app/features/profile/providers/profile_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:climate_app/core/services/hive_encryption_service.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';
import 'dart:developer' as developer;

/// Service for handling Firebase Cloud Messaging (FCM) push notifications
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  String? _fcmToken;
  ProfileProvider? _profileProvider;

  /// Set this from main.dart so notification taps can navigate via GoRouter.
  GoRouter? router;

  /// Tracks currently subscribed topics so we can unsubscribe on zone change.
  final Set<String> _subscribedTopics = {};

  static const String _notificationsBoxName = 'notifications_history';
  Box<Map>? _notificationsBox;

  /// ValueNotifier for unread notification count
  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  /// Get current FCM token
  String? get fcmToken => _fcmToken;

  /// Initialize FCM, Local Notifications, and Hive
  ///
  /// [profileProvider] should be the app-level Provider instance so that
  /// the FCM token is saved to the correct user profile in Firestore.
  Future<void> initialize({ProfileProvider? profileProvider}) async {
    if (_initialized) return;
    _profileProvider = profileProvider;

    try {
      // Get encryption cipher for secure notification storage
      final cipher = await HiveEncryptionService().getCipher();

      // Initialize Hive box for notifications with encryption
      _notificationsBox = await Hive.openBox<Map>(
        _notificationsBoxName,
        encryptionCipher: cipher,
      );

      // Request permission for iOS
      final NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        developer.log(
          'User declined notification permissions',
          name: 'NotificationService',
        );
        return;
      }

      // Initialize local notifications
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings iosSettings =
          DarwinInitializationSettings(
            requestAlertPermission: true,
            requestBadgePermission: true,
            requestSoundPermission: true,
          );

      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _localNotifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Get FCM token
      _fcmToken = await _fcm.getToken();
      if (_fcmToken != null) {
        developer.log('FCM Token: $_fcmToken', name: 'NotificationService');
        // Save token via the app-level ProfileProvider
        if (_profileProvider != null) {
          await _profileProvider!.updateFCMToken(_fcmToken!);
        } else {
          developer.log(
            'Warning: no ProfileProvider — FCM token not persisted',
            name: 'NotificationService',
          );
        }
      }

      // Listen for token refresh
      _fcm.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        developer.log(
          'FCM Token refreshed: $newToken',
          name: 'NotificationService',
        );
        _profileProvider?.updateFCMToken(newToken);
      });

      // Background handler is already registered in main.dart — do NOT
      // register a second one here (Firebase only allows one handler).

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);

      // Handle notification taps when app is in background
      FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

      _initialized = true;
      _updateUnreadCount();

      // Subscribe to zone-based topics using monitoring zone
      await _subscribeToZoneTopics();

      developer.log(
        'FCM initialized successfully',
        name: 'NotificationService',
      );
    } on Exception catch (e) {
      developer.log(
        'FCM initialization error: $e',
        name: 'NotificationService',
      );
    }
  }

  /// Handle foreground messages
  Future<void> _onForegroundMessage(RemoteMessage message) async {
    developer.log(
      'Foreground message: ${message.notification?.title}',
      name: 'NotificationService',
    );

    // Save to history
    await _saveNotification(
      title: message.notification?.title ?? 'New Alert',
      body: message.notification?.body ?? '',
      data: message.data,
    );

    // Show local notification when app is in foreground
    if (message.notification != null) {
      await showLocalNotification(
        title: message.notification!.title ?? 'New Alert',
        body: message.notification!.body ?? '',
        payload: message.data.toString(),
      );
    }
  }

  /// Save notification to local history
  Future<void> _saveNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    if (_notificationsBox == null) return;

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final notification = {
      'id': id,
      'title': title,
      'body': body,
      'data': data ?? {},
      'timestamp': DateTime.now().toIso8601String(),
      'isRead': false,
      'type': data?['type'] ?? 'system',
    };

    await _notificationsBox!.put(id, notification);
    _updateUnreadCount();
    await _evictOldNotifications();
    developer.log('Notification saved: $id', name: 'NotificationService');
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
      developer.log(
        'Notification marked as read: $id',
        name: 'NotificationService',
      );
    }
  }

  /// Mark all notifications as read
  Future<void> markAllAsRead() async {
    if (_notificationsBox == null) return;

    final keys = _notificationsBox!.keys;
    for (var key in keys) {
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

    // Delete entries older than 30 days
    final staleKeys = _notificationsBox!.keys.where((key) {
      final n = _notificationsBox!.get(key);
      if (n == null) return true;
      final ts = DateTime.tryParse(n['timestamp']?.toString() ?? '');
      return ts != null && ts.isBefore(cutoff);
    }).toList();

    if (staleKeys.isNotEmpty) {
      await _notificationsBox!.deleteAll(staleKeys);
      developer.log(
        'Evicted ${staleKeys.length} notifications older than 30 days',
        name: 'NotificationService',
      );
    }

    // Trim to max 200 — delete oldest first
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
      developer.log(
        'Trimmed ${toDelete.length} notifications to stay within $maxEntries limit',
        name: 'NotificationService',
      );
    }
  }

  /// Handle notification tap when app is in background
  void _onMessageOpenedApp(RemoteMessage message) {
    developer.log(
      'Notification opened: ${message.notification?.title}',
      name: 'NotificationService',
    );
    // Navigate to appropriate screen based on message data
    _handleNotificationNavigation(message.data);
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    developer.log(
      'Notification tapped: ${response.payload}',
      name: 'NotificationService',
    );
    if (response.payload != null && response.payload!.isNotEmpty) {
      try {
        final data = jsonDecode(response.payload!) as Map<String, dynamic>;
        _handleNotificationNavigation(data);
      } on FormatException {
        // Payload is not JSON — treat as simple type
        _handleNotificationNavigation({'type': 'alert'});
      }
    }
  }

  /// Show local notification
  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'alerts_channel',
          'Hazard Alerts',
          channelDescription: 'Notifications for climate hazard alerts',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }

  /// Handle notification navigation using the injected [router].
  void _handleNotificationNavigation(Map<String, dynamic> data) {
    final type = data['type'] ?? 'alert';
    final id = data['id'] as String? ?? data['reportId'] as String? ?? '';

    developer.log(
      'Notification nav: type=$type id=$id',
      name: 'NotificationService',
    );

    if (router == null) {
      developer.log(
        'GoRouter not set — cannot navigate',
        name: 'NotificationService',
      );
      return;
    }

    switch (type) {
      case 'report':
      case 'verification':
        if (id.isNotEmpty) {
          router!.go('/report/$id');
        } else {
          router!.go('/reports-status');
        }
        break;
      case 'alert':
        if (id.isNotEmpty) {
          router!.go('/alert/$id');
        } else {
          router!.go('/alerts');
        }
        break;
      case 'chat':
        router!.go('/chat');
        break;
      default:
        router!.go('/notifications');
    }
  }

  /// Subscribe to FCM topics based on the user's monitoring zone.
  ///
  /// Call this after initialization or when the user changes their zone.
  Future<void> _subscribeToZoneTopics() async {
    final zone = _profileProvider?.monitoringZone;
    if (zone == null || zone.isEmpty) return;

    // Always subscribe to the "all_alerts" global topic
    await subscribeToTopic('all_alerts');

    // Sanitize topic names: FCM allows [a-zA-Z0-9-_.~%]
    String sanitize(String s) =>
        s.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_').toLowerCase();

    if (zone.contains(', ')) {
      // LGA format: "Makurdi, Benue"
      final parts = zone.split(', ');
      final lga = sanitize(parts[0]);
      final state = sanitize(parts[1]);
      await subscribeToTopic('state_$state');
      await subscribeToTopic('lga_$lga');
    } else if (zone.endsWith(' State')) {
      // State format: "Benue State"
      final state = sanitize(zone.replaceAll(' State', ''));
      await subscribeToTopic('state_$state');
    }
  }

  /// Re-subscribe after the user changes their monitoring zone.
  Future<void> updateZoneSubscriptions() async {
    // Unsubscribe from all previously subscribed topics
    for (final topic in _subscribedTopics.toList()) {
      await unsubscribeFromTopic(topic);
    }
    _subscribedTopics.clear();
    await _subscribeToZoneTopics();
  }

  /// Subscribe to a topic
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _fcm.subscribeToTopic(topic);
      _subscribedTopics.add(topic);
      developer.log('Subscribed to topic: $topic', name: 'NotificationService');
    } on Exception catch (e) {
      developer.log(
        'Error subscribing to topic $topic: $e',
        name: 'NotificationService',
      );
    }
  }

  /// Unsubscribe from a topic
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _fcm.unsubscribeFromTopic(topic);
      developer.log(
        'Unsubscribed from topic: $topic',
        name: 'NotificationService',
      );
    } on Exception catch (e) {
      developer.log(
        'Error unsubscribing from topic $topic: $e',
        name: 'NotificationService',
      );
    }
  }

  /// Update unread count and app badge
  Future<void> _updateUnreadCount() async {
    if (_notificationsBox == null) return;

    final count = _notificationsBox!.values
        .where((n) => n['isRead'] == false)
        .length;

    unreadCount.value = count;

    try {
      // Badge clearing is handled by standard iOS/Android mechanisms
      // or requires a specific badge package which is not currently added.
      // Leaving this empty for now to avoid build errors.
    } on Exception catch (e) {
      developer.log('Error setting badge: $e', name: 'NotificationService');
    }
  }

  /// Get initial message if app was opened from terminated state
  Future<RemoteMessage?> getInitialMessage() async {
    return await _fcm.getInitialMessage();
  }
}
