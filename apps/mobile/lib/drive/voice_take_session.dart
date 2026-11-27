import 'dart:async';

import 'package:flutter/foundation.dart';

import 'custom_voice.dart';
import 'voice_clip_player.dart';
import 'voice_recorder.dart';

/// Something that went wrong while recording or previewing, for the page to
/// explain in its own language.
enum VoiceTakeIssue {
  microphoneDenied,
  couldNotStart,
  nothingRecorded,
  tooShort,
  unplayable,
}

/// Records, previews, keeps or discards one take at a time for a language
/// pack. Shared by the phrase list and the "record missing phrases" flow so
/// both behave the same.
class VoiceTakeSession extends ChangeNotifier {
  VoiceTakeSession({
    required this.voice,
    required this.language,
    VoiceRecorder Function()? recorder,
    VoiceClipPlayer Function()? player,
    this.maxRecording = const Duration(seconds: 6),
    this.onIssue,
  }) : _recorderFactory = recorder ?? RecordVoiceRecorder.new,
       _playerFactory = player ?? AudioplayersClipPlayer.new;

  final CustomVoiceController voice;

  /// The pack being recorded ('en' or 'zh').
  String language;
  final Duration maxRecording;
  final void Function(VoiceTakeIssue issue)? onIssue;
  final VoiceRecorder Function() _recorderFactory;
  final VoiceClipPlayer Function() _playerFactory;
  VoiceRecorder? _recorder;
  VoiceClipPlayer? _player;
  Timer? _autoStop;
  bool _disposed = false;

  String? _recordingId;
  ({String id, String path})? _draft;
  String? _playingId;

  /// The phrase being recorded now.
  String? get recordingId => _recordingId;

  /// A finished take waiting to be kept or discarded.
  ({String id, String path})? get draft => _draft;
  String? get playingId => _playingId;
  bool get busy => _recordingId != null;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _issue(VoiceTakeIssue issue) {
    if (!_disposed) onIssue?.call(issue);
  }

  /// Starts recording [phraseId], or stops if it is already recording.
  Future<void> record(String phraseId) async {
    if (!voice.plus) return;
    if (_recordingId == phraseId) return stopRecording();
    if (_recordingId != null) await cancelRecording();
    await discardDraft();
    await stopPlayback();
    final recorder = _recorder ??= _recorderFactory();
    try {
      if (!await recorder.requestPermission()) {
        _issue(VoiceTakeIssue.microphoneDenied);
        return;
      }
      final path = await voice.draftPath(language);
      await recorder.start(path);
      if (_disposed) return;
      _recordingId = phraseId;
      _autoStop = Timer(maxRecording, stopRecording);
      _changed();
    } catch (_) {
      _issue(VoiceTakeIssue.couldNotStart);
    }
  }

  Future<void> stopRecording() async {
    _autoStop?.cancel();
    final id = _recordingId;
    if (id == null) return;
    String? path;
    try {
      path = await _recorder?.stop();
    } catch (_) {}
    _recordingId = null;
    _draft = path == null ? null : (id: id, path: path);
    _changed();
    if (path == null) _issue(VoiceTakeIssue.nothingRecorded);
  }

  Future<void> cancelRecording() async {
    _autoStop?.cancel();
    if (_recordingId == null) return;
    try {
      await _recorder?.cancel();
    } catch (_) {}
    _recordingId = null;
    _changed();
  }

  Future<void> discardDraft() async {
    final draft = _draft;
    if (draft == null) return;
    _draft = null;
    _changed();
    await voice.discardDraft(draft.path);
  }

  /// Keeps the take; false (and [VoiceTakeIssue.tooShort]) if it was too
  /// short to use.
  Future<bool> keepDraft() async {
    final draft = _draft;
    if (draft == null) return false;
    await stopPlayback();
    final saved = await voice.saveClip(language, draft.id, draft.path);
    _draft = null;
    _changed();
    if (!saved) _issue(VoiceTakeIssue.tooShort);
    return saved;
  }

  /// Plays [path]. A recording that cannot be played is flagged so guidance
  /// skips it; a draft is not.
  Future<void> play(String id, String? path, {bool draft = false}) async {
    if (path == null) return;
    await stopPlayback();
    final player = _player ??= _playerFactory();
    _playingId = id;
    _changed();
    try {
      await player.play(path);
    } catch (_) {
      if (_playingId != id) return; // Stopped by the user.
      if (!draft) voice.reportBroken(language, id);
      _issue(VoiceTakeIssue.unplayable);
    } finally {
      if (_playingId == id) {
        _playingId = null;
        _changed();
      }
    }
  }

  Future<void> stopPlayback() async {
    if (_playingId == null) return;
    _playingId = null;
    _changed();
    try {
      await _player?.stop();
    } catch (_) {}
  }

  /// Cancels anything in progress, for a language switch or a lost
  /// entitlement.
  Future<void> reset() async {
    await cancelRecording();
    await discardDraft();
    await stopPlayback();
  }

  @override
  void dispose() {
    _disposed = true;
    _autoStop?.cancel();
    final draft = _draft;
    if (draft != null) unawaited(voice.discardDraft(draft.path));
    final recorder = _recorder;
    if (recorder != null) {
      unawaited(
        (_recordingId != null ? recorder.cancel() : Future<void>.value())
            .catchError((Object _) {})
            .whenComplete(() => recorder.dispose().catchError((Object _) {})),
      );
    }
    unawaited(_player?.dispose().catchError((Object _) {}));
    super.dispose();
  }
}
