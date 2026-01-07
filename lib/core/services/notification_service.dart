import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:climate_app/features/profile/providers/profile_provider.dart';
import 'package:climate_app/core/router/app_router.dart';
import 'dart:developer' as developer;

/// Handle background messages
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  developer.log('Background message: ${message.messageId}');
}

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

  static const String _notificationsBoxName = 'notifications_history';
  Box<Map>? _notificationsBox;

  /// Get current FCM token
  String? get fcmToken => _fcmToken;

  /// Initialize FCM, Local Notifications, and Hive
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Initialize Hive box for notifications
      _notificationsBox = await Hive.openBox<Map>(_notificationsBoxName);

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
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Get FCM token
      _fcmToken = await _fcm.getToken();
      if (_fcmToken != null) {
        developer.log('FCM Token: $_fcmToken', name: 'NotificationService');
        // Save token to Appwrite user profile
        await ProfileProvider().updateFCMToken(_fcmToken!);
      }

      // Listen for token refresh
      _fcm.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        developer.log(
          'FCM Token refreshed: $newToken',
          name: 'NotificationService',
        );
        ProfileProvider().updateFCMToken(newToken);
      });

      // Handle background messages
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);

      // Handle notification taps when app is in background
      FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

      _initialized = true;
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
  }

  /// Clear all notifications
  Future<void> clearAll() async {
    if (_notificationsBox == null) return;
    await _notificationsBox!.clear();
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
    if (response.payload != null) {
      // Assuming payload is a JSON string with type and id
      _handleNotificationNavigation({'type': 'alert'}); // Default for now
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
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload,
    );
  }

  /// Handle notification navigation
  void _handleNotificationNavigation(Map<String, dynamic> data) {
    final type = data['type'] ?? 'alert';

    switch (type) {
      case 'alert':
        appRouter.push('/alerts');
        break;
      case 'message':
        appRouter.push('/chat');
        break;
      case 'report':
        appRouter.push('/reports-status');
        break;
      default:
        appRouter.push('/');
    }
    developer.log('Handling notification: $data', name: 'NotificationService');
  }

  /// Subscribe to a topic
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _fcm.subscribeToTopic(topic);
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

  /// Get initial message if app was opened from terminated state
  Future<RemoteMessage?> getInitialMessage() async {
    return await _fcm.getInitialMessage();
  }
}
