import 'dart:io';

import 'package:appwrite/appwrite.dart' as aw;
import 'package:flutter_test/flutter_test.dart';

import 'package:climate_app/core/services/appwrite/appwrite_auth_backend.dart';
import 'package:climate_app/core/services/appwrite/appwrite_data_backend.dart';
import 'package:climate_app/core/services/data_backend.dart';

import 'live_appwrite.dart';

/// The three adapter paths that need more than a request/response:
/// realtime, file upload, and a named server operation.
///
/// Phase 16 covered documents and queries. These are the parts that
/// reach a websocket, a storage bucket, and a Function respectively,
/// and none had ever run.
void main() {
  if (!liveConfigured) {
    test('Appwrite realtime/files/ops', () {}, skip: skipUnlessLive);
    return;
  }

  useLiveAppwrite();

  late AppwriteDataBackend backend;
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final cleanup = <Future<void> Function()>[];

  setUpAll(() async {
    AppwriteDataBackend.installErrorVocabulary();
    backend = AppwriteDataBackend(
      client: aw.Client()
          .setEndpoint(liveEndpoint)
          // The realtime container is published separately in the local
          // stack. On Cloud `/v1/realtime` is proxied on the same host
          // and the SDK derives this from the endpoint, so only a
          // self-hosted deployment needs it said out loud.
          .setEndPointRealtime(liveRealtime)
          .setProject(liveProject),
    );
    backend.client.setSession(liveSession);
    await AppwriteAuthBackend(data: backend).restore();
    expect(backend.currentUserId, liveUserId);
  });

  tearDownAll(() async {
    for (final undo in cleanup) {
      try {
        await undo();
      } on Exception {
        // Best effort.
      }
    }
  });

  group('realtime', () {
    test(
      'a collection stream emits the initial page, then each change',
      () async {
        // Filtered on a value only this test writes. The other live
        // suite uses `contacts` under the same account, and the two run
        // concurrently, so a filter on `userId` alone makes the counts
        // below depend on what the other suite happens to be doing.
        // `phone` is the key because the test renames `name`.
        final marker = '0803${'$stamp'.substring('$stamp'.length - 7)}';
        final seen = <List<Map<String, dynamic>>>[];
        final sub = backend
            .subscribeToCollection(
              collectionId: 'contacts',
              queries: [FQuery.equal('phone', marker), FQuery.limit(25)],
            )
            .listen(seen.add);
        addTearDown(sub.cancel);

        // The first emission is the initial list, fetched not pushed.
        await _until(() => seen.isNotEmpty, 'the initial page');
        final before = seen.last.length;
        expect(before, 0, reason: 'nothing else writes this phone');

        final docId = 'rt-$stamp'.substring(0, 36.clamp(0, 'rt-$stamp'.length));
        cleanup.add(
          () => backend.deleteDocument(
            collectionId: 'contacts',
            documentId: docId,
          ),
        );
        await backend.createDocument(
          collectionId: 'contacts',
          documentId: docId,
          data: {
            'userId': liveUserId,
            'name': 'Realtime Contact',
            'phone': marker,
          },
        );

        await _until(
          () => seen.last.any((d) => d[r'$id'] == docId),
          'the created document to arrive over the socket',
        );
        expect(seen.last.length, before + 1);

        // An update replaces rather than duplicates — the list is keyed
        // by `$id`, which is what the Postgres stream got from its
        // primary key.
        await backend.updateDocument(
          collectionId: 'contacts',
          documentId: docId,
          data: {'name': 'Renamed'},
        );
        await _until(
          () => seen.last.any(
            (d) => d[r'$id'] == docId && d['name'] == 'Renamed',
          ),
          'the update to arrive',
        );
        expect(
          seen.last.where((d) => d[r'$id'] == docId),
          hasLength(1),
          reason: 'an update must replace, not duplicate',
        );

        await backend.deleteDocument(
          collectionId: 'contacts',
          documentId: docId,
        );
        await _until(
          () => !seen.last.any((d) => d[r'$id'] == docId),
          'the delete to remove it',
        );
      },
    );

    test('a document stream emits null when the document goes', () async {
      final docId = 'rtd-$stamp'.substring(0, 36.clamp(0, 'rtd-$stamp'.length));
      await backend.createDocument(
        collectionId: 'contacts',
        documentId: docId,
        data: {'userId': liveUserId, 'name': 'Watched', 'phone': '08031234567'},
      );

      final seen = <Map<String, dynamic>?>[];
      final sub = backend
          .subscribeToDocument(collectionId: 'contacts', documentId: docId)
          .listen(seen.add);
      addTearDown(sub.cancel);

      await _until(() => seen.isNotEmpty, 'the first emission');
      expect(seen.last?['name'], 'Watched');

      await backend.deleteDocument(collectionId: 'contacts', documentId: docId);
      await _until(() => seen.last == null, 'null after the delete');
    });
  });

  group('files', () {
    test('uploads bytes and returns a URL that serves them back', () async {
      // A one-pixel PNG, so the stubbed compressor has something real.
      final bytes = _onePixelPng;
      final path = '$liveUserId/report_$stamp.jpg';
      final url = await backend.uploadFile(
        bucketId: 'report-images',
        storagePath: path,
        fileBytes: bytes,
      );
      cleanup.add(
        () => backend.deleteFile(bucketId: 'report-images', storagePath: path),
      );

      expect(url, contains('/storage/buckets/report-images/files/'));
      expect(url, contains('/view'));
      expect(url, contains('project='));

      final fetched = await HttpClient()
          .getUrl(Uri.parse(url))
          .then((r) => r.close());
      expect(fetched.statusCode, 200, reason: 'the stored URL must resolve');
    });

    test('evidence is write-once: the same path twice is refused', () async {
      final path = '$liveUserId/dup_$stamp.jpg';
      await backend.uploadFile(
        bucketId: 'report-images',
        storagePath: path,
        fileBytes: _onePixelPng,
      );

      // Phase 3: evidence is immutable. The bucket grants `create` and
      // `read` and nothing else, so a second upload to the same path
      // cannot quietly replace the first — and neither can an `upsert`,
      // which is the point. Nothing in the app asks for one.
      await expectLater(
        backend.uploadFile(
          bucketId: 'report-images',
          storagePath: path,
          fileBytes: _onePixelPng,
        ),
        throwsA(isA<aw.AppwriteException>()),
      );
      await expectLater(
        backend.uploadFile(
          bucketId: 'report-images',
          storagePath: path,
          fileBytes: _onePixelPng,
          upsert: true,
        ),
        throwsA(isA<aw.AppwriteException>()),
      );
    });

    test('an avatar can be replaced by its owner', () async {
      // The one bucket the app upserts into: `ProfileProvider` replaces
      // the avatar in place, so `profile-images` carries per-file
      // `update`/`delete` for the uploader.
      final path = '$liveUserId/avatar_$stamp.jpg';
      final first = await backend.uploadFile(
        bucketId: 'profile-images',
        storagePath: path,
        fileBytes: _onePixelPng,
      );
      cleanup.add(
        () => backend.deleteFile(bucketId: 'profile-images', storagePath: path),
      );
      expect(first, contains('/view'));

      await expectLater(
        backend.uploadFile(
          bucketId: 'profile-images',
          storagePath: path,
          fileBytes: _onePixelPng,
        ),
        throwsA(isA<aw.AppwriteException>()),
        reason: 'still refused without an explicit overwrite',
      );

      final replaced = await backend.uploadFile(
        bucketId: 'profile-images',
        storagePath: path,
        fileBytes: _onePixelPng,
        upsert: true,
      );
      expect(replaced, contains('/view'));
      final fetched = await HttpClient()
          .getUrl(Uri.parse(replaced))
          .then((r) => r.close());
      expect(fetched.statusCode, 200);
    });

    test('a thumbnail is reachable from the photo URL alone', () async {
      // The whole point of deriving rather than storing: display code
      // has the stored URL and nothing else.
      final path = '$liveUserId/thumbed_$stamp.jpg';
      final file = File(
        '${Directory.systemTemp.createTempSync('thumb').path}/p.png',
      )..writeAsBytesSync(_onePixelPng);
      addTearDown(() => file.parent.deleteSync(recursive: true));

      final photo = await backend.uploadFile(
        bucketId: 'report-images',
        storagePath: path,
        fileBytes: _onePixelPng,
      );
      cleanup.add(
        () => backend.deleteFile(bucketId: 'report-images', storagePath: path),
      );

      final thumbUrl = backend.thumbUrlFor(photo);
      expect(thumbUrl, isNotNull);
      expect(thumbUrl, isNot(photo));

      // Before the thumbnail exists the derived URL 404s, which is what
      // the image widget's fallback is for.
      expect(await _statusOf(thumbUrl!), 404);

      await backend.uploadThumbnailFromPath(
        bucketId: 'report-images',
        storagePath: path,
        file: file,
      );
      // Not cleaned up: `deleteFile` takes a storage path and derives
      // the id from it, and a thumbnail's id is derived from its
      // photo's, so no path names it. Nothing in the app deletes
      // evidence either, and this bucket grants no `delete` at all.

      // ...and afterwards the same derived URL serves it.
      expect(await _statusOf(thumbUrl), 200);
    });

    test('a /preview URL serves a smaller render', () async {
      // `displayUrl` is off unless APPWRITE_IMAGE_TRANSFORMS is set,
      // because transformations are plan-gated on Cloud. The URL it
      // would produce is checked here against a server that has them,
      // so the shape is known good when it is switched on.
      final path = '$liveUserId/preview_$stamp.jpg';
      final photo = await backend.uploadFile(
        bucketId: 'report-images',
        storagePath: path,
        fileBytes: _onePixelPng,
      );
      cleanup.add(
        () => backend.deleteFile(bucketId: 'report-images', storagePath: path),
      );

      final preview = AppwriteDataBackend.previewUrlFor(
        photo,
        width: 64,
        quality: 60,
      );
      expect(preview, contains('/preview?'));
      expect(preview, contains('project='), reason: '/preview needs it too');
      expect(await _statusOf(preview), 200);
    });

    test('a file id is derived from the whole path, not its tail', () async {
      // Two agents whose ids end alike must not collide; Phase 9's bug.
      final a = AppwriteDataBackend.fileIdFor(
        'aaaaaaaa-dead-beef-cafe-000000000001/report_$stamp.jpg',
      );
      final b = AppwriteDataBackend.fileIdFor(
        'bbbbbbbb-dead-beef-cafe-000000000001/report_$stamp.jpg',
      );
      expect(a, isNot(b));
      expect(a.length, lessThanOrEqualTo(36));
    });
  });

  // These were skipped for a long time, and the reason was real: both
  // run the adapter's `_execute`, which used to parse the SDK's
  // `Execution` model. SDK 26 replaced that model's `functionId` with
  // `resourceId` and `resourceType` once executions grew to cover
  // sites, and it reads them with `map['...']!` — so against a server
  // below 2.0, which answers with the old shape, `Execution.fromMap`
  // throws `Bad state: No element` before the response body is ever
  // read. Nothing in this repository was at fault, and nothing in this
  // repository could run.
  //
  // Waiting for Cloud was the wrong answer. The app does not only
  // target Cloud — the whole point of `infra/appwrite/local` is that it
  // can be self-hosted — and a client that cannot call a Function on
  // the server the project ships a compose file for is broken, not
  // blocked. `appwrite_execution.dart` reads the three fields the
  // adapter actually wants out of the execution the server sent, and
  // every server since 1.x has all three.
  group('callOperation', () {
    test('reopens a report through the operation Function', () async {
      // Somebody else's report, seeded by `prep-dart.mjs`: a reviewer
      // may not decide their own, so one filed here could never reach
      // the operation.
      expect(
        liveForeignReport,
        isNotEmpty,
        reason: 'run prep-dart.mjs; see live_appwrite.dart',
      );

      // Close it first, so reopening is a visible change. This also
      // exercises the adapter's Function routing — `reports` is not
      // client-writable, so the update goes through `write`.
      await backend.updateDocument(
        collectionId: 'reports',
        documentId: liveForeignReport,
        data: {'status': 'approved'},
      );
      final approved = await backend.getDocument(
        collectionId: 'reports',
        documentId: liveForeignReport,
      );
      expect(approved['status'], 'approved');

      await backend.callOperation(
        'reopen_report',
        params: {'p_report_id': liveForeignReport},
      );

      final after = await backend.getDocument(
        collectionId: 'reports',
        documentId: liveForeignReport,
      );
      expect(after['status'], 'pending');
      expect(after['verificationCount'], 0);
      expect(after['escalated'], false);
      expect(
        after['approvedAt'],
        isNull,
        reason: 'the reopen clears the decision it is undoing',
      );
    });

    test('a report that is already pending is refused, not reopened', () async {
      // The Function checks the state before it checks who is asking,
      // so this is the refusal a client can actually reach: a reviewer
      // cannot approve their own report, so they cannot get one of
      // their own into a state where reopening it would be allowed.
      // Who may reopen whose report is covered by the Function's unit
      // tests and by `infra/appwrite/local/e2e-operation.mjs`, which
      // has a key and can set that up.
      final mine = 'op-own-$stamp'.substring(
        0,
        36.clamp(0, 'op-own-$stamp'.length),
      );
      await backend.createDocument(
        collectionId: 'reports',
        documentId: mine,
        data: {
          'hazardType': 'flood',
          'description': 'Filed by the caller',
          'state': 'Benue',
          'lga': 'Makurdi',
          'ward': 'North Bank I',
          'severity': 'high',
        },
      );
      cleanup.add(
        () => backend.deleteDocument(collectionId: 'reports', documentId: mine),
      );

      await expectLater(
        backend.callOperation('reopen_report', params: {'p_report_id': mine}),
        throwsA(
          isA<aw.AppwriteException>().having(
            (e) => e.message,
            'message',
            contains('already pending'),
          ),
        ),
      );
    });

    test('an unknown operation is refused, not silently ignored', () async {
      // Matched on the message, not just the type: while this group was
      // skipped the assertion was `isA<AppwriteException>()` alone, and
      // once it ran again it passed on `Invalid Origin` — a refusal
      // from a different layer entirely, for a request that never
      // reached the Function.
      await expectLater(
        backend.callOperation('drop_everything'),
        throwsA(
          isA<aw.AppwriteException>().having(
            (e) => e.message,
            'message',
            contains('Unknown operation'),
          ),
        ),
      );
    });
  });
}

/// The status of a plain GET, with no credential — which is all
/// `CachedNetworkImage` sends.
Future<int> _statusOf(String url) async {
  final response = await HttpClient()
      .getUrl(Uri.parse(url))
      .then((r) => r.close());
  await response.drain<void>();
  return response.statusCode;
}

/// Polls until [done], or fails naming what was waited for.
Future<void> _until(bool Function() done, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}

/// A 1x1 transparent PNG.
final List<int> _onePixelPng = [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];
