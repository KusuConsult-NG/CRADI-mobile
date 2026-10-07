import 'dart:convert';
import 'dart:io';

import 'package:appwrite/appwrite.dart' as aw;
import 'package:flutter_test/flutter_test.dart';

import 'package:climate_app/core/services/appwrite/appwrite_auth_backend.dart';
import 'package:climate_app/core/services/appwrite/appwrite_execution.dart';

import 'live_appwrite.dart';

/// Two requests in this backend are hand-rolled rather than made through
/// the SDK — the email sign-in (the SDK's cookie parser throws on
/// Appwrite's `Set-Cookie`) and a Function execution (the SDK's
/// `Execution.fromMap` needs fields a 1.x server does not send).
///
/// Both took their URL from `AppwriteConfig`, which is compiled in from
/// `--dart-define`. Every other call takes it from the client. So a
/// caller handed a client pointed at another server — which is the only
/// reason these constructors accept one — had all its traffic go to that
/// server except these two, which went wherever the binary was built
/// for. In a unit build that is the empty string, and in a test build
/// against a local stack it is whatever happened to be defined.
///
/// Each test here points a client at a server of its own and asserts the
/// request arrives. Before the fix it did not: there was nowhere for it
/// to arrive.
void main() {
  // In `test/integration` and using `useLiveAppwrite()`, but it needs no
  // live server — it serves its own. What it needs is the three things
  // that file undoes, all of them properties of the harness rather than
  // of the code: `TestWidgetsFlutterBinding` installs an `HttpOverrides`
  // that answers every request 400 without touching the network, and
  // the SDK's IO client builds its cookie jar and user-agent from
  // plugins that have no implementation in a test VM. So this cannot
  // live in `test/unit`, where the request would never leave.
  useLiveAppwrite();

  late HttpServer server;
  late List<HttpRequest> seen;
  late String endpoint;

  setUp(() async {
    seen = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    endpoint = 'http://127.0.0.1:${server.port}/v1';
    server.listen((request) async {
      seen.add(request);
      final path = request.uri.path;
      request.response.headers.contentType = ContentType.json;
      if (path.endsWith('/account/sessions/email')) {
        request.response.statusCode = 201;
        request.response.write(jsonEncode({'\$id': 's1', 'secret': 'sess'}));
      } else if (path.endsWith('/account')) {
        request.response.write(
          jsonEncode({
            '\$id': 'u1',
            '\$createdAt': '2026-01-01T00:00:00.000+00:00',
            '\$updatedAt': '2026-01-01T00:00:00.000+00:00',
            'name': 'Amina',
            'email': 'amina@example.com',
            'emailVerification': true,
            'phoneVerification': false,
            'status': true,
            'labels': <String>[],
            'prefs': <String, dynamic>{},
            'registration': '2026-01-01T00:00:00.000+00:00',
            'passwordUpdate': '',
            'phone': '',
            'accessedAt': '2026-01-01T00:00:00.000+00:00',
            'mfa': false,
            'targets': <dynamic>[],
          }),
        );
      } else {
        request.response.statusCode = 201;
        request.response.write(
          jsonEncode({
            '\$id': 'e1',
            'status': 'completed',
            'responseStatusCode': 200,
            'responseBody': jsonEncode({'ok': true}),
            'errors': '',
            'logs': '',
          }),
        );
      }
      await request.response.close();
    });
  });

  tearDown(() async => server.close(force: true));

  aw.Client clientFor() => aw.Client()
    ..setEndpoint(endpoint)
    ..setProject('injected');

  test(
    'the hand-rolled sign-in goes to the injected client’s server',
    () async {
      final backend = AppwriteAuthBackend(client: clientFor());
      final outcome = await backend.signInWithPassword(
        email: 'amina@example.com',
        password: 'Password1!',
      );

      expect(outcome.hasSession, isTrue);
      expect(
        seen.map((r) => r.uri.path),
        contains('/v1/account/sessions/email'),
      );
      // And it carried the injected project, not the compiled-in one.
      expect(seen.first.headers.value('x-appwrite-project'), 'injected');
    },
  );

  test('a Function execution goes to the injected client’s server', () async {
    final body = await createExecution(clientFor(), 'client', {
      'op': 'create',
    }, path: '/write');

    // `createExecution` answers with the execution envelope; the
    // adapters read `responseBody` out of it. What matters here is only
    // that it reached this server at all.
    expect(body[r'$id'], 'e1');
    expect(seen.single.uri.path, '/v1/functions/client/executions');
    expect(seen.single.headers.value('x-appwrite-project'), 'injected');
  });
}
