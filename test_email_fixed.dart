// ignore_for_file: unused_import, avoid_print, unused_local_variable, empty_catches, avoid_catches_without_on_clauses
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() async {
  print("Testing Resend API...");

  const apiKey = 're_C1GhEJ5U_DScqhvDStZ21HTfCo5HisWUe';
  const resendUrl = 'https://api.resend.com/emails';
  const fromEmail = 'apps@ewer.cradil.org';
  const fromName = 'EWER Alert System';
  const to = 'hackkusu@gmail.com';
  const subject = 'Test from Dart script';
  const html = '<p>Test</p>';

  try {
    final response = await http.post(
      Uri.parse(resendUrl),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'from': '$fromName <$fromEmail>',
        'to': [to],
        'subject': subject,
        'html': html,
      }),
    );

    final success = response.statusCode == 200 || response.statusCode == 201;
    print("Status: ${response.statusCode}");
    print("Body: ${response.body}");
  } catch (e) {
    print("Exception: $e");
  }
}
