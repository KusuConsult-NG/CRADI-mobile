import 'package:flutter_test/flutter_test.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart';
import 'package:flutter/services.dart';

/// Unit tests for ReportingProvider
///
/// Tests state management logic
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Mock Firebase before any tests run
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/firebase_core'),
          (MethodCall methodCall) async {
            if (methodCall.method == 'Firebase#initializeCore') {
              return [
                {
                  'name': '[DEFAULT]',
                  'options': {
                    'apiKey': 'test',
                    'appId': 'test',
                    'messagingSenderId': 'test',
                    'projectId': 'test',
                  },
                  'pluginConstants': {},
                },
              ];
            }
            return null;
          },
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/firebase_auth'),
          (MethodCall methodCall) async => null,
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/cloud_firestore'),
          (MethodCall methodCall) async => null,
        );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/firebase_storage'),
          (MethodCall methodCall) async => null,
        );
  });

  group('Reporting Provider', () {
    test('should be able to instantiate', () {
      final provider = ReportingProvider();
      expect(provider, isNotNull);
    });

    test('should initialize with default values', () {
      final provider = ReportingProvider();
      expect(provider.hazardType, isNull);
      expect(provider.severity, isNull);
      expect(provider.isLoading, isFalse);
    });

    test('should update hazard type', () {
      final provider = ReportingProvider();
      provider.setHazardType('flood');
      expect(provider.hazardType, equals('flood'));
    });

    test('should update severity level', () {
      final provider = ReportingProvider();
      provider.setSeverity('high');
      expect(provider.severity, equals('high'));
    });

    test('should reset all fields', () {
      final provider = ReportingProvider();
      provider.setHazardType('flood');
      provider.setSeverity('high');

      provider.reset();

      expect(provider.hazardType, isNull);
      expect(provider.severity, isNull);
    });
  });
}
