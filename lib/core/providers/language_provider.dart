import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:climate_app/core/services/tts_service.dart';

class LanguageProvider extends ChangeNotifier {
  /// Languages offered in the picker: only those with ARB translations
  /// (lib/l10n/app_*.arb), so choosing one really changes the app's text.
  /// Yoruba, Igbo and Pidgin are hidden until their ARB files exist.
  ///
  /// This provider only holds the selected locale; every display string
  /// comes from AppLocalizations (the ARB files).
  static const Map<String, Locale> supportedLanguages = {
    'English': Locale('en'),
    'Hausa': Locale('ha'),
  };

  static const String defaultLanguage = 'English';

  String _selectedLanguage = defaultLanguage;

  String get selectedLanguage => _selectedLanguage;

  /// The app locale for [selectedLanguage] (English for anything else).
  Locale get locale => localeFor(_selectedLanguage);

  static Locale localeFor(String language) =>
      supportedLanguages[language] ?? supportedLanguages[defaultLanguage]!;

  /// A stored choice that is no longer offered (e.g. Yoruba) falls back to
  /// English so the picker and the app text agree.
  static String normalize(String? language) =>
      supportedLanguages.containsKey(language) ? language! : defaultLanguage;

  LanguageProvider() {
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _selectedLanguage = normalize(prefs.getString('selected_language'));
      TTSService().preferredLanguageCode = locale.languageCode;
      notifyListeners();
    } on Exception catch (e) {
      debugPrint('Could not load language preference: $e');
    }
  }

  Future<void> setLanguage(String language) async {
    _selectedLanguage = normalize(language);
    TTSService().preferredLanguageCode = locale.languageCode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_language', _selectedLanguage);
  }
}
