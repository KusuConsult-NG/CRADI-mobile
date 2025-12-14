import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:developer' as developer;

class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// Initialize notifications
  Future<void> initialize() async {
    // Request permission
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      developer.log('User granted permission', name: 'NotificationService');
    } else if (settings.authorizationStatus ==
        AuthorizationStatus.provisional) {
      developer.log(
        'User granted provisional permission',
        name: 'NotificationService',
      );
    } else {
      developer.log(
        'User declined or has not accepted permission',
        name: 'NotificationService',
      );
    }

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      developer.log(
        'Got a message whilst in the foreground!',
        name: 'NotificationService',
      );
      developer.log(
        'Message data: ${message.data}',
        name: 'NotificationService',
      );

      if (message.notification != null) {
        developer.log(
          'Message also contained a notification: ${message.notification}',
          name: 'NotificationService',
        );
        // TODO: Show local notification using flutter_local_notifications if needed
      }
    });
  }

  /// Get FCM Token
  Future<String?> getToken() async {
    try {
      final token = await _messaging.getToken();
      developer.log('FCM Token: $token', name: 'NotificationService');
      return token;
    } on Exception catch (e) {
      developer.log('Error getting FCM token: $e', name: 'NotificationService');
      return null;
    }
  }
}
