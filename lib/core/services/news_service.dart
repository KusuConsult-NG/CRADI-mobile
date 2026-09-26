import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:developer' as developer;

class NewsService {
  static const String _baseUrl = 'https://api.reliefweb.int/v1/reports';

  /// Fetch latest reports/news related to disasters and climate in Nigeria
  Future<List<Map<String, dynamic>>> fetchLatestNews({int limit = 10}) async {
    try {
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

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data['data'] ?? [];

        return items
            .whereType<Map<dynamic, dynamic>>()
            .map(mapReliefWebItem)
            .toList();
      } else {
        developer.log(
          'API Error ${response.statusCode}: ${response.body}',
          name: 'NewsService',
        );
        return _getFallbackNews();
      }
    } on Exception catch (e) {
      developer.log('Error fetching news: $e', name: 'NewsService');
      return _getFallbackNews();
    }
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

  /// Fallback news when API is unavailable or rate limited
  List<Map<String, dynamic>> _getFallbackNews() {
    return [
      {
        'id': 'fallback-1',
        'title': 'Flood Safety: What to do before, during, and after',
        'url':
            'https://www.redcross.org/get-help/how-to-prepare-for-emergencies/types-of-emergencies/flood.html',
        'date': DateTime.now().toIso8601String(),
        'source': 'Safety Guide',
      },
      {
        'id': 'fallback-2',
        'title': 'NIMET Seasonal Climate Prediction 2024',
        'url': 'https://nimet.gov.ng/',
        'date': DateTime.now()
            .subtract(const Duration(days: 2))
            .toIso8601String(),
        'source': 'NIMET',
      },
      {
        'id': 'fallback-3',
        'title': 'Emergency Contact Directory: Nigeria',
        'url': 'https://www.redcrossnigeria.org/',
        'date': DateTime.now()
            .subtract(const Duration(days: 5))
            .toIso8601String(),
        'source': 'Red Cross',
      },
      {
        'id': 'fallback-4',
        'title': 'Understanding Early Warning Systems',
        'url': 'https://www.undrr.org/terminology/early-warning-system',
        'date': DateTime.now()
            .subtract(const Duration(days: 10))
            .toIso8601String(),
        'source': 'UNDRR',
      },
      {
        'id': 'fallback-5',
        'title': 'How to Report a Disaster Incident',
        'url': '#',
        'date': DateTime.now()
            .subtract(const Duration(days: 1))
            .toIso8601String(),
        'source': 'CRADI Help',
      },
    ];
  }
}
