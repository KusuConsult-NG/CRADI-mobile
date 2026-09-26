import 'dart:io';

import 'package:climate_app/core/providers/connectivity_provider.dart';
import 'package:climate_app/core/providers/language_provider.dart';
import 'package:climate_app/core/providers/settings_provider.dart';
import 'package:climate_app/core/services/biometric_service.dart';
import 'package:climate_app/core/services/notification_service.dart';
import 'package:climate_app/core/services/remote_config_service.dart';
import 'package:climate_app/core/services/tts_service.dart';
import 'package:climate_app/features/alerts/providers/alerts_provider.dart';
import 'package:climate_app/features/profile/widgets/sos_sheet.dart';
import 'package:climate_app/features/settings/screens/help_support_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:climate_app/core/l10n/l10n.dart';

/// LocalAuthentication stand-in whose calls throw [error] (or succeed).
class _FakeLocalAuth implements LocalAuthentication {
  _FakeLocalAuth({this.error, this.canCheck = true});

  final Object? error;
  final bool canCheck;

  @override
  Future<bool> get canCheckBiometrics async => canCheck;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<Object> authMessages = const [],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async {
    final e = error;
    if (e != null) throw e;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LanguageProvider', () {
    test('offers only languages with ARB translations', () {
      expect(LanguageProvider.supportedLanguages.keys, [
        'English',
        'Hausa',
        'Yoruba',
        'Igbo',
        'Pidgin',
      ]);
      for (final locale in LanguageProvider.supportedLanguages.values) {
        expect(
          File('lib/l10n/app_${locale.languageCode}.arb').existsSync(),
          isTrue,
          reason: 'missing ARB for ${locale.languageCode}',
        );
        expect(
          LanguageProvider.nativeNames,
          contains(
            LanguageProvider.supportedLanguages.entries
                .firstWhere((e) => e.value == locale)
                .key,
          ),
        );
      }
    });

    test('maps languages to locales, unknown ones to English', () {
      expect(LanguageProvider.localeFor('Hausa'), const Locale('ha'));
      expect(LanguageProvider.localeFor('English'), const Locale('en'));
      expect(LanguageProvider.localeFor('Yoruba'), const Locale('yo'));
      expect(LanguageProvider.localeFor('Igbo'), const Locale('ig'));
      expect(LanguageProvider.localeFor('Pidgin'), const Locale('pcm'));
      expect(LanguageProvider.localeFor('French'), const Locale('en'));
    });

    test('a stored untranslated language falls back to English', () async {
      SharedPreferences.setMockInitialValues({'selected_language': 'French'});
      final p = LanguageProvider();
      await Future<void>.delayed(Duration.zero);
      expect(p.selectedLanguage, 'English');
      expect(p.locale, const Locale('en'));
    });

    test('setLanguage changes the locale and TTS language', () async {
      final p = LanguageProvider();
      await p.setLanguage('Hausa');
      expect(p.locale, const Locale('ha'));
      expect(TTSService().preferredLanguageCode, 'ha');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('selected_language'), 'Hausa');
      await p.setLanguage('Pidgin');
      expect(p.locale, const Locale('pcm'));
      expect(TTSService().preferredLanguageCode, 'pcm');
      // A language that isn't offered falls back to English.
      await p.setLanguage('Klingon');
      expect(p.selectedLanguage, 'English');
      expect(TTSService().preferredLanguageCode, 'en');
    });
  });

  group('TTSService', () {
    test('maps app languages to voice tags, English otherwise', () {
      expect(TTSService.languageTagFor('ha'), 'ha-NG');
      expect(TTSService.languageTagFor('yo'), 'yo-NG');
      expect(TTSService.languageTagFor('ig'), 'ig-NG');
      expect(TTSService.languageTagFor('pcm'), 'en-NG');
      expect(TTSService.languageTagFor('en'), 'en-US');
      expect(TTSService.languageTagFor('fr'), 'en-US');
    });
  });

  group('Help & Support mailto', () {
    test('encodes spaces as %20, not +', () {
      final uri = HelpSupportScreen.supportMailUri(
        address: 'support@cradi.org',
        subject: englishL10n.helpSupportEmailSubject,
        body: englishL10n.helpSupportEmailBody,
      );
      final s = uri.toString();
      expect(s, startsWith('mailto:support@cradi.org?'));
      expect(s, isNot(contains('+')));
      expect(s, contains('subject=CRADI%20App%20Support%20Request'));
      expect(s, contains('%0A'));
    });

    test('support address comes from app_settings, default when unset', () {
      final cfg = RemoteConfigService()..debugSetValues({});
      expect(cfg.supportEmail, 'support@cradi.org');
      cfg.debugSetValues({'support_email': 'help@example.org'});
      expect(cfg.supportEmail, 'help@example.org');
      cfg.debugSetValues({'support_email': '  '});
      expect(cfg.supportEmail, 'support@cradi.org');
      cfg.debugSetValues({});
    });
  });

  group('SOS', () {
    test('tel links strip formatting characters', () {
      expect(telUri('112').toString(), 'tel:112');
      expect(telUri('+234 (803) 123-4567').toString(), 'tel:+2348031234567');
    });
  });

  group('BiometricService', () {
    test('LocalAuthException is caught and its code exposed', () async {
      final bio = BiometricService.withLocalAuth(
        _FakeLocalAuth(
          error: const LocalAuthException(
            code: LocalAuthExceptionCode.noBiometricsEnrolled,
          ),
        ),
      );
      expect(await bio.authenticate(), isFalse);
      expect(bio.lastErrorCode, LocalAuthExceptionCode.noBiometricsEnrolled);
      expect(bio.lastErrorIsNotEnrolled, isTrue);
    });

    test('success clears the previous error', () async {
      final failing = BiometricService.withLocalAuth(
        _FakeLocalAuth(
          error: const LocalAuthException(
            code: LocalAuthExceptionCode.userCanceled,
          ),
        ),
      );
      expect(await failing.authenticate(), isFalse);
      expect(failing.lastErrorCode, LocalAuthExceptionCode.userCanceled);

      final ok = BiometricService.withLocalAuth(_FakeLocalAuth());
      expect(await ok.authenticate(), isTrue);
      expect(ok.lastErrorCode, isNull);
    });

    test('no biometrics hardware reports a code without prompting', () async {
      final bio = BiometricService.withLocalAuth(
        _FakeLocalAuth(canCheck: false),
      );
      expect(await bio.authenticate(), isFalse);
      expect(bio.lastErrorCode, LocalAuthExceptionCode.noBiometricHardware);
    });

    test('messages: none for cancellation, enrolment hint otherwise', () {
      expect(
        BiometricService.messageFor(LocalAuthExceptionCode.userCanceled),
        isNull,
      );
      expect(
        BiometricService.messageFor(LocalAuthExceptionCode.noCredentialsSet)!(
          englishL10n,
        ),
        contains('No biometrics enrolled'),
      );
      expect(
        BiometricService.messageFor(LocalAuthExceptionCode.biometricLockout)!(
          englishL10n,
        ),
        contains('locked'),
      );
    });
  });

  group('SettingsProvider', () {
    test('push / critical toggles persist and restore', () async {
      final a = SettingsProvider.forTesting();
      await a.init();
      expect(a.pushNotifications, isTrue);
      expect(a.criticalAlerts, isTrue);
      await a.setPushNotifications(false);
      await a.setCriticalAlerts(false);

      final b = SettingsProvider.forTesting();
      await b.init();
      expect(b.pushNotifications, isFalse);
      expect(b.criticalAlerts, isFalse);
    });

    test('push opt-in/out is a no-op without OneSignal configured', () async {
      expect(await NotificationService().setPushSubscribed(false), isFalse);
    });
  });

  group('NotificationService history', () {
    late Directory dir;
    late Box<Map> box;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('notif_hist');
      Hive.init(dir.path);
      box = await Hive.openBox<Map>('notifications_history_test');
      NotificationService().attachHistoryBoxForTesting(box);
    });

    tearDownAll(() async {
      await box.deleteFromDisk();
      await dir.delete(recursive: true);
    });

    Future<void> add(String id) => box.put(id, {
      'id': id,
      'title': 't',
      'body': 'b',
      'timestamp': DateTime.now().toIso8601String(),
      'isRead': false,
    });

    test('is cleared on sign-out', () async {
      final service = NotificationService();
      await service.setUserForTesting('user-a');
      await add('1');
      expect(service.getNotifications(), hasLength(1));
      await service.onUserSignedOut();
      expect(service.getNotifications(), isEmpty);
    });

    test('kept for the same user, dropped for another account', () async {
      final service = NotificationService();
      await service.setUserForTesting('user-a');
      await add('1');
      await service.setUserForTesting('user-a');
      expect(service.getNotifications(), hasLength(1));
      // Another account on this device (no sign-out clear ran).
      await service.setUserForTesting('user-b');
      expect(service.getNotifications(), isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(NotificationService.historyOwnerKey), 'user-b');
    });
  });

  group('AlertsProvider.targetsLga', () {
    test('matches by LGA name only (alerts have no state column)', () {
      expect(AlertsProvider.targetsLga({'target_lga': 'Obi'}, 'obi'), true);
      expect(AlertsProvider.targetsLga({'target_lga': 'Obi'}, 'Bassa'), false);
    });
  });

  group('ConnectivityProvider manual offline', () {
    test('switching manual offline off fires onReconnect when online', () {
      final p = ConnectivityProvider.forTesting();
      var calls = 0;
      p.onReconnect = () => calls++;
      p.setManualOffline(true);
      expect(calls, 0);
      p.setManualOffline(false);
      expect(calls, 1);
      p.setManualOffline(false); // unchanged
      expect(calls, 1);
    });

    test('no reconnect while the device itself is offline', () {
      final p = ConnectivityProvider.forTesting(online: false);
      var calls = 0;
      p.onReconnect = () => calls++;
      p.setManualOffline(true);
      p.setManualOffline(false);
      expect(calls, 0);
    });
  });

  group('RemoteConfigService min version', () {
    tearDown(() {
      RemoteConfigService()
        ..debugSetValues({})
        ..debugSetCurrentVersion(null);
    });

    test('compareVersions', () {
      expect(RemoteConfigService.compareVersions('1.0.14', '1.0.14'), 0);
      expect(RemoteConfigService.compareVersions('1.0.14+22', '1.0.14'), 0);
      expect(
        RemoteConfigService.compareVersions('1.0.9', '1.0.14'),
        lessThan(0),
      );
      expect(
        RemoteConfigService.compareVersions('1.2', '1.1.9'),
        greaterThan(0),
      );
      expect(RemoteConfigService.compareVersions('2.0.0', '2'), 0);
    });

    test('updateRequired follows app_min_version', () {
      final cfg = RemoteConfigService()..debugSetCurrentVersion('1.0.14');
      cfg.debugSetValues({'app_min_version': '1.1.0'});
      expect(cfg.updateRequired.value, isTrue);
      cfg.debugSetValues({'app_min_version': '1.0.14'});
      expect(cfg.updateRequired.value, isFalse);
      cfg.debugSetValues({});
      expect(cfg.updateRequired.value, isFalse); // default 1.0.0
    });
  });
}
