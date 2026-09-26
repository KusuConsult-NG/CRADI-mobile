import 'dart:async';
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
        ({String? category}) async => [
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
      final p = provider(({String? category}) async => [row('1', 'flood', imageUrl: '')]);
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
      final p = provider(({String? category}) async => []);
      await p.fetchGuides();
      expect(p.error, isNull);
      expect(p.guides, isEmpty);
      // Guides an admin deleted must also disappear offline.
      expect(cache, isEmpty);
    });

    test('category lists are not cached', () async {
      final p = provider(({String? category}) async => [row('1', 'flood')]);
      await p.fetchGuides(category: 'Flood');
      expect(p.guidesFor('Flood'), hasLength(1));
      expect(cacheWrites, 0);
    });

    test('a category tab is filtered on the server by every spelling', () async {
      final asked = <String?>[];
      final p = provider(({String? category}) async {
        asked.add(category);
        return [row('1', 'flood')];
      });

      await p.fetchGuides();
      await p.fetchGuides(category: 'flood');
      await p.fetchGuides(category: 'Flood');
      // The normalised category label reaches the fetcher, so the query is
      // the same however the tab names the category.
      expect(asked, [allKnowledgeCategories, 'Flood', 'Flood']);

      final values = knowledgeCategoryQueryValues('Flood');
      expect(values, containsAll(['flood', 'Flood', 'flooding', 'Flooding']));
      expect(values, isNot(contains('fire')));
      // Every stored spelling the offline filter accepts is queried for.
      for (final v in values) {
        expect(
          guideMatchesCategory({'hazardType': v}, 'Flood'),
          isTrue,
          reason: v,
        );
      }
    });

    test('knowledgeCategoryQueryValues: no server filter for All or an '
        'unknown category', () {
      expect(knowledgeCategoryQueryValues(null), isEmpty);
      expect(knowledgeCategoryQueryValues(allKnowledgeCategories), isEmpty);
      expect(knowledgeCategoryQueryValues('Tsunami'), ['Tsunami', 'tsunami']);
      expect(
        knowledgeCategoryQueryValues('Extreme Heat'),
        containsAll(['extreme_heat', 'Extreme Heat', 'heatwave', 'Heatwave']),
      );
    });

    test('online category tabs match hazard type, label and aliases like '
        'the offline filter', () async {
      final rows = [
        row('1', 'flood'),
        {...row('2', 'Flooding'), 'category': null},
        {...row('3', ''), 'hazardType': null, 'category': 'Flood'},
        row('4', 'fire'),
        {...row('5', 'FLOODS'), 'category': 'floods'},
      ];
      final p = provider(({String? category}) async => rows);
      await p.fetchGuides(category: 'Flood');
      expect(p.guidesFor('Flood').map((g) => g['id']), ['1', '2', '3', '5']);
      await p.fetchGuides(category: 'fire');
      expect(p.guidesFor('Fire').map((g) => g['id']), ['4']);

      // Same result as the offline (cached) filter.
      await p.fetchGuides();
      final offline = provider(({String? category}) async => throw Exception('offline'));
      await offline.fetchGuides(category: 'Flood');
      expect(
        offline.guidesFor('Flood').map((g) => g['id']),
        p.guidesFor('Flood').map((g) => g['id']),
      );
    });

    test('overlapping fetches: a superseded result is dropped and loading '
        'ends only with the latest request', () async {
      final first = Completer<List<Map<String, dynamic>>>();
      final second = Completer<List<Map<String, dynamic>>>();
      final pending = [first, second];
      final p = provider(({String? category}) => pending.removeAt(0).future);

      final a = p.fetchGuides(category: 'Flood');
      final b = p.fetchGuides(category: 'Flood');
      expect(p.isLoadingCategory('Flood'), isTrue);

      // The newer request answers first.
      second.complete([row('new', 'flood')]);
      await b;
      expect(p.isLoadingCategory('Flood'), isFalse);
      expect(p.guidesFor('Flood').map((g) => g['id']), ['new']);

      // The stale answer arrives later and is ignored.
      first.complete([row('stale', 'flood')]);
      await a;
      expect(p.guidesFor('Flood').map((g) => g['id']), ['new']);
      expect(p.isLoadingCategory('Flood'), isFalse);
    });

    test(
      'a superseded request does not end the latest one\'s loading',
      () async {
        final first = Completer<List<Map<String, dynamic>>>();
        final second = Completer<List<Map<String, dynamic>>>();
        final pending = [first, second];
        final p = provider(({String? category}) => pending.removeAt(0).future);

        final a = p.fetchGuides();
        final b = p.fetchGuides();
        first.completeError(Exception('timeout'));
        await a;
        expect(p.isLoading, isTrue);
        expect(p.error, isNull);

        second.complete([row('1', 'flood')]);
        await b;
        expect(p.isLoading, isFalse);
        expect(p.guides.map((g) => g['id']), ['1']);
      },
    );

    test('fetch error: the cache is served, marked offline', () async {
      cache = [
        {...row('1', 'flood'), 'id': '1', 'isOffline': false},
        {...row('2', 'fire'), 'id': '2', 'isOffline': false},
      ];
      final p = provider(({String? category}) async => throw Exception('offline'));
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
      final p = provider(({String? category}) async => throw Exception('offline'));
      await p.fetchGuides();
      expect(p.error, isNull);
      expect(p.guides, isEmpty);
    });

    test('fetch error and no cache: load error, nothing bundled', () async {
      final p = provider(({String? category}) async => throw Exception('offline'));
      await p.fetchGuides();
      expect(p.guides, isEmpty);
      expect(p.error, isNotNull);
      expect(p.error!(englishL10n), englishL10n.knowledgeLoadError);
    });

    test('an unreadable cache counts as no cache', () async {
      final p = KnowledgeProvider(
        fetchRows: ({String? category}) async => throw Exception('offline'),
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

    test('ReliefWeb payload with a non-list "data" is a FormatException, '
        'not a TypeError', () {
      expect(
        () => NewsService.parseReliefWebBody('{"data": {"oops": 1}}'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => NewsService.parseReliefWebBody('{"data": "x"}'),
        throwsA(isA<FormatException>()),
      );
      expect(NewsService.parseReliefWebBody('{"totalCount": 0}'), isEmpty);
      expect(NewsService.parseReliefWebBody('[]'), isEmpty);
      final items = NewsService.parseReliefWebBody(
        '{"data": [{"id": 7, "fields": {"title": "T", "url": "https://r/7"}},'
        ' "junk"]}',
      );
      expect(items.single['id'], 7);
      expect(items.single['url'], 'https://r/7');
    });

    test('a source throwing an Error falls through to the next one', () async {
      final s = NewsService(
        fetchLiveFeed: (_) async => throw TypeError(),
        fetchCuratedLinks: (_) async => curated,
      );
      expect(await s.fetchLatestNews(), curated);
    });

    test('NewsProvider always ends loading, even on an Error', () async {
      final p = NewsProvider(
        newsService: NewsService(
          fetchLiveFeed: (_) async => throw TypeError(),
          fetchCuratedLinks: (_) async => throw StateError('bad row'),
        ),
      );
      await p.fetchNews();
      expect(p.isLoading, isFalse);
      expect(p.newsItems, isEmpty);
      expect(p.error, isNotNull);
    });

    test(
      'NewsProvider ends loading when the service itself throws an Error',
      () async {
        final p = NewsProvider(newsService: _ThrowingNewsService());
        await p.fetchNews();
        expect(p.isLoading, isFalse);
        expect(p.error, isNotNull);
      },
    );
  });

  test('reading time is estimated from the text', () {
    expect(readingMinutes(null), 1);
    expect(readingMinutes('a few words'), 1);
    expect(readingMinutes(List.filled(450, 'word').join(' ')), 3);
  });
}

class _ThrowingNewsService extends NewsService {
  @override
  Future<List<Map<String, dynamic>>> fetchLatestNews({int limit = 10}) async =>
      throw TypeError();
}
