import 'dart:async';

import 'package:flutter/material.dart';

import '../drive/custom_voice.dart';
import '../drive/voice_clip_player.dart';
import '../drive/voice_recorder.dart';
import '../drive/voice_take_session.dart';
import '../theme/waybi_theme.dart';
import 'custom_voice_guided_page.dart';

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

/// Localized wording for a take problem.
String voiceTakeIssueText(VoiceTakeIssue issue, bool zh) {
  String t(String en, String cn) => zh ? cn : en;
  return switch (issue) {
    VoiceTakeIssue.microphoneDenied => t(
      'Microphone access is off. Allow it for Waybi in Settings to record.',
      '麦克风权限已关闭。请在系统设置中允许 Waybi 使用麦克风后再录音。',
    ),
    VoiceTakeIssue.couldNotStart => t('Recording could not start.', '无法开始录音。'),
    VoiceTakeIssue.nothingRecorded => t(
      'Nothing was recorded. Try again.',
      '没有录到声音，请重试。',
    ),
    VoiceTakeIssue.tooShort => t(
      'That take was too short to use. Please record again.',
      '这段录音太短，请重新录制。',
    ),
    VoiceTakeIssue.unplayable => t(
      'This recording can’t be played. Please record it again.',
      '这段录音无法播放，请重新录制。',
    ),
  };
}

/// Section titles of the recording page.
String voicePhraseGroupTitle(VoicePhraseGroup group, bool zh) {
  String t(String en, String cn) => zh ? cn : en;
  return switch (group) {
    VoicePhraseGroup.distance => t('Distances', '距离'),
    VoicePhraseGroup.maneuver => t('Turns', '转弯与车道'),
    VoicePhraseGroup.connector => t('Connecting words', '连接词'),
    VoicePhraseGroup.camera => t('Cameras', '摄像头提醒'),
    VoicePhraseGroup.roadAlert => t('Road alerts', '道路提醒'),
    VoicePhraseGroup.trip => t('Trip messages', '行程消息'),
    VoicePhraseGroup.arrival => t('Arrival', '到达'),
  };
}

class _CustomVoicePageState extends State<CustomVoicePage> {
  late String _pack = widget.initialPack == 'zh' ? 'zh' : 'en';
  late final VoiceTakeSession _takes = VoiceTakeSession(
    voice: _voice,
    language: _pack,
    recorder: widget.recorder,
    player: widget.player,
    maxRecording: CustomVoicePage.maxRecording,
    onIssue: (issue) => _message(voiceTakeIssueText(issue, _zh)),
  );

  CustomVoiceController get _voice => widget.controller;
  bool get _zh => widget.language == 'zh';
  String _t(String en, String zh) => _zh ? zh : en;

  @override
  void initState() {
    super.initState();
    _voice.addListener(_changed);
    _takes.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    if (!_voice.plus && _takes.busy) unawaited(_takes.cancelRecording());
    setState(() {});
  }

  @override
  void dispose() {
    _voice.removeListener(_changed);
    _takes.removeListener(_changed);
    _takes.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _delete(VoicePhrase phrase) async {
    await _takes.stopPlayback();
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
    await _takes.reset();
    await _voice.deleteAll();
  }

  List<VoicePhrase> get _missing => [
    for (final phrase in voicePhrasesFor(_pack))
      if (!_voice.recorded(_pack).contains(phrase.id) ||
          _voice.isBroken(_pack, phrase.id))
        phrase,
  ];

  Future<void> _recordMissing() async {
    final missing = _missing;
    if (missing.isEmpty || !_voice.plus) return;
    await _takes.reset();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CustomVoiceGuidedPage(
          controller: _voice,
          language: widget.language,
          pack: _pack,
          phrases: missing,
          recorder: widget.recorder,
          player: widget.player,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plus = _voice.plus;
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
          if (!plus) _upsell(context),
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
          SwitchListTile(
            key: const ValueKey('custom-voice-omit-roads'),
            contentPadding: EdgeInsets.zero,
            title: Text(_t('Don’t read road names', '不播报路名')),
            subtitle: Text(
              _t(
                'Leaves out road names and the words before them, so a fully recorded voice is the only voice you hear.',
                '省略路名及前面的连接词；录完全部短语后，导航只会用你的声音。',
              ),
            ),
            value: _voice.omitRoadNames,
            onChanged: plus ? (value) => _voice.setOmitRoadNames(value) : null,
          ),
          const SizedBox(height: 4),
          _privacyNote(context),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'en', label: Text('English')),
              ButtonSegment(value: 'zh', label: Text('中文')),
            ],
            selected: {_pack},
            onSelectionChanged: (value) async {
              await _takes.reset();
              setState(() {
                _pack = value.first;
                _takes.language = _pack;
              });
            },
          ),
          const SizedBox(height: 12),
          _completeness(context, plus),
          for (final group in VoicePhraseGroup.values)
            if (voicePhrasesFor(_pack, group).isNotEmpty) ...[
              _groupHeader(context, group),
              for (final phrase in voicePhrasesFor(_pack, group))
                _phraseRow(
                  phrase,
                  _voice.recorded(_pack).contains(phrase.id),
                  plus,
                ),
            ],
        ],
      ),
    );
  }

  Widget _upsell(BuildContext context) => Card(
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
  );

  Widget _privacyNote(BuildContext context) => Row(
    children: [
      const Icon(Icons.phone_iphone_rounded, size: 18),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          _t(
            'Recordings stay on this device. Waybi never uploads them.',
            '录音只保存在本机，Waybi 不会上传。',
          ),
          style: context.textStyles.bodySmall,
        ),
      ),
    ],
  );

  Widget _completeness(BuildContext context, bool plus) {
    final total = voicePhrasesFor(_pack).length;
    final missing = _missing.length;
    final done = total - missing;
    return Card(
      key: const ValueKey('custom-voice-progress'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              missing == 0
                  ? _t(
                      'All $total phrases recorded — every fixed word is in your voice',
                      '已录全部 $total 条短语，所有固定播报都是你的声音',
                    )
                  : _t(
                      '$done of $total recorded — unrecorded phrases use the standard voice',
                      '已录 $done / $total 条，没录的短语使用标准语音',
                    ),
              style: context.textStyles.titleSmall,
            ),
            const SizedBox(height: 8),
            Semantics(
              label: _t('Recording progress', '录制进度'),
              value: '$done / $total',
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : done / total,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            if (missing > 0 && plus) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey('custom-voice-record-missing'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(WaybiTouch.minTarget),
                ),
                onPressed: _recordMissing,
                icon: const Icon(Icons.mic_rounded),
                label: Text(
                  _t('Record missing phrases ($missing)', '录制缺少的短语（$missing）'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _groupHeader(BuildContext context, VoicePhraseGroup group) {
    final phrases = voicePhrasesFor(_pack, group);
    final recorded = phrases
        .where((phrase) => _voice.recorded(_pack).contains(phrase.id))
        .length;
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 4),
      child: Semantics(
        header: true,
        child: Row(
          children: [
            Expanded(
              child: Text(
                voicePhraseGroupTitle(group, _zh),
                style: context.textStyles.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              _t(
                '$recorded of ${phrases.length}',
                '$recorded / ${phrases.length}',
              ),
              key: ValueKey('custom-voice-group-${group.name}'),
              style: context.textStyles.bodySmall?.copyWith(
                color: recorded == phrases.length
                    ? context.status.success
                    : context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _phraseRow(VoicePhrase phrase, bool recorded, bool plus) {
    final recording = _takes.recordingId == phrase.id;
    final draft = _takes.draft?.id == phrase.id ? _takes.draft : null;
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
            ? context.status.danger
            : recorded
            ? context.status.success
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
              onPressed: () => _takes.play(phrase.id, draft.path, draft: true),
            ),
            IconButton(
              key: ValueKey('custom-voice-keep-${phrase.id}'),
              tooltip: _t('Keep', '保留'),
              icon: const Icon(Icons.check_rounded),
              onPressed: _takes.keepDraft,
            ),
            IconButton(
              key: ValueKey('custom-voice-discard-${phrase.id}'),
              tooltip: _t('Discard', '放弃'),
              icon: const Icon(Icons.close_rounded),
              onPressed: _takes.discardDraft,
            ),
          ] else ...[
            if (recorded && !recording)
              IconButton(
                key: ValueKey('custom-voice-play-${phrase.id}'),
                tooltip: _t('Play', '试听'),
                icon: Icon(
                  _takes.playingId == phrase.id
                      ? Icons.stop_rounded
                      : Icons.play_arrow_rounded,
                ),
                onPressed: _takes.playingId == phrase.id
                    ? _takes.stopPlayback
                    : () => _takes.play(
                        phrase.id,
                        _voice.recordingPath(_pack, phrase.id),
                      ),
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
              color: recording ? context.status.danger : null,
              onPressed: plus ? () => _takes.record(phrase.id) : null,
            ),
          ],
        ],
      ),
    );
  }
}
