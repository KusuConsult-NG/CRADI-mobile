import 'package:flutter_tts/flutter_tts.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

class TTSService {
  static final TTSService _instance = TTSService._internal();
  factory TTSService() => _instance;
  TTSService._internal();

  FlutterTts? _flutterTts;
  bool _isInitialized = false;

  /// App language (set by LanguageProvider); applied on the next [speak]
  /// when the device has a voice for it, else English is used.
  String preferredLanguageCode = 'en';
  String? _appliedLanguage;

  /// Speech language tags per app language code.
  static const Map<String, String> _languageTags = {
    'en': 'en-US',
    'ha': 'ha-NG',
    'yo': 'yo-NG',
    'ig': 'ig-NG',
    // Nigerian Pidgin has no speech voices; Nigerian English reads it best.
    'pcm': 'en-NG',
  };

  /// The speech language tag for [code]; English for unknown codes.
  @visibleForTesting
  static String languageTagFor(String code) =>
      _languageTags[code] ?? _languageTags['en']!;

  Future<void> init() async {
    if (_isInitialized) return;

    try {
      _flutterTts = FlutterTts();

      // Set handlers for debugging
      _flutterTts?.setErrorHandler((msg) {
        debugPrint('TTS Error: $msg');
      });

      if (Platform.isIOS) {
        await _flutterTts?.setSharedInstance(true);
        await _flutterTts
            ?.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
              IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
              IosTextToSpeechAudioCategoryOptions.allowBluetooth,
              IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
            ], IosTextToSpeechAudioMode.defaultMode);
      }

      await _flutterTts?.setLanguage(languageTagFor('en'));
      _appliedLanguage = languageTagFor('en');
      await _flutterTts?.setSpeechRate(0.5);
      await _flutterTts?.setVolume(1.0);
      await _flutterTts?.setPitch(1.0);

      // getEngines is Android-only (it throws on iOS).
      if (Platform.isAndroid) {
        final engines = await _flutterTts?.getEngines;
        debugPrint('TTS Engines: $engines');
      }

      _isInitialized = true;
      debugPrint('TTS Initialized Successfully');
    } on Exception catch (e) {
      debugPrint('TTS Initialization Error: $e');
      _isInitialized = false; // Ensure we try again if failed
    }
  }

  Future<void> speak(String text) async {
    if (!_isInitialized) await init();
    if (text.isNotEmpty) {
      await _applyPreferredLanguage();
      await _flutterTts?.speak(text);
    }
  }

  Future<void> _applyPreferredLanguage() async {
    final tts = _flutterTts;
    if (tts == null) return;
    var tag = languageTagFor(preferredLanguageCode);
    if (tag == _appliedLanguage) return;
    try {
      final available = await tts.isLanguageAvailable(tag);
      if (available != true) tag = languageTagFor('en');
      if (tag == _appliedLanguage) return;
      await tts.setLanguage(tag);
      _appliedLanguage = tag;
    } on Exception catch (e) {
      debugPrint('TTS language error: $e');
    }
  }

  /// Stops speech in progress. Screens that speak should call this when
  /// they are left (e.g. in dispose).
  Future<void> stop() async {
    if (_isInitialized) {
      await _flutterTts?.stop();
    }
  }
}
