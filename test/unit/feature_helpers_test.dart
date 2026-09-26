import 'package:climate_app/features/alerts/providers/alerts_provider.dart';
import 'package:climate_app/features/alerts/screens/alert_severity.dart';
import 'package:climate_app/features/contacts/models/emergency_contact_model.dart';
import 'package:climate_app/features/knowledge_base/knowledge_categories.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('alert severity', () {
    test('maps staff severities to colours', () {
      expect(alertSeverityColor('info'), Colors.blue);
      expect(alertSeverityColor('warning'), Colors.orange);
      expect(alertSeverityColor('critical'), Colors.red);
      expect(alertSeverityColor('Critical Severity'), Colors.red);
    });

    test('labels come from the alert severity', () {
      expect(alertSeverityLabel('warning'), 'Warning');
      expect(alertSeverityLabel(null), 'Unspecified severity');
    });
  });

  group('AlertsProvider.targetsLga', () {
    test("'All' reaches everyone", () {
      expect(AlertsProvider.targetsLga({'targetLga': 'All'}, 'Makurdi'), true);
      expect(AlertsProvider.targetsLga({'targetLga': 'All'}, null), true);
      expect(AlertsProvider.targetsLga(const {}, 'Makurdi'), true);
    });

    test('LGA alerts only reach that LGA (case-insensitive)', () {
      final alert = {'targetLga': 'Oturkpo'};
      expect(AlertsProvider.targetsLga(alert, 'oturkpo'), true);
      expect(AlertsProvider.targetsLga(alert, 'Makurdi'), false);
      expect(AlertsProvider.targetsLga(alert, null), false);
    });
  });

  group('knowledge categories', () {
    test('admin hazard types and reader labels resolve to one category', () {
      expect(knowledgeCategoryFor('flood')?.label, 'Flood');
      expect(knowledgeCategoryFor('Flood')?.hazardType, 'flood');
      expect(knowledgeCategoryFor('wildfires')?.label, 'Fire');
      expect(knowledgeCategoryFor('Extreme Heat')?.hazardType, 'extreme_heat');
      expect(knowledgeCategoryFor('nonsense'), isNull);
    });

    test('every category is offered as a reader filter', () {
      expect(knowledgeCategoryFilters.first, allKnowledgeCategories);
      for (final c in knowledgeCategories) {
        expect(knowledgeCategoryFilters, contains(c.label));
      }
    });

    test('guideMatchesCategory uses hazardType, then category', () {
      expect(guideMatchesCategory({'hazardType': 'storm'}, 'Storm'), true);
      expect(guideMatchesCategory({'hazardType': 'storm'}, 'Flood'), false);
      // Bundled guides only carry a category label.
      expect(guideMatchesCategory({'category': 'Safety'}, 'Safety'), true);
      expect(guideMatchesCategory({'category': 'Safety'}, 'All'), true);
      expect(guideMatchesCategory({'category': 'Safety'}, null), true);
    });
  });

  group('EmergencyContact validation', () {
    test('name is required', () {
      expect(EmergencyContact.validateName(''), isNotNull);
      expect(EmergencyContact.validateName('  '), isNotNull);
      expect(EmergencyContact.validateName('Ada'), isNull);
    });

    test('phone must be a plausible number', () {
      expect(EmergencyContact.validatePhone(''), isNotNull);
      expect(EmergencyContact.validatePhone('abc'), isNotNull);
      expect(EmergencyContact.validatePhone('12'), isNotNull);
      expect(EmergencyContact.validatePhone('112'), isNull);
      expect(EmergencyContact.validatePhone('0803 123 4567'), isNull);
      expect(EmergencyContact.validatePhone('+2348031234567'), isNull);
      expect(EmergencyContact.validatePhone('+234803123456789012'), isNotNull);
    });
  });
}
