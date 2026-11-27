import 'dart:async';

import 'package:flutter/material.dart';

import '../data/voice_pack_repository.dart';
import '../drive/custom_voice.dart';
import '../drive/voice_clip_player.dart';
import '../drive/voice_recorder.dart';
import '../drive/voice_take_session.dart';
import '../theme/waybi_theme.dart';
import 'custom_voice_guided_page.dart';
import 'friendly_error.dart';
import 'voice_pack_import_page.dart';
import 'voice_pack_share_page.dart';

/// The navigation voice: choose the standard voice, your own recordings
/// (Waybi Plus: record, preview, re-record, delete, share) or a voice
/// someone shared with you (free).
class CustomVoicePage extends StatefulWidget {
  const CustomVoicePage({
    super.key,
    required this.controller,
    required this.language,
    this.initialPack,
    this.onOpenPlus,
    this.recorder,
    this.player,
    this.sharing,
    this.signedIn = false,
  });

  final CustomVoiceController controller;

  /// App language for this page's own text ('en' or 'zh').
  final String language;

  /// Which pack to show first ('en' or 'zh').
  final String? initialPack;
  final VoidCallback? onOpenPlus;
  final VoiceRecorder Function()? recorder;
  final VoiceClipPlayer Function()? player;

  /// Voice sharing; without it the sharing section is hidden.
  final VoicePackRepository? sharing;

  /// Signed in: the member's shared codes can be listed and revoked.
  final bool signedIn;

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

  List<SharedVoicePack>? _shared;
  bool _loadingShared = false;
  String? _sharedError;

  @override
  void initState() {
    super.initState();
    _voice.addListener(_changed);
    _takes.addListener(_changed);
    if (widget.sharing != null && widget.signedIn) unawaited(_loadShared());
  }

  Future<void> _loadShared() async {
    final sharing = widget.sharing;
    if (sharing == null || !widget.signedIn) return;
    setState(() {
      _loadingShared = true;
      _sharedError = null;
    });
    try {
      final packs = await sharing.mine();
      if (mounted) setState(() => _shared = packs);
    } catch (error) {
      if (mounted) {
        setState(
          () => _sharedError = friendlyErrorMessage(
            error,
            widget.language,
            fallback: _t(
              'Your shared voices couldn’t be loaded.',
              '暂时无法加载你分享的语音。',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingShared = false);
    }
  }

  Future<void> _openShare() async {
    final sharing = widget.sharing;
    if (sharing == null || !_voice.plus) return;
    await _takes.reset();
    if (!mounted) return;
    final shared = await Navigator.of(context).push<SharedVoicePack>(
      MaterialPageRoute(
        builder: (_) => VoicePackSharePage(
          controller: _voice,
          repository: sharing,
          language: widget.language,
        ),
      ),
    );
    if (shared != null) await _loadShared();
  }

  Future<void> _openImport() async {
    final sharing = widget.sharing;
    if (sharing == null) return;
    await _takes.reset();
    if (!mounted) return;
    final name = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => VoicePackImportPage(
          controller: _voice,
          repository: sharing,
          language: widget.language,
          player: widget.player,
        ),
      ),
    );
    if (name != null) _message(_t('Guidance now uses “$name”', '导航已改用“$name”'));
  }

  Future<void> _revoke(SharedVoicePack pack) async {
    final sharing = widget.sharing;
    if (sharing == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('Stop sharing “${pack.name}”?', '停止分享“${pack.name}”？')),
        content: Text(
          _t(
            'The code stops working and the recordings are deleted from Waybi. People who already installed this voice keep their copy.',
            '代码将失效，录音会从 Waybi 删除。已经安装的人会保留他们的副本。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_t('Cancel', '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_t('Stop sharing', '停止分享')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await sharing.revoke(pack.code);
      _message(_t('“${pack.name}” is no longer shared', '已停止分享“${pack.name}”'));
    } catch (error) {
      _message(
        friendlyErrorMessage(
          error,
          widget.language,
          fallback: _t(
            'The code couldn’t be revoked. Please try again.',
            '暂时无法撤销代码，请稍后重试。',
          ),
        ),
      );
    }
    await _loadShared();
  }

  Future<void> _removePack(InstalledVoicePack pack) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('Remove “${pack.name}”?', '移除“${pack.name}”？')),
        content: Text(
          _t(
            'Its recordings are deleted from this device. You can install it again with its code while it is still shared.',
            '它的录音会从本机删除。只要对方仍在分享，你可以用代码重新安装。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_t('Cancel', '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_t('Remove', '移除')),
          ),
        ],
      ),
    );
    if (confirmed == true) await _voice.removePack(pack.code);
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
          _voiceChoice(context, plus),
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
            onChanged: plus || _voice.installedPacks.isNotEmpty
                ? (value) => _voice.setOmitRoadNames(value)
                : null,
          ),
          const SizedBox(height: 4),
          _privacyNote(context),
          if (widget.sharing != null) ...[
            const SizedBox(height: 16),
            _sharingCard(context, plus),
          ],
          const SizedBox(height: 20),
          Semantics(
            header: true,
            child: Text(
              _t('My recordings', '我的录音'),
              style: context.textStyles.titleLarge,
            ),
          ),
          const SizedBox(height: 8),
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
                    'Recording your own voice is part of Waybi Plus',
                    '录制自己的声音是 Waybi Plus 功能',
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _t(
              'Anyone can use a voice someone shared with them. Recordings you made earlier stay on this device and can be deleted here.',
              '任何人都可以使用别人分享的语音。之前的录音仍保存在本机，可以在这里删除。',
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
            'Recordings stay on this device unless you choose to share your voice.',
            '除非你选择分享，录音只保存在本机。',
          ),
          style: context.textStyles.bodySmall,
        ),
      ),
    ],
  );

  Widget _voiceChoice(BuildContext context, bool plus) {
    final packCode = _voice.activePackCode;
    final selected = packCode != null
        ? 'pack:$packCode'
        : _voice.enabled && plus
        ? 'own'
        : 'standard';
    final ownCount = CustomVoiceController.languages.fold<int>(
      0,
      (sum, language) => sum + _voice.recorded(language).length,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            _t('Guidance voice', '导航语音'),
            style: context.textStyles.titleLarge,
          ),
        ),
        const SizedBox(height: 4),
        RadioGroup<String>(
          groupValue: selected,
          onChanged: (value) {
            if (value == null) return;
            if (value == 'standard') {
              unawaited(_voice.useStandardVoice());
            } else if (value == 'own') {
              unawaited(_voice.useOwnVoice());
            } else {
              unawaited(_voice.usePack(value.substring(5)));
            }
          },
          child: Column(
            children: [
              RadioListTile<String>(
                key: const ValueKey('custom-voice-use-standard'),
                contentPadding: EdgeInsets.zero,
                value: 'standard',
                title: Text(_t('Standard voice', '标准语音')),
              ),
              RadioListTile<String>(
                key: const ValueKey('custom-voice-use-own'),
                contentPadding: EdgeInsets.zero,
                value: 'own',
                enabled: plus,
                title: Text(_t('My recordings', '我的录音')),
                subtitle: Text(
                  plus
                      ? _t(
                          '$ownCount phrases recorded · the rest uses the standard voice',
                          '已录 $ownCount 条 · 其余使用标准语音',
                        )
                      : _t('Waybi Plus', 'Waybi Plus'),
                ),
              ),
              for (final pack in _voice.installedPacks)
                RadioListTile<String>(
                  key: ValueKey('custom-voice-use-pack-${pack.code}'),
                  contentPadding: EdgeInsets.zero,
                  value: 'pack:${pack.code}',
                  title: Text(pack.name),
                  subtitle: Text(
                    _t(
                      'Shared voice · ${pack.clipCount} phrases · ${VoicePackRepository.formatCode(pack.code)}',
                      '分享的语音 · ${pack.clipCount} 条短语 · ${VoicePackRepository.formatCode(pack.code)}',
                    ),
                  ),
                  secondary: IconButton(
                    key: ValueKey('custom-voice-remove-pack-${pack.code}'),
                    tooltip: _t('Remove from this device', '从本机移除'),
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => _removePack(pack),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sharingCard(BuildContext context, bool plus) {
    final hasRecordings = _voice.shareableRecordings().isNotEmpty;
    final shared = _shared ?? const <SharedVoicePack>[];
    return Card(
      key: const ValueKey('custom-voice-sharing'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _t('Shared voices', '分享语音'),
              style: context.textStyles.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              _t(
                'Share your recordings with a code, or use a voice someone sent you. There is no public list of voices.',
                '用代码分享你的录音，或使用别人发给你的语音。语音不会公开展示。',
              ),
              style: context.textStyles.bodySmall,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('custom-voice-import'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(WaybiTouch.minTarget),
              ),
              onPressed: _openImport,
              icon: const Icon(Icons.download_rounded),
              label: Text(_t('Use a shared voice', '使用分享的语音')),
            ),
            if (plus) ...[
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                key: const ValueKey('custom-voice-share'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(WaybiTouch.minTarget),
                ),
                onPressed: hasRecordings ? _openShare : null,
                icon: const Icon(Icons.ios_share_rounded),
                label: Text(_t('Share my voice', '分享我的声音')),
              ),
              if (!hasRecordings)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _t('Record some phrases first.', '请先录制一些短语。'),
                    style: context.textStyles.bodySmall,
                  ),
                ),
            ],
            if (_loadingShared) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_sharedError case final error?) ...[
              const SizedBox(height: 12),
              Text(error, style: TextStyle(color: context.status.danger)),
              TextButton(
                key: const ValueKey('custom-voice-shared-retry'),
                onPressed: _loadShared,
                child: Text(_t('Try again', '重试')),
              ),
            ],
            if (shared.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                _t('Your share codes', '你的分享代码'),
                style: context.textStyles.labelLarge,
              ),
              for (final pack in shared)
                ListTile(
                  key: ValueKey('custom-voice-shared-${pack.code}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(pack.name),
                  subtitle: Text(
                    _t(
                      '${pack.displayCode} · installed ${pack.importCount} times',
                      '${pack.displayCode} · 已安装 ${pack.importCount} 次',
                    ),
                  ),
                  trailing: TextButton(
                    key: ValueKey('custom-voice-revoke-${pack.code}'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(
                        WaybiTouch.minTarget,
                        WaybiTouch.minTarget,
                      ),
                    ),
                    onPressed: () => _revoke(pack),
                    child: Text(_t('Revoke', '撤销')),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

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
