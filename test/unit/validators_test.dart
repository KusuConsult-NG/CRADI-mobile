import 'package:flutter_test/flutter_test.dart';
import 'package:climate_app/core/utils/validators.dart';
import 'package:climate_app/core/l10n/l10n.dart';

void main() {
  group('Phone Number Validation', () {
    test('valid local format', () {
      expect(
        Validators.validatePhoneNumber('08012345678', englishL10n),
        isNull,
      );
    });

    test('valid international format with +', () {
      expect(
        Validators.validatePhoneNumber('+2348012345678', englishL10n),
        isNull,
      );
    });

    test('valid international format without +', () {
      expect(
        Validators.validatePhoneNumber('2348012345678', englishL10n),
        isNull,
      );
    });

    test('null returns error', () {
      expect(Validators.validatePhoneNumber(null, englishL10n), isNotNull);
    });

    test('empty returns error', () {
      expect(Validators.validatePhoneNumber('', englishL10n), isNotNull);
    });

    test('too short returns error', () {
      expect(Validators.validatePhoneNumber('0801234', englishL10n), isNotNull);
    });

    test('non-Nigerian prefix rejected', () {
      expect(
        Validators.validatePhoneNumber('01012345678', englishL10n),
        isNotNull,
      );
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
      expect(Validators.validateEmail('test@example.com', englishL10n), isNull);
    });

    test('null email', () {
      expect(Validators.validateEmail(null, englishL10n), isNotNull);
    });

    test('empty email', () {
      expect(Validators.validateEmail('', englishL10n), isNotNull);
    });

    test('missing @', () {
      expect(
        Validators.validateEmail('testexample.com', englishL10n),
        isNotNull,
      );
    });

    test('missing domain', () {
      expect(Validators.validateEmail('test@', englishL10n), isNotNull);
    });

    test('isValidEmail helper', () {
      expect(Validators.isValidEmail('a@b.co'), isTrue);
      expect(Validators.isValidEmail('invalid'), isFalse);
      expect(Validators.isValidEmail(null), isFalse);
    });
  });

  group('Password Validation', () {
    test('valid strong password', () {
      expect(Validators.validatePassword('MyP@ss1234', englishL10n), isNull);
    });

    test('null password', () {
      expect(Validators.validatePassword(null, englishL10n), isNotNull);
    });

    test('too short', () {
      expect(Validators.validatePassword('A1@b', englishL10n), isNotNull);
    });

    test('no uppercase', () {
      expect(Validators.validatePassword('myp@ss1234', englishL10n), isNotNull);
    });

    test('no lowercase', () {
      expect(Validators.validatePassword('MYP@SS1234', englishL10n), isNotNull);
    });

    test('no number', () {
      expect(Validators.validatePassword('MyP@ssword', englishL10n), isNotNull);
    });

    test('no special char', () {
      expect(Validators.validatePassword('MyPass1234', englishL10n), isNotNull);
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
      final info = Validators.getPasswordStrengthInfo(4, englishL10n);
      expect(info['label'], equals('Strong'));
      expect(info['color'], isA<int>());
    });

    test('strength capped at 4', () {
      // Even very complex passwords should max at 4
      expect(
        Validators.getPasswordStrength('MyStr0ng!Pass'),
        lessThanOrEqualTo(4),
      );
    });
  });

  group('Text Validation', () {
    test('valid text passes', () {
      expect(Validators.validateText('Normal text', englishL10n), isNull);
    });

    test('null text fails', () {
      expect(Validators.validateText(null, englishL10n), isNotNull);
    });

    test('empty text fails', () {
      expect(Validators.validateText('', englishL10n), isNotNull);
    });

    test('min length enforced', () {
      expect(
        Validators.validateText('ab', englishL10n, minLength: 5),
        isNotNull,
      );
    });

    test('max length enforced', () {
      expect(
        Validators.validateText('a' * 20, englishL10n, maxLength: 10),
        isNotNull,
      );
    });

    test('SQL injection detected', () {
      expect(
        Validators.validateText("'; DROP TABLE users;", englishL10n),
        contains('Invalid'),
      );
    });

    test('script injection detected', () {
      expect(
        Validators.validateText('<script>alert("xss")</script>', englishL10n),
        contains('Invalid'),
      );
    });
  });

  group('Address Validation', () {
    test('valid address passes', () {
      expect(
        Validators.validateAddress('123 Main Street, Makurdi', englishL10n),
        isNull,
      );
    });

    test('too short address fails', () {
      expect(Validators.validateAddress('Short', englishL10n), isNotNull);
    });

    test('null address fails', () {
      expect(Validators.validateAddress(null, englishL10n), isNotNull);
    });
  });

  group('Location Validation', () {
    test('valid location passes', () {
      expect(
        Validators.validateLocation('Benue', 'State', englishL10n),
        isNull,
      );
    });

    test('empty location fails', () {
      expect(Validators.validateLocation('', 'State', englishL10n), isNotNull);
    });

    test('too short location fails', () {
      expect(Validators.validateLocation('A', 'LGA', englishL10n), isNotNull);
    });

    test('special chars rejected', () {
      expect(
        Validators.validateLocation('Test@#\$', 'Ward', englishL10n),
        isNotNull,
      );
    });
  });

  group('Required Field Validation', () {
    test('non-empty passes', () {
      expect(
        Validators.validateRequired('value', 'Field', englishL10n),
        isNull,
      );
    });

    test('null fails with field name', () {
      expect(
        Validators.validateRequired(null, 'Name', englishL10n),
        contains('Name'),
      );
    });

    test('empty string fails', () {
      expect(Validators.validateRequired('', 'Phone', englishL10n), isNotNull);
    });
  });
}
