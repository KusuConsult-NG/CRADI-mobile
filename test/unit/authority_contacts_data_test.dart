import 'package:flutter_test/flutter_test.dart';
import 'package:climate_app/core/data/authority_contacts_data.dart';

void main() {
  group('AuthorityContactsData.normalizeSeverity', () {
    test('accepts canonical lowercase values', () {
      for (final s in ['low', 'medium', 'high', 'critical']) {
        expect(AuthorityContactsData.normalizeSeverity(s), s);
      }
    });

    test('accepts legacy display labels', () {
      expect(AuthorityContactsData.normalizeSeverity('High Severity'), 'high');
      expect(
        AuthorityContactsData.normalizeSeverity('Critical Severity'),
        'critical',
      );
      expect(
        AuthorityContactsData.normalizeSeverity('Medium Severity'),
        'medium',
      );
      expect(AuthorityContactsData.normalizeSeverity('Critical'), 'critical');
    });

    test('unknown values fall back to low', () {
      expect(AuthorityContactsData.normalizeSeverity(''), 'low');
      expect(AuthorityContactsData.normalizeSeverity('bogus'), 'low');
    });
  });

  test('legacy and canonical severities notify the same recipients', () {
    List<String> phones(String severity) =>
        AuthorityContactsData.getAlertPhoneNumbers(
          lga: 'Makurdi',
          state: 'Benue',
          severity: severity,
        );

    expect(phones('Critical Severity'), phones('critical'));
    expect(phones('High Severity'), phones('high'));
  });
}
