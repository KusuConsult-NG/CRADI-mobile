import 'package:climate_app/core/constants/hazards.dart';
import 'package:climate_app/core/l10n/l10n.dart';
import 'package:climate_app/features/admin/screens/admin_users_screen.dart';
import 'package:climate_app/features/alerts/screens/alerts_list_screen.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/knowledge_base/knowledge_categories.dart';
import 'package:climate_app/features/verification/models/verification_report_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

VerificationReport _report(String hazard, {String id = 'r'}) =>
    VerificationReport.fromMap({'hazardType': hazard, 'status': 'pending'}, id);

void main() {
  group('Alerts hazard filter', () {
    test('every hazard filters its own reports, legacy spellings included', () {
      final reports = [
        for (final h in Hazard.values) _report(h.storedName, id: h.name),
        _report('Floods', id: 'legacy-flood'),
        _report('Pest/Disease', id: 'legacy-pest'),
        _report('Heatwave', id: 'legacy-heat'),
        _report('Something else', id: 'unknown'),
      ];
      for (final h in Hazard.values) {
        final ids = filterReportsByHazard(reports, {h}).map((r) => r.id);
        expect(ids, contains(h.name), reason: h.name);
        for (final other in Hazard.values.where((o) => o != h)) {
          expect(ids, isNot(contains(other.name)), reason: '$h vs $other');
        }
      }
      expect(
        filterReportsByHazard(reports, {Hazard.flooding}).map((r) => r.id),
        containsAll(['flooding', 'legacy-flood']),
      );
      expect(
        filterReportsByHazard(reports, {
          Hazard.extremeTemperatures,
        }).map((r) => r.id),
        containsAll(['extremeTemperatures', 'legacy-heat']),
      );
      // Crop disease is no longer dropped by a "pest" substring match.
      expect(
        filterReportsByHazard(reports, {Hazard.cropDisease}).map((r) => r.id),
        ['cropDisease'],
      );
      expect(filterReportsByHazard(reports, const {}), hasLength(13));
    });

    test('category ids from other screens map to hazards', () {
      for (final h in Hazard.values) {
        expect(alertHazardsForCategory(h.storedName), {h});
      }
      expect(alertHazardsForCategory('Floods'), {Hazard.flooding});
      expect(alertHazardsForCategory('Flooding'), {Hazard.flooding});
      expect(alertHazardsForCategory('Pest/Disease'), {
        Hazard.pestOutbreak,
        Hazard.cropDisease,
      });
      expect(alertHazardsForCategory(null), isEmpty);
      expect(alertHazardsForCategory('All Alerts'), isEmpty);
    });
  });

  group('Safety guides category per hazard', () {
    const expected = {
      Hazard.flooding: 'flood',
      Hazard.extremeTemperatures: 'extreme_heat',
      Hazard.drought: 'extreme_heat',
      Hazard.windstorms: 'storm',
      Hazard.wildfires: 'fire',
      Hazard.erosion: 'erosion',
      Hazard.pestOutbreak: 'disease',
      Hazard.cropDisease: 'disease',
      Hazard.conflict: 'conflict',
    };

    test('knowledgeCategoryFor resolves all 9 hazards', () {
      expect(expected.keys, containsAll(Hazard.values));
      for (final h in Hazard.values) {
        final category = knowledgeCategoryFor(h.storedName);
        expect(category?.hazardType, expected[h], reason: h.storedName);
        // HazardGuidesScreen selects the tab by the category label.
        expect(knowledgeCategoryFilters, contains(category!.label));
      }
      expect(
        knowledgeCategoryFor('Extreme Temperature')?.hazardType,
        'extreme_heat',
      );
    });
  });

  group('Verification requests', () {
    test('row kind is kept separately from the hazard', () {
      final r = VerificationReport.fromMap({
        'hazardType': 'Flooding',
        'type': 'verification_request',
        'locationDetails': 'Verification Request',
      }, 'id1');
      expect(r.type, 'Flooding');
      expect(r.reportType, VerificationReport.verificationRequestType);
      expect(r.isVerificationRequest, isTrue);
      // Survives the provider's display overrides and the offline cache.
      final copy = r.copyWith(type: 'Flooding', location: r.location);
      expect(copy.isVerificationRequest, isTrue);
      final cached = VerificationReport.fromMap(r.toJson(), 'id1');
      expect(cached.type, 'Flooding');
      expect(cached.isVerificationRequest, isTrue);
    });

    test('stored placeholder location is shown localised', () {
      final r = VerificationReport.fromMap({
        'hazardType': 'Drought',
        'type': 'verification_request',
        'locationDetails': 'Verification Request',
      }, 'id2');
      expect(r.location, 'Verification Request');
      expect(
        r.displayLocation(englishL10n),
        englishL10n.verificationRequestBadge,
      );
      final ordinary = VerificationReport.fromMap({
        'hazardType': 'Drought',
        'locationDetails': 'Main market',
      }, 'id3');
      expect(ordinary.isVerificationRequest, isFalse);
      expect(ordinary.displayLocation(englishL10n), 'Main market');
    });

    test('request route roles are reachable from the verification list', () {
      expect(
        AuthProvider.verifierRoles,
        containsAll(AuthProvider.verificationRequestRoles),
      );
      expect(
        AuthProvider.verificationRequestRoles,
        isNot(contains(UserRole.techSupport)),
      );
    });
  });

  group('Admin approval errors', () {
    test('unconfirmed-account refusal gets its own message', () {
      const refused = PostgrestException(
        message:
            'This account has not confirmed its email or phone yet, so it '
            'cannot be approved',
        code: '42501',
      );
      expect(isUnconfirmedApprovalError(refused), isTrue);
      expect(
        adminUserWriteErrorMessage(refused, englishL10n),
        englishL10n.adminUsersApproveUnconfirmed,
      );
      const rls = PostgrestException(
        message: 'permission denied for table profiles',
        code: '42501',
      );
      expect(
        adminUserWriteErrorMessage(rls, englishL10n),
        englishL10n.adminUsersNoPermission,
      );
      expect(
        adminUserWriteErrorMessage(Exception('boom'), englishL10n),
        englishL10n.adminUsersUpdateFailed,
      );
    });
  });
}
