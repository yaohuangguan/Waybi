import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// One completion-aware queue for turns and camera alerts. Google runs
/// silently and its live turn feed supplies our guidance text.
class VoiceEngine {
  VoiceEngine({FlutterTts? tts}) : _tts = tts ?? FlutterTts();
  final FlutterTts _tts;
  Future<void>? _initializing;
  String _language = 'en-NZ';
  int _generation = 0;
  Future<void> _speechQueue = Future<void>.value();

  Future<void> setLanguage(String language) async {
    _language = language == 'zh-CN' ? 'zh-CN' : 'en-NZ';
  }

  Future<void> initialize() =>
      _initializing ??= _initialize().catchError((Object error) {
        _initializing = null;
        throw error;
      });

  Future<void> _initialize() async {
    await _tts.setLanguage(_language);
    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1);
    await _tts.awaitSpeakCompletion(true);
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _tts.setAudioAttributesForNavigation();
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
        IosTextToSpeechAudioCategoryOptions.duckOthers,
        IosTextToSpeechAudioCategoryOptions.allowBluetooth,
      ], IosTextToSpeechAudioMode.voicePrompt);
    }
  }

  Future<void> _enqueue(
    String Function() message, {
    String? language,
    bool Function()? stillRelevant,
  }) {
    final generation = _generation;
    final speech = _speechQueue.catchError((Object _) {}).then((_) async {
      if (generation != _generation || !(stillRelevant?.call() ?? true)) return;
      await initialize();
      if (generation != _generation || !(stillRelevant?.call() ?? true)) return;
      await _tts.setLanguage(language ?? _language);
      if (generation != _generation || !(stillRelevant?.call() ?? true)) return;
      final text = message().trim();
      if (text.isNotEmpty) await _tts.speak(text);
    });
    _speechQueue = speech;
    return speech;
  }

  Future<void> guidance(
    String message, {
    String? language,
    bool Function()? stillRelevant,
  }) =>
      _enqueue(() => message, language: language, stillRelevant: stillRelevant);

  Future<void> stop() async {
    ++_generation;
    final stopped = _initializing == null
        ? Future<void>.value()
        : _tts.stop().then<void>((_) {});
    // Some engines do not resolve speak() when cancelled. New speech must
    // wait for stop(), without waiting on that abandoned completion future.
    _speechQueue = stopped;
    await stopped;
  }

  Future<void> cameraAlert({
    required int distanceMeters,
    required String cameraType,
    required String roadName,
    String? speedLimit,
    bool Function()? stillRelevant,
  }) => _enqueue(() {
    final lower = cameraType.toLowerCase();
    final red = lower.contains('red light');
    final average = lower.contains('average');
    final type = _language == 'zh-CN'
        ? (red
              ? '红灯摄像头'
              : average
              ? '区间测速摄像头'
              : '固定测速摄像头')
        : (red
              ? 'Red-light safety camera'
              : average
              ? 'Average-speed camera'
              : 'Fixed speed camera');
    return _language == 'zh-CN'
        ? '前方 $distanceMeters 米有$type，位于$roadName。请遵守限速。'
        : '$type in $distanceMeters metres on $roadName. Observe the posted speed limit.';
  }, stillRelevant: stillRelevant);

  Future<void> dispose() => stop();
}
