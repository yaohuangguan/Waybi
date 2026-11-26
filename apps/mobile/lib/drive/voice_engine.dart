import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../domain/map_layer_settings.dart';
import 'custom_voice.dart';
import 'voice_clip_player.dart';

/// One completion-aware queue and temporary audio session for spoken guidance.
///
/// When a Waybi Plus member has recorded a custom voice pack, sentences are
/// split into recorded clips and TTS text. Any clip that is missing or fails
/// to play is spoken by TTS instead, so guidance never goes silent.
class VoiceEngine {
  VoiceEngine({
    FlutterTts? tts,
    this._customVoice,
    VoiceClipPlayer Function()? clipPlayer,
  }) : _tts = tts ?? FlutterTts(),
       _clipPlayerFactory = clipPlayer ?? AudioplayersClipPlayer.new;
  final FlutterTts _tts;
  CustomVoiceClips? _customVoice;
  final VoiceClipPlayer Function() _clipPlayerFactory;
  VoiceClipPlayer? _clipPlayer;

  set customVoice(CustomVoiceClips? clips) => _customVoice = clips;
  static const _audioSession = MethodChannel('waybi/navigation_audio');
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
      await _tts.autoStopSharedSession(true);
    }
  }

  Future<void> _releaseIosAudio() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await _audioSession.invokeMethod<void>('release');
    } catch (error) {
      debugPrint('Navigation audio release failed: $error');
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
      final text = message().trim();
      if (text.isEmpty) return false;
      final speechLanguage = language ?? _language;
      await _tts.setLanguage(speechLanguage);
      final pack = speechLanguage.startsWith('zh') ? 'zh' : 'en';
      final segments = _plan(text, pack);
      try {
        for (final segment in segments) {
          // Configure mixing before activating; activating an exclusive
          // session even briefly can pause music without giving it a chance
          // to resume.
          if (defaultTargetPlatform == TargetPlatform.iOS) {
            await _audioSession.invokeMethod<void>('prepare');
          }
          if (generation != _generation ||
              (segment == segments.first && !(stillRelevant?.call() ?? true))) {
            return false;
          }
          if (segment is ClipSegment &&
              await _playClip(pack, segment, generation)) {
            continue;
          }
          if (generation != _generation) return false;
          final result = await _tts.speak(segment.text);
          if (result != 1 && result != true) {
            throw StateError('Speech did not complete');
          }
        }
        return true;
      } finally {
        // stop() releases a cancelled generation before allowing new speech.
        // A late completion must not deactivate that new speech's session.
        if (generation == _generation) await _releaseIosAudio();
      }
    });
    _speechQueue = speech.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return speech;
  }

  List<VoiceSegment> _plan(String text, String pack) {
    final clips = _customVoice;
    if (clips == null) return [TtsSegment(text)];
    try {
      final playable = clips.playable(pack);
      if (playable.isEmpty) return [TtsSegment(text)];
      return planCustomVoice(text, pack, playable);
    } catch (error) {
      debugPrint('Custom voice planning failed: $error');
      return [TtsSegment(text)];
    }
  }

  /// True when the clip played to the end. False means: speak it with TTS.
  Future<bool> _playClip(
    String pack,
    ClipSegment segment,
    int generation,
  ) async {
    final clips = _customVoice;
    final path = clips?.clipPath(pack, segment.phraseId);
    if (clips == null || path == null) return false;
    try {
      await (_clipPlayer ??= _clipPlayerFactory()).play(path);
      return true;
    } catch (error) {
      // A cancelled generation is not a broken clip.
      if (generation != _generation) return true;
      debugPrint('Custom voice clip ${segment.phraseId} failed: $error');
      clips.reportBroken(pack, segment.phraseId);
      try {
        await _clipPlayer?.stop();
      } catch (_) {}
      return false;
    }
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
    final clipPlayer = _clipPlayer;
    final stopped = Future.wait<void>([
      if (_initializing != null) _tts.stop().then<void>((_) {}),
      if (clipPlayer != null) clipPlayer.stop().catchError((Object _) {}),
    ]).then<void>((_) {});
    final released = _initializing == null && clipPlayer == null
        ? stopped
        : stopped.whenComplete(_releaseIosAudio);
    // Some engines do not resolve speak() when cancelled. New speech must
    // wait for stop(), without waiting on that abandoned completion future.
    _speechQueue = released;
    await released;
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

  Future<void> dispose() async {
    await stop();
    final player = _clipPlayer;
    _clipPlayer = null;
    await player?.dispose();
  }

  Future<bool> roadAlert(
    String Function() message, {
    String? language,
    bool Function()? stillRelevant,
  }) => _enqueue(message, language: language, stillRelevant: stillRelevant);
}
