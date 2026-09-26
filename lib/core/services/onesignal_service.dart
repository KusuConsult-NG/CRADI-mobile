import 'dart:developer' as developer;
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:go_router/go_router.dart';

/// Central OneSignal Push Notification Service
///
/// Replaces or runs in tandem with FCM for push notifications.
/// Automatically handles user tagging (state, LGA, ward, user role)
/// allowing zero-effort geo-targeted emergency alerts.
class OneSignalService {
  static final OneSignalService _instance = OneSignalService._internal();
  factory OneSignalService() => _instance;
  OneSignalService._internal();

  bool _initialized = false;
  GoRouter? router;

  /// Initialize OneSignal with [appId].
  Future<void> initialize({required String appId}) async {
    if (_initialized) return;

    try {
      // 1. Initialize SDK
      OneSignal.initialize(appId);

      // 2. Request push permission
      await OneSignal.Notifications.requestPermission(true);

      // 3. Setup notification click listener
      OneSignal.Notifications.addClickListener((event) {
        final data = event.notification.additionalData;
        developer.log(
          'OneSignal notification clicked: $data',
          name: 'OneSignalService',
        );
        _handleNotificationNavigation(data);
      });

      // 4. Setup foreground notification listener
      OneSignal.Notifications.addForegroundWillDisplayListener((event) {
        developer.log(
          'OneSignal foreground notification: ${event.notification.title}',
          name: 'OneSignalService',
        );
        // By default display the notification
        event.preventDefault();
        event.notification.display();
      });

      _initialized = true;
      developer.log(
        'OneSignal initialized successfully',
        name: 'OneSignalService',
      );
    } on Exception catch (e) {
      developer.log(
        'OneSignal initialization error: $e',
        name: 'OneSignalService',
      );
    }
  }

  /// Get the unique OneSignal Subscription ID (Player ID)
  String? get subscriptionId => OneSignal.User.pushSubscription.id;

  /// Tag user with their monitoring zone & role for targeted alerts.
  /// Example: { "state": "Benue", "lga": "Makurdi", "role": "ewm" }
  Future<void> setUserTags({
    required String? state,
    required String? lga,
    required String? ward,
    required String? role,
  }) async {
    try {
      final tags = <String, String>{};
      if (state != null && state.isNotEmpty) {
        tags['state'] = state.trim().toLowerCase();
      }
      if (lga != null && lga.isNotEmpty) {
        tags['lga'] = lga.trim().toLowerCase();
      }
      if (ward != null && ward.isNotEmpty) {
        tags['ward'] = ward.trim().toLowerCase();
      }
      if (role != null && role.isNotEmpty) {
        tags['role'] = role.trim().toLowerCase();
      }

      if (tags.isNotEmpty) {
        await OneSignal.User.addTags(tags);
        developer.log(
          'OneSignal tags updated: $tags',
          name: 'OneSignalService',
        );
      }
    } on Exception catch (e) {
      developer.log(
        'Error setting OneSignal tags: $e',
        name: 'OneSignalService',
      );
    }
  }

  /// Login user ID to link with OneSignal analytics & targeted sends
  Future<void> login(String externalUserId) async {
    try {
      await OneSignal.login(externalUserId);
      developer.log(
        'OneSignal logged in: $externalUserId',
        name: 'OneSignalService',
      );
    } on Exception catch (e) {
      developer.log('OneSignal login error: $e', name: 'OneSignalService');
    }
  }

  /// Logout user
  Future<void> logout() async {
    try {
      await OneSignal.logout();
      developer.log('OneSignal logged out', name: 'OneSignalService');
    } on Exception catch (e) {
      developer.log('OneSignal logout error: $e', name: 'OneSignalService');
    }
  }

  /// Handle navigation on notification tap
  void _handleNotificationNavigation(Map<String, dynamic>? data) {
    if (data == null || router == null) return;

    final type = data['type'] ?? 'alert';
    final id = data['id'] as String? ?? data['reportId'] as String? ?? '';

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
}
