import 'package:climate_app/features/reporting/providers/reporting_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeSeverity', () {
    test('keeps canonical lowercase values', () {
      for (final v in ['low', 'medium', 'high', 'critical']) {
        expect(normalizeSeverity(v), v);
      }
    });

    test('maps legacy display labels', () {
      expect(normalizeSeverity('High Severity'), 'high');
      expect(normalizeSeverity('Critical Severity'), 'critical');
      expect(normalizeSeverity('LOW'), 'low');
    });

    test('returns null for unknown values', () {
      expect(normalizeSeverity(null), isNull);
      expect(normalizeSeverity('Unknown'), isNull);
    });
  });

  test('isAlertSeverity is true only for high/critical', () {
    expect(isAlertSeverity('high'), isTrue);
    expect(isAlertSeverity('Critical Severity'), isTrue);
    expect(isAlertSeverity('medium'), isFalse);
    expect(isAlertSeverity(null), isFalse);
  });
}
