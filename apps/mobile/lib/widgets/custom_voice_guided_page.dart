import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/map_provider.dart';
import '../domain/route_option.dart';
import '../domain/transit_lane.dart';
import '../drive/custom_voice.dart';
import '../drive/voice_clip_player.dart';
import '../drive/voice_prompts.dart';
import '../drive/voice_recorder.dart';
import '../drive/voice_take_session.dart';
import '../theme/waybi_theme.dart';
import 'custom_voice_page.dart';

/// Steps through the phrases that still use the standard voice, one at a
/// time: record, listen, keep (and move on), record again or skip.
class CustomVoiceGuidedPage extends StatefulWidget {
  const CustomVoiceGuidedPage({
    super.key,
    required this.controller,
    required this.language,
    required this.pack,
    required this.phrases,
    this.recorder,
    this.player,
  });

  final CustomVoiceController controller;

  /// App language for this page's text.
  final String language;

  /// The language pack being recorded.
  final String pack;
  final List<VoicePhrase> phrases;
  final VoiceRecorder Function()? recorder;
  final VoiceClipPlayer Function()? player;

  @override
  State<CustomVoiceGuidedPage> createState() => _CustomVoiceGuidedPageState();
}

/// A sentence that shows how a glue word is used, so it can be read with the
/// right intonation. Null for phrases that are a whole sentence already.
String? voicePhraseExample(String phraseId, String language) {
  RouteStepInfo step(String modifier) => RouteStepInfo(
    instruction: '',
    distanceMeters: 0,
    location: const GeoPoint(0, 0),
    maneuverType: 'turn',
    maneuverModifier: modifier,
    roadName: 'Queen Street',
  );
  String camera() => VoicePrompts.camera(
    metres: 300,
    cameraType: 'speed',
    roadName: 'Queen Street',
    language: language,
  ).text;
  return switch (phraseId) {
    VoicePhraseId.distanceIn || VoicePhraseId.distanceMetres =>
      VoicePrompts.turn(step('left'), language, metres: 650).text,
    VoicePhraseId.distanceKilometres => VoicePrompts.turn(
      step('left'),
      language,
      metres: 1700,
    ).text,
    VoicePhraseId.onto ||
    VoicePhraseId.toward => VoicePrompts.routeStep(step('left'), language).text,
    VoicePhraseId.on ||
    VoicePhraseId.locatedOn ||
    VoicePhraseId.thereIs => camera(),
    VoicePhraseId.timeTo ||
    VoicePhraseId.timeHour ||
    VoicePhraseId.timeMinute => renderUtteranceParts(
      VoicePrompts.scheduleParts(
        const TransitSchedule(
          days: [1, 2, 3, 4, 5],
          windows: [
            [450, 570],
          ],
          known: true,
        ),
        language,
      ),
      language,
    ),
    _ => null,
  };
}

class _CustomVoiceGuidedPageState extends State<CustomVoiceGuidedPage> {
  late final VoiceTakeSession _takes = VoiceTakeSession(
    voice: widget.controller,
    language: widget.pack,
    recorder: widget.recorder,
    player: widget.player,
    maxRecording: CustomVoicePage.maxRecording,
    onIssue: (issue) => _message(voiceTakeIssueText(issue, _zh)),
  );
  int _index = 0;
  int _kept = 0;

  bool get _zh => widget.language == 'zh';
  String _t(String en, String zh) => _zh ? zh : en;
  bool get _done => _index >= widget.phrases.length;
  VoicePhrase get _phrase => widget.phrases[_index];

  @override
  void initState() {
    super.initState();
    _takes.addListener(_changed);
    widget.controller.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    if (!widget.controller.plus && _takes.busy) {
      unawaited(_takes.cancelRecording());
    }
    setState(() {});
  }

  @override
  void dispose() {
    _takes.removeListener(_changed);
    widget.controller.removeListener(_changed);
    _takes.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _next({bool kept = false}) async {
    await _takes.reset();
    if (!mounted) return;
    setState(() {
      if (kept) _kept++;
      _index++;
    });
  }

  Future<void> _keep() async {
    if (await _takes.keepDraft()) await _next(kept: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_t('Record missing phrases', '录制缺少的短语'))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: _done ? _finished(context) : _step(context),
        ),
      ),
    );
  }

  Widget _finished(BuildContext context) => Column(
    key: const ValueKey('custom-voice-guided-done'),
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Icon(Icons.check_circle_rounded, size: 56, color: context.status.success),
      const SizedBox(height: 16),
      Text(
        _t('All done', '完成啦'),
        textAlign: TextAlign.center,
        style: context.textStyles.headlineSmall,
      ),
      const SizedBox(height: 8),
      Text(
        _t(
          'You recorded $_kept of ${widget.phrases.length} phrases. Skipped phrases keep using the standard voice.',
          '本次录制了 $_kept / ${widget.phrases.length} 条短语。跳过的短语继续使用标准语音。',
        ),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      FilledButton(
        key: const ValueKey('custom-voice-guided-close'),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(WaybiTouch.minTarget),
        ),
        onPressed: () => Navigator.of(context).pop(),
        child: Text(_t('Done', '完成')),
      ),
    ],
  );

  Widget _step(BuildContext context) {
    final phrase = _phrase;
    final recording = _takes.recordingId == phrase.id;
    final draft = _takes.draft?.id == phrase.id ? _takes.draft : null;
    final example = voicePhraseExample(phrase.id, widget.pack);
    final plus = widget.controller.plus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _t(
            'Phrase ${_index + 1} of ${widget.phrases.length} · ${voicePhraseGroupTitle(phrase.group, false)}',
            '第 ${_index + 1} / ${widget.phrases.length} 条 · ${voicePhraseGroupTitle(phrase.group, true)}',
          ),
          key: const ValueKey('custom-voice-guided-step'),
          style: context.textStyles.bodySmall,
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: _index / widget.phrases.length,
          minHeight: 4,
        ),
        const Spacer(),
        Text(
          _t('Read aloud', '请读出'),
          textAlign: TextAlign.center,
          style: context.textStyles.labelLarge?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          child: Text(
            '“${phrase.prompt(widget.pack)}”',
            key: const ValueKey('custom-voice-guided-prompt'),
            textAlign: TextAlign.center,
            style: context.textStyles.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (example != null) ...[
          const SizedBox(height: 12),
          Text(
            _t('As in: $example', '用在：$example'),
            textAlign: TextAlign.center,
            style: context.textStyles.bodyMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          recording
              ? _t('Recording… tap stop when done', '录音中…读完点停止')
              : draft != null
              ? _t('Listen back, then keep it or record again.', '试听后，保留或重录。')
              : _t(
                  'Say it the way you’d like to hear it while driving.',
                  '用你希望开车时听到的语气读出来。',
                ),
          textAlign: TextAlign.center,
        ),
        const Spacer(),
        if (draft == null)
          FilledButton.icon(
            key: const ValueKey('custom-voice-guided-record'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(64),
              backgroundColor: recording ? context.status.danger : null,
              foregroundColor: recording ? context.status.onDanger : null,
            ),
            onPressed: plus ? () => _takes.record(phrase.id) : null,
            icon: Icon(recording ? Icons.stop_rounded : Icons.mic_rounded),
            label: Text(recording ? _t('Stop', '停止') : _t('Record', '录音')),
          )
        else ...[
          FilledButton.icon(
            key: const ValueKey('custom-voice-guided-keep'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            onPressed: _keep,
            icon: const Icon(Icons.check_rounded),
            label: Text(_t('Keep and continue', '保留并继续')),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('custom-voice-guided-play'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(WaybiTouch.minTarget),
                  ),
                  onPressed: _takes.playingId == phrase.id
                      ? _takes.stopPlayback
                      : () => _takes.play(phrase.id, draft.path, draft: true),
                  icon: Icon(
                    _takes.playingId == phrase.id
                        ? Icons.stop_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  label: Text(_t('Listen', '试听')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('custom-voice-guided-retake'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(WaybiTouch.minTarget),
                  ),
                  onPressed: () => _takes.record(phrase.id),
                  icon: const Icon(Icons.replay_rounded),
                  label: Text(_t('Record again', '重录')),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey('custom-voice-guided-skip'),
          style: TextButton.styleFrom(
            minimumSize: const Size.fromHeight(WaybiTouch.minTarget),
          ),
          onPressed: recording ? null : _next,
          child: Text(_t('Skip for now', '先跳过')),
        ),
      ],
    );
  }
}
