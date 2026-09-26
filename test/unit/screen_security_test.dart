import 'package:climate_app/core/utils/screen_security.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A trivial screen that opts into FLAG_SECURE.
class _SecureScreen extends StatefulWidget {
  const _SecureScreen({this.label = 'secure'});
  final String label;

  @override
  State<_SecureScreen> createState() => _SecureScreenState();
}

class _SecureScreenState extends State<_SecureScreen>
    with ScreenSecurityMixin<_SecureScreen> {
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(widget.label)));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> calls;

  setUp(() {
    calls = <String>[];
    ScreenSecurityMixin.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ScreenSecurityMixin.channel, (call) async {
          calls.add(call.method);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ScreenSecurityMixin.channel, null);
    ScreenSecurityMixin.resetForTesting();
  });

  // flutter_test defaults the target platform to Android, which is the only
  // platform where the flag is real.
  testWidgets('adds FLAG_SECURE on mount and clears it on dispose', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _SecureScreen()));
    await tester.pump();
    expect(calls, ['addSecureFlag']);
    expect(ScreenSecurityMixin.activeCount, 1);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    expect(calls, ['addSecureFlag', 'clearSecureFlag']);
    expect(ScreenSecurityMixin.activeCount, 0);
  });

  testWidgets('the flag survives navigating between two secured screens', (
    tester,
  ) async {
    // The incoming route is mounted before the outgoing one is disposed, so a
    // naive clear-on-dispose would drop FLAG_SECURE mid-transition. The
    // reference count must keep it set.
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const _SecureScreen(label: 'first'),
      ),
    );
    await tester.pump();
    expect(calls, ['addSecureFlag']);

    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const _SecureScreen(label: 'second'),
      ),
    );
    await tester.pumpAndSettle();

    // Still exactly one add, no clear: both screens are secured.
    expect(calls, ['addSecureFlag']);
    expect(ScreenSecurityMixin.activeCount, 2);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(calls, ['addSecureFlag']);
    expect(ScreenSecurityMixin.activeCount, 1);
  });

  testWidgets('is a no-op on iOS, where FLAG_SECURE has no equivalent', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      expect(ScreenSecurityMixin.isSupportedPlatform, isFalse);
      await tester.pumpWidget(const MaterialApp(home: _SecureScreen()));
      await tester.pump();
      expect(calls, isEmpty);
      expect(ScreenSecurityMixin.activeCount, 0);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();
      expect(calls, isEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('a missing native handler does not crash the screen', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ScreenSecurityMixin.channel, null);
    await tester.pumpWidget(const MaterialApp(home: _SecureScreen()));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
