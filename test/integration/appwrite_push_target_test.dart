import 'dart:convert';
import 'dart:io';

import 'package:appwrite/appwrite.dart' as aw;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:climate_app/core/services/appwrite/appwrite_data_backend.dart';
import 'package:climate_app/core/services/appwrite/appwrite_push_targets.dart';

import 'live_appwrite.dart';

/// Registering this device as an Appwrite push target, against a server of
/// this test's own.
///
/// It needs no live Appwrite but does need `useLiveAppwrite()`, for the
/// same reason `appwrite_injected_client_test.dart` does: under the
/// default test harness an `HttpOverrides` answers every request 400
/// without it ever leaving, and the SDK's IO client wants plugins a test
/// VM has no implementation for. So a request here actually arrives, which
/// is the only way to assert what was sent.
void main() {
  useLiveAppwrite();

  late HttpServer server;
  late List<({String method, String path, Map<String, dynamic> body})> seen;
  late String endpoint;

  /// Whether the next `createPushTarget` is answered with Appwrite's 409.
  late bool targetExists;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    seen = [];
    targetExists = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    endpoint = 'http://127.0.0.1:${server.port}/v1';
    server.listen((request) async {
      final raw = await utf8.decodeStream(request);
      seen.add((
        method: request.method,
        path: request.uri.path,
        body: raw.isEmpty
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(jsonDecode(raw) as Map),
      ));
      request.response.headers.contentType = ContentType.json;

      if (request.uri.path.contains('/account/targets/push') &&
          request.method == 'POST' &&
          targetExists) {
        // What a device that has registered before gets. Appwrite's own
        // refusal for an id that is taken, which is the ordinary case from
        // the second launch onwards rather than an error.
        request.response.statusCode = 409;
        request.response.write(
          jsonEncode({
            'message': 'Target already exists',
            'code': 409,
            'type': 'target_already_exists',
          }),
        );
      } else if (request.uri.path.contains('/account/targets')) {
        request.response.statusCode = request.method == 'POST' ? 201 : 200;
        request.response.write(
          jsonEncode({
            r'$id': 'tgt',
            r'$createdAt': '2026-10-07T00:00:00.000+00:00',
            r'$updatedAt': '2026-10-07T00:00:00.000+00:00',
            'name': '',
            'userId': 'u1',
            'providerId': '',
            'providerType': 'push',
            'identifier': 'token',
            'expired': false,
          }),
        );
      } else {
        // The Function execution behind `callOperation`.
        request.response.statusCode = 201;
        request.response.write(
          jsonEncode({
            r'$id': 'e1',
            'status': 'completed',
            'responseStatusCode': 200,
            'responseBody': jsonEncode({
              'topics': ['all-users', 'state-benue', 'lga-benue-obi'],
              'targets': 1,
            }),
            'errors': '',
            'logs': '',
          }),
        );
      }
      await request.response.close();
    });
  });

  tearDown(() async => server.close(force: true));

  AppwritePushTargets targetsFor() => AppwritePushTargets(
    data: AppwriteDataBackend(
      client: aw.Client()
        ..setEndpoint(endpoint)
        ..setProject('injected'),
    ),
  );

  test('registers the token, then asks the server to subscribe it', () async {
    final registered = await targetsFor().register('fcm-token-1');

    expect(registered, isTrue);
    final create = seen.firstWhere(
      (r) => r.path.endsWith('/account/targets/push'),
    );
    expect(create.method, 'POST');
    expect(create.body['identifier'], 'fcm-token-1');
    expect(create.body['targetId'], startsWith('dev-'));
    // Unset in a test build, and Appwrite then files the target under the
    // project's default push provider.
    expect(create.body.containsKey('providerId'), isFalse);

    // The subscription is the server's to decide: the client names no
    // topic, it only says the device is here.
    final sync = seen.last;
    expect(sync.path, contains('/functions/client/executions'));
    final payload = jsonDecode(sync.body['body'].toString()) as Map;
    expect(payload['operation'], 'sync_push_subscriptions');
    expect(sync.body['path'], '/operation');
  });

  test('keeps one target id per installation', () async {
    await targetsFor().register('fcm-token-1');
    final first = seen
        .firstWhere((r) => r.path.endsWith('/account/targets/push'))
        .body['targetId'];

    // A second launch: a new instance, the same stored preferences.
    seen.clear();
    targetExists = true;
    await targetsFor().register('fcm-token-2');

    final again = seen
        .firstWhere((r) => r.path.endsWith('/account/targets/push'))
        .body['targetId'];
    expect(
      again,
      first,
      reason: 'a new id per launch leaves a dead target behind',
    );
  });

  test('updates the target when the token changed under it', () async {
    targetExists = true;
    final registered = await targetsFor().register('fcm-token-2');

    expect(registered, isTrue);
    // A PUT, which is what the SDK's `updatePushTarget` sends — the one
    // detail here that was guessed wrong first time round.
    final update = seen.firstWhere((r) => r.method == 'PUT');
    expect(update.path, contains('/account/targets/'));
    expect(update.path, endsWith('/push'));
    expect(update.body['identifier'], 'fcm-token-2');
    // And the subscription sync still ran: a refreshed token with no
    // subscriptions is the silent half of this failure.
    expect(seen.last.path, contains('/functions/client/executions'));
  });

  test(
    'does nothing with no token, rather than registering an empty one',
    () async {
      expect(await targetsFor().register(''), isFalse);
      expect(seen, isEmpty);
    },
  );

  test('a refusal that is not a 409 is raised, not written off', () async {
    await server.close(force: true);
    // Nothing is listening now, so the SDK's own transport failure stands
    // in for any refusal the 409 branch does not cover.
    await expectLater(
      targetsFor().register('fcm-token-1'),
      throwsA(isA<aw.AppwriteException>()),
    );
  });
}
