import 'package:flutter_test/flutter_test.dart';

import 'package:climate_app/core/services/offline_storage_service.dart';

/// What the offline queue adds to a queued row before sending it.
///
/// `syncedAt` is a column `reports` has and no other collection does.
/// Appwrite refuses a field a collection has not declared — a 400
/// `document_invalid_structure` — and `isAppwritePermanent` reads that
/// as permanent, which this queue answers by marking the item
/// **rejected**: never retried, and gone unless somebody opens the
/// offline screen. Stamping it unconditionally therefore turned the
/// first queued write of anything but a report into a discarded one,
/// and a field agent's queued work is the only data in this app that
/// cannot be recreated from the server.
void main() {
  group('a queued report', () {
    test('is forced to pending and stamped with the sync time', () {
      final data = <String, dynamic>{
        'status': 'approved',
        'hazardType': 'flood',
      };
      stampForSync('reports', data);

      // The client does not get to choose the status of a new report.
      expect(data['status'], 'pending');
      expect(data['syncedAt'], isA<DateTime>());
      expect(data['hazardType'], 'flood');
    });
  });

  group('a queued row of any other collection', () {
    test('is not given a syncedAt the collection has no column for', () {
      for (final collection in [
        'verifications',
        'contacts',
        'messages',
        'ndpa_consents',
        'login_history',
      ]) {
        final data = <String, dynamic>{'reportId': 'r1'};
        stampForSync(collection, data);
        expect(
          data.containsKey('syncedAt'),
          isFalse,
          reason: '$collection has no syncedAt column',
        );
      }
    });

    test('and is not forced to pending, which is a report’s word', () {
      final data = <String, dynamic>{'isConfirmed': true};
      stampForSync('verifications', data);

      expect(data.containsKey('status'), isFalse);
      expect(data, {'isConfirmed': true});
    });
  });
}
