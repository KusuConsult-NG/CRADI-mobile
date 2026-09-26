import 'dart:convert';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/core/services/supabase_service.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:developer' as developer;

/// Loads a list of news maps ({id, title, url, date, source}).
typedef NewsFetcher = Future<List<Map<String, dynamic>>> Function(int limit);

/// Thrown when no news source (live feed, curated links, device cache)
/// has anything to show.
class NewsUnavailableException implements Exception {
  const NewsUnavailableException();

  @override
  String toString() => 'NewsUnavailableException';
}

/// News for the Knowledge Base and Home screens.
///
/// Sources, in order:
/// 1. the live ReliefWeb feed;
/// 2. curated links managed by admins in the `news_links` table;
/// 3. the last list either source returned, cached on the device.
///
/// Nothing is invented: when all three are empty or unavailable the caller
/// shows its error / empty state.
class NewsService {
  NewsService({NewsFetcher? fetchLiveFeed, NewsFetcher? fetchCuratedLinks})
    : _fetchLiveFeed = fetchLiveFeed ?? _fetchReliefWeb,
      _fetchCuratedLinks = fetchCuratedLinks ?? _fetchNewsLinks;

  static const String _baseUrl = 'https://api.reliefweb.int/v1/reports';

  /// SharedPreferences key of the last successful news list (JSON).
  static const String cacheKey = 'news_cache_v1';

  final NewsFetcher _fetchLiveFeed;
  final NewsFetcher _fetchCuratedLinks;

  /// Latest news, falling back as described on [NewsService]. Returns an
  /// empty list when a source answered with no items and nothing is cached;
  /// throws [NewsUnavailableException] when every source failed and nothing
  /// is cached.
  Future<List<Map<String, dynamic>>> fetchLatestNews({int limit = 10}) async {
    var anySourceAnswered = false;
    for (final entry in <String, NewsFetcher>{
      'ReliefWeb': _fetchLiveFeed,
      'news_links': _fetchCuratedLinks,
    }.entries) {
      try {
        final items = await entry.value(limit);
        anySourceAnswered = true;
        if (items.isNotEmpty) {
          await _writeCache(items);
          return items;
        }
        developer.log('${entry.key}: no items', name: 'NewsService');
      } on Exception catch (e) {
        developer.log('${entry.key} failed: $e', name: 'NewsService');
      }
    }

    final cached = await _readCache();
    if (cached != null && cached.isNotEmpty) {
      developer.log(
        'Serving ${cached.length} cached news items',
        name: 'NewsService',
      );
      return cached;
    }
    if (anySourceAnswered) return const [];
    throw const NewsUnavailableException();
  }

  /// Latest reports/news related to disasters and climate in Nigeria from
  /// ReliefWeb. Throws on any failure.
  static Future<List<Map<String, dynamic>>> _fetchReliefWeb(int limit) async {
    final queryParams = {
      'appname': 'cradi-mobile',
      'query[value]':
          'Nigeria AND (flood OR drought OR "climate change" OR disaster OR hazard)',
      'sort[]': 'date:desc',
      'limit': limit.toString(),
      'preset': 'latest',
      'profile': 'list',
      // The public report page URL; `href` is the API resource URL.
      'fields[include][]': 'url',
    };

    final uri = Uri.parse(_baseUrl).replace(queryParameters: queryParams);
    developer.log('Fetching news from: $uri', name: 'NewsService');

    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw http.ClientException(
        'ReliefWeb API error ${response.statusCode}',
        uri,
      );
    }
    final data = json.decode(response.body);
    final List<dynamic> items = (data is Map ? data['data'] : null) ?? [];
    return items
        .whereType<Map<dynamic, dynamic>>()
        .map(mapReliefWebItem)
        .toList();
  }

  /// Active curated links from `news_links`, in admin-defined order.
  static Future<List<Map<String, dynamic>>> _fetchNewsLinks(int limit) async {
    final rows = await SupabaseService().listDocuments(
      collectionId: AppConfig.newsLinksCollection,
      queries: [
        FQuery.equal('isActive', true),
        FQuery.orderAsc('sortOrder'),
        FQuery.orderAsc('createdAt'),
      ],
      limitCount: limit,
    );
    return rows.map(mapNewsLinkRow).toList();
  }

  /// Maps one `news_links` row (app-shaped, see `fromRow`) to the news map
  /// used by the UI. Curated links carry no publication date, so `date` is
  /// empty (the UI then shows none).
  static Map<String, dynamic> mapNewsLinkRow(Map<String, dynamic> row) {
    return {
      'id': row[r'$id'] ?? row['id'],
      'title': row['title'],
      'url': row['url'],
      'date': '',
      'source': row['source'] ?? '',
    };
  }

  /// Maps one ReliefWeb API item to the news map used by the UI. The link is
  /// the public page (`fields.url`), falling back to the API `href` only
  /// when the page URL is missing.
  static Map<String, dynamic> mapReliefWebItem(Map<dynamic, dynamic> item) {
    final rawFields = item['fields'];
    final fields = rawFields is Map ? rawFields : const {};
    final sources = fields['source'];
    final firstSource = sources is List && sources.isNotEmpty
        ? sources.first
        : null;
    final pageUrl = fields['url'];
    final date = fields['date'];
    return {
      'id': item['id'],
      // A missing title is shown with a localised placeholder by the UI.
      'title': fields['title'],
      'url': (pageUrl is String && pageUrl.isNotEmpty) ? pageUrl : item['href'],
      'date': date is Map ? (date['created'] ?? '') : '',
      'source': firstSource is Map
          ? (firstSource['name'] ?? 'ReliefWeb')
          : 'ReliefWeb',
    };
  }

  Future<void> _writeCache(List<Map<String, dynamic>> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cacheKey, jsonEncode(items));
    } on Object catch (e) {
      developer.log('News cache write failed: $e', name: 'NewsService');
    }
  }

  Future<List<Map<String, dynamic>>?> _readCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(cacheKey);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    } on Object catch (e) {
      developer.log('News cache unreadable: $e', name: 'NewsService');
      return null;
    }
  }
}
