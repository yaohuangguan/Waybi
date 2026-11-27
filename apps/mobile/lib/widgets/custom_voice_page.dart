import 'dart:async';

import 'package:flutter/material.dart';

import '../drive/custom_voice.dart';
import '../drive/voice_clip_player.dart';
import '../drive/voice_recorder.dart';

/// Waybi Plus: record, preview, re-record and delete custom guidance clips.
class CustomVoicePage extends StatefulWidget {
  const CustomVoicePage({
    super.key,
    required this.controller,
    required this.language,
    this.initialPack,
    this.onOpenPlus,
    this.recorder,
    this.player,
  });

  final CustomVoiceController controller;

  /// App language for this page's own text ('en' or 'zh').
  final String language;

  /// Which pack to show first ('en' or 'zh').
  final String? initialPack;
  final VoidCallback? onOpenPlus;
  final VoiceRecorder Function()? recorder;
  final VoiceClipPlayer Function()? player;

  static const maxRecording = Duration(seconds: 6);

  @override
  State<CustomVoicePage> createState() => _CustomVoicePageState();
}

class _CustomVoicePageState extends State<CustomVoicePage> {
  late String _pack = widget.initialPack == 'zh' ? 'zh' : 'en';
  VoiceRecorder? _recorder;
  VoiceClipPlayer? _player;
  String? _recordingId;
  Timer? _autoStop;
  ({String id, String path})? _draft;
  String? _playingId;

  CustomVoiceController get _voice => widget.controller;
  bool get _zh => widget.language == 'zh';
  String _t(String en, String zh) => _zh ? zh : en;

  @override
  void initState() {
    super.initState();
    _voice.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    if (!_voice.plus && _recordingId != null) unawaited(_cancelRecording());
    setState(() {});
  }

  @override
  void dispose() {
    _voice.removeListener(_changed);
    _autoStop?.cancel();
    final draft = _draft;
    if (draft != null) unawaited(_voice.discardDraft(draft.path));
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

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _record(VoicePhrase phrase) async {
    if (!_voice.plus) return;
    if (_recordingId == phrase.id) return _stopRecording();
    if (_recordingId != null) await _cancelRecording();
    await _discardDraft();
    await _stopPlayback();
    final recorder = _recorder ??= (widget.recorder ?? RecordVoiceRecorder.new)
        .call();
    try {
      if (!await recorder.requestPermission()) {
        _message(
          _t(
            'Microphone access is off. Allow it for Waybi in Settings to record.',
            '麦克风权限已关闭。请在系统设置中允许 Waybi 使用麦克风后再录音。',
          ),
        );
        return;
      }
      final path = await _voice.draftPath(_pack);
      await recorder.start(path);
      if (!mounted) return;
      setState(() => _recordingId = phrase.id);
      _autoStop = Timer(CustomVoicePage.maxRecording, _stopRecording);
    } catch (_) {
      _message(_t('Recording could not start.', '无法开始录音。'));
    }
  }

  Future<void> _stopRecording() async {
    _autoStop?.cancel();
    final id = _recordingId;
    if (id == null) return;
    String? path;
    try {
      path = await _recorder?.stop();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _recordingId = null;
      _draft = path == null ? null : (id: id, path: path);
    });
    if (path == null) {
      _message(_t('Nothing was recorded. Try again.', '没有录到声音，请重试。'));
    }
  }

  Future<void> _cancelRecording() async {
    _autoStop?.cancel();
    try {
      await _recorder?.cancel();
    } catch (_) {}
    if (mounted) setState(() => _recordingId = null);
  }

  Future<void> _discardDraft() async {
    final draft = _draft;
    if (draft == null) return;
    _draft = null;
    await _voice.discardDraft(draft.path);
    if (mounted) setState(() {});
  }

  Future<void> _keepDraft() async {
    final draft = _draft;
    if (draft == null) return;
    await _stopPlayback();
    final saved = await _voice.saveClip(_pack, draft.id, draft.path);
    if (!mounted) return;
    setState(() => _draft = null);
    if (!saved) {
      _message(
        _t(
          'That take was too short to use. Please record again.',
          '这段录音太短，请重新录制。',
        ),
      );
    }
  }

  Future<void> _play(String id, String? path, {bool draft = false}) async {
    if (path == null) return;
    await _stopPlayback();
    final player = _player ??= (widget.player ?? AudioplayersClipPlayer.new)
        .call();
    setState(() => _playingId = id);
    try {
      await player.play(path);
    } catch (_) {
      if (_playingId != id) return; // Stopped by the user.
      if (!draft) _voice.reportBroken(_pack, id);
      _message(
        _t(
          'This recording can’t be played. Please record it again.',
          '这段录音无法播放，请重新录制。',
        ),
      );
    } finally {
      if (mounted && _playingId == id) setState(() => _playingId = null);
    }
  }

  Future<void> _stopPlayback() async {
    if (_playingId == null) return;
    setState(() => _playingId = null);
    try {
      await _player?.stop();
    } catch (_) {}
  }

  Future<void> _delete(VoicePhrase phrase) async {
    await _stopPlayback();
    await _voice.deleteClip(_pack, phrase.id);
  }

  Future<void> _deleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('Delete all recordings?', '删除全部录音？')),
        content: Text(
          _t(
            'This removes your English and Chinese recordings from this device. Guidance will use the standard voice.',
            '将从本机删除你的中英文全部录音，导航会改用标准语音。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_t('Cancel', '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_t('Delete', '删除')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _stopPlayback();
    await _discardDraft();
    await _voice.deleteAll();
  }

  String _groupTitle(VoicePhraseGroup group) => switch (group) {
    VoicePhraseGroup.distance => _t('Distances', '距离'),
    VoicePhraseGroup.maneuver => _t('Turns and lanes', '转弯与车道'),
    VoicePhraseGroup.camera => _t('Camera alerts', '摄像头提醒'),
    VoicePhraseGroup.arrival => _t('Arrival', '到达'),
  };

  @override
  Widget build(BuildContext context) {
    final plus = _voice.plus;
    final recorded = _voice.recorded(_pack);
    final hasAny = CustomVoiceController.languages.any(
      (language) => _voice.recorded(language).isNotEmpty,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('My navigation voice', '我的导航语音')),
        actions: [
          if (hasAny)
            IconButton(
              key: const ValueKey('custom-voice-delete-all'),
              tooltip: _t('Delete all recordings', '删除全部录音'),
              icon: const Icon(Icons.delete_sweep_rounded),
              onPressed: _deleteAll,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (!plus)
            Card(
              key: const ValueKey('custom-voice-upsell'),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.lock_rounded),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _t(
                              'Custom navigation voice is part of Waybi Plus',
                              '自定义导航语音是 Waybi Plus 功能',
                            ),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _t(
                        'Guidance uses the standard voice. Any recordings you made earlier stay on this device and can be deleted here.',
                        '目前使用标准语音播报。之前的录音仍保存在本机，可以在这里删除。',
                      ),
                    ),
                    if (widget.onOpenPlus != null) ...[
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: widget.onOpenPlus,
                        child: Text(_t('See Waybi Plus', '了解 Waybi Plus')),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          SwitchListTile(
            key: const ValueKey('custom-voice-enabled'),
            contentPadding: EdgeInsets.zero,
            title: Text(_t('Use my voice for guidance', '导航使用我的声音')),
            subtitle: Text(
              _t(
                'Phrases you haven’t recorded, road names and other numbers use the standard voice.',
                '没录的短语、路名和其他数字仍由标准语音播报。',
              ),
            ),
            value: plus && _voice.enabled,
            onChanged: plus ? (value) => _voice.setEnabled(value) : null,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.phone_iphone_rounded, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _t(
                    'Recordings stay on this device. Waybi never uploads them.',
                    '录音只保存在本机，Waybi 不会上传。',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'en', label: Text('English')),
              ButtonSegment(value: 'zh', label: Text('中文')),
            ],
            selected: {_pack},
            onSelectionChanged: (value) async {
              if (_recordingId != null) await _cancelRecording();
              await _discardDraft();
              await _stopPlayback();
              setState(() => _pack = value.first);
            },
          ),
          const SizedBox(height: 8),
          Text(
            _t(
              '${recorded.length} of ${customVoicePhrases.length} phrases recorded',
              '已录 ${recorded.length} / ${customVoicePhrases.length} 条短语',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (final group in VoicePhraseGroup.values) ...[
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 4),
              child: Text(
                _groupTitle(group),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final phrase in customVoicePhrases.where(
              (phrase) => phrase.group == group,
            ))
              _phraseRow(phrase, recorded.contains(phrase.id), plus),
          ],
        ],
      ),
    );
  }

  Widget _phraseRow(VoicePhrase phrase, bool recorded, bool plus) {
    final recording = _recordingId == phrase.id;
    final draft = _draft?.id == phrase.id ? _draft : null;
    final broken = recorded && _voice.isBroken(_pack, phrase.id);
    final status = recording
        ? _t('Recording… tap stop when done', '录音中…读完点停止')
        : draft != null
        ? _t('New take — keep it?', '新录音，要保留吗？')
        : broken
        ? _t('Can’t be played — please re-record', '无法播放，请重新录制')
        : recorded
        ? _t('Recorded', '已录制')
        : _t('Standard voice', '标准语音');
    return ListTile(
      key: ValueKey('custom-voice-${phrase.id}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        broken
            ? Icons.error_outline_rounded
            : recorded
            ? Icons.check_circle_rounded
            : Icons.radio_button_unchecked_rounded,
        color: broken
            ? Theme.of(context).colorScheme.error
            : recorded
            ? Theme.of(context).colorScheme.primary
            : null,
      ),
      title: Text('“${phrase.prompt(_pack)}”'),
      subtitle: Text(status),
      trailing: Wrap(
        spacing: 0,
        children: [
          if (draft != null) ...[
            IconButton(
              key: ValueKey('custom-voice-play-draft-${phrase.id}'),
              tooltip: _t('Play new take', '试听新录音'),
              icon: const Icon(Icons.play_arrow_rounded),
              onPressed: () => _play(phrase.id, draft.path, draft: true),
            ),
            IconButton(
              key: ValueKey('custom-voice-keep-${phrase.id}'),
              tooltip: _t('Keep', '保留'),
              icon: const Icon(Icons.check_rounded),
              onPressed: _keepDraft,
            ),
            IconButton(
              key: ValueKey('custom-voice-discard-${phrase.id}'),
              tooltip: _t('Discard', '放弃'),
              icon: const Icon(Icons.close_rounded),
              onPressed: _discardDraft,
            ),
          ] else ...[
            if (recorded && !recording)
              IconButton(
                key: ValueKey('custom-voice-play-${phrase.id}'),
                tooltip: _t('Play', '试听'),
                icon: Icon(
                  _playingId == phrase.id
                      ? Icons.stop_rounded
                      : Icons.play_arrow_rounded,
                ),
                onPressed: _playingId == phrase.id
                    ? _stopPlayback
                    : () => _play(phrase.id, _voice.clipPath(_pack, phrase.id)),
              ),
            if (recorded && !recording)
              IconButton(
                key: ValueKey('custom-voice-delete-${phrase.id}'),
                tooltip: _t('Delete', '删除'),
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () => _delete(phrase),
              ),
            IconButton(
              key: ValueKey('custom-voice-record-${phrase.id}'),
              tooltip: recording
                  ? _t('Stop', '停止')
                  : recorded
                  ? _t('Re-record', '重新录制')
                  : _t('Record', '录制'),
              icon: Icon(recording ? Icons.stop_circle_rounded : Icons.mic),
              color: recording ? Theme.of(context).colorScheme.error : null,
              onPressed: plus ? () => _record(phrase) : null,
            ),
          ],
        ],
      ),
    );
  }
}
