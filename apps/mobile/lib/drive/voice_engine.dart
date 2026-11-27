import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../domain/map_layer_settings.dart';

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
class VoiceEngine {
  VoiceEngine({FlutterTts? tts}) : _tts = tts ?? FlutterTts();
  final FlutterTts _tts;
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
    final stopped = _tts
        .stop()
        .then<void>((_) {})
        .whenComplete(_releaseIosAudio);
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
      await _tts.setLanguage(utterance.language ?? _language);
      // Configure mixing before activating; activating an exclusive session
      // even briefly can pause music without giving it a chance to resume.
      prepared = true;
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _audioSession.invokeMethod<void>('prepare');
      }
      if (!_live(utterance)) return;
      _speaking = utterance;
      final result = await Future.any<Object?>([
        Future<Object?>.value(_tts.speak(text)),
        utterance._aborted.future,
      ]);
      if (utterance.aborted) return;
      if (result != 1 && result != true) {
        throw StateError('Speech did not complete');
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
    final stopped = _initializing == null
        ? Future<void>.value()
        : _tts.stop().then<void>((_) {}).whenComplete(_releaseIosAudio);
    // Some engines do not resolve speak() when cancelled. New speech must
    // wait for stop(), without waiting on that abandoned completion future.
    _barrier = stopped.catchError((Object _) {});
    current?.abort();
    for (final utterance in pending) {
      utterance.abort();
    }
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
