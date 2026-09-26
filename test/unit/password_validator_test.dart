import 'dart:ui' show Locale;

import 'package:climate_app/core/l10n/l10n.dart';
import 'package:climate_app/core/l10n/severity_label.dart';
import 'package:climate_app/core/l10n/zone_label.dart';
import 'package:climate_app/core/utils/password_validator.dart';
import 'package:climate_app/core/utils/string_extensions.dart';
import 'package:flutter_test/flutter_test.dart';

/// A password that satisfies every rule (no sequential run of three).
const _strong = 'Tr0ub4dour&97';

void main() {
  final l10n = englishL10n;

  group('PasswordValidator.validate', () {
    test('accepts a password meeting every requirement', () {
      expect(PasswordValidator.validate(_strong, l10n), isNull);
    });

    test('rejects a password shorter than 8 characters', () {
      expect(PasswordValidator.validate('Ab1!xy', l10n), isNotNull);
    });

    test('rejects a password longer than 128 characters', () {
      final long = 'Aa1!${'x' * 130}';
      expect(long.length, greaterThan(128));
      expect(PasswordValidator.validate(long, l10n), isNotNull);
    });

    test('a 128-character password is still accepted', () {
      // 'Aa1!' + filler, with no three-character sequential run.
      final exact = 'Aa1!${'zq' * 62}';
      expect(exact.length, 128);
      expect(PasswordValidator.validate(exact, l10n), isNull);
    });

    test('requires an uppercase letter', () {
      expect(PasswordValidator.validate('troubadour&97', l10n), isNotNull);
    });

    test('requires a lowercase letter', () {
      expect(PasswordValidator.validate('TROUBADOUR&97', l10n), isNotNull);
    });

    test('requires a digit', () {
      expect(PasswordValidator.validate('Troubadour&xy', l10n), isNotNull);
    });

    test('requires a special character', () {
      expect(PasswordValidator.validate('Troubadour97', l10n), isNotNull);
    });

    test('every documented special character satisfies the rule', () {
      for (final ch in r'''!@#$%^&*(),.?":{}|<>_-+=[]\;/'''.split('')) {
        expect(
          PasswordValidator.validate('Troub4dour$ch', l10n),
          isNull,
          reason: 'special character "$ch" should be accepted',
        );
      }
    });

    test('rejects a known common password', () {
      // Padded so it fails on "common", not on the character-class rules.
      expect(PasswordValidator.isCommonPassword('Password123'), isTrue);
      expect(PasswordValidator.isCommonPassword('PASSWORD123'), isTrue);
      expect(PasswordValidator.isCommonPassword('nothing-like-it'), isFalse);
    });

    test('rejects three sequential digits', () {
      expect(PasswordValidator.validate('Troub&dour123', l10n), isNotNull);
    });

    test('rejects three sequential lowercase letters', () {
      expect(PasswordValidator.validate('Troub4&dourxyz', l10n), isNotNull);
    });

    test('rejects three sequential uppercase letters', () {
      expect(PasswordValidator.validate('Troub4&dourXYZ', l10n), isNotNull);
    });

    test('two sequential characters are allowed', () {
      expect(PasswordValidator.validate('Troub4&dourxy', l10n), isNull);
    });

    test('an empty password fails on length, never throws', () {
      expect(PasswordValidator.validate('', l10n), isNotNull);
    });

    test('messages are localised, not hard-coded English', () {
      final ha = lookupAppLocalizations(const Locale('ha'));
      final en = PasswordValidator.validate('short', l10n);
      final hausa = PasswordValidator.validate('short', ha);
      expect(en, isNotNull);
      expect(hausa, isNotNull);
      expect(hausa, isNot(en));
    });
  });

  group('PasswordValidator.calculateStrength', () {
    test('is clamped to 0..100', () {
      for (final p in ['', 'a', 'password', '0123456789', _strong, 'A' * 200]) {
        final score = PasswordValidator.calculateStrength(p);
        expect(score, inInclusiveRange(0, 100));
      }
    });

    test('a strong password scores higher than a weak one', () {
      expect(
        PasswordValidator.calculateStrength(_strong),
        greaterThan(PasswordValidator.calculateStrength('abcdefgh')),
      );
    });

    test('a common password is penalised below its raw score', () {
      // 'password1' has lowercase + digits + length >= 8.
      expect(PasswordValidator.calculateStrength('password1'), lessThan(30));
    });

    test('a sequential run costs points', () {
      final withSeq = PasswordValidator.calculateStrength('Qw3rt!abc');
      final without = PasswordValidator.calculateStrength('Qw3rt!azq');
      expect(withSeq, lessThan(without));
    });

    test('a 16+ character varied password reaches the top band', () {
      expect(
        PasswordValidator.calculateStrength('Zq7!Mv2%Kx9#Bn4@'),
        greaterThanOrEqualTo(80),
      );
    });
  });

  group('PasswordValidator.getStrengthLabel', () {
    test('each band has its own label', () {
      final labels = <String>{
        PasswordValidator.getStrengthLabel(0, l10n),
        PasswordValidator.getStrengthLabel(45, l10n),
        PasswordValidator.getStrengthLabel(70, l10n),
        PasswordValidator.getStrengthLabel(100, l10n),
      };
      expect(labels.length, 4);
    });

    test('band boundaries fall on the stronger side', () {
      expect(
        PasswordValidator.getStrengthLabel(30, l10n),
        isNot(PasswordValidator.getStrengthLabel(29, l10n)),
      );
      expect(
        PasswordValidator.getStrengthLabel(80, l10n),
        isNot(PasswordValidator.getStrengthLabel(79, l10n)),
      );
    });
  });

  group('PasswordValidator.getRequirements', () {
    test('an empty password meets only the "not common" requirement', () {
      final reqs = PasswordValidator.getRequirements('', l10n);
      expect(reqs.length, 6);
      expect(reqs.where((r) => r.isMet).length, 1);
      expect(reqs.last.isMet, isTrue);
    });

    test('a strong password meets all of them', () {
      final reqs = PasswordValidator.getRequirements(_strong, l10n);
      expect(reqs.every((r) => r.isMet), isTrue);
    });

    test('descriptions are non-empty and unique', () {
      final reqs = PasswordValidator.getRequirements('abc', l10n);
      expect(reqs.every((r) => r.description.trim().isNotEmpty), isTrue);
      expect(reqs.map((r) => r.description).toSet().length, reqs.length);
    });
  });

  group('StringNormalization.normalizeForBackend', () {
    test('spelling variants of an LGA collapse to one key', () {
      expect('Akoko-Edo'.normalizeForBackend(), 'akokoedo');
      expect('Akoko Edo'.normalizeForBackend(), 'akokoedo');
      expect('akoko_edo'.normalizeForBackend(), 'akokoedo');
      expect('AKOKOEDO'.normalizeForBackend(), 'akokoedo');
    });

    test('digits survive and punctuation does not', () {
      expect(
        "Ile-Ife (Osun) 2".normalizeForBackend(),
        'ileife osun 2'.replaceAll(RegExp(r'[^a-z0-9]'), ''),
      );
      expect(''.normalizeForBackend(), '');
      expect('---'.normalizeForBackend(), '');
    });

    test('non-ASCII letters are dropped rather than transliterated', () {
      // Known limitation: accented place names lose the accented character.
      expect('Oyo-Èkìtì'.normalizeForBackend(), 'oyokt');
    });
  });

  group('monitoringZoneLabel', () {
    test('a state zone is localised around the place name', () {
      final label = monitoringZoneLabel(l10n, 'Benue State');
      expect(label, contains('Benue'));
      expect(label, isNot('Benue State '));
    });

    test('an LGA zone is shown verbatim', () {
      expect(monitoringZoneLabel(l10n, 'Makurdi, Benue'), 'Makurdi, Benue');
    });

    test('an empty zone does not throw', () {
      expect(monitoringZoneLabel(l10n, ''), '');
    });

    test('a place literally named "State" is not truncated to empty', () {
      expect(monitoringZoneLabel(l10n, 'State'), 'State');
    });
  });

  group('severityLabel', () {
    test('canonical values are localised', () {
      for (final s in ['low', 'medium', 'high', 'critical']) {
        expect(severityLabel(l10n, s), isNotEmpty);
      }
      expect(
        {
          for (final s in ['low', 'medium', 'high', 'critical'])
            severityLabel(l10n, s),
        }.length,
        4,
      );
    });

    test('a null or blank severity reads as unknown', () {
      expect(severityLabel(l10n, null), l10n.commonUnknown);
      expect(severityLabel(l10n, '   '), l10n.commonUnknown);
    });

    test('an unrecognised severity is shown as stored', () {
      expect(severityLabel(l10n, 'catastrophic'), 'catastrophic');
    });

    test('a non-string severity does not throw', () {
      expect(severityLabel(l10n, 3), '3');
      expect(severityLabel(l10n, {'a': 1}), isNotEmpty);
    });
  });
}
