import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One recordable phrase in the custom voice pack.
///
/// [en] / [zh] list every spelling the guidance code produces for the
/// phrase; the first entry is the prompt the user reads aloud when recording.
@immutable
class VoicePhrase {
  const VoicePhrase(this.id, this.group, this.en, this.zh, {this.metres});
  final String id;
  final VoicePhraseGroup group;
  final List<String> en;
  final List<String> zh;

  /// Distance phrases only: the distance this clip announces.
  final int? metres;

  List<String> texts(String language) => language == 'zh' ? zh : en;
  String prompt(String language) => texts(language).first;
}

enum VoicePhraseGroup { distance, maneuver, camera, arrival }

const _distances = [50, 100, 200, 300, 400, 500, 800, 1000, 1500, 2000];

String _enDistance(int metres) =>
    metres >= 1000 ? 'In ${_km(metres)} kilometres' : 'In $metres metres';
String _zhDistance(int metres) =>
    metres >= 1000 ? '${_km(metres)} 公里后' : '$metres 米后';
String _km(int metres) => metres % 1000 == 0
    ? '${metres ~/ 1000}'
    : (metres / 1000).toStringAsFixed(1);

/// Fixed phrases, matched against the sentences produced by
/// `navigation_language.dart`, `VoiceEngine.cameraAlert` and arrival speech.
final List<VoicePhrase> customVoicePhrases = List.unmodifiable([
  for (final metres in _distances)
    VoicePhrase(
      'in_$metres',
      VoicePhraseGroup.distance,
      [_enDistance(metres)],
      [_zhDistance(metres)],
      metres: metres,
    ),
  const VoicePhrase(
    'turn_left',
    VoicePhraseGroup.maneuver,
    ['Turn left'],
    ['左转'],
  ),
  const VoicePhrase(
    'turn_right',
    VoicePhraseGroup.maneuver,
    ['Turn right'],
    ['右转'],
  ),
  const VoicePhrase(
    'bear_left',
    VoicePhraseGroup.maneuver,
    ['Bear left', 'Turn slight left', 'Slight left'],
    ['向左前方行驶'],
  ),
  const VoicePhrase(
    'bear_right',
    VoicePhraseGroup.maneuver,
    ['Bear right', 'Turn slight right', 'Slight right'],
    ['向右前方行驶'],
  ),
  const VoicePhrase(
    'sharp_left',
    VoicePhraseGroup.maneuver,
    ['Turn sharp left', 'Sharp left'],
    ['向左急转'],
  ),
  const VoicePhrase(
    'sharp_right',
    VoicePhraseGroup.maneuver,
    ['Turn sharp right', 'Sharp right'],
    ['向右急转'],
  ),
  const VoicePhrase(
    'keep_left',
    VoicePhraseGroup.maneuver,
    ['Keep left'],
    ['靠左行驶'],
  ),
  const VoicePhrase(
    'keep_right',
    VoicePhraseGroup.maneuver,
    ['Keep right'],
    ['靠右行驶'],
  ),
  const VoicePhrase(
    'continue_straight',
    VoicePhraseGroup.maneuver,
    ['Continue straight'],
    ['继续直行'],
  ),
  const VoicePhrase(
    'continue_route',
    VoicePhraseGroup.maneuver,
    ['Continue on route'],
    ['沿路线继续行驶'],
  ),
  const VoicePhrase(
    'uturn',
    VoicePhraseGroup.maneuver,
    ['Make a U-turn'],
    ['掉头'],
  ),
  for (var exit = 1; exit <= 4; exit++)
    VoicePhrase(
      'roundabout_exit_$exit',
      VoicePhraseGroup.maneuver,
      ['At the roundabout, take exit $exit'],
      ['进入环岛，从第 $exit 个出口驶出'],
    ),
  const VoicePhrase(
    'roundabout',
    VoicePhraseGroup.maneuver,
    ['Enter the roundabout'],
    ['驶入环岛'],
  ),
  const VoicePhrase(
    'exit_left',
    VoicePhraseGroup.maneuver,
    ['Take the left exit'],
    ['从左侧出口驶出'],
  ),
  const VoicePhrase(
    'exit_right',
    VoicePhraseGroup.maneuver,
    ['Take the right exit'],
    ['从右侧出口驶出'],
  ),
  const VoicePhrase(
    'exit',
    VoicePhraseGroup.maneuver,
    ['Take the exit'],
    ['从出口驶出'],
  ),
  const VoicePhrase(
    'ramp',
    VoicePhraseGroup.maneuver,
    ['Take the ramp'],
    ['驶入匝道'],
  ),
  const VoicePhrase(
    'merge',
    VoicePhraseGroup.maneuver,
    ['Merge ahead'],
    ['汇入前方道路'],
  ),
  const VoicePhrase(
    'ferry',
    VoicePhraseGroup.maneuver,
    ['Take the ferry'],
    ['搭乘渡轮'],
  ),
  const VoicePhrase(
    'camera_speed',
    VoicePhraseGroup.camera,
    ['Speed camera', 'Fixed speed camera'],
    ['定点测速摄像头'],
  ),
  const VoicePhrase(
    'camera_average',
    VoicePhraseGroup.camera,
    ['Average-speed camera'],
    ['区间测速摄像头'],
  ),
  const VoicePhrase(
    'camera_red_light_speed',
    VoicePhraseGroup.camera,
    ['Red-light + speed camera'],
    ['红灯及测速摄像头'],
  ),
  const VoicePhrase(
    'camera_red_light',
    VoicePhraseGroup.camera,
    ['Red-light camera'],
    ['红灯摄像头'],
  ),
  const VoicePhrase(
    'camera_bus_lane',
    VoicePhraseGroup.camera,
    ['Bus-lane camera'],
    ['专用车道摄像头'],
  ),
  const VoicePhrase(
    'camera_safety',
    VoicePhraseGroup.camera,
    ['Safety camera'],
    ['安全摄像头'],
  ),
  const VoicePhrase(
    'arrived',
    VoicePhraseGroup.arrival,
    ['You have arrived', 'Arrive at destination'],
    ['已到达目的地', '到达目的地'],
  ),
]);

VoicePhrase? customVoicePhrase(String id) {
  for (final phrase in customVoicePhrases) {
    if (phrase.id == id) return phrase;
  }
  return null;
}

/// A piece of one guidance sentence: a recorded clip, or text for system TTS.
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

final _boundaryPunctuation = RegExp(r'[,.;:!?，。；：！？、]');
final _onlyPunctuation = RegExp(r'^[\s,.;:!?，。；：！？、]*$');
final _enDistancePattern = RegExp(
  r'^in (\d+(?:\.\d+)?) ?(m|metres|meters|km|kilometres|kilometers)\b',
  caseSensitive: false,
);
final _zhDistancePattern = RegExp(r'^(\d+(?:\.\d+)?) ?(米|公里)后');

/// Splits a guidance sentence into recorded clips and TTS text.
///
/// Phrases are only matched at the start of a clause (start of text, after a
/// clip, or after punctuation), so words inside road names never trigger a
/// clip. Distances use a clip only when the spoken distance is close to the
/// recorded one. When nothing matches, the whole sentence is a single TTS
/// segment, identical to the default voice.
List<VoiceSegment> planCustomVoice(
  String text,
  String language,
  Set<String> recorded,
) {
  final source = text.trim();
  if (source.isEmpty) return const [];
  if (recorded.isEmpty) return [TtsSegment(source)];
  final zh = language == 'zh';
  final candidates = <(String, String)>[
    for (final phrase in customVoicePhrases)
      if (phrase.group != VoicePhraseGroup.distance &&
          recorded.contains(phrase.id))
        for (final spelling in phrase.texts(language)) (phrase.id, spelling),
  ]..sort((a, b) => b.$2.length.compareTo(a.$2.length));

  final segments = <VoiceSegment>[];
  final pending = StringBuffer();
  void flush() {
    final raw = pending.toString();
    pending.clear();
    if (_onlyPunctuation.hasMatch(raw)) return;
    final cleaned = raw.replaceFirst(RegExp(r'^[\s,;:，；：、]+'), '').trim();
    if (cleaned.isNotEmpty) segments.add(TtsSegment(cleaned));
  }

  var index = 0;
  var clauseStart = true;
  while (index < source.length) {
    if (clauseStart) {
      // Skip whitespace/punctuation between clauses without losing it.
      var probe = index;
      while (probe < source.length &&
          (source[probe].trim().isEmpty ||
              _boundaryPunctuation.hasMatch(source[probe]))) {
        probe++;
      }
      final rest = source.substring(probe);
      final match =
          _matchDistance(rest, zh, recorded) ??
          _matchPhrase(rest, zh, candidates);
      if (match != null) {
        pending.write(source.substring(index, probe));
        flush();
        segments.add(ClipSegment(match.$1, rest.substring(0, match.$2)));
        index = probe + match.$2;
        continue;
      }
    }
    final char = source[index];
    pending.write(char);
    index++;
    clauseStart =
        _boundaryPunctuation.hasMatch(char) &&
        (zh || index >= source.length || source[index].trim().isEmpty);
  }
  flush();
  if (!segments.any((segment) => segment is ClipSegment)) {
    return [TtsSegment(source)];
  }
  return segments;
}

(String, int)? _matchPhrase(
  String rest,
  bool zh,
  List<(String, String)> candidates,
) {
  final lower = zh ? rest : rest.toLowerCase();
  for (final (id, spelling) in candidates) {
    final target = zh ? spelling : spelling.toLowerCase();
    if (!lower.startsWith(target)) continue;
    if (!zh &&
        lower.length > target.length &&
        RegExp(r'[a-z0-9-]').hasMatch(lower[target.length])) {
      continue;
    }
    return (id, spelling.length);
  }
  return null;
}

(String, int)? _matchDistance(String rest, bool zh, Set<String> recorded) {
  final match = (zh ? _zhDistancePattern : _enDistancePattern).firstMatch(rest);
  if (match == null) return null;
  final value = double.tryParse(match.group(1)!);
  if (value == null) return null;
  final unit = match.group(2)!.toLowerCase();
  final metres = unit.startsWith('k') || unit == '公里' ? value * 1000 : value;
  String? best;
  var bestError = double.infinity;
  for (final distance in _distances) {
    final id = 'in_$distance';
    if (!recorded.contains(id)) continue;
    final error = (metres - distance).abs();
    final tolerance = distance * 0.08 < 15 ? 15 : distance * 0.08;
    if (error <= tolerance && error < bestError) {
      best = id;
      bestError = error;
    }
  }
  if (best == null) return null;
  var length = match.end;
  // Swallow the comma that follows "In 300 m," so the next clause starts.
  while (length < rest.length && RegExp(r'[,，\s]').hasMatch(rest[length])) {
    length++;
  }
  return (best, length);
}

/// What [VoiceEngine] needs to play recorded clips.
abstract class CustomVoiceClips {
  /// Phrase ids that may be played now for [language] ('en' or 'zh').
  /// Empty when custom voice is unavailable (not Plus, switched off).
  Set<String> playable(String language);
  String? clipPath(String language, String phraseId);

  /// Called when a clip failed to play; it is skipped until re-recorded.
  void reportBroken(String language, String phraseId);
}

/// On-device custom voice pack, gated on Waybi Plus.
///
/// Recordings live only in the app's documents directory and are never
/// uploaded. If Plus lapses, the files are kept but not played; the member
/// can still delete them.
class CustomVoiceController extends ChangeNotifier implements CustomVoiceClips {
  CustomVoiceController({required this._rootDirectory});

  static const enabledKey = 'waybi.plus.custom_voice.enabled.v1';
  static const languages = ['en', 'zh'];

  /// Files smaller than this are treated as failed recordings.
  static const minimumClipBytes = 1024;

  final Future<Directory> Function() _rootDirectory;
  final Map<String, Set<String>> _recorded = {for (final l in languages) l: {}};
  final Map<String, Set<String>> _broken = {for (final l in languages) l: {}};
  Directory? _root;
  bool _plus = false;
  bool _enabled = false;
  bool _loaded = false;

  bool get plus => _plus;
  bool get enabled => _enabled;
  bool get loaded => _loaded;

  /// True when guidance should use the recorded clips.
  bool get active => _plus && _enabled;

  Set<String> recorded(String language) =>
      Set.unmodifiable(_recorded[language] ?? const <String>{});
  bool isBroken(String language, String id) =>
      _broken[language]?.contains(id) ?? false;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(enabledKey) ?? false;
      final root = await _voiceRoot();
      for (final language in languages) {
        final set = _recorded[language]!..clear();
        final folder = Directory('${root.path}/$language');
        if (!await folder.exists()) continue;
        await for (final entry in folder.list()) {
          if (entry is! File || !entry.path.endsWith('.m4a')) continue;
          final id = entry.uri.pathSegments.last.replaceFirst(
            RegExp(r'\.m4a$'),
            '',
          );
          if (customVoicePhrase(id) == null) continue;
          if (await entry.length() < minimumClipBytes) continue;
          set.add(id);
        }
      }
    } catch (error) {
      debugPrint('Custom voice unavailable: $error');
    }
    _loaded = true;
    notifyListeners();
  }

  /// Mirrors the account entitlement. Called whenever the profile changes.
  void setPlus(bool plus) {
    if (_plus == plus) return;
    _plus = plus;
    notifyListeners();
  }

  Future<void> setEnabled(bool enabled) async {
    if (enabled && !_plus) return;
    _enabled = enabled;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(enabledKey, enabled);
    } catch (_) {
      /* The toggle still applies for this session. */
    }
  }

  Future<Directory> _voiceRoot() async {
    final cached = _root;
    if (cached != null) return cached;
    final base = await _rootDirectory();
    return _root = Directory('${base.path}/custom_voice');
  }

  /// Where a new take is written before the user keeps it.
  Future<String> draftPath(String language) async {
    final root = await _voiceRoot();
    final folder = Directory('${root.path}/drafts');
    await folder.create(recursive: true);
    return '${folder.path}/$language-${DateTime.now().microsecondsSinceEpoch}.m4a';
  }

  String _finalPath(Directory root, String language, String id) =>
      '${root.path}/$language/$id.m4a';

  /// Keeps a draft as the clip for [id], replacing any earlier take.
  Future<bool> saveClip(String language, String id, String draft) async {
    if (!languages.contains(language) || customVoicePhrase(id) == null) {
      return false;
    }
    final file = File(draft);
    if (!await file.exists() || await file.length() < minimumClipBytes) {
      await _deleteQuietly(file);
      return false;
    }
    final root = await _voiceRoot();
    final target = File(_finalPath(root, language, id));
    await target.parent.create(recursive: true);
    await file.copy(target.path);
    await _deleteQuietly(file);
    _recorded[language]!.add(id);
    _broken[language]!.remove(id);
    notifyListeners();
    return true;
  }

  Future<void> discardDraft(String draft) => _deleteQuietly(File(draft));

  Future<void> deleteClip(String language, String id) async {
    final root = await _voiceRoot();
    await _deleteQuietly(File(_finalPath(root, language, id)));
    _recorded[language]?.remove(id);
    _broken[language]?.remove(id);
    notifyListeners();
  }

  /// Removes every recording, in both languages.
  Future<void> deleteAll() async {
    final root = await _voiceRoot();
    try {
      if (await root.exists()) await root.delete(recursive: true);
    } catch (error) {
      debugPrint('Custom voice delete failed: $error');
    }
    for (final language in languages) {
      _recorded[language]!.clear();
      _broken[language]!.clear();
    }
    notifyListeners();
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  @override
  Set<String> playable(String language) {
    if (!active) return const {};
    final recorded = _recorded[language];
    if (recorded == null || recorded.isEmpty) return const {};
    return recorded.difference(_broken[language]!);
  }

  @override
  String? clipPath(String language, String phraseId) {
    final root = _root;
    if (root == null || !(_recorded[language]?.contains(phraseId) ?? false)) {
      return null;
    }
    return _finalPath(root, language, phraseId);
  }

  @override
  void reportBroken(String language, String phraseId) {
    if (_broken[language]?.add(phraseId) ?? false) notifyListeners();
  }
}
