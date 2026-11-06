import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Guidage vocal (synthèse vocale native, hors connexion). Les annonces se placent en file d'attente ;
/// une annonce urgente interrompt celle en cours.
class VoiceService {
  VoiceService({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  bool _ready = false;
  bool enabled = true;
  String? _voiceName;
  double _volume = 1.0;
  double _rate = 0.5;

  Future<void> init() async {
    if (_ready) return;
    try {
      await _tts.setLanguage('fr-FR');
      await _tts.awaitSpeakCompletion(true);
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _tts.setSharedInstance(true);
        await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [IosTextToSpeechAudioCategoryOptions.duckOthers, IosTextToSpeechAudioCategoryOptions.mixWithOthers],
          IosTextToSpeechAudioMode.voicePrompt,
        );
      }
      _ready = true;
    } catch (_) {
      _ready = false; // La navigation fonctionne sans voix ; l'interface affiche toujours les instructions.
    }
  }

  Future<void> configure({required bool enabled, String? voiceName, required double volume, required double rate}) async {
    this.enabled = enabled;
    _volume = volume;
    _rate = rate;
    _voiceName = voiceName;
    if (!_ready) return;
    try {
      await _tts.setVolume(volume);
      await _tts.setSpeechRate(rate);
      if (voiceName != null) {
        await _tts.setVoice({'name': voiceName, 'locale': 'fr-FR'});
      }
    } catch (_) {}
  }

  /// Voix françaises disponibles sur l'appareil.
  Future<List<String>> frenchVoices() async {
    try {
      await init();
      final voices = await _tts.getVoices as List<dynamic>?;
      final out = <String>{};
      for (final v in voices ?? const []) {
        if (v is Map && '${v['locale']}'.toLowerCase().startsWith('fr')) out.add('${v['name']}');
      }
      return out.toList()..sort();
    } catch (_) {
      return const [];
    }
  }

  Future<void> speak(String text, {bool interrupt = false}) async {
    if (!enabled || text.trim().isEmpty) return;
    await init();
    if (!_ready) return;
    try {
      if (interrupt) await _tts.stop();
      await _tts.setVolume(_volume);
      await _tts.setSpeechRate(_rate);
      if (_voiceName != null) await _tts.setVoice({'name': _voiceName!, 'locale': 'fr-FR'});
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
