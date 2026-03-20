import 'package:flutter_test/flutter_test.dart';
import 'package:climate_app/core/utils/validators.dart';

void main() {
  group('Phone Number Validation', () {
    test('valid local format', () {
      expect(Validators.validatePhoneNumber('08012345678'), isNull);
    });

    test('valid international format with +', () {
      expect(Validators.validatePhoneNumber('+2348012345678'), isNull);
    });

    test('valid international format without +', () {
      expect(Validators.validatePhoneNumber('2348012345678'), isNull);
    });

    test('null returns error', () {
      expect(Validators.validatePhoneNumber(null), isNotNull);
    });

    test('empty returns error', () {
      expect(Validators.validatePhoneNumber(''), isNotNull);
    });

    test('too short returns error', () {
      expect(Validators.validatePhoneNumber('0801234'), isNotNull);
    });

    test('non-Nigerian prefix rejected', () {
      expect(Validators.validatePhoneNumber('01012345678'), isNotNull);
    });
  });

  group('Phone Number Normalization', () {
    test('local to international', () {
      expect(
        Validators.normalizePhoneNumber('08012345678'),
        equals('+2348012345678'),
      );
    });

    test('already international with +', () {
      expect(
        Validators.normalizePhoneNumber('+2348012345678'),
        equals('+2348012345678'),
      );
    });

    test('international without +', () {
      expect(
        Validators.normalizePhoneNumber('2348012345678'),
        equals('+2348012345678'),
      );
    });

    test('strips spaces and dashes', () {
      expect(
        Validators.normalizePhoneNumber('080 1234-5678'),
        equals('+2348012345678'),
      );
    });
  });

  group('Email Validation', () {
    test('valid email', () {
      expect(Validators.validateEmail('test@example.com'), isNull);
    });

    test('null email', () {
      expect(Validators.validateEmail(null), isNotNull);
    });

    test('empty email', () {
      expect(Validators.validateEmail(''), isNotNull);
    });

    test('missing @', () {
      expect(Validators.validateEmail('testexample.com'), isNotNull);
    });

    test('missing domain', () {
      expect(Validators.validateEmail('test@'), isNotNull);
    });

    test('isValidEmail helper', () {
      expect(Validators.isValidEmail('a@b.co'), isTrue);
      expect(Validators.isValidEmail('invalid'), isFalse);
      expect(Validators.isValidEmail(null), isFalse);
    });
  });

  group('Password Validation', () {
    test('valid strong password', () {
      expect(Validators.validatePassword('MyP@ss1234'), isNull);
    });

    test('null password', () {
      expect(Validators.validatePassword(null), isNotNull);
    });

    test('too short', () {
      expect(Validators.validatePassword('A1@b'), isNotNull);
    });

    test('no uppercase', () {
      expect(Validators.validatePassword('myp@ss1234'), isNotNull);
    });

    test('no lowercase', () {
      expect(Validators.validatePassword('MYP@SS1234'), isNotNull);
    });

    test('no number', () {
      expect(Validators.validatePassword('MyP@ssword'), isNotNull);
    });

    test('no special char', () {
      expect(Validators.validatePassword('MyPass1234'), isNotNull);
    });
  });

  group('Password Strength', () {
    test('empty = 0', () {
      expect(Validators.getPasswordStrength(''), equals(0));
    });

    test('short weak password = 0', () {
      expect(Validators.getPasswordStrength('abc'), equals(0));
    });

    test('strong password = 4', () {
      expect(Validators.getPasswordStrength('MyStr0ng!Pass'), equals(4));
    });

    test('strength info returns label and color', () {
      final info = Validators.getPasswordStrengthInfo(4);
      expect(info['label'], equals('Strong'));
      expect(info['color'], isA<int>());
    });

    test('strength capped at 4', () {
      // Even very complex passwords should max at 4
      expect(Validators.getPasswordStrength('MyStr0ng!Pass'), lessThanOrEqualTo(4));
    });
  });

  group('Text Validation', () {
    test('valid text passes', () {
      expect(Validators.validateText('Normal text'), isNull);
    });

    test('null text fails', () {
      expect(Validators.validateText(null), isNotNull);
    });

    test('empty text fails', () {
      expect(Validators.validateText(''), isNotNull);
    });

    test('min length enforced', () {
      expect(
        Validators.validateText('ab', minLength: 5),
        isNotNull,
      );
    });

    test('max length enforced', () {
      expect(
        Validators.validateText('a' * 20, maxLength: 10),
        isNotNull,
      );
    });

    test('SQL injection detected', () {
      expect(
        Validators.validateText("'; DROP TABLE users;"),
        contains('Invalid'),
      );
    });

    test('script injection detected', () {
      expect(
        Validators.validateText('<script>alert("xss")</script>'),
        contains('Invalid'),
      );
    });
  });

  group('Address Validation', () {
    test('valid address passes', () {
      expect(
        Validators.validateAddress('123 Main Street, Makurdi'),
        isNull,
      );
    });

    test('too short address fails', () {
      expect(Validators.validateAddress('Short'), isNotNull);
    });

    test('null address fails', () {
      expect(Validators.validateAddress(null), isNotNull);
    });
  });

  group('Location Validation', () {
    test('valid location passes', () {
      expect(Validators.validateLocation('Benue', 'State'), isNull);
    });

    test('empty location fails', () {
      expect(Validators.validateLocation('', 'State'), isNotNull);
    });

    test('too short location fails', () {
      expect(Validators.validateLocation('A', 'LGA'), isNotNull);
    });

    test('special chars rejected', () {
      expect(
        Validators.validateLocation('Test@#\$', 'Ward'),
        isNotNull,
      );
    });
  });

  group('Required Field Validation', () {
    test('non-empty passes', () {
      expect(Validators.validateRequired('value', 'Field'), isNull);
    });

    test('null fails with field name', () {
      expect(
        Validators.validateRequired(null, 'Name'),
        contains('Name'),
      );
    });

    test('empty string fails', () {
      expect(Validators.validateRequired('', 'Phone'), isNotNull);
    });
  });
}
