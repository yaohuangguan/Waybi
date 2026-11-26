import 'package:record/record.dart';

/// Records one short custom-voice clip to a local file.
abstract class VoiceRecorder {
  /// Asks for microphone access when needed. False if the user declined.
  Future<bool> requestPermission();
  Future<void> start(String path);

  /// Returns the finished file path, or null if nothing was recorded.
  Future<String?> stop();
  Future<void> cancel();
  Future<void> dispose();
}

class RecordVoiceRecorder implements VoiceRecorder {
  RecordVoiceRecorder({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();
  final AudioRecorder _recorder;

  @override
  Future<bool> requestPermission() => _recorder.hasPermission();

  @override
  Future<void> start(String path) => _recorder.start(
    const RecordConfig(
      encoder: AudioEncoder.aacLc,
      numChannels: 1,
      sampleRate: 44100,
      bitRate: 96000,
      noiseSuppress: true,
    ),
    path: path,
  );

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Future<void> dispose() => _recorder.dispose();
}
