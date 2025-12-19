import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageProvider extends ChangeNotifier {
  String _selectedLanguage = 'English';

  String get selectedLanguage => _selectedLanguage;

  LanguageProvider() {
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedLanguage = prefs.getString('selected_language') ?? 'English';
    notifyListeners();
  }

  Future<void> setLanguage(String language) async {
    _selectedLanguage = language;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_language', language);
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

  String get attentionText {
    return _t(
      en: '3 new items requiring attention.',
      ha: 'Abubuwan 3 na buƙatar kulawa.',
      yo: 'Awọn ohun 3 nilo akiyesi.',
      ig: 'Ihe 3 chọrọ nlebara anya.',
      pi: '3 things wey need ur attention.',
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
