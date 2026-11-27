import 'package:flutter/foundation.dart';

import 'voice_phrases.dart';

/// One piece of a spoken prompt.
///
/// Prompts are built from parts rather than parsed from finished sentences,
/// so every fixed word can be played from a recording and only genuinely
/// dynamic text (road and place names, numbers, times) needs the standard
/// voice.
@immutable
sealed class UtterancePart {
  const UtterancePart({this.road = false});

  /// The part only exists to name a road ("onto", "Queen Street", the comma
  /// before "位于"). Dropped when the member turns off road names.
  final bool road;
}

/// Fixed wording with a recordable phrase.
final class PhrasePart extends UtterancePart {
  const PhrasePart(this.phraseId, {super.road});
  final String phraseId;

  @override
  bool operator ==(Object other) =>
      other is PhrasePart && other.phraseId == phraseId && other.road == road;
  @override
  int get hashCode => Object.hash(phraseId, road);
  @override
  String toString() => 'Phrase($phraseId)';
}

/// Text that is never recorded: a road or place name, a number, a time.
final class DynamicPart extends UtterancePart {
  const DynamicPart(this.text, {super.road});
  final String text;

  @override
  bool operator ==(Object other) =>
      other is DynamicPart && other.text == text && other.road == road;
  @override
  int get hashCode => Object.hash(text, road);
  @override
  String toString() => 'Dynamic($text)';
}

/// "In 300 m" / "300 米后". Played from the nearest recorded distance clip
/// when it is close; otherwise as "In" + the number + "metres".
final class DistancePart extends UtterancePart {
  const DistancePart(this.metres, {this.words = false});
  final num metres;

  /// English only: "In 300 metres" rather than "In 300 m".
  final bool words;

  bool get _km => _safe >= 1000;
  num get _safe => metres.isFinite && metres > 0 ? metres : 0;

  /// The spoken number: whole metres, or kilometres to one decimal.
  String get number =>
      _km ? (_safe / 1000).toStringAsFixed(1) : '${_safe.round()}';

  String text(String language) {
    if (language == 'zh') return '$number ${_km ? '公里' : '米'}后';
    final unit = words ? (_km ? 'kilometres' : 'metres') : (_km ? 'km' : 'm');
    return 'In $number $unit';
  }

  /// The same distance as phrases around a dynamic number.
  List<UtterancePart> spelledOut(String language) => [
    if (language != 'zh') const PhrasePart(VoicePhraseId.distanceIn),
    DynamicPart(number),
    PhrasePart(
      _km ? VoicePhraseId.distanceKilometres : VoicePhraseId.distanceMetres,
    ),
  ];

  /// The recorded distance clip close enough to stand for this distance.
  String? snap(Set<String> playable) {
    final value = _safe;
    String? best;
    var bestError = double.infinity;
    for (final distance in voiceDistances) {
      final id = VoicePhraseId.distance(distance);
      if (!playable.contains(id)) continue;
      final error = (value - distance).abs().toDouble();
      final tolerance = distance * 0.08 < 15 ? 15 : distance * 0.08;
      if (error <= tolerance && error < bestError) {
        best = id;
        bestError = error;
      }
    }
    return best;
  }

  @override
  bool operator ==(Object other) =>
      other is DistancePart && other.metres == metres && other.words == words;
  @override
  int get hashCode => Object.hash(metres, words);
  @override
  String toString() => 'Distance($metres)';
}

/// Punctuation between parts: a short pause for the standard voice.
final class PausePart extends UtterancePart {
  const PausePart(this.mark, {super.road});
  final String mark;

  bool get endsSentence => _sentenceEnd.hasMatch(mark);

  @override
  bool operator ==(Object other) =>
      other is PausePart && other.mark == mark && other.road == road;
  @override
  int get hashCode => Object.hash(mark, road);
  @override
  String toString() => 'Pause($mark)';
}

final _sentenceEnd = RegExp(r'[.!?。！？]');
final _ascii = RegExp(r'[A-Za-z0-9]');
final _cjk = RegExp(r'[㐀-鿿]');

/// A spoken prompt: its [parts] for recorded clips and the plain [text] the
/// standard voice reads, the screen shows and logs record.
@immutable
class VoiceUtterance {
  /// [text] overrides the rendering of [parts], for example a routing
  /// engine's richer instruction ("Take exit 414 towards Albany") that the
  /// standard voice keeps reading word for word.
  VoiceUtterance(this.language, List<UtterancePart> parts, {String? text})
    : parts = List.unmodifiable(parts),
      text = (text ?? renderUtteranceParts(parts, language)).trim();

  /// A message with no structure. A custom voice falls back to matching
  /// phrases at the start of its clauses.
  VoiceUtterance.freeform(String text, this.language)
    : parts = const [],
      text = text.trim();

  /// 'en' or 'zh'.
  final String language;
  final List<UtterancePart> parts;
  final String text;

  bool get structured => parts.isNotEmpty;
  bool get isEmpty => text.isEmpty;

  /// Text-to-speech language for this prompt.
  String get speechLanguage => language == 'zh' ? 'zh-CN' : 'en-NZ';

  /// The plain text without road names and the words that introduce them.
  String get textWithoutRoadNames => structured
      ? renderUtteranceParts(withoutRoadNames(parts), language)
      : text;

  @override
  String toString() => 'VoiceUtterance($language, $parts)';
}

/// Drops road names together with their connectors and pauses, and tidies
/// the punctuation left behind.
List<UtterancePart> withoutRoadNames(List<UtterancePart> parts) => _tidyPauses([
  for (final part in parts)
    if (!part.road) part,
]);

List<UtterancePart> _tidyPauses(List<UtterancePart> parts) {
  final tidy = <UtterancePart>[];
  for (final part in parts) {
    if (part is PausePart) {
      if (tidy.isEmpty) continue;
      final last = tidy.last;
      if (last is PausePart) {
        if (part.endsSentence && !last.endsSentence) tidy.last = part;
        continue;
      }
    }
    tidy.add(part);
  }
  return tidy;
}

/// The words a part stands for, before sentence capitalisation.
String utterancePartText(UtterancePart part, String language) => switch (part) {
  PhrasePart(:final phraseId) =>
    customVoicePhrase(phraseId)?.texts(language).firstOrNull ?? '',
  DynamicPart(:final text) => text.trim(),
  DistancePart() => part.text(language),
  PausePart(:final mark) => mark,
};

/// Joins parts the way each language writes them: English with spaces and
/// sentence-case, Chinese without spaces except between Chinese and Latin
/// letters or digits.
String renderUtteranceParts(
  List<UtterancePart> parts,
  String language, {
  bool sentenceStart = true,
}) {
  final zh = language == 'zh';
  final out = StringBuffer();
  var start = sentenceStart;
  var last = '';
  for (final part in parts) {
    var text = utterancePartText(part, language);
    if (text.isEmpty) continue;
    if (part is PausePart) {
      if (out.isEmpty) continue;
      out.write(text);
      last = text;
      if (part.endsSentence) start = true;
      continue;
    }
    if (!zh) {
      if (start) {
        if (part is! DynamicPart) text = _capitalise(text);
      } else if (part is PhrasePart &&
          !(customVoicePhrase(part.phraseId)?.keepCase ?? false)) {
        text = _decapitalise(text);
      }
      if (out.isNotEmpty) out.write(' ');
    } else if (last.isNotEmpty &&
        ((_cjk.hasMatch(last[last.length - 1]) && _ascii.hasMatch(text[0])) ||
            (_ascii.hasMatch(last[last.length - 1]) &&
                _cjk.hasMatch(text[0])))) {
      out.write(' ');
    }
    out.write(text);
    last = text;
    start = false;
  }
  return out.toString();
}

String _capitalise(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

String _decapitalise(String text) {
  if (text.length < 2) return text.toLowerCase();
  // "T2 transit lane" and "U-turn" style words keep their capital.
  if (!RegExp(r'[a-z]').hasMatch(text[1])) return text;
  return text[0].toLowerCase() + text.substring(1);
}

/// A piece of one prompt as played: a recorded clip, or text for system TTS.
@immutable
sealed class VoiceSegment {
  const VoiceSegment(this.text);

  /// The words this segment stands for, used if a clip cannot be played.
  final String text;
}

class ClipSegment extends VoiceSegment {
  const ClipSegment(this.phraseId, super.text);
  final String phraseId;
  @override
  bool operator ==(Object other) =>
      other is ClipSegment && other.phraseId == phraseId && other.text == text;
  @override
  int get hashCode => Object.hash(phraseId, text);
  @override
  String toString() => 'Clip($phraseId)';
}

class TtsSegment extends VoiceSegment {
  const TtsSegment(super.text);
  @override
  bool operator ==(Object other) => other is TtsSegment && other.text == text;
  @override
  int get hashCode => text.hashCode;
  @override
  String toString() => 'Tts($text)';
}

/// Plays a structured prompt: each recorded phrase as its clip, everything
/// else (unrecorded phrases, dynamic text) as standard-voice runs.
///
/// Without a single playable clip the prompt is spoken exactly as [VoiceUtterance.text],
/// identical to the standard voice. With [omitRoadNames] road names and the
/// words that introduce them are left out.
List<VoiceSegment> planUtterance(
  VoiceUtterance utterance,
  Set<String> playable, {
  bool omitRoadNames = false,
}) {
  assert(utterance.structured);
  final language = utterance.language;
  final source = omitRoadNames
      ? withoutRoadNames(utterance.parts)
      : utterance.parts;
  final parts = <UtterancePart>[];
  for (final part in source) {
    if (part is! DistancePart) {
      parts.add(part);
      continue;
    }
    final snapped = part.snap(playable);
    if (snapped != null) {
      parts.add(PhrasePart(snapped));
    } else {
      final spelled = part.spelledOut(language);
      final anyRecorded = spelled.any(
        (piece) => piece is PhrasePart && playable.contains(piece.phraseId),
      );
      parts.addAll(anyRecorded ? spelled : [part]);
    }
  }

  final segments = <VoiceSegment>[];
  final pending = <UtterancePart>[];
  var sentenceStart = true;
  var pendingStart = true;
  void flush() {
    while (pending.isNotEmpty && pending.first is PausePart) {
      if ((pending.removeAt(0) as PausePart).endsSentence) pendingStart = true;
    }
    if (pending.any((part) => part is! PausePart)) {
      final text = renderUtteranceParts(
        pending,
        language,
        sentenceStart: pendingStart,
      ).trim();
      if (text.isNotEmpty) segments.add(TtsSegment(text));
    }
    pending.clear();
  }

  for (final part in parts) {
    final phrase = part is PhrasePart ? customVoicePhrase(part.phraseId) : null;
    if (part is PhrasePart &&
        phrase != null &&
        phrase.availableIn(language) &&
        playable.contains(part.phraseId)) {
      flush();
      segments.add(
        ClipSegment(
          part.phraseId,
          renderUtteranceParts([part], language, sentenceStart: sentenceStart),
        ),
      );
      sentenceStart = false;
      continue;
    }
    if (pending.isEmpty) pendingStart = sentenceStart;
    pending.add(part);
    if (part is PausePart) {
      if (part.endsSentence) sentenceStart = true;
    } else {
      sentenceStart = false;
    }
  }
  flush();
  if (!segments.any((segment) => segment is ClipSegment)) {
    final text = omitRoadNames
        ? utterance.textWithoutRoadNames
        : utterance.text;
    return text.isEmpty ? const [] : [TtsSegment(text)];
  }
  return segments;
}
