import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/voice_pack_repository.dart';
import '../drive/custom_voice.dart';
import '../drive/voice_clip_player.dart';
import '../theme/waybi_theme.dart';
import 'friendly_error.dart';

/// Anyone: enter a code or paste a link, preview a few clips, and install
/// a voice someone shared. Installing is free; the voice then plays for
/// guidance like a member's own recordings.
class VoicePackImportPage extends StatefulWidget {
  const VoicePackImportPage({
    super.key,
    required this.controller,
    required this.repository,
    required this.language,
    this.initialCode,
    this.player,
  });

  final CustomVoiceController controller;
  final VoicePackRepository repository;

  /// App language for this page's text.
  final String language;
  final String? initialCode;
  final VoiceClipPlayer Function()? player;

  /// Clips downloaded at once while installing.
  static const parallelDownloads = 4;

  /// Phrases offered as a preview, in order of preference.
  static const previewPhrases = [
    'turn_left',
    'in_300',
    'arrived',
    'turn_right',
    'camera_speed',
    'keep_left',
    'merge',
  ];

  @override
  State<VoicePackImportPage> createState() => _VoicePackImportPageState();
}

class _VoicePackImportPageState extends State<VoicePackImportPage> {
  late final _code = TextEditingController(text: widget.initialCode ?? '');
  SharedVoicePack? _pack;
  bool _looking = false;
  bool _installing = false;
  double? _progress;
  String? _error;
  String? _playing;
  VoiceClipPlayer? _player;

  bool get _zh => widget.language == 'zh';
  String _t(String en, String zh) => _zh ? zh : en;

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
    if (widget.initialCode != null) unawaited(_lookUp());
  }

  @override
  void dispose() {
    _code.dispose();
    unawaited(_player?.dispose().catchError((Object _) {}));
    super.dispose();
  }

  String _failure(Object error, String fallback) =>
      friendlyErrorMessage(error, widget.language, fallback: fallback);

  Future<void> _lookUp() async {
    final code = VoicePackRepository.normalizeCode(_code.text);
    if (code == null) {
      setState(
        () => _error = _t(
          'Enter the 10-character code or paste the link you were sent.',
          '请输入 10 位代码，或粘贴收到的链接。',
        ),
      );
      return;
    }
    setState(() {
      _looking = true;
      _error = null;
      _pack = null;
    });
    try {
      final pack = await widget.repository.fetch(code);
      if (mounted) setState(() => _pack = pack);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = _failure(
            error,
            _t('This voice couldn’t be found.', '找不到这个语音。'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _looking = false);
    }
  }

  /// Phrases this app understands, per language in the pack.
  Map<String, List<String>> _installable(SharedVoicePack pack) => {
    for (final MapEntry(key: language, value: clips) in pack.clips.entries)
      if (CustomVoiceController.languages.contains(language))
        language: [
          for (final id in clips.keys)
            if (customVoicePhrase(id)?.availableIn(language) ?? false) id,
        ],
  };

  List<(String, String)> _previews(SharedVoicePack pack) {
    final installable = _installable(pack);
    final preferred = widget.language == 'zh' ? ['zh', 'en'] : ['en', 'zh'];
    for (final language in preferred) {
      final ids = installable[language] ?? const [];
      final picks = [
        for (final id in VoicePackImportPage.previewPhrases)
          if (ids.contains(id)) (language, id),
      ];
      if (picks.isNotEmpty) return picks.take(3).toList();
      if (ids.isNotEmpty) {
        return [for (final id in ids.take(3)) (language, id)];
      }
    }
    return const [];
  }

  Future<void> _preview(
    SharedVoicePack pack,
    String language,
    String id,
  ) async {
    final key = '$language/$id';
    final player = _player ??= (widget.player ?? AudioplayersClipPlayer.new)
        .call();
    if (_playing == key) {
      setState(() => _playing = null);
      await player.stop().catchError((Object _) {});
      return;
    }
    setState(() {
      _playing = key;
      _error = null;
    });
    try {
      final bytes = await widget.repository.downloadClip(pack, language, id);
      final path = await widget.controller.writePreview(
        pack.code,
        language,
        id,
        bytes,
      );
      if (_playing != key) return;
      await player.play(path);
    } catch (error) {
      if (mounted && _playing == key) {
        setState(
          () => _error = _failure(
            error,
            _t('That recording couldn’t be played.', '这段录音无法播放。'),
          ),
        );
      }
    } finally {
      if (mounted && _playing == key) setState(() => _playing = null);
    }
  }

  Future<void> _install(SharedVoicePack pack) async {
    final wanted = [
      for (final MapEntry(key: language, value: ids) in _installable(
        pack,
      ).entries)
        for (final id in ids) (language, id),
    ];
    if (wanted.isEmpty) return;
    setState(() {
      _installing = true;
      _progress = 0;
      _error = null;
    });
    try {
      final clips = <String, Map<String, Uint8List>>{};
      var done = 0;
      var next = 0;
      Future<void> worker() async {
        while (next < wanted.length) {
          final (language, id) = wanted[next++];
          final bytes = await widget.repository.downloadClip(
            pack,
            language,
            id,
          );
          (clips[language] ??= {})[id] = bytes;
          done++;
          if (mounted) setState(() => _progress = done / wanted.length);
        }
      }

      await Future.wait([
        for (var i = 0; i < VoicePackImportPage.parallelDownloads; i++)
          worker(),
      ]);
      await widget.controller.installPack(
        code: pack.code,
        name: pack.name,
        clips: clips,
      );
      unawaited(widget.repository.recordImport(pack.code));
      await widget.controller.usePack(pack.code);
      if (!mounted) return;
      Navigator.of(context).pop(pack.name);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = _failure(
          error,
          _t(
            'The voice couldn’t be installed. Check your connection and try again.',
            '语音安装失败，请检查网络后重试。',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pack = _pack;
    return Scaffold(
      appBar: AppBar(title: Text(_t('Use a shared voice', '使用分享的语音'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            _t(
              'Enter the code someone shared with you, or paste their waybi.co/voice link. Using a shared voice is free.',
              '输入别人分享给你的代码，或粘贴 waybi.co/voice 链接。使用分享的语音是免费的。',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('voice-import-code'),
            controller: _code,
            enabled: !_installing,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _lookUp(),
            decoration: InputDecoration(
              labelText: _t('Code or link', '代码或链接'),
              hintText: 'ABCDE FGHJK',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            key: const ValueKey('voice-import-look-up'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(WaybiTouch.minTarget),
            ),
            onPressed: _looking || _installing || _code.text.trim().isEmpty
                ? null
                : _lookUp,
            child: Text(
              _looking ? _t('Looking up…', '正在查找…') : _t('Look up', '查找'),
            ),
          ),
          if (_error case final error?) ...[
            const SizedBox(height: 12),
            Text(
              error,
              key: const ValueKey('voice-import-error'),
              style: TextStyle(color: context.status.danger),
            ),
          ],
          if (pack != null) ...[
            const SizedBox(height: 20),
            _packCard(context, pack),
          ],
        ],
      ),
    );
  }

  Widget _packCard(BuildContext context, SharedVoicePack pack) {
    final installable = _installable(pack);
    final count = installable.values.fold<int>(
      0,
      (sum, ids) => sum + ids.length,
    );
    final languages = [
      if ((installable['en'] ?? const []).isNotEmpty) 'English',
      if ((installable['zh'] ?? const []).isNotEmpty) '中文',
    ].join(' · ');
    final installed = widget.controller.installedPack(pack.code) != null;
    return Card(
      key: const ValueKey('voice-import-pack'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(pack.name, style: context.textStyles.titleMedium),
            const SizedBox(height: 4),
            Text(
              _t('$count phrases · $languages', '$count 条短语 · $languages'),
              style: context.textStyles.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final (language, id) in _previews(pack))
              ListTile(
                key: ValueKey('voice-import-preview-$language-$id'),
                contentPadding: EdgeInsets.zero,
                title: Text('“${customVoicePhrase(id)!.prompt(language)}”'),
                trailing: IconButton(
                  tooltip: _t('Listen', '试听'),
                  icon: Icon(
                    _playing == '$language/$id'
                        ? Icons.stop_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  onPressed: _installing
                      ? null
                      : () => _preview(pack, language, id),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              _t(
                'Unrecorded phrases, road names and numbers use the standard voice. If the owner stops sharing this voice, your installed copy keeps working.',
                '没有录制的短语、路名和数字使用标准语音。即使分享者之后撤销，已安装的语音仍可继续使用。',
              ),
              style: context.textStyles.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (_installing) ...[
              Semantics(
                label: _t('Installing', '正在安装'),
                value: '${((_progress ?? 0) * 100).round()}%',
                child: LinearProgressIndicator(value: _progress),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              key: const ValueKey('voice-import-install'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(WaybiTouch.minTarget),
              ),
              onPressed: _installing || count == 0
                  ? null
                  : () => _install(pack),
              icon: const Icon(Icons.download_rounded),
              label: Text(
                _installing
                    ? _t('Installing…', '正在安装…')
                    : installed
                    ? _t('Update and use this voice', '更新并使用这个语音')
                    : _t('Install and use this voice', '安装并使用这个语音'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
