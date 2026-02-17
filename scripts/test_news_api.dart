// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:http/http.dart' as http;

Future<void> main() async {
  print('🚀 Testing ReliefWeb API...');

  const baseUrl = 'https://api.reliefweb.int/v1/reports';
  final queryParams = {
    'appname': 'rw-api-explorer',
    'query[value]':
        'Nigeria AND (flood OR drought OR "climate change" OR disaster OR hazard)',
    'sort[]': 'date:desc',
    'limit': '5',
    'preset': 'latest',
    'profile': 'list',
  };

  final uri = Uri.parse(baseUrl).replace(queryParameters: queryParams);
  print('Requesting: $uri');

  try {
    final response = await http.get(uri);

    print('Status Code: ${response.statusCode}');

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final int total = data['totalCount'] ?? 0;
      final List<dynamic> items = data['data'] ?? [];

      print('Total Results: $total');
      print('Items Fetched: ${items.length}');

      for (final item in items) {
        final fields = item['fields'] ?? {};
        print('------------------------------------------------');
        print('Title: ${fields['title']}');
        print('Date: ${fields['date']?['created']}');
        print('Source: ${(fields['source'] as List?)?.first['name']}');
        print('URL: ${item['href']}');
      }
    } else {
      print('❌ Error: API returned ${response.statusCode}');
      print('Body: ${response.body}');
    }
  } on Exception catch (e) {
    print('Test failed: $e');
  }
}
