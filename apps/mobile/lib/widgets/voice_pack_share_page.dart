import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/voice_pack_repository.dart';
import '../drive/custom_voice.dart';
import '../theme/waybi_theme.dart';
import 'friendly_error.dart';

/// Waybi Plus: upload the member's own recordings and get a code to share.
class VoicePackSharePage extends StatefulWidget {
  const VoicePackSharePage({
    super.key,
    required this.controller,
    required this.repository,
    required this.language,
  });

  final CustomVoiceController controller;
  final VoicePackRepository repository;

  /// App language for this page's text.
  final String language;

  static const maxNameLength = 40;

  @override
  State<VoicePackSharePage> createState() => _VoicePackSharePageState();
}

class _VoicePackSharePageState extends State<VoicePackSharePage> {
  final _name = TextEditingController();
  bool _consent = false;
  bool _uploading = false;
  double? _progress;
  String? _error;
  SharedVoicePack? _shared;

  bool get _zh => widget.language == 'zh';
  String _t(String en, String zh) => _zh ? zh : en;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _ready =>
      !_uploading &&
      _consent &&
      _name.text.trim().isNotEmpty &&
      widget.controller.shareableRecordings().isNotEmpty;

  Future<void> _share() async {
    if (!_ready) return;
    setState(() {
      _uploading = true;
      _progress = 0;
      _error = null;
    });
    try {
      final clips = <VoicePackUploadClip>[];
      for (final clip in widget.controller.shareableRecordings()) {
        clips.add(
          VoicePackUploadClip(
            language: clip.language,
            phraseId: clip.phraseId,
            bytes: await File(clip.path).readAsBytes(),
          ),
        );
      }
      final shared = await widget.repository.upload(
        name: _name.text,
        consent: _consent,
        clips: clips,
        onProgress: (sent, total) {
          if (mounted && total > 0) setState(() => _progress = sent / total);
        },
      );
      if (!mounted) return;
      setState(() => _shared = shared);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = friendlyErrorMessage(
          error,
          widget.language,
          fallback: _t(
            'Your voice couldn’t be shared. Please try again.',
            '暂时无法分享你的声音，请稍后重试。',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _copy(String text, String done) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(done)));
  }

  @override
  Widget build(BuildContext context) {
    final shared = _shared;
    return Scaffold(
      appBar: AppBar(title: Text(_t('Share my voice', '分享我的声音'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: shared == null ? _form(context) : _result(context, shared),
      ),
    );
  }

  List<Widget> _form(BuildContext context) {
    final recordings = widget.controller.shareableRecordings();
    final en = recordings.where((clip) => clip.language == 'en').length;
    final zh = recordings.length - en;
    return [
      Text(
        _t(
          'Anyone you give the code to can use your recordings for their navigation voice. They don’t need Waybi Plus.',
          '拿到代码的人都可以把你的录音用作导航语音，对方不需要 Waybi Plus。',
        ),
      ),
      const SizedBox(height: 12),
      Text(
        _t(
          'Shares $en English and $zh Chinese recordings.',
          '将分享 $en 条英文录音和 $zh 条中文录音。',
        ),
        key: const ValueKey('voice-share-count'),
        style: context.textStyles.bodySmall,
      ),
      const SizedBox(height: 16),
      TextField(
        key: const ValueKey('voice-share-name'),
        controller: _name,
        enabled: !_uploading,
        maxLength: VoicePackSharePage.maxNameLength,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: _t('Name of this voice', '语音名称'),
          hintText: _t('For example, Mum’s voice', '例如：妈妈的声音'),
          border: const OutlineInputBorder(),
        ),
      ),
      CheckboxListTile(
        key: const ValueKey('voice-share-consent'),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: _consent,
        onChanged: _uploading
            ? null
            : (value) => setState(() => _consent = value ?? false),
        title: Text(
          _t('This is my own voice and I agree to share it', '这是我本人的声音，我同意分享'),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        _t(
          'Your recordings are uploaded to Waybi and kept until you revoke the code or delete your account. People who already installed your voice keep their copy.',
          '录音会上传到 Waybi，直到你撤销代码或删除账号。已经安装的人会保留他们的副本。',
        ),
        style: context.textStyles.bodySmall?.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 16),
      if (_uploading) ...[
        Semantics(
          label: _t('Uploading', '正在上传'),
          value: '${((_progress ?? 0) * 100).round()}%',
          child: LinearProgressIndicator(value: _progress),
        ),
        const SizedBox(height: 12),
      ],
      if (_error case final error?) ...[
        Text(
          error,
          key: const ValueKey('voice-share-error'),
          style: TextStyle(color: context.status.danger),
        ),
        const SizedBox(height: 12),
      ],
      FilledButton.icon(
        key: const ValueKey('voice-share-submit'),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(WaybiTouch.minTarget),
        ),
        onPressed: _ready ? _share : null,
        icon: const Icon(Icons.ios_share_rounded),
        label: Text(
          _uploading
              ? _t('Uploading…', '正在上传…')
              : _t('Create share code', '生成分享代码'),
        ),
      ),
    ];
  }

  List<Widget> _result(BuildContext context, SharedVoicePack shared) => [
    Icon(Icons.check_circle_rounded, size: 48, color: context.status.success),
    const SizedBox(height: 12),
    Text(
      _t('“${shared.name}” is ready to share', '“${shared.name}”已可以分享'),
      textAlign: TextAlign.center,
      style: context.textStyles.titleMedium,
    ),
    const SizedBox(height: 16),
    Semantics(
      label: _t('Share code', '分享代码'),
      child: SelectableText(
        shared.displayCode,
        key: const ValueKey('voice-share-code'),
        textAlign: TextAlign.center,
        style: context.textStyles.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
          color: context.colors.primary,
        ),
      ),
    ),
    const SizedBox(height: 4),
    SelectableText(
      shared.url,
      key: const ValueKey('voice-share-link'),
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 16),
    Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const ValueKey('voice-share-copy-code'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(WaybiTouch.minTarget),
            ),
            onPressed: () => _copy(shared.code, _t('Code copied', '已复制代码')),
            icon: const Icon(Icons.copy_rounded),
            label: Text(_t('Copy code', '复制代码')),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            key: const ValueKey('voice-share-copy-link'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(WaybiTouch.minTarget),
            ),
            onPressed: () => _copy(shared.url, _t('Link copied', '已复制链接')),
            icon: const Icon(Icons.link_rounded),
            label: Text(_t('Copy link', '复制链接')),
          ),
        ),
      ],
    ),
    const SizedBox(height: 16),
    Text(
      _t(
        'They open Waybi, go to My navigation voice → Use a shared voice, and enter the code. You can revoke it any time from My navigation voice.',
        '对方打开 Waybi，进入“我的导航语音 → 使用分享的语音”，输入代码即可。你可以随时在“我的导航语音”里撤销。',
      ),
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 16),
    TextButton(
      key: const ValueKey('voice-share-done'),
      style: TextButton.styleFrom(
        minimumSize: const Size.fromHeight(WaybiTouch.minTarget),
      ),
      onPressed: () => Navigator.of(context).pop(shared),
      child: Text(_t('Done', '完成')),
    ),
  ];
}
