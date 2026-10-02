import 'dart:convert';

import 'package:appwrite/appwrite.dart' as aw;
import 'package:http/http.dart' as http;

import 'package:climate_app/core/services/appwrite/appwrite_config.dart';

/// Runs an Appwrite Function and hands back the execution as the server
/// sent it.
///
/// Not `Functions.createExecution`, which is the obvious call, because
/// its parsing is tied to a server version this app does not only
/// target. `Execution.fromMap` reads `resourceId` and `resourceType`
/// with `map['...']!`, and those fields arrived in **Appwrite 2.3** — so
/// against 1.8 or 1.9 it throws `Bad state: No element` before the
/// response body is looked at, inside the SDK's model rather than
/// anywhere here. Every Function call the app makes went through it:
/// `write`, `operation` and `auth` alike, which is registration,
/// recovery and every write the client is not allowed to make directly.
///
/// Only three fields are wanted — the status code, the response body
/// and whether the run completed — and all three have been there since
/// 1.x. Reading them directly works on every server the app will meet
/// and cannot be broken by a field appearing or disappearing beside
/// them.
///
/// The headers are the SDK's own, so the session (or JWT), the response
/// format and the `Origin` the server checks against its platform list
/// are exactly what every other call sends. The project is **not** among
/// them: `setProject` writes only to `config`, and each generated
/// service method puts `X-Appwrite-Project` on its own call — so this
/// has to as well. Leaving it out does not read as "no project": with an
/// `Origin` header and no project to match it against, Appwrite answers
/// `Invalid Origin. Register your new client …`, which sends you looking
/// at the platform list instead of at the missing header.
Future<Map<String, dynamic>> createExecution(
  aw.Client client,
  String functionId,
  Map<String, dynamic> payload,
) async {
  final uri = Uri.parse(
    '${AppwriteConfig.endpoint}'
    '/functions/${Uri.encodeComponent(functionId)}/executions',
  );
  http.Response response;
  try {
    response = await http.post(
      uri,
      headers: {
        ...client.getHeaders(),
        'X-Appwrite-Project': client.config['project'] ?? '',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'body': jsonEncode(payload),
        'async': false,
        'method': 'POST',
        'headers': {'content-type': 'application/json'},
      }),
    );
  } on Object catch (e) {
    throw aw.AppwriteException('Could not reach the server: $e', 503);
  }

  final decoded = decodeJsonBody(response.body);
  if (response.statusCode >= 400) {
    // The execution was refused outright — which is not the same as a
    // Function that ran and refused, and the callers tell them apart. A
    // guest calling a Function whose execute permission is `users`
    // lands here.
    throw aw.AppwriteException(
      decoded['message']?.toString() ?? 'The request was refused',
      response.statusCode,
      decoded['type']?.toString(),
      response.body,
    );
  }
  return decoded;
}

/// A JSON object from a response body, however badly it went.
///
/// A Function that crashed before writing JSON still has something to
/// say, and losing it to a parse error loses the only description of
/// what happened.
Map<String, dynamic> decodeJsonBody(String body) {
  if (body.isEmpty) return const {};
  try {
    final decoded = jsonDecode(body);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : {'value': decoded};
  } on FormatException {
    return {'message': body};
  }
}
