import 'package:flutter_test/flutter_test.dart';

/// Light-weight tests for the monitoring zone filter logic.
///
/// The actual filter runs inside ReportsStatusProvider.fetchReports() which
/// depends on Firestore. Here we test the pure-function logic that decides
/// whether a report passes the monitoring zone check.
void main() {
  group('Monitoring Zone Filter Logic', () {
    // Reproduce the filter logic from reports_status_provider.dart
    bool passesZoneFilter(
      Map<String, dynamic> report,
      String? monitoringZone,
    ) {
      if (monitoringZone == null || monitoringZone.isEmpty) return true;

      if (monitoringZone.contains(', ')) {
        // LGA format: "Makurdi, Benue"
        final parts = monitoringZone.split(', ');
        final lga = parts[0];
        return report['lga']?.toString().toLowerCase() == lga.toLowerCase();
      } else if (monitoringZone.endsWith(' State')) {
        // State format: "Benue State"
        final state = monitoringZone.replaceAll(' State', '');
        return report['state']?.toString().toLowerCase() == state.toLowerCase();
      }
      return true; // Unknown format — don't filter
    }

    test('null zone passes all reports', () {
      final report = {'state': 'Benue', 'lga': 'Makurdi'};
      expect(passesZoneFilter(report, null), isTrue);
    });

    test('empty zone passes all reports', () {
      final report = {'state': 'Benue', 'lga': 'Makurdi'};
      expect(passesZoneFilter(report, ''), isTrue);
    });

    test('state filter matches correct state', () {
      final report = {'state': 'Benue', 'lga': 'Makurdi'};
      expect(passesZoneFilter(report, 'Benue State'), isTrue);
    });

    test('state filter rejects wrong state', () {
      final report = {'state': 'Nasarawa', 'lga': 'Karu'};
      expect(passesZoneFilter(report, 'Benue State'), isFalse);
    });

    test('LGA filter matches correct LGA', () {
      final report = {'state': 'Benue', 'lga': 'Makurdi'};
      expect(passesZoneFilter(report, 'Makurdi, Benue'), isTrue);
    });

    test('LGA filter rejects wrong LGA', () {
      final report = {'state': 'Benue', 'lga': 'Gboko'};
      expect(passesZoneFilter(report, 'Makurdi, Benue'), isFalse);
    });

    test('LGA filter is case-insensitive', () {
      final report = {'state': 'Benue', 'lga': 'makurdi'};
      expect(passesZoneFilter(report, 'Makurdi, Benue'), isTrue);
    });

    test('state filter is case-insensitive', () {
      final report = {'state': 'benue', 'lga': 'Makurdi'};
      expect(passesZoneFilter(report, 'Benue State'), isTrue);
    });

    test('report with missing lga field fails LGA filter', () {
      final report = <String, dynamic>{'state': 'Benue'};
      expect(passesZoneFilter(report, 'Makurdi, Benue'), isFalse);
    });

    test('report with missing state field fails state filter', () {
      final report = <String, dynamic>{'lga': 'Makurdi'};
      expect(passesZoneFilter(report, 'Benue State'), isFalse);
    });

    test('unknown zone format passes all reports', () {
      final report = {'state': 'Benue', 'lga': 'Makurdi'};
      expect(passesZoneFilter(report, 'Benue Zone A'), isTrue);
    });
  });

  group('Offline Sync Queue Data Structure', () {
    // Reproduce the addToSyncQueue wrapping logic
    Map<String, dynamic> wrapForQueue(Map<String, dynamic> input) {
      final docId = input.remove('docId') as String? ??
          DateTime.now().millisecondsSinceEpoch.toString();
      final collection = input.remove('collection') as String?;
      final collectionId = input.remove('collectionId') as String?;

      return {
        'docId': docId,
        if (collection != null) 'collection': collection, // ignore: use_null_aware_elements
        if (collectionId != null) 'collectionId': collectionId, // ignore: use_null_aware_elements
        'data': input,
        'timestamp': DateTime.now().toIso8601String(),
        'retryCount': 0,
      };
    }

    // Reproduce the syncPendingReports unwrapping logic
    Map<String, dynamic>? unwrapFromQueue(Map<String, dynamic> item) {
      return item['data'] as Map<String, dynamic>?;
    }

    String? getCollection(Map<String, dynamic> item) {
      return (item['collection'] ?? item['collectionId']) as String?;
    }

    test('wraps data under "data" key', () {
      final input = {
        'hazardType': 'Flood',
        'severity': 'critical',
        'docId': 'doc123',
        'collection': 'reports',
      };
      final queued = wrapForQueue(input);

      expect(queued['data'], isA<Map<String, dynamic>>());
      expect(queued['data']['hazardType'], equals('Flood'));
      expect(queued['data']['severity'], equals('critical'));
      expect(queued['docId'], equals('doc123'));
      expect(queued['collection'], equals('reports'));
    });

    test('strips meta keys from data', () {
      final input = {
        'hazardType': 'Flood',
        'docId': 'doc123',
        'collection': 'reports',
      };
      final queued = wrapForQueue(input);
      final data = queued['data'] as Map<String, dynamic>;

      expect(data.containsKey('docId'), isFalse);
      expect(data.containsKey('collection'), isFalse);
    });

    test('unwraps data correctly', () {
      final queued = {
        'docId': 'doc123',
        'collection': 'reports',
        'data': {'hazardType': 'Flood'},
        'timestamp': '2026-03-20T00:00:00Z',
        'retryCount': 0,
      };

      final data = unwrapFromQueue(queued);
      expect(data, isNotNull);
      expect(data!['hazardType'], equals('Flood'));
    });

    test('getCollection checks both key names', () {
      expect(getCollection({'collection': 'reports'}), equals('reports'));
      expect(
        getCollection({'collectionId': 'reports'}),
        equals('reports'),
      );
      expect(getCollection({}), isNull);
    });

    test('handles collectionId variant', () {
      final input = {
        'hazardType': 'Flood',
        'docId': 'doc123',
        'collectionId': 'reports',
      };
      final queued = wrapForQueue(input);

      expect(queued['collectionId'], equals('reports'));
      expect(queued['data']['hazardType'], equals('Flood'));
    });

    test('generates docId if not provided', () {
      final input = {'hazardType': 'Flood'};
      final queued = wrapForQueue(input);

      expect(queued['docId'], isNotNull);
      expect(queued['docId'], isA<String>());
    });
  });
}
