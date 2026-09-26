import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:climate_app/core/services/tts_service.dart';

class LanguageProvider extends ChangeNotifier {
  /// Languages offered in the picker: only those with ARB translations
  /// (lib/l10n/app_*.arb), so choosing one really changes the app's text.
  /// Yoruba, Igbo and Pidgin have in-app strings below but no ARB files;
  /// they are hidden until translations exist.
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

  // Helper method for translations
  String _t({
    required String en,
    required String ha,
    required String yo,
    required String ig,
    required String pi,
  }) {
    switch (_selectedLanguage) {
      case 'Hausa':
        return ha;
      case 'Yoruba':
        return yo;
      case 'Igbo':
        return ig;
      case 'Pidgin':
        return pi;
      default:
        return en;
    }
  }

  // --- Common ---
  String get ok => _t(en: 'OK', ha: 'TO', yo: 'DARA', ig: 'DARA', pi: 'OYA NA');
  String get cancel =>
      _t(en: 'Cancel', ha: 'Soke', yo: 'Fagilee', ig: 'Kagbuo', pi: 'Cancel');
  String get back =>
      _t(en: 'Back', ha: 'Baya', yo: 'Pada', ig: 'Azụ', pi: 'Go Back');
  String get save =>
      _t(en: 'Save', ha: 'Ajiye', yo: 'Fipamọ', ig: 'Chekwa', pi: 'Save am');

  // --- Home ---
  String get greeting {
    return _t(
      en: 'Hello, {name}',
      ha: 'Sannu, {name}',
      yo: 'Bawo, {name}',
      ig: 'Nno, {name}',
      pi: 'How far, {name}',
    );
  }

  // --- Navigation ---
  String get navHome =>
      _t(en: 'Home', ha: 'Gida', yo: 'Ile', ig: 'Ụlọ', pi: 'Home');
  String get navAlerts =>
      _t(en: 'Alerts', ha: 'Faɗakarwa', yo: 'Itaniji', ig: 'Mba', pi: 'Alerts');
  String get navGuides => _t(
    en: 'Guides',
    ha: 'Jagora',
    yo: 'Awọn itọsọna',
    ig: 'Ntuziaka',
    pi: 'Guides',
  );
  String get navReport =>
      _t(en: 'Report', ha: 'Rahoto', yo: 'Ijabọ', ig: 'Akụkọ', pi: 'Report');
  String get navSettings => _t(
    en: 'Settings',
    ha: 'Saituna',
    yo: 'Ètò',
    ig: 'Ntọala',
    pi: 'Settings',
  );

  // --- Settings Screen ---
  String get settingsTitle => _t(
    en: 'Settings',
    ha: 'Saituna',
    yo: 'Awọn Ètò',
    ig: 'Ntọala',
    pi: 'Settings',
  );

  String get notifications => _t(
    en: 'NOTIFICATIONS',
    ha: 'SANARWA',
    yo: 'IFILO',
    ig: 'AMỤMA',
    pi: 'NOTIFICATIONS',
  );
  String get pushNotifications => _t(
    en: 'Push Notifications',
    ha: 'Sanarwa',
    yo: 'Awọn iwifunni Titari',
    ig: 'Amụma',
    pi: 'Push Notifications',
  );
  String get criticalAlerts => _t(
    en: 'Critical Alert Override',
    ha: 'Faɗakarwa Mai Muhimmanci',
    yo: 'Itaniji pataki',
    ig: 'Isi Amụma',
    pi: 'Serious Alerts',
  );
  String get dnd => _t(
    en: 'Do Not Disturb',
    ha: 'Kada a Dame Ni',
    yo: 'Maṣe di mi lọwọ',
    ig: 'Enyela Nsogbu',
    pi: 'No Disturb Me',
  );

  String get dataStorage => _t(
    en: 'DATA & STORAGE',
    ha: 'DATA & AJIYA',
    yo: 'DATA & IMO',
    ig: 'DATA & NCHEKWA',
    pi: 'DATA & STORAGE',
  );
  String get wifiOnly => _t(
    en: 'Download over Wi-Fi Only',
    ha: 'Zazzage kan Wi-Fi Kawai',
    yo: 'Ṣe igbasilẹ lori Wi-Fi nikan',
    ig: 'Budata naanị na Wi-Fi',
    pi: 'Download only with Wi-Fi',
  );
  String get lowData => _t(
    en: 'Low Data Mode',
    ha: 'Yanayin Ƙarancin Data',
    yo: 'Ipo Data Kekere',
    ig: 'Ọnọdụ Data Dị Ala',
    pi: 'Small Data Mode',
  );

  String get general => _t(
    en: 'GENERAL',
    ha: 'JAMA\'A',
    yo: 'GBOGBOGBO',
    ig: 'ARA',
    pi: 'GENERAL',
  );
  String get language =>
      _t(en: 'Language', ha: 'Harshe', yo: 'Ede', ig: 'Asụsụ', pi: 'Language');
  String get helpFaq => _t(
    en: 'Help & FAQ',
    ha: 'Taimako & FAQ',
    yo: 'Iranlọwọ & FAQ',
    ig: 'Enyemaka & FAQ',
    pi: 'Help & FAQ',
  );
  String get aboutApp => _t(
    en: 'About App',
    ha: 'Game da App',
    yo: 'Nipa App',
    ig: 'Banyere App',
    pi: 'About App',
  );

  String get logout =>
      _t(en: 'Log Out', ha: 'Fita', yo: 'Jade', ig: 'Pụọ', pi: 'Comot');
}
