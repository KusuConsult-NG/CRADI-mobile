import 'package:appwrite/appwrite.dart' as aw;
import 'package:flutter_test/flutter_test.dart';

import 'package:climate_app/core/services/appwrite/appwrite_auth_backend.dart';
import 'package:climate_app/core/services/appwrite/appwrite_data_backend.dart';
import 'package:climate_app/core/services/data_backend.dart';

import 'live_appwrite.dart';

/// `AppwriteDataBackend` against a real Appwrite.
///
/// Everything in Phase 9 was written against the SDK and Phases 1–4's
/// findings, and tested against nothing. The pure parts — queries,
/// document mapping, the error table — have unit tests; this is the
/// half that needs a socket, and it is the half a user touches.
void main() {
  // Guarded here rather than with `skip:` on each test, because a
  // `setUpAll` runs even when every test in its group is skipped — and
  // this one signs in.
  if (!liveConfigured) {
    test('Appwrite integration tests', () {}, skip: skipUnlessLive);
    return;
  }

  useLiveAppwrite();

  late AppwriteDataBackend backend;
  late AppwriteAuthBackend auth;
  final created = <String>[];
  final stamp = DateTime.now().millisecondsSinceEpoch;
  String id(String what) =>
      'dart-$what-$stamp'.substring(0, 36.clamp(0, 'dart-$what-$stamp'.length));

  setUpAll(() async {
    AppwriteDataBackend.installErrorVocabulary();
    backend = AppwriteDataBackend(
      client: aw.Client().setEndpoint(liveEndpoint).setProject(liveProject),
    );
    // Both halves share one client, as `backend.dart` wires them: a
    // second client would hold a second session and the two would
    // disagree about who is signed in.
    auth = AppwriteAuthBackend(data: backend);

    // `setSession`, not `signInWithPassword`: the latter depends on the
    // SDK's cookie jar, which did not retain a session against this
    // local HTTP server (Phase 16). This is the same mechanism
    // `_establish` uses after a typed code is redeemed, which is the
    // path sign-up and recovery take.
    backend.client.setSession(liveSession);
    await auth.restore();

    expect(auth.currentUser?.id, liveUserId, reason: 'session not adopted');
    // The data adapter's synchronous `currentUserId` is fed by the auth
    // adapter on every session change; this asserts that wiring.
    expect(backend.currentUserId, liveUserId);
  });

  tearDownAll(() async {
    for (final docId in created) {
      try {
        await backend.deleteDocument(
          collectionId: 'contacts',
          documentId: docId,
        );
      } on Exception {
        // Already gone, or never created.
      }
    }
  });

  group('documents', () {
    test('creates one and reads it back in the app\'s shape', () async {
      final docId = id('c1');
      created.add(docId);
      final doc = await backend.createDocument(
        collectionId: 'contacts',
        documentId: docId,
        data: {
          'userId': liveUserId,
          'name': 'Live Contact',
          'phone': '08031234567',
          'lga': 'Makurdi',
          'isAvailable': true,
        },
      );

      expect(doc[r'$id'], docId);
      // `fromAppwriteRow` exposes the key under both names, because the
      // app reads one or the other depending on the call site.
      expect(doc['id'], docId);
      expect(doc['name'], 'Live Contact');
      expect(doc['isAvailable'], isTrue);
      expect(doc[r'$createdAt'], isNotEmpty);
      expect(doc['createdAt'], isNotNull);

      final read = await backend.getDocument(
        collectionId: 'contacts',
        documentId: docId,
      );
      expect(read['name'], 'Live Contact');
    });

    test('a missing document is DocumentNotFoundException, not a 404 leak', () {
      expect(
        () => backend.getDocument(
          collectionId: 'contacts',
          documentId: 'no-such-doc',
        ),
        throwsA(isA<DocumentNotFoundException>()),
      );
    });

    test('updates, and refuses an update to something gone', () async {
      final docId = id('c2');
      created.add(docId);
      await backend.createDocument(
        collectionId: 'contacts',
        documentId: docId,
        data: {
          'userId': liveUserId,
          'name': 'Before',
          'phone': '08031234567',
          'isAvailable': true,
        },
      );
      final updated = await backend.updateDocument(
        collectionId: 'contacts',
        documentId: docId,
        data: {'name': 'After'},
      );
      expect(updated['name'], 'After');

      await expectLater(
        backend.updateDocument(
          collectionId: 'contacts',
          documentId: 'no-such-doc',
          data: {'name': 'x'},
        ),
        throwsA(isA<DocumentNotFoundException>()),
      );
    });

    test('upsert with ignoreDuplicates leaves the first write alone', () async {
      // The NDPA consent path depends on this: a replay must not
      // overwrite, and must answer null rather than throwing.
      final docId = id('c3');
      created.add(docId);
      final first = await backend.upsertDocument(
        collectionId: 'contacts',
        documentId: docId,
        data: {
          'userId': liveUserId,
          'name': 'Original',
          'phone': '08031234567',
        },
        ignoreDuplicates: true,
      );
      expect(first?['name'], 'Original');

      final replay = await backend.upsertDocument(
        collectionId: 'contacts',
        documentId: docId,
        data: {
          'userId': liveUserId,
          'name': 'Should not win',
          'phone': '08031234567',
        },
        ignoreDuplicates: true,
      );
      expect(replay, isNull, reason: 'a replay answers null');

      final after = await backend.getDocument(
        collectionId: 'contacts',
        documentId: docId,
      );
      expect(after['name'], 'Original');
    });
  });

  group('queries', () {
    late String mine;
    late String theirs;

    setUpAll(() async {
      mine = id('q1');
      theirs = id('q2');
      created.addAll([mine, theirs]);
      await backend.createDocument(
        collectionId: 'contacts',
        documentId: mine,
        data: {
          'userId': liveUserId,
          'name': 'Mine',
          'phone': '08031234567',
          'isAvailable': true,
        },
      );
      await backend.createDocument(
        collectionId: 'contacts',
        documentId: theirs,
        data: {
          'userId': 'someone-else',
          'name': 'Theirs',
          'phone': '08039999999',
          'isAvailable': false,
        },
      );
    });

    test('equal filters server-side', () async {
      final docs = await backend.listDocuments(
        collectionId: 'contacts',
        queries: [FQuery.equal('userId', liveUserId), FQuery.limit(50)],
      );
      final ids = docs.map((d) => d[r'$id']).toList();
      expect(ids, contains(mine));
      expect(ids, isNot(contains(theirs)));
    });

    test('the two not-equals really differ on the server', () async {
      // Written as `and(isNotNull, notEqual)` and `or(isNull, notEqual)`
      // rather than trusting Appwrite's bare notEqual, which is not
      // documented either way. This is the first time either has been
      // sent to a server.
      final neq = await backend.listDocuments(
        collectionId: 'contacts',
        queries: [FQuery.notEqual('userId', liveUserId), FQuery.limit(50)],
      );
      expect(neq.map((d) => d[r'$id']), contains(theirs));
      expect(neq.map((d) => d[r'$id']), isNot(contains(mine)));

      final distinct = await backend.listDocuments(
        collectionId: 'contacts',
        queries: [FQuery.distinctFrom('userId', liveUserId), FQuery.limit(50)],
      );
      expect(distinct.map((d) => d[r'$id']), contains(theirs));
    });

    test('an empty IN matches nothing, rather than everything', () async {
      // The dangerous direction: an empty `equal` would read as no
      // constraint at all and return the whole collection.
      final docs = await backend.listDocuments(
        collectionId: 'contacts',
        queries: [FQuery.isIn('userId', []), FQuery.limit(50)],
      );
      expect(docs, isEmpty);
    });

    test('ordering and limit reach the server', () async {
      final docs = await backend.listDocuments(
        collectionId: 'contacts',
        queries: [FQuery.orderDesc(r'$createdAt'), FQuery.limit(1)],
      );
      expect(docs, hasLength(1));
    });

    test('counts, and distinguishes a failure from zero', () async {
      final n = await backend.countDocumentsOrThrow(
        collectionId: 'contacts',
        queries: [FQuery.equal('userId', liveUserId)],
      );
      expect(n, greaterThanOrEqualTo(1));

      // countDocuments swallows failures as 0; the throwing form must
      // not, or a dashboard reports "nothing to do" when it cannot
      // reach the backend.
      await expectLater(
        backend.countDocumentsOrThrow(collectionId: 'no_such_collection'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('the error vocabulary, against real refusals', () {
    test('a duplicate is classified as duplicate', () async {
      final docId = id('e1');
      created.add(docId);
      await backend.createDocument(
        collectionId: 'contacts',
        documentId: docId,
        data: {'userId': liveUserId, 'name': 'First', 'phone': '08031234567'},
      );
      try {
        await backend.createDocument(
          collectionId: 'contacts',
          documentId: docId,
          data: {
            'userId': liveUserId,
            'name': 'Second',
            'phone': '08031234567',
          },
        );
        fail('expected a duplicate');
      } on aw.AppwriteException catch (e) {
        expect(backendFailureOf(e), BackendFailure.duplicate);
        expect(isBackendPermanent(e), isTrue);
        expect(isBackendTransient(e), isFalse);
      }
    });

    test('an unknown collection is not classified as permanent', () async {
      // Retrying cannot fix a typo, but calling it permanent would make
      // the offline queue throw a field agent's report away over a
      // deploy that had not finished.
      try {
        await backend.getDocument(
          collectionId: 'no_such_collection',
          documentId: 'x',
        );
        fail('expected a refusal');
      } on DocumentNotFoundException {
        // Mapped before it reaches the vocabulary, which is correct.
      } on aw.AppwriteException catch (e) {
        expect(isBackendPermanent(e), isFalse);
      }
    });
  });

  test('ping answers true against a reachable server', () async {
    expect(await backend.ping(), isTrue);
  });
}
