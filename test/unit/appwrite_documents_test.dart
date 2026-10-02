import 'package:flutter_test/flutter_test.dart';

import 'package:climate_app/core/services/appwrite/appwrite_data_backend.dart';
import 'package:climate_app/core/services/appwrite/appwrite_documents.dart';

void main() {
  group('a realtime payload becomes an app document', () {
    test('the id is exposed under both names the app reads', () {
      final doc = fromAppwritePayload({
        r'$id': 'r1',
        r'$collectionId': 'reports',
        r'$databaseId': 'cradi',
        r'$permissions': ['read("user:u1")'],
        r'$createdAt': '2026-03-01T09:00:00.000+00:00',
        r'$updatedAt': '2026-03-02T09:00:00.000+00:00',
        'status': 'pending',
      });

      expect(doc[r'$id'], 'r1');
      expect(doc['id'], 'r1');
      expect(doc['status'], 'pending');
      // Appwrite's bookkeeping is not the document's data.
      expect(doc.containsKey(r'$collectionId'), isFalse);
      expect(doc.containsKey(r'$permissions'), isFalse);
    });

    test("a collection's own createdAt is not overwritten by Appwrite's", () {
      // `reports.createdAt` is when the hazard was seen, not when the row
      // was written. Letting the system timestamp win would put the wrong
      // date on an offline report submitted days later, and nothing would
      // flag it.
      final doc = fromAppwritePayload({
        r'$id': 'r1',
        r'$createdAt': '2026-03-05T09:00:00.000+00:00',
        r'$updatedAt': '2026-03-05T09:00:00.000+00:00',
        'createdAt': '2026-03-01T06:30:00.000Z',
      });

      expect(doc['createdAt'], '2026-03-01T06:30:00.000Z');
      expect(doc[r'$createdAt'], '2026-03-05T09:00:00.000+00:00');
    });

    test("and is filled in when the collection has none", () {
      final doc = fromAppwritePayload({
        r'$id': 'c1',
        r'$createdAt': '2026-03-05T09:00:00.000+00:00',
        r'$updatedAt': '2026-03-06T09:00:00.000+00:00',
      });
      expect(doc['createdAt'], '2026-03-05T09:00:00.000+00:00');
      expect(doc['updatedAt'], '2026-03-06T09:00:00.000+00:00');
    });
  });

  group('a write payload drops what Appwrite owns', () {
    test('ids and timestamps are not sent back', () {
      // `$id` goes in the SDK call as `rowId`; sending any of these inside
      // `data` is a 400.
      final data = toAppwriteData({
        r'$id': 'r1',
        'id': 'r1',
        r'$createdAt': 'x',
        r'$updatedAt': 'x',
        r'$permissions': <String>[],
        'status': 'pending',
        'createdAt': '2026-03-01T06:30:00.000Z',
      });

      expect(data.keys, unorderedEquals(['status', 'createdAt']));
    });
  });

  group('storage paths become file ids', () {
    test('the slashes of a path are replaced', () {
      expect(
        AppwriteDataBackend.fileIdFor('u1/report_123.jpg'),
        'u1-report_123.jpg',
      );
    });

    test('a long path is never longer than an Appwrite id', () {
      final id = AppwriteDataBackend.fileIdFor(
        '0199c0de-dead-beef-cafe-000000000001/report_1772539200000.jpg',
      );
      expect(id.length, lessThanOrEqualTo(36));
      expect(id, matches(RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$')));
    });

    test('the same path always gives the same id', () {
      // Re-uploading after a retry must replace the file, not add a
      // second copy — the offline queue retries by path.
      const path = '0199c0de-dead-beef-cafe-000000000001/report_17725392.jpg';
      expect(
        AppwriteDataBackend.fileIdFor(path),
        AppwriteDataBackend.fileIdFor(path),
      );
    });

    test('an id may not begin with a punctuation character', () {
      expect(AppwriteDataBackend.fileIdFor('_leading'), startsWith('f'));
      expect(
        AppwriteDataBackend.fileIdFor('/leading').startsWith(RegExp('[._-]')),
        isFalse,
      );
    });

    test('long paths that differ only near the front still differ', () {
      // The case truncation got wrong: the filename is 24 of the 36
      // characters, so only a tail of the user id would have survived and
      // one agent's photo could overwrite another's.
      final a = AppwriteDataBackend.fileIdFor(
        'aaaaaaaa-dead-beef-cafe-000000000001/report_1772539200000.jpg',
      );
      final b = AppwriteDataBackend.fileIdFor(
        'bbbbbbbb-dead-beef-cafe-000000000001/report_1772539200000.jpg',
      );
      expect(a, isNot(equals(b)));
    });

    test('ids stay distinct across a realistic batch', () {
      final ids = <String>{};
      for (var user = 0; user < 60; user++) {
        for (var n = 0; n < 60; n++) {
          ids.add(
            AppwriteDataBackend.fileIdFor(
              '0199c0de-dead-beef-cafe-${user.toString().padLeft(12, '0')}'
              '/report_177253920${n.toString().padLeft(4, '0')}.jpg',
            ),
          );
        }
      }
      expect(ids, hasLength(3600));
    });
  });
}
