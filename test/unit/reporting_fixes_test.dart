import 'dart:async';
import 'dart:io';

import 'package:climate_app/core/constants/hazards.dart';
import 'package:climate_app/core/data/mvp_locations_data.dart';
import 'package:climate_app/core/services/offline_storage_service.dart';
import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:climate_app/core/l10n/l10n.dart';

void main() {
  group('Hazard metadata', () {
    test('stored names resolve to themselves', () {
      for (final h in Hazard.values) {
        expect(Hazard.tryParse(h.storedName), h);
        expect(Hazard.canonicalName(h.storedName), h.storedName);
      }
    });

    test('legacy aliases resolve to the stored hazard', () {
      expect(Hazard.tryParse('flood'), Hazard.flooding);
      expect(Hazard.tryParse('Wildfire'), Hazard.wildfires);
      expect(Hazard.tryParse('Extreme Heat'), Hazard.extremeTemperatures);
      expect(Hazard.tryParse('high winds'), Hazard.windstorms);
      expect(Hazard.canonicalName('Extreme Heat'), 'Extreme Temperatures');
    });

    test('unknown hazards fall back gracefully', () {
      expect(Hazard.tryParse('Meteor'), isNull);
      expect(Hazard.labelFor('Meteor', englishL10n), 'Meteor');
      expect(Hazard.labelFor(null, englishL10n), 'Unknown Hazard');
    });

    test('high and medium severity colours differ', () {
      expect(
        SeverityColors.nameFor('high'),
        isNot(SeverityColors.nameFor('medium')),
      );
      expect(
        SeverityColors.fromName(SeverityColors.nameFor('high')),
        isNot(SeverityColors.fromName(SeverityColors.nameFor('medium'))),
      );
    });
  });

  group('CSV export', () {
    test('escapes commas, quotes and newlines (RFC 4180)', () {
      expect(ReportsStatusProvider.csvEscape('plain'), 'plain');
      expect(ReportsStatusProvider.csvEscape('a,b'), '"a,b"');
      expect(ReportsStatusProvider.csvEscape('say "hi"'), '"say ""hi"""');
      expect(ReportsStatusProvider.csvEscape('line1\nline2'), '"line1\nline2"');
      expect(ReportsStatusProvider.csvEscape(null), '');
      expect(ReportsStatusProvider.csvEscape(-7.5), '-7.5');
    });

    test('neutralises spreadsheet formulas', () {
      expect(
        ReportsStatusProvider.csvEscape('=HYPERLINK(1)'),
        "'=HYPERLINK(1)",
      );
    });

    test('builds one CRLF-terminated row per report', () {
      final csv = ReportsStatusProvider.buildCsv([
        {
          'id': 'r1',
          'hazardType': 'flood',
          'severity': 'High Severity',
          'status': 'pending',
          'submittedAt': '2026-09-25T10:30:00Z',
          'lga': 'Makurdi',
          'description': 'Water, everywhere',
          'latitude': null,
        },
      ]);
      final lines = csv.split('\r\n');
      expect(lines.first, startsWith('ID,Hazard,Severity,Status'));
      expect(lines[1], startsWith('r1,Flooding,high,pending,2026-09-25T10:30'));
      expect(lines[1], contains('"Water, everywhere"'));
      expect(csv.endsWith('\r\n'), isTrue);
    });
  });

  group('State-aware location lookups', () {
    test('Obi exists in two states and is ambiguous without a state', () {
      expect(
        MVPLocationsData.getStatesForLGA('Obi'),
        containsAll(['Benue', 'Nasarawa']),
      );
      expect(MVPLocationsData.isAmbiguousLGA('Obi'), isTrue);
      expect(MVPLocationsData.resolveStateForLGA('Obi'), isNull);
      expect(
        MVPLocationsData.resolveStateForLGA('Obi', preferredState: 'Nasarawa'),
        'Nasarawa',
      );
    });

    test('wards differ by state for the same LGA name', () {
      final benue = MVPLocationsData.getWardsForLGA('Obi', state: 'Benue');
      final nasarawa = MVPLocationsData.getWardsForLGA(
        'Obi',
        state: 'Nasarawa',
      );
      expect(benue, isNotEmpty);
      expect(nasarawa, isNotEmpty);
      expect(benue, isNot(equals(nasarawa)));
      expect(nasarawa, contains('Agwatashi'));
    });

    test('unambiguous LGAs still resolve without a state', () {
      expect(MVPLocationsData.resolveStateForLGA('Makurdi'), 'Benue');
      expect(MVPLocationsData.getWardsForLGA('Makurdi'), isNotEmpty);
      expect(MVPLocationsData.resolveStateForLGA('Nowhere'), isNull);
    });
  });

  group('Offline queue error policy', () {
    test('connectivity failures are transient', () {
      expect(isTransientNetworkError(const SocketException('x')), isTrue);
      expect(isTransientNetworkError(TimeoutException('x')), isTrue);
      expect(isTransientNetworkError(http.ClientException('x')), isTrue);
    });

    test('server refusals are permanent, not transient', () {
      for (final code in ['42501', '23514', '23502', '22P02']) {
        final e = PostgrestException(message: 'no', code: code);
        expect(isPermanentSyncError(e), isTrue, reason: code);
        expect(isTransientNetworkError(e), isFalse, reason: code);
      }
      expect(
        isPermanentSyncError(const PostgrestException(message: 'x')),
        isFalse,
      );
    });

    test('terminal failures are detected', () {
      expect(
        OfflineStorageService.isTerminalFailure({
          'status': OfflineStorageService.statusRejected,
        }),
        isTrue,
      );
      expect(
        OfflineStorageService.isTerminalFailure({
          'status': 'failed',
          'retryCount': OfflineStorageService.maxSyncAttempts,
        }),
        isTrue,
      );
      expect(
        OfflineStorageService.isTerminalFailure({
          'status': 'failed',
          'retryCount': 1,
        }),
        isFalse,
      );
    });

    test('OfflineQueuedException carries a user message', () {
      const e = OfflineQueuedException();
      expect(e.message(englishL10n), isNotEmpty);
      expect(e.toString(), e.message(englishL10n));
    });
  });
}
