import 'dart:async';
import 'dart:io';

import 'package:climate_app/core/data/nigeria_locations_data.dart';
import 'package:climate_app/core/services/geolocation_service.dart';
import 'package:climate_app/core/services/news_service.dart';
import 'package:climate_app/core/services/offline_storage_service.dart';
import 'package:climate_app/core/utils/input_sanitizer.dart';
import 'package:climate_app/features/contacts/models/emergency_contact_model.dart';
import 'package:climate_app/features/knowledge_base/knowledge_categories.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:climate_app/core/l10n/l10n.dart';

Position _pos(double lat, double lng) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime(2026),
  accuracy: 5,
  altitude: 0,
  heading: 0,
  speed: 0,
  speedAccuracy: 0,
  altitudeAccuracy: 0,
  headingAccuracy: 0,
);

void main() {
  group('InputSanitizer.cleanForStorage', () {
    test('keeps quotes, ampersands and slashes as typed (no escaping)', () {
      expect(
        InputSanitizer.cleanForStorage(
          "  Water didn't recede & roads <closed> 1/2 \"now\" ",
        ),
        "Water didn't recede & roads <closed> 1/2 \"now\"",
      );
    });

    test('collapses whitespace and strips control characters', () {
      expect(InputSanitizer.cleanForStorage('a\u0000b \t\n  c\u007F'), 'ab c');
    });

    test('preserveNewlines keeps line breaks, trims each line', () {
      expect(
        InputSanitizer.cleanForStorage(
          ' line 1  \r\n\r\n\r\n\n  line   2 ',
          preserveNewlines: true,
        ),
        'line 1\n\nline 2',
      );
    });

    test('enforces maxLength', () {
      expect(
        InputSanitizer.cleanForStorage('x' * 600, maxLength: 500).length,
        500,
      );
    });
  });

  group('NigeriaLocationsData lookups are null-safe', () {
    test('blank or unknown state yields no LGAs instead of throwing', () {
      expect(NigeriaLocationsData.getLGAsForState(''), isEmpty);
      expect(NigeriaLocationsData.getLGAsForState('Atlantis'), isEmpty);
      expect(NigeriaLocationsData.isValidLGA('', 'Jos North'), isFalse);
      expect(NigeriaLocationsData.isValidLGA('Atlantis', 'X'), isFalse);
      expect(NigeriaLocationsData.isValidState(''), isFalse);
    });

    test('known state still resolves', () {
      expect(NigeriaLocationsData.getLGAsForState('Plateau'), isNotEmpty);
      expect(NigeriaLocationsData.isValidState('Plateau'), isTrue);
    });
  });

  test('EmergencyContact.toMap always includes organization and lga', () {
    final map = EmergencyContact(
      id: '1',
      name: 'A',
      role: 'r',
      phone: '112',
      category: 'other',
    ).toMap();
    expect(map.containsKey('organization'), isTrue);
    expect(map['organization'], isNull);
    expect(map.containsKey('lga'), isTrue);
    expect(map['lga'], isNull);
  });

  group('sync queue retry accounting', () {
    test('transient network errors do not consume a retry', () {
      expect(
        OfflineStorageService.failureCountsAsRetry(
          const SocketException('offline'),
        ),
        isFalse,
      );
      expect(
        OfflineStorageService.failureCountsAsRetry(TimeoutException('t')),
        isFalse,
      );
      expect(
        OfflineStorageService.failureCountsAsRetry(Exception('server 500')),
        isTrue,
      );
      expect(OfflineStorageService.nextRetryCount(2, countsAsRetry: false), 2);
      expect(OfflineStorageService.nextRetryCount(2, countsAsRetry: true), 3);
    });
  });

  group('NewsService.mapReliefWebItem', () {
    test('links to the public page URL, not the API href', () {
      final item = NewsService.mapReliefWebItem({
        'id': 1,
        'href': 'https://api.reliefweb.int/v1/reports/1',
        'fields': {
          'title': 'Floods',
          'url': 'https://reliefweb.int/report/nigeria/floods',
          'date': {'created': '2026-09-01T10:00:00+00:00'},
          'source': [
            {'name': 'OCHA'},
          ],
        },
      });
      expect(item['url'], 'https://reliefweb.int/report/nigeria/floods');
      expect(item['source'], 'OCHA');
      expect(item['date'], '2026-09-01T10:00:00+00:00');
    });

    test('falls back to href when the page URL is missing', () {
      final item = NewsService.mapReliefWebItem({
        'id': 2,
        'href': 'https://api.reliefweb.int/v1/reports/2',
        'fields': {'title': 'T'},
      });
      expect(item['url'], 'https://api.reliefweb.int/v1/reports/2');
      expect(item['source'], 'ReliefWeb');
      expect(item['date'], '');
    });
  });

  group('formatKnowledgeDate', () {
    test('formats ISO strings and DateTimes as local d MMM yyyy', () {
      final utc = DateTime.utc(2026, 3, 5, 12);
      final expected = DateFormat('d MMM yyyy').format(utc.toLocal());
      expect(formatKnowledgeDate(utc.toIso8601String()), expected);
      expect(formatKnowledgeDate(utc), expected);
    });

    test('keeps free text and ignores empty values', () {
      expect(formatKnowledgeDate('March 2026'), 'March 2026');
      expect(formatKnowledgeDate(''), isNull);
      expect(formatKnowledgeDate(null), isNull);
    });
  });

  group('GeolocationService.fetchPositionWithFallback', () {
    test('returns a fresh fix without a message', () async {
      final service = GeolocationService();
      final p = await service.fetchPositionWithFallback(
        current: () async => _pos(9.9, 8.9),
        lastKnown: () async => null,
      );
      expect(p!.latitude, 9.9);
      expect(service.lastErrorMessage, isNull);
    });

    test('falls back to the last known position on timeout', () async {
      final service = GeolocationService();
      final p = await service.fetchPositionWithFallback(
        current: () async => throw TimeoutException('no fix'),
        lastKnown: () async => _pos(1, 2),
      );
      expect(p!.latitude, 1);
      expect(service.lastErrorMessage!(englishL10n), contains('last known'));
    });

    test(
      'returns null with a clear message when nothing is available',
      () async {
        final service = GeolocationService();
        final p = await service.fetchPositionWithFallback(
          current: () async => throw TimeoutException('no fix'),
          lastKnown: () async => null,
        );
        expect(p, isNull);
        expect(service.lastErrorMessage!(englishL10n), contains('Timed out'));
      },
    );
  });

  group('ReportingProvider', () {
    test('clamps a future incident time to now', () {
      final provider = ReportingProvider();
      provider.setReportDateTime(DateTime.now().add(const Duration(hours: 3)));
      expect(
        provider.reportDateTime.isAfter(
          DateTime.now().add(const Duration(seconds: 1)),
        ),
        isFalse,
      );
      final past = DateTime.now().subtract(const Duration(days: 1));
      provider.setReportDateTime(past);
      expect(provider.reportDateTime, past);
    });

    test('tracks approximate coordinates and clears them', () {
      final provider = ReportingProvider();
      provider.setLocation(9.1, 8.7, approximate: true);
      expect(provider.locationIsApproximate, isTrue);
      provider.setLocation(9.2, 8.8);
      expect(provider.locationIsApproximate, isFalse);
      provider.clearLocation();
      expect(provider.latitude, isNull);
      expect(provider.longitude, isNull);
    });
  });
}
