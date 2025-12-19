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
      };

      final uri = Uri.parse(_baseUrl).replace(queryParameters: queryParams);
      developer.log('Fetching news from: $uri', name: 'NewsService');

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data['data'] ?? [];

        return items.map((item) {
          final fields = item['fields'] ?? {};
          return {
            'id': item['id'],
            'title': fields['title'] ?? 'No Title',
            'url': item['href'],
            'date': fields['date']?['created'] ?? '',
            'source': (fields['source'] as List?)?.first['name'] ?? 'ReliefWeb',
          };
        }).toList();
      } else {
        throw Exception('Failed to fetch news: ${response.statusCode}');
      }
    } on Exception catch (e) {
      developer.log('Error fetching news: $e', name: 'NewsService');
      return [];
    }
  }
}
