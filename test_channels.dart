// ignore_for_file: depend_on_referenced_packages, uri_does_not_exist, undefined_identifier, avoid_print, prefer_const_declarations, avoid_catches_without_on_clauses, unused_local_variable
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io';

Future<void> main() async {
  // Load environment variables
  await dotenv.load(fileName: '.env.production');

  final apiKey = dotenv.env['TERMII_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    print('Failed to load TERMII_API_KEY');
    return;
  }

  final testNumber = '2347036171049'; // Using the test number provided earlier
  print('Testing Termii generic channel...');
  await testSend(apiKey, testNumber, 'generic', 'EWER');

  print('\nTesting Termii dnd channel...');
  await testSend(apiKey, testNumber, 'dnd', 'EWER');
}

Future<void> testSend(
  String apiKey,
  String to,
  String channel,
  String senderId,
) async {
  final url = Uri.parse('https://api.ng.termii.com/api/sms/send');
  final body = {
    'to': to,
    'from': senderId,
    'sms': 'Test message for channel $channel',
    'type': 'plain',
    'channel': channel,
    'api_key': apiKey,
  };

  try {
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );
    print('Response Code ($channel): ${response.statusCode}');
    print('Response Body ($channel): ${response.body}');
  } catch (e) {
    print('Error ($channel): $e');
  }
}
