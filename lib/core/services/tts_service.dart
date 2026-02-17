import 'package:flutter_tts/flutter_tts.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

class TTSService {
  static final TTSService _instance = TTSService._internal();
  factory TTSService() => _instance;
  TTSService._internal();

  FlutterTts? _flutterTts;
  bool _isInitialized = false;

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
        await _flutterTts?.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
            IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          ],
          IosTextToSpeechAudioMode.defaultMode,
        );
      }

      await _flutterTts?.setLanguage("en-US");
      await _flutterTts?.setSpeechRate(0.5);
      await _flutterTts?.setVolume(1.0);
      await _flutterTts?.setPitch(1.0);

      // Verify engine
      final engines = await _flutterTts?.getEngines;
      debugPrint('TTS Engines: $engines');

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
      await _flutterTts?.speak(text);
    }
  }

  Future<void> stop() async {
    if (_isInitialized) {
      await _flutterTts?.stop();
    }
  }
}
