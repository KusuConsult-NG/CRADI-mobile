import 'dart:developer' as developer;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

/// FCM Verification Script
///
/// Tests Firebase Cloud Messaging setup to ensure push notifications work
///
/// Run with: flutter run lib/scripts/verify_fcm.dart
/// Or add to main app and call during testing

class FCMVerificationScript {
  static Future<Map<String, dynamic>> verify() async {
    final results = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'tests': <String, dynamic>{},
      'overallStatus': 'pending',
    };

    developer.log('🔔 Starting FCM Verification', name: 'FCMVerification');

    try {
      // Test 1: Firebase Initialization
      developer.log(
        'Test 1: Checking Firebase initialization...',
        name: 'FCMVerification',
      );
      try {
        final app = Firebase.app();
        results['tests']['firebase_initialized'] = {
          'status': 'pass',
          'message': 'Firebase initialized successfully',
          'appName': app.name,
          'options': app.options.projectId,
        };
        developer.log(
          '✅ Firebase initialized: ${app.options.projectId}',
          name: 'FCMVerification',
        );
      } on Object catch (e) {
        results['tests']['firebase_initialized'] = {
          'status': 'fail',
          'error': e.toString(),
        };
        developer.log(
          '❌ Firebase not initialized: $e',
          name: 'FCMVerification',
        );
        results['overallStatus'] = 'fail';
        return results;
      }

      // Test 2: FCM Instance
      developer.log('Test 2: Getting FCM instance...', name: 'FCMVerification');
      final fcm = FirebaseMessaging.instance;
      results['tests']['fcm_instance'] = {
        'status': 'pass',
        'message': 'FCM instance obtained',
      };
      developer.log('✅ FCM instance obtained', name: 'FCMVerification');

      // Test 3: Request Permissions
      developer.log(
        'Test 3: Requesting notification permissions...',
        name: 'FCMVerification',
      );
      try {
        final settings = await fcm.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );

        results['tests']['permissions'] = {
          'status':
              settings.authorizationStatus == AuthorizationStatus.authorized
              ? 'pass'
              : 'warning',
          'authorizationStatus': settings.authorizationStatus.toString(),
          'alert': settings.alert.toString(),
          'badge': settings.badge.toString(),
          'sound': settings.sound.toString(),
        };

        if (settings.authorizationStatus == AuthorizationStatus.authorized) {
          developer.log(
            '✅ Notification permissions granted',
            name: 'FCMVerification',
          );
        } else {
          developer.log(
            '⚠️ Notification permissions: ${settings.authorizationStatus}',
            name: 'FCMVerification',
          );
        }
      } on Object catch (e) {
        results['tests']['permissions'] = {
          'status': 'fail',
          'error': e.toString(),
        };
        developer.log(
          '❌ Permission request failed: $e',
          name: 'FCMVerification',
        );
      }

      // Test 4: Get FCM Token
      developer.log('Test 4: Requesting FCM token...', name: 'FCMVerification');
      try {
        final token = await fcm.getToken();

        if (token != null && token.isNotEmpty) {
          results['tests']['token_generation'] = {
            'status': 'pass',
            'message': 'FCM token generated successfully',
            'tokenLength': token.length,
            'tokenPreview': '${token.substring(0, 20)}...',
          };
          developer.log(
            '✅ FCM Token: ${token.substring(0, 20)}...',
            name: 'FCMVerification',
          );
          developer.log(
            'Full token (copy to test): $token',
            name: 'FCMVerification',
          );
        } else {
          results['tests']['token_generation'] = {
            'status': 'fail',
            'error': 'Token is null or empty',
          };
          developer.log('❌ Failed to get FCM token', name: 'FCMVerification');
        }
      } on Object catch (e) {
        results['tests']['token_generation'] = {
          'status': 'fail',
          'error': e.toString(),
        };
        developer.log('❌ Token generation error: $e', name: 'FCMVerification');
      }

      // Test 5: Set up Token Refresh Listener
      developer.log(
        'Test 5: Setting up token refresh listener...',
        name: 'FCMVerification',
      );
      try {
        fcm.onTokenRefresh.listen((newToken) {
          developer.log(
            '🔄 FCM Token refreshed: ${newToken.substring(0, 20)}...',
            name: 'FCMVerification',
          );
        });

        results['tests']['token_refresh_listener'] = {
          'status': 'pass',
          'message': 'Token refresh listener set up',
        };
        developer.log(
          '✅ Token refresh listener active',
          name: 'FCMVerification',
        );
      } on Object catch (e) {
        results['tests']['token_refresh_listener'] = {
          'status': 'warning',
          'error': e.toString(),
        };
        developer.log(
          '⚠️ Token refresh listener error: $e',
          name: 'FCMVerification',
        );
      }

      // Test 6: Set up Foreground Message Handler
      developer.log(
        'Test 6: Setting up foreground message handler...',
        name: 'FCMVerification',
      );
      try {
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          developer.log(
            '📬 Foreground message received!',
            name: 'FCMVerification',
          );
          developer.log(
            'Title: ${message.notification?.title}',
            name: 'FCMVerification',
          );
          developer.log(
            'Body: ${message.notification?.body}',
            name: 'FCMVerification',
          );
          developer.log('Data: ${message.data}', name: 'FCMVerification');
        });

        results['tests']['foreground_handler'] = {
          'status': 'pass',
          'message': 'Foreground message handler set up',
        };
        developer.log(
          '✅ Foreground message handler active',
          name: 'FCMVerification',
        );
      } on Object catch (e) {
        results['tests']['foreground_handler'] = {
          'status': 'fail',
          'error': e.toString(),
        };
        developer.log(
          '❌ Foreground handler error: $e',
          name: 'FCMVerification',
        );
      }

      // Test 7: Configure Background Handler
      developer.log(
        'Test 7: Checking background handler...',
        name: 'FCMVerification',
      );
      results['tests']['background_handler'] = {
        'status': 'info',
        'message':
            'Background handler must be defined at top level in main.dart',
        'note':
            'Add: FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);',
      };
      developer.log(
        'ℹ️ Ensure background handler is set in main.dart',
        name: 'FCMVerification',
      );

      // Overall Status
      final failures = results['tests'].values
          .where((test) => test['status'] == 'fail')
          .length;
      final warnings = results['tests'].values
          .where((test) => test['status'] == 'warning')
          .length;

      if (failures == 0 && warnings == 0) {
        results['overallStatus'] = 'pass';
        developer.log('✅ FCM Verification PASSED', name: 'FCMVerification');
      } else if (failures > 0) {
        results['overallStatus'] = 'fail';
        developer.log(
          '❌ FCM Verification FAILED ($failures failures, $warnings warnings)',
          name: 'FCMVerification',
        );
      } else {
        results['overallStatus'] = 'warning';
        developer.log(
          '⚠️ FCM Verification PASSED with warnings ($warnings warnings)',
          name: 'FCMVerification',
        );
      }

      developer.log('\n📊 Verification Summary:', name: 'FCMVerification');
      developer.log(
        'Status: ${results['overallStatus']}',
        name: 'FCMVerification',
      );
      developer.log(
        'Tests passed: ${results['tests'].values.where((t) => t['status'] == 'pass').length}',
        name: 'FCMVerification',
      );
      developer.log('Tests failed: $failures', name: 'FCMVerification');
      developer.log('Warnings: $warnings', name: 'FCMVerification');

      return results;
    } on Object catch (e, stackTrace) {
      developer.log(
        '❌ Critical error during verification',
        name: 'FCMVerification',
      );
      developer.log('Error: $e', name: 'FCMVerification');
      developer.log('StackTrace: $stackTrace', name: 'FCMVerification');

      results['overallStatus'] = 'fail';
      results['criticalError'] = {
        'error': e.toString(),
        'stackTrace': stackTrace.toString(),
      };

      return results;
    }
  }

  /// Show verification results in UI
  static Widget buildResultsUI(Map<String, dynamic> results) {
    return Scaffold(
      appBar: AppBar(title: const Text('FCM Verification Results')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStatusCard(results['overallStatus']),
          const SizedBox(height: 16),
          ...results['tests'].entries.map((entry) {
            return _buildTestCard(entry.key, entry.value);
          }),
        ],
      ),
    );
  }

  static Widget _buildStatusCard(String status) {
    Color color;
    IconData icon;
    String message;

    switch (status) {
      case 'pass':
        color = Colors.green;
        icon = Icons.check_circle;
        message = 'All FCM tests passed!';
        break;
      case 'warning':
        color = Colors.orange;
        icon = Icons.warning;
        message = 'FCM tests passed with warnings';
        break;
      case 'fail':
        color = Colors.red;
        icon = Icons.error;
        message = 'FCM tests failed';
        break;
      default:
        color = Colors.grey;
        icon = Icons.info;
        message = 'Running tests...';
    }

    return Card(
      color: color.withValues(alpha: 0.1),
      child: ListTile(
        leading: Icon(icon, color: color, size: 40),
        title: Text(
          message,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ),
    );
  }

  static Widget _buildTestCard(String testName, Map<String, dynamic> testData) {
    Color color;
    IconData icon;

    switch (testData['status']) {
      case 'pass':
        color = Colors.green;
        icon = Icons.check_circle_outline;
        break;
      case 'warning':
        color = Colors.orange;
        icon = Icons.warning_amber;
        break;
      case 'fail':
        color = Colors.red;
        icon = Icons.error_outline;
        break;
      default:
        color = Colors.blue;
        icon = Icons.info_outline;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Icon(icon, color: color),
        title: Text(
          testName.replaceAll('_', ' ').toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(testData['message'] ?? testData['error'] ?? ''),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                testData.toString(),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Example: Run verification and show results
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  final results = await FCMVerificationScript.verify();

  runApp(MaterialApp(home: FCMVerificationScript.buildResultsUI(results)));
}
