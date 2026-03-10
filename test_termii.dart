// ignore_for_file: depend_on_referenced_packages, uri_does_not_exist, undefined_identifier, avoid_print, prefer_const_declarations, avoid_catches_without_on_clauses, unused_local_variable
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  const apiKey =
      'TLqowdGuBlhiEpgzeHiOydfGZsPeblLnmKFUidFLEBzbvmoPjAttNOxnkPseyp';
  const url = 'https://api.ng.termii.com/api/sms/send';

  final body = {
    'to':
        '2348030000000', // Replace with a safe test number or keep it as is to see the API error
    'from': 'CRADI',
    'sms': 'Test message from CRADI',
    'type': 'plain',
    'channel': 'generic',
    'api_key': apiKey,
  };

  print('Sending request to \$url');
  final response = await http.post(
    Uri.parse(url),
    headers: {'Content-Type': 'application/json'},
    body: json.encode(body),
  );

  print('Status Code: \${response.statusCode}');
  print('Response Body: \${response.body}');
}
