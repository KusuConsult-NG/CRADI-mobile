import 'package:climate_app/core/l10n/fallback_localizations.dart';
import 'package:climate_app/core/l10n/l10n.dart';
import 'package:climate_app/core/providers/language_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every offered language must render app text, Material widgets (dialogs,
/// back buttons, text fields) and localised dates without throwing, including
/// languages Flutter's own Material localisations don't cover (ha, yo, ig,
/// pcm), which fall back to English Material strings.
void main() {
  for (final entry in LanguageProvider.supportedLanguages.entries) {
    testWidgets('renders in ${entry.key}', (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        MaterialApp(
          locale: entry.value,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: appLocalizationsDelegates,
          home: Builder(
            builder: (context) {
              captured = context;
              return Scaffold(
                appBar: AppBar(title: Text(context.l10n.appTitle)),
                body: Column(
                  children: [
                    Text(context.l10n.logout),
                    const TextField(),
                    Text(
                      localizedDateFormat(
                        context,
                        'yMMMd',
                      ).format(DateTime(2026, 9, 26)),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(Localizations.localeOf(captured), entry.value);
      expect(MaterialLocalizations.of(captured), isNotNull);
      expect(find.text(AppLocalizations.of(captured)!.logout), findsOneWidget);

      showDialog<void>(
        context: captured,
        builder: (c) => AlertDialog(
          title: Text(c.l10n.appTitle),
          actions: [TextButton(onPressed: () {}, child: Text(c.l10n.logout))],
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
