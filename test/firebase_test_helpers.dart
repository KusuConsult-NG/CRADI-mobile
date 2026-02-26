// test/firebase_test_helpers.dart
//
// Shared Firebase mock initialization for widget and unit tests.
// Usage:
//   setupFirebaseAuthMocks();
//   setUpAll(() async { await Firebase.initializeApp(); });

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Call at the top of a test file (outside any group) to mock Firebase.
void setupFirebaseAuthMocks() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    _mockFirebaseCore();
    _mockFirebaseAuth();
    _mockFirestore();
  });
}

void _mockFirebaseCore() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/firebase_core'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'Firebase#initializeCore') {
            return [
              {
                'name': '[DEFAULT]',
                'options': {
                  'apiKey': 'test-api-key',
                  'appId': '1:123456789:android:test',
                  'messagingSenderId': '123456789',
                  'projectId': 'ewer-8f788-test',
                },
                'pluginConstants': {},
              },
            ];
          }
          if (methodCall.method == 'Firebase#initializeApp') {
            return {
              'name': '[DEFAULT]',
              'options': {
                'apiKey': 'test-api-key',
                'appId': '1:123456789:android:test',
                'messagingSenderId': '123456789',
                'projectId': 'ewer-8f788-test',
              },
              'pluginConstants': {},
            };
          }
          return null;
        },
      );
}

void _mockFirebaseAuth() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/firebase_auth'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'Auth#registerAuthStateListener') {
            return null;
          }
          if (methodCall.method == 'Auth#registerIdTokenListener') return null;
          return null;
        },
      );
}

void _mockFirestore() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/cloud_firestore'),
        (MethodCall methodCall) async => null,
      );
}
