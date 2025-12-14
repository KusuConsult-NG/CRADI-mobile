import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:climate_app/features/auth/screens/otp_screen.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';

/// Widget tests for OTP Screen
///
/// Tests OTP verification UI renders correctly
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Mock Firebase
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
  });

  group('OtpScreen Widget Tests', () {
    Widget createOtpScreen() {
      return ChangeNotifierProvider(
        create: (_) => AuthProvider(),
        child: const MaterialApp(home: OtpScreen()),
      );
    }

    testWidgets('should render OTP screen', (WidgetTester tester) async {
      await tester.pumpWidget(createOtpScreen());
      expect(find.byType(OtpScreen), findsOneWidget);
    });

    testWidgets('should display scaffold', (WidgetTester tester) async {
      await tester.pumpWidget(createOtpScreen());
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('should display app bar', (WidgetTester tester) async {
      await tester.pumpWidget(createOtpScreen());
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('should have input fields', (WidgetTester tester) async {
      await tester.pumpWidget(createOtpScreen());
      expect(find.byType(TextFormField), findsWidgets);
    });

    testWidgets('should have verify button', (WidgetTester tester) async {
      await tester.pumpWidget(createOtpScreen());
      expect(find.byType(ElevatedButton), findsWidgets);
    });

    testWidgets('should display text widgets', (WidgetTester tester) async {
      await tester.pumpWidget(createOtpScreen());
      expect(find.byType(Text), findsWidgets);
    });

    testWidgets('should have column layout', (WidgetTester tester) async {
      await tester.pumpWidget(createOtpScreen());
      expect(find.byType(Column), findsWidgets);
    });

    testWidgets('should have row layout', (WidgetTester tester) async {
      await tester.pumpWidget(createOtpScreen());
      expect(find.byType(Row), findsWidgets);
    });

    testWidgets('should display icons', (WidgetTester tester) async {
      await tester.pumpWidget(createOtpScreen());
      expect(find.byType(Icon), findsWidgets);
    });

    testWidgets('should render without errors', (WidgetTester tester) async {
      await tester.pumpWidget(createOtpScreen());
      await tester.pump();
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });
}
