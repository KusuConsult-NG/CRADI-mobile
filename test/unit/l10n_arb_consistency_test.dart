import 'dart:convert';
import 'dart:io';

import 'package:climate_app/core/l10n/l10n.dart';
import 'package:climate_app/core/l10n/relative_time.dart';
import 'package:climate_app/core/l10n/fallback_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every translation (`lib/l10n/app_<locale>.arb`) must define every key of
/// the English template, with the same placeholders, so `flutter gen-l10n`
/// never falls back silently and no placeholder is lost in translation.
void main() {
  const arbDir = 'lib/l10n';
  const templateFile = 'app_en.arb';

  Map<String, dynamic> readArb(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

  bool isMessageKey(String key) => !key.startsWith('@');

  /// Placeholder names used in an ICU message: `{name}` and the argument of
  /// `{name, plural, …}` / `{name, select, …}`; plural/select case bodies
  /// such as `other{…}` or `=1{…}` are not placeholders.
  Set<String> placeholdersIn(String message) => {
    for (final m in RegExp(
      r'(?<![\w=])\{\s*([A-Za-z_]\w*)\s*(?:\}|,)',
    ).allMatches(message))
      m.group(1)!,
  };

  final template = readArb('$arbDir/$templateFile');
  final templateKeys = template.keys.where(isMessageKey).toSet();

  final translations =
      Directory(arbDir)
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where(
            (name) =>
                name.startsWith('app_') &&
                name.endsWith('.arb') &&
                name != templateFile,
          )
          .toList()
        ..sort();

  test('there is at least one translation besides English', () {
    expect(translations, isNotEmpty);
  });

  test('every template key has a description for translators', () {
    final missing = [
      for (final key in templateKeys)
        if ((template['@$key'] as Map<String, dynamic>?)?['description']
                is! String ||
            ((template['@$key'] as Map)['description'] as String)
                .trim()
                .isEmpty)
          key,
    ];
    expect(missing, isEmpty, reason: 'keys without an @description');
  });

  test('template placeholders are declared in the metadata', () {
    for (final key in templateKeys) {
      final used = placeholdersIn(template[key] as String);
      final declared =
          ((template['@$key'] as Map<String, dynamic>?)?['placeholders']
                  as Map<String, dynamic>?)
              ?.keys
              .toSet() ??
          <String>{};
      expect(declared, used, reason: 'placeholders of "$key"');
    }
  });

  for (final file in translations) {
    group(file, () {
      final arb = readArb('$arbDir/$file');
      final keys = arb.keys.where(isMessageKey).toSet();

      test('defines every key of $templateFile', () {
        expect(templateKeys.difference(keys), isEmpty);
      });

      test('has no keys missing from $templateFile', () {
        expect(keys.difference(templateKeys), isEmpty);
      });

      test('uses the same placeholders as $templateFile', () {
        final mismatched = <String>[];
        for (final key in templateKeys.intersection(keys)) {
          final expected = placeholdersIn(template[key] as String);
          final actual = placeholdersIn(arb[key] as String);
          if (!expected.containsAll(actual) || !actual.containsAll(expected)) {
            mismatched.add('$key: expected $expected, got $actual');
          }
        }
        expect(mismatched, isEmpty);
      });
    });
  }

  group('locale-aware formatting', () {
    test('locales without intl date data fall back to English', () {
      // Hausa, Yoruba, Igbo and Pidgin have no intl date symbols; formatting
      // with them must not throw.
      for (final code in ['ha', 'yo', 'ig', 'pcm']) {
        expect(intlLocaleFor(Locale(code)), isNull, reason: code);
      }
      expect(intlLocaleFor(null), isNull);
    });

    testWidgets('dates format under Hausa without throwing', (tester) async {
      late String formatted;
      late String greeting;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ha'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              formatted = localizedDateFormat(
                context,
                'MMM d, y',
              ).format(DateTime(2026, 3, 5));
              greeting = context.l10n.homeGreeting('Ada');
              return const SizedBox();
            },
          ),
        ),
      );
      expect(formatted, 'Mar 5, 2026');
      expect(greeting, 'Sannu, Ada');
    });

    test('relative times are localised with plurals', () {
      final now = DateTime(2026, 1, 1, 12);
      expect(relativeTimeLabel(englishL10n, now, now: now), 'Just now');
      expect(
        relativeTimeLabel(
          englishL10n,
          now.subtract(const Duration(minutes: 5)),
          now: now,
        ),
        '5m ago',
      );
      expect(
        relativeTimeLabel(
          englishL10n,
          now.subtract(const Duration(days: 15)),
          now: now,
        ),
        '2w ago',
      );
    });
  });
}
