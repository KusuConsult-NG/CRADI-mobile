import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:climate_app/l10n/app_localizations.dart';

export 'package:climate_app/l10n/app_localizations.dart';

/// A user-facing message created outside the widget tree (services,
/// providers, validators). The UI resolves it against the current locale's
/// strings with `message(context.l10n)`, so the service layer never needs a
/// BuildContext and never hard-codes display text.
typedef LocalizedText = String Function(AppLocalizations l10n);

/// English strings for places without a locale: log lines, `toString()`,
/// and tests. Never use this for text shown in the UI.
final AppLocalizations englishL10n = lookupAppLocalizations(const Locale('en'));

extension AppLocalizationsContext on BuildContext {
  /// The app strings for the current locale.
  AppLocalizations get l10n => AppLocalizations.of(this)!;

  /// The intl locale to format dates and numbers with (see [intlLocaleFor]).
  String? get intlLocale => intlLocaleFor(Localizations.maybeLocaleOf(this));
}

/// An intl locale name that has date-formatting data for [locale], or null
/// to use intl's default (US English).
///
/// intl throws for locales it has no data for (e.g. Hausa, Yoruba, Igbo,
/// Pidgin), so those fall back to English formatting instead of crashing.
String? intlLocaleFor(Locale? locale) {
  if (locale == null) return null;
  for (final candidate in [locale.toString(), locale.languageCode]) {
    try {
      if (DateFormat.localeExists(candidate)) return candidate;
    } on Object catch (_) {
      // Treat any lookup failure as "no data".
    }
  }
  return null;
}

/// A [DateFormat] for [pattern] in the current locale, falling back to
/// English where intl has no data for it.
DateFormat localizedDateFormat(BuildContext context, String pattern) =>
    DateFormat(pattern, context.intlLocale);
