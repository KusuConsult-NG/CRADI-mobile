import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp();

  runApp(const CrashlyticsTestApp());
}

class CrashlyticsTestApp extends MaterialApp {
  const CrashlyticsTestApp({super.key})
    : super(home: const CrashlyticsTestScreen(), title: 'Crashlytics Test');
}

class CrashlyticsTestScreen extends StatefulWidget {
  const CrashlyticsTestScreen({super.key});

  @override
  State<CrashlyticsTestScreen> createState() => _CrashlyticsTestScreenState();
}

class _CrashlyticsTestScreenState extends State<CrashlyticsTestScreen> {
  final List<String> _testResults = [];

  void _logTest(String message) {
    setState(() {
      _testResults.add(message);
    });
    debugPrint('🧪 $message');
  }

  // Test 1: Non-Fatal Error
  Future<void> _testNonFatalError() async {
    _logTest('Testing non-fatal error...');
    try {
      throw Exception('Test non-fatal error');
    } catch (error, stackTrace) {
      await FirebaseCrashlytics.instance.recordError(
        error,
        stackTrace,
        fatal: false,
        reason: 'Testing non-fatal error reporting',
      );
      _logTest('✅ Non-fatal error logged');
    }
  }

  // Test 2: Custom Log Messages
  Future<void> _testCustomLogs() async {
    _logTest('Testing custom logs...');
    await FirebaseCrashlytics.instance.log('User opened test screen');
    await FirebaseCrashlytics.instance.log('User initiated crash test');
    _logTest('✅ Custom logs recorded');
  }

  // Test 3: Set Custom Keys
  Future<void> _testCustomKeys() async {
    _logTest('Testing custom keys...');
    await FirebaseCrashlytics.instance.setCustomKey('test_mode', true);
    await FirebaseCrashlytics.instance.setCustomKey(
      'test_timestamp',
      DateTime.now().toString(),
    );
    await FirebaseCrashlytics.instance.setCustomKey('test_count', 1);
    _logTest('✅ Custom keys set');
  }

  // Test 4: Set User Identifier
  Future<void> _testUserIdentifier() async {
    _logTest('Testing user identifier...');
    await FirebaseCrashlytics.instance.setUserIdentifier('test_user_12345');
    _logTest('✅ User identifier set');
  }

  // Test 5: Fatal Crash (use with caution!)
  void _testFatalCrash() {
    _logTest('⚠️ WARNING: This will crash the app!');
    _logTest('Crashing in 2 seconds...');

    Future.delayed(const Duration(seconds: 2), () {
      // This will trigger a fatal crash
      FirebaseCrashlytics.instance.crash();
    });
  }

  // Test 6: Async Error
  Future<void> _testAsyncError() async {
    _logTest('Testing async error...');
    try {
      await Future.delayed(const Duration(milliseconds: 100));
      throw StateError('Test async error');
    } catch (error, stackTrace) {
      await FirebaseCrashlytics.instance.recordError(
        error,
        stackTrace,
        fatal: false,
      );
      _logTest('✅ Async error logged');
    }
  }

  // Test 7: Flutter Error
  void _testFlutterError() {
    _logTest('Testing Flutter error handler...');

    // Create a Flutter error
    final details = FlutterErrorDetails(
      exception: Exception('Test Flutter framework error'),
      stack: StackTrace.current,
      library: 'crashlytics_test',
      context: ErrorDescription('Testing Crashlytics integration'),
    );

    // This will be caught by FlutterError.onError
    FlutterError.reportError(details);
    _logTest('✅ Flutter error reported');
  }

  // Run All Non-Destructive Tests
  Future<void> _runAllSafeTests() async {
    _logTest('🚀 Running all safe tests...');
    await _testCustomLogs();
    await _testCustomKeys();
    await _testUserIdentifier();
    await _testNonFatalError();
    await _testAsyncError();
    _testFlutterError();
    _logTest('🎉 All safe tests completed!');
    _logTest('');
    _logTest('Check Firebase Console in 5-10 minutes');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Firebase Crashlytics Test'),
        backgroundColor: Colors.red,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _testResults.length,
              itemBuilder: (context, index) {
                final result = _testResults[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    result,
                    style: TextStyle(
                      color: result.startsWith('✅')
                          ? Colors.green
                          : result.startsWith('⚠️')
                          ? Colors.orange
                          : Colors.black87,
                      fontWeight:
                          result.startsWith('🚀') || result.startsWith('🎉')
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Test Controls',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                // Safe tests
                ElevatedButton(
                  onPressed: _runAllSafeTests,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('🧪 Run All Safe Tests'),
                ),
                const SizedBox(height: 8),

                // Individual tests
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton(
                      onPressed: _testNonFatalError,
                      child: const Text('Non-Fatal Error'),
                    ),
                    ElevatedButton(
                      onPressed: _testCustomLogs,
                      child: const Text('Custom Logs'),
                    ),
                    ElevatedButton(
                      onPressed: _testFlutterError,
                      child: const Text('Flutter Error'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                const Divider(),
                const SizedBox(height: 8),

                // Destructive test
                ElevatedButton(
                  onPressed: _testFatalCrash,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('⚠️ TEST FATAL CRASH (App will close)'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Note: Check Firebase Console 5-10 minutes after tests',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
