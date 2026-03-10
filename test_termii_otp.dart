// ignore_for_file: depend_on_referenced_packages, uri_does_not_exist, undefined_identifier, avoid_print, prefer_const_declarations, avoid_catches_without_on_clauses, unused_local_variable
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  const apiKey =
      'TLqowdGuBlhiEpgzeHiOydfGZsPeblLnmKFUidFLEBzbvmoPjAttNOxnkPseyp';
  const url = 'https://api.ng.termii.com/api/sms/send';

  // Format Nigerian number: 07036171049 -> 2347036171049
  const phone = '2347036171049';
  const otp = '123456';

  final message =
      '''
Your CRADI verification code is: $otp
Valid for 10 minutes.
Do not share this code.
''';

  final body = {
    'to': phone,
    'from': 'CRADI',
    'sms': message,
    'type': 'plain',
    'channel': 'generic',
    'api_key': apiKey,
  };

  print('Sending OTP test using current implementation to $phone...');

  try {
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );

    print('Status Code: ${response.statusCode}');
    print('Response Body: ${response.body}');

    if (response.statusCode == 200 || response.statusCode == 201) {
      print('✅ Success! Check your phone for the SMS.');
    } else {
      print('❌ Failed to send SMS.');
    }
  } catch (e) {
    print('❌ Error: $e');
  }
}
