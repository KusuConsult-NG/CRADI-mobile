import 'package:climate_app/features/knowledge_base/guide_bookmarks.dart';
import 'package:climate_app/features/knowledge_base/widgets/guide_bookmark_button.dart';
import 'package:climate_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Defect 2: the bookmark icons on the knowledge base list were painted
/// unconditionally and did nothing. They are a real control now.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GuideBookmarks().resetForTesting();
  });

  Widget host(Map<String, dynamic> guide) => MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Center(child: GuideBookmarkButton(guide: guide)),
    ),
  );

  testWidgets('shows the real state and toggles it', (tester) async {
    await tester.pumpWidget(host({'id': 'g1', 'title': 'Flood Safety'}));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    await tester.tap(find.byIcon(Icons.bookmark_border));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    expect(GuideBookmarks().contains('g1'), isTrue);

    await tester.tap(find.byIcon(Icons.bookmark));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    expect(GuideBookmarks().contains('g1'), isFalse);
  });

  testWidgets('reflects a bookmark made elsewhere without a rebuild', (
    tester,
  ) async {
    await tester.pumpWidget(host({'id': 'g1', 'title': 'Flood Safety'}));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);

    // Another screen (e.g. the guide detail) saves the same guide.
    await GuideBookmarks().toggle('g1');
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
  });

  testWidgets('a guide that cannot be identified shows no control', (
    tester,
  ) async {
    await tester.pumpWidget(host(const {}));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bookmark_border), findsNothing);
    expect(find.byIcon(Icons.bookmark), findsNothing);
  });

  testWidgets('the tap target is at least 40pt', (tester) async {
    await tester.pumpWidget(host({'id': 'g1'}));
    await tester.pumpAndSettle();
    final size = tester.getSize(find.byType(InkWell));
    expect(size.width, greaterThanOrEqualTo(40));
    expect(size.height, greaterThanOrEqualTo(40));
  });
}
