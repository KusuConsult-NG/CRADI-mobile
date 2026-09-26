import 'dart:convert';

import 'package:climate_app/core/l10n/l10n.dart';
import 'package:climate_app/core/services/news_service.dart';
import 'package:climate_app/core/services/supabase_mapping.dart';
import 'package:climate_app/features/knowledge_base/knowledge_categories.dart';
import 'package:climate_app/features/knowledge_base/providers/knowledge_provider.dart';
import 'package:climate_app/features/knowledge_base/providers/news_provider.dart';
import 'package:climate_app/features/knowledge_base/widgets/guide_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Built-in content (guides, fallback news) now comes from the database, with
/// a device cache for offline use; nothing is bundled or invented.
void main() {
  Map<String, dynamic> row(String id, String hazard, {String? imageUrl}) => {
    r'$id': id,
    'title': 'Guide $id',
    'content': 'Body $id',
    'category': knowledgeCategoryFor(hazard)?.label,
    'hazardType': hazard,
    'imageUrl': imageUrl,
    'updatedAt': '2026-01-01T00:00:00Z',
  };

  group('KnowledgeProvider', () {
    late List<Map<String, dynamic>>? cache;
    late int cacheWrites;

    KnowledgeProvider provider(GuideRowsFetcher fetch) => KnowledgeProvider(
      fetchRows: fetch,
      writeCache: (guides) async {
        cacheWrites++;
        cache = guides.map((g) => Map<String, dynamic>.of(g)).toList();
      },
      readCache: () => cache,
    );

    setUp(() {
      cache = null;
      cacheWrites = 0;
    });

    test('online: rows are shown and the unfiltered list is cached', () async {
      final p = provider(
        (_) async => [
          row('1', 'flood', imageUrl: 'https://cdn.example.org/a.jpg'),
          row('2', 'fire'),
        ],
      );
      await p.fetchGuides();
      expect(p.error, isNull);
      expect(p.guides.map((g) => g['id']), ['1', '2']);
      expect(p.guides.every((g) => g['isOffline'] == false), isTrue);
      expect(cacheWrites, 1);
      expect(cache, hasLength(2));
    });

    test('no stock image is substituted for a guide without one', () async {
      final p = provider((_) async => [row('1', 'flood', imageUrl: '')]);
      await p.fetchGuides();
      final guide = p.guides.single;
      expect(guide['imageUrl'], isNull);
      expect(guideImageUrl(guide), isNull);
      expect(
        guideImageUrl({'imageUrl': 'https://cdn.example.org/x.png'}),
        'https://cdn.example.org/x.png',
      );
    });

    test('an empty table is an empty list, and is cached', () async {
      cache = [row('old', 'flood')];
      final p = provider((_) async => []);
      await p.fetchGuides();
      expect(p.error, isNull);
      expect(p.guides, isEmpty);
      // Guides an admin deleted must also disappear offline.
      expect(cache, isEmpty);
    });

    test('category lists are not cached', () async {
      String? requested;
      final p = provider((hazard) async {
        requested = hazard;
        return [row('1', 'flood')];
      });
      await p.fetchGuides(category: 'Flood');
      expect(requested, 'flood');
      expect(p.guidesFor('Flood'), hasLength(1));
      expect(cacheWrites, 0);
    });

    test('fetch error: the cache is served, marked offline', () async {
      cache = [
        {...row('1', 'flood'), 'id': '1', 'isOffline': false},
        {...row('2', 'fire'), 'id': '2', 'isOffline': false},
      ];
      final p = provider((_) async => throw Exception('offline'));
      await p.fetchGuides();
      expect(p.error, isNull);
      expect(p.guides.map((g) => g['id']), ['1', '2']);
      expect(p.guides.every((g) => g['isOffline'] == true), isTrue);

      await p.fetchGuides(category: 'Fire');
      expect(p.errorFor('Fire'), isNull);
      expect(p.guidesFor('Fire').map((g) => g['id']), ['2']);
    });

    test('fetch error with an empty cache: empty list, no error', () async {
      cache = [];
      final p = provider((_) async => throw Exception('offline'));
      await p.fetchGuides();
      expect(p.error, isNull);
      expect(p.guides, isEmpty);
    });

    test('fetch error and no cache: load error, nothing bundled', () async {
      final p = provider((_) async => throw Exception('offline'));
      await p.fetchGuides();
      expect(p.guides, isEmpty);
      expect(p.error, isNotNull);
      expect(p.error!(englishL10n), englishL10n.knowledgeLoadError);
    });

    test('an unreadable cache counts as no cache', () async {
      final p = KnowledgeProvider(
        fetchRows: (_) async => throw Exception('offline'),
        writeCache: (_) async {},
        readCache: () => throw Exception('Hive not initialized'),
      );
      await p.fetchGuides();
      expect(p.guides, isEmpty);
      expect(p.error, isNotNull);
    });
  });

  group('NewsService', () {
    final live = [
      {
        'id': 1,
        'title': 'Flood report',
        'url': 'https://reliefweb.int/report/1',
        'date': '2026-09-01T00:00:00+00:00',
        'source': 'OCHA',
      },
    ];
    final curated = [
      NewsService.mapNewsLinkRow({
        r'$id': 'n1',
        'title': 'NiMet Seasonal Climate Prediction',
        'url': 'https://nimet.gov.ng/',
        'source': 'NiMet',
        'sortOrder': 20,
        'isActive': true,
      }),
    ];

    Future<List<Map<String, dynamic>>> fail(int _) async =>
        throw Exception('down');

    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('curated link rows carry no date', () {
      expect(curated.single, {
        'id': 'n1',
        'title': 'NiMet Seasonal Climate Prediction',
        'url': 'https://nimet.gov.ng/',
        'date': '',
        'source': 'NiMet',
      });
      expect(formatKnowledgeDate(curated.single['date']), isNull);
    });

    test('news_links is declared in the schema mapping', () {
      expect(
        SupabaseSchema.columns['news_links'],
        containsAll([
          'id',
          'title',
          'url',
          'source',
          'sort_order',
          'is_active',
        ]),
      );
    });

    test('live feed first, and the result is cached', () async {
      var curatedCalls = 0;
      final s = NewsService(
        fetchLiveFeed: (_) async => live,
        fetchCuratedLinks: (_) async {
          curatedCalls++;
          return curated;
        },
      );
      expect(await s.fetchLatestNews(), live);
      expect(curatedCalls, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString(NewsService.cacheKey)!), live);
    });

    test('live feed down: curated links, cached', () async {
      final s = NewsService(
        fetchLiveFeed: fail,
        fetchCuratedLinks: (_) async => curated,
      );
      expect(await s.fetchLatestNews(), curated);
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString(NewsService.cacheKey)!), curated);
    });

    test('both sources down: the last cached list', () async {
      SharedPreferences.setMockInitialValues({
        NewsService.cacheKey: jsonEncode(live),
      });
      final s = NewsService(fetchLiveFeed: fail, fetchCuratedLinks: fail);
      expect(await s.fetchLatestNews(), live);
    });

    test('both sources down and no cache: unavailable', () async {
      final s = NewsService(fetchLiveFeed: fail, fetchCuratedLinks: fail);
      expect(s.fetchLatestNews(), throwsA(isA<NewsUnavailableException>()));
    });

    test('sources answered with nothing and no cache: empty list', () async {
      final s = NewsService(
        fetchLiveFeed: (_) async => [],
        fetchCuratedLinks: (_) async => [],
      );
      expect(await s.fetchLatestNews(), isEmpty);
    });

    test(
      'NewsProvider shows the error state when nothing is available',
      () async {
        final p = NewsProvider(
          newsService: NewsService(
            fetchLiveFeed: fail,
            fetchCuratedLinks: fail,
          ),
        );
        await p.fetchNews();
        expect(p.newsItems, isEmpty);
        expect(p.error, isNotNull);
        expect(p.error!(englishL10n), englishL10n.knowledgeNewsLoadError);
      },
    );

    test('NewsProvider lists curated links when the feed is down', () async {
      final p = NewsProvider(
        newsService: NewsService(
          fetchLiveFeed: fail,
          fetchCuratedLinks: (_) async => curated,
        ),
      );
      await p.fetchNews();
      expect(p.error, isNull);
      expect(p.newsItems, curated);
    });
  });

  test('reading time is estimated from the text', () {
    expect(readingMinutes(null), 1);
    expect(readingMinutes('a few words'), 1);
    expect(readingMinutes(List.filled(450, 'word').join(' ')), 3);
  });
}
