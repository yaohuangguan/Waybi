import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

/// Plays one recorded guidance clip and completes when it finishes.
abstract class VoiceClipPlayer {
  /// Throws if the clip cannot be played to the end.
  Future<void> play(String path);
  Future<void> stop();
  Future<void> dispose();
}

/// Plays clips with the same audio routing as navigation TTS: navigation
/// guidance usage with transient ducking focus on Android, and a mixing,
/// ducking voice-prompt style session on iOS.
class AudioplayersClipPlayer implements VoiceClipPlayer {
  AudioplayersClipPlayer({AudioPlayer? player})
    : _player = player ?? AudioPlayer();
  final AudioPlayer _player;
  bool _configured = false;

  static const maxClipDuration = Duration(seconds: 8);

  static final navigationContext = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.speech,
      usageType: AndroidUsageType.assistanceNavigationGuidance,
      audioFocus: AndroidAudioFocus.gainTransientMayDuck,
    ),
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playback,
      options: const {
        AVAudioSessionOptions.mixWithOthers,
        AVAudioSessionOptions.duckOthers,
      },
    ),
  );

  @override
  Future<void> play(String path) async {
    if (!_configured) {
      await _player.setAudioContext(navigationContext);
      await _player.setReleaseMode(ReleaseMode.stop);
      _configured = true;
    }
    final done = Completer<void>();
    final complete = _player.onPlayerComplete.listen((_) {
      if (!done.isCompleted) done.complete();
    });
    final state = _player.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.stopped && !done.isCompleted) {
        done.completeError(StateError('Clip stopped'));
      }
    });
    try {
      await _player.play(DeviceFileSource(path));
      await done.future.timeout(maxClipDuration);
    } finally {
      await complete.cancel();
      await state.cancel();
    }
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}
