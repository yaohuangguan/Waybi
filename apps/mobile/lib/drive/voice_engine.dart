import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../domain/map_layer_settings.dart';
import 'custom_voice.dart';
import 'voice_clip_player.dart';

/// Order of spoken prompts. Within one priority, prompts play first-in,
/// first-out; a higher priority always plays before a lower one.
enum VoicePriority {
  /// Camera, road-event and transit-lane reminders.
  alert,

  /// Guidance such as "In 800 m, turn left" or trip messages.
  guidance,

  /// An imminent maneuver: interrupts an alert that is already speaking.
  urgent,
}

class _Utterance {
  _Utterance(
    this.message, {
    required this.language,
    required this.stillRelevant,
    required this.priority,
    required this.generation,
    required this.sequence,
  });
  final String Function() message;
  final String? language;
  final bool Function()? stillRelevant;
  final VoicePriority priority;
  final int generation;
  final int sequence;
  final completer = Completer<bool>();
  final _aborted = Completer<void>();
  bool get aborted => _aborted.isCompleted;

  bool get relevant => stillRelevant?.call() ?? true;

  void abort() {
    if (!_aborted.isCompleted) _aborted.complete();
    if (!completer.isCompleted) completer.complete(false);
  }
}

/// One completion-aware priority queue and temporary audio session for spoken
/// guidance. Speech never overlaps; turn prompts never wait behind alerts.
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
  int _sequence = 0;
  final List<_Utterance> _queue = [];
  _Utterance? _speaking;
  bool _pumping = false;

  /// New speech waits for a pending native stop, never for an abandoned
  /// completion (some engines never resolve a cancelled `speak`).
  Future<void> _barrier = Future<void>.value();

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
    VoicePriority priority = VoicePriority.alert,
  }) {
    final utterance = _Utterance(
      message,
      language: language,
      stillRelevant: stillRelevant,
      priority: priority,
      generation: _generation,
      sequence: _sequence++,
    );
    _queue.add(utterance);
    final current = _speaking;
    if (priority == VoicePriority.urgent &&
        current != null &&
        current.priority == VoicePriority.alert) {
      _interrupt(current);
    }
    unawaited(_pump());
    return utterance.completer.future;
  }

  void _interrupt(_Utterance current) {
    current.abort();
    final clipPlayer = _clipPlayer;
    final stopped = Future.wait<void>([
      _tts.stop().then<void>((_) {}),
      if (clipPlayer != null) clipPlayer.stop().catchError((Object _) {}),
    ]).then<void>((_) {}).whenComplete(_releaseIosAudio);
    _barrier = stopped.catchError((Object _) {});
  }

  _Utterance? _takeNext() {
    _Utterance? best;
    for (final candidate in _queue) {
      if (best == null ||
          candidate.priority.index > best.priority.index ||
          (candidate.priority == best.priority &&
              candidate.sequence < best.sequence)) {
        best = candidate;
      }
    }
    if (best != null) _queue.remove(best);
    return best;
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (_queue.isNotEmpty) {
        await _barrier;
        final next = _takeNext();
        if (next == null) break;
        await _speak(next);
      }
    } finally {
      _pumping = false;
    }
  }

  bool _live(_Utterance utterance) =>
      !utterance.aborted &&
      utterance.generation == _generation &&
      utterance.relevant;

  Future<void> _speak(_Utterance utterance) async {
    var prepared = false;
    Object? failure;
    StackTrace? failureStack;
    var spoken = false;
    try {
      if (!_live(utterance)) return;
      await initialize();
      if (!_live(utterance)) return;
      final text = utterance.message().trim();
      if (text.isEmpty) return;
      final speechLanguage = utterance.language ?? _language;
      await _tts.setLanguage(speechLanguage);
      final pack = speechLanguage.startsWith('zh') ? 'zh' : 'en';
      final segments = _plan(text, pack);
      for (final segment in segments) {
        // Configure mixing before activating; activating an exclusive session
        // even briefly can pause music without giving it a chance to resume.
        prepared = true;
        if (defaultTargetPlatform == TargetPlatform.iOS) {
          await _audioSession.invokeMethod<void>('prepare');
        }
        // Relevance is decided once, before the first word; a sentence that
        // has started finishes unless it is interrupted or stopped.
        if (identical(segment, segments.first) ? !_live(utterance)
            : utterance.aborted || utterance.generation != _generation) {
          return;
        }
        _speaking = utterance;
        if (segment is ClipSegment &&
            await _playClip(pack, segment, utterance)) {
          if (utterance.aborted) return;
          continue;
        }
        if (utterance.aborted || utterance.generation != _generation) return;
        final result = await Future.any<Object?>([
          Future<Object?>.value(_tts.speak(segment.text)),
          utterance._aborted.future,
        ]);
        if (utterance.aborted) return;
        if (result != 1 && result != true) {
          throw StateError('Speech did not complete');
        }
      }
      spoken = true;
    } catch (error, stack) {
      failure = error;
      failureStack = stack;
    } finally {
      if (identical(_speaking, utterance)) _speaking = null;
      // stop() and interruptions release their own session; a late
      // completion must not deactivate the next utterance's session.
      if (prepared &&
          !utterance.aborted &&
          utterance.generation == _generation) {
        await _releaseIosAudio();
      }
      if (!utterance.completer.isCompleted) {
        if (failure != null) {
          utterance.completer.completeError(failure, failureStack);
        } else {
          utterance.completer.complete(spoken);
        }
      }
    }
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
    _Utterance utterance,
  ) async {
    final clips = _customVoice;
    final path = clips?.clipPath(pack, segment.phraseId);
    if (clips == null || path == null) return false;
    try {
      await (_clipPlayer ??= _clipPlayerFactory()).play(path);
      return true;
    } catch (error) {
      // A stopped generation or an interrupted alert is not a broken clip.
      if (utterance.aborted || utterance.generation != _generation) {
        return true;
      }
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
    VoicePriority priority = VoicePriority.guidance,
  }) => _enqueue(
    () => message,
    language: language,
    stillRelevant: stillRelevant,
    priority: priority,
  ).then<void>((_) {});

  /// A maneuver prompt. [message] is built when it is spoken, so a distance
  /// reflects the car's position then, and [stillRelevant] drops a prompt the
  /// car has already passed. An [urgent] prompt interrupts a speaking alert.
  Future<bool> turnPrompt(
    String Function() message, {
    String? language,
    bool Function()? stillRelevant,
    bool urgent = false,
  }) => _enqueue(
    message,
    language: language,
    stillRelevant: stillRelevant,
    priority: urgent ? VoicePriority.urgent : VoicePriority.guidance,
  );

  Future<void> stop() async {
    ++_generation;
    final current = _speaking;
    final pending = List.of(_queue);
    _queue.clear();
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
    _barrier = released.catchError((Object _) {});
    current?.abort();
    for (final utterance in pending) {
      utterance.abort();
    }
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
