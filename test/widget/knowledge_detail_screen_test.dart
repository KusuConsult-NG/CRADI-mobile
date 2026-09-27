import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:climate_app/features/knowledge_base/guide_bookmarks.dart';
import 'package:climate_app/features/knowledge_base/screens/knowledge_detail_screen.dart';
import 'package:climate_app/features/knowledge_base/knowledge_categories.dart';
import 'package:climate_app/features/knowledge_base/providers/knowledge_provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:climate_app/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'knowledge_detail_screen_test.mocks.dart';

@GenerateMocks([KnowledgeProvider])
void main() {
  late MockKnowledgeProvider mockKnowledgeProvider;

  final testGuide = {
    'id': 'guide-001',
    'title': 'Flood Safety Guide',
    'category': 'Safety',
    'description': 'How to stay safe during floods.',
    'content':
        '**Preparation**\n\nAlways have an emergency kit ready.\n\nKnow your evacuation routes.',
    'lastUpdated': 'March 2026',
    'imageUrl': '',
  };

  final relatedGuide = {
    'id': 'guide-002',
    'title': 'Drought Preparedness',
    'category': 'Safety',
    'description': 'Preparing for drought conditions.',
    'content': 'Store water and conserve resources.',
  };

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // GuideBookmarks is a process-wide singleton; drop what an earlier
    // test saved so each one starts with nothing bookmarked.
    GuideBookmarks().resetForTesting();
    mockKnowledgeProvider = MockKnowledgeProvider();
    when(mockKnowledgeProvider.guides).thenReturn([testGuide, relatedGuide]);
    when(mockKnowledgeProvider.hasListeners).thenReturn(false);
  });

  Widget buildScreen({Map<String, dynamic>? guide}) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (ctx, state) =>
              KnowledgeDetailScreen(guide: guide ?? testGuide),
        ),
        GoRoute(
          path: '/knowledge-base/detail',
          builder: (ctx, state) => const SizedBox(),
        ),
      ],
    );

    return ChangeNotifierProvider<KnowledgeProvider>.value(
      value: mockKnowledgeProvider,
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
  }

  group('KnowledgeDetailScreen Widget Tests', () {
    testWidgets('should display guide title', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(find.text('Flood Safety Guide'), findsOneWidget);
    });

    testWidgets('should display app bar with Guide Detail title', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(find.text('Guide Detail'), findsOneWidget);
    });

    testWidgets('should display category badge', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(find.text('Safety'), findsOneWidget);
    });

    testWidgets('should display last updated info', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(find.text('Updated March 2026'), findsOneWidget);
    });

    testWidgets('formats updatedAt supplied by the provider', (tester) async {
      final updated = DateTime.utc(2026, 2, 14, 12);
      await tester.pumpWidget(
        buildScreen(
          guide: {
            ...testGuide,
            'lastUpdated': null,
            'updatedAt': updated.toIso8601String(),
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Updated ${DateFormat('d MMM yyyy').format(updated.toLocal())}',
        ),
        findsOneWidget,
      );
    });

    testWidgets('should display reading time estimated from the content', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      // The short test content reads in under a minute.
      expect(find.text('1 min read'), findsOneWidget);
      expect(find.text('5 min read'), findsNothing);
    });

    testWidgets('should display share button', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.share_outlined), findsOneWidget);
    });

    testWidgets(
      'should display bookmark button (outline when not bookmarked)',
      (tester) async {
        await tester.pumpWidget(buildScreen());
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
      },
    );

    testWidgets('should display TTS button', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget);
    });

    testWidgets('should toggle bookmark icon on tap', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      // Initially shows outline bookmark
      expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
      expect(find.byIcon(Icons.bookmark), findsNothing);

      // Tap the bookmark button
      await tester.tap(find.byIcon(Icons.bookmark_border));
      await tester.pumpAndSettle();

      // Should now show filled bookmark
      expect(find.byIcon(Icons.bookmark), findsOneWidget);

      // Should show SnackBar feedback
      expect(find.text('Guide bookmarked'), findsOneWidget);
    });

    testWidgets('should un-bookmark on second tap', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      // Tap to bookmark
      await tester.tap(find.byIcon(Icons.bookmark_border));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.bookmark), findsOneWidget);

      // Dismiss first SnackBar
      ScaffoldMessenger.of(
        tester.element(find.byType(Scaffold).first),
      ).clearSnackBars();
      await tester.pumpAndSettle();

      // Tap to un-bookmark
      await tester.tap(find.byIcon(Icons.bookmark));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
      expect(find.text('Bookmark removed'), findsOneWidget);
    });

    testWidgets('should render dynamic content when content is provided', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      // Content sections should be rendered (bold headers + paragraphs)
      expect(find.text('Preparation'), findsOneWidget);
      expect(find.text('Always have an emergency kit ready.'), findsOneWidget);
    });

    testWidgets(
      'should show "coming soon" fallback when content and description are empty',
      (tester) async {
        final guideNoContent = {
          ...testGuide,
          'content': null,
          'description': null,
        };
        await tester.pumpWidget(buildScreen(guide: guideNoContent));
        await tester.pumpAndSettle();
        expect(find.text('Detailed content coming soon.'), findsOneWidget);
      },
    );

    testWidgets('should fall back to the description when content is empty', (
      tester,
    ) async {
      final guideNoContent = {...testGuide, 'content': ''};
      await tester.pumpWidget(buildScreen(guide: guideNoContent));
      await tester.pumpAndSettle();
      expect(find.text('Detailed content coming soon.'), findsNothing);
      expect(find.text('How to stay safe during floods.'), findsWidgets);
    });

    testWidgets('should display Related Topics section', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      // Scroll down to find Related Topics
      await tester.scrollUntilVisible(find.text('Related Topics'), 200);
      expect(find.text('Related Topics'), findsOneWidget);
    });

    testWidgets('should display related guide from same category', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Drought Preparedness'), 200);
      expect(find.text('Drought Preparedness'), findsOneWidget);
    });

    testWidgets('should display back button', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_back_ios_new), findsOneWidget);
    });

    testWidgets('should show the shared Safety category icon', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(find.byIcon(knowledgeCategoryFor('Safety')!.icon), findsWidgets);
    });
  });
}
