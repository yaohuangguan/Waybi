import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../domain/map_layer_settings.dart';

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
    await _configureIosAudio();
  }

  Future<void> _configureIosAudio() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
        IosTextToSpeechAudioCategoryOptions.duckOthers,
        IosTextToSpeechAudioCategoryOptions.allowBluetooth,
      ], IosTextToSpeechAudioMode.voicePrompt);
    }
  }

  Future<bool> _enqueue(
    String Function() message, {
    String? language,
    bool Function()? stillRelevant,
  }) {
    final generation = _generation;
    final speech = _speechQueue.catchError((Object _) {}).then((_) async {
      if (generation != _generation || !(stillRelevant?.call() ?? true)) {
        return false;
      }
      await initialize();
      if (generation != _generation || !(stillRelevant?.call() ?? true)) {
        return false;
      }
      await _tts.setLanguage(language ?? _language);
      // The native navigation SDK can change the shared session after our
      // initial setup. Restore playback routing immediately before speech.
      await _configureIosAudio();
      if (generation != _generation || !(stillRelevant?.call() ?? true)) {
        return false;
      }
      final text = message().trim();
      if (text.isEmpty) return false;
      final result = await _tts.speak(text);
      if (result != 1 && result != true) {
        throw StateError('Speech did not complete');
      }
      return true;
    });
    _speechQueue = speech.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return speech;
  }

  Future<void> guidance(
    String message, {
    String? language,
    bool Function()? stillRelevant,
  }) => _enqueue(
    () => message,
    language: language,
    stillRelevant: stillRelevant,
  ).then<void>((_) {});

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

  Future<bool> cameraAlert({
    required int distanceMeters,
    required String cameraType,
    required String roadName,
    String? speedLimit,
    int Function()? currentDistanceMeters,
    bool Function()? stillRelevant,
  }) => _enqueue(() {
    final kind = CameraKindLabel.fromType(cameraType);
    final type = kind == CameraKind.spotSpeed && _language != 'zh-CN'
        ? 'Fixed speed camera'
        : kind.cameraLabel(_language == 'zh-CN' ? 'zh' : 'en');
    final metres = currentDistanceMeters?.call() ?? distanceMeters;
    final road = roadName.trim().isEmpty
        ? ''
        : (_language == 'zh-CN' ? '，位于$roadName' : ' on $roadName');
    return _language == 'zh-CN'
        ? '前方 $metres 米有$type$road。'
        : '$type in $metres metres$road.';
  }, stillRelevant: stillRelevant);

  Future<void> dispose() => stop();
  Future<bool> roadAlert(
    String Function() message, {
    String? language,
    bool Function()? stillRelevant,
  }) => _enqueue(message, language: language, stillRelevant: stillRelevant);
}
