import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'voice_phrases.dart';
import 'voice_utterance.dart';

export 'voice_phrases.dart';
export 'voice_utterance.dart';

final _boundaryPunctuation = RegExp(r'[,.;:!?，。；：！？、]');
final _onlyPunctuation = RegExp(r'^[\s,.;:!?，。；：！？、]*$');
final _enDistancePattern = RegExp(
  r'^in (\d+(?:\.\d+)?) ?(m|metres|meters|km|kilometres|kilometers)\b',
  caseSensitive: false,
);
final _zhDistancePattern = RegExp(r'^(\d+(?:\.\d+)?) ?(米|公里)后');

/// Splits a free-form sentence into recorded clips and TTS text.
///
/// Only for messages that were not built from parts (see [planUtterance]).
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
          phrase.standalone &&
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
  for (final distance in voiceDistances) {
    final id = VoicePhraseId.distance(distance);
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

  /// Leave road names (and the words introducing them) out of prompts, so
  /// a fully recorded pack speaks only in the recorded voice.
  bool get omitRoadNames;
}

/// A voice someone shared, installed on this device.
@immutable
class InstalledVoicePack {
  const InstalledVoicePack({
    required this.code,
    required this.name,
    required this.clips,
    required this.installedAt,
  });

  final String code;
  final String name;

  /// language → phrase ids with an installed clip.
  final Map<String, Set<String>> clips;
  final DateTime installedAt;

  int get clipCount => clips.values.fold(0, (sum, ids) => sum + ids.length);
  List<String> get languages => [
    for (final language in CustomVoiceController.languages)
      if (clips[language]?.isNotEmpty ?? false) language,
  ];
}

/// Which voice guidance uses.
enum VoiceChoice { standard, own, shared }

/// The custom navigation voice: the member's own recordings (Waybi Plus)
/// and voices other people shared (free to use).
///
/// Own recordings live in the app's documents directory and are only
/// uploaded when the member chooses to share them. If Plus lapses, the files
/// are kept but not played; the member can still delete them. An installed
/// shared voice is a separate folder per share code and keeps working even
/// if its owner later revokes the code.
class CustomVoiceController extends ChangeNotifier implements CustomVoiceClips {
  CustomVoiceController({required this._rootDirectory});

  static const enabledKey = 'waybi.plus.custom_voice.enabled.v1';
  static const omitRoadNamesKey = 'waybi.custom_voice.omit_road_names.v1';
  static const activeVoiceKey = 'waybi.custom_voice.active.v1';

  /// Shared clips are checked by size and SHA-256 before installing.
  static const minimumPackClipBytes = 512;
  static const languages = ['en', 'zh'];

  /// Files smaller than this are treated as failed recordings.
  static const minimumClipBytes = 1024;

  final Future<Directory> Function() _rootDirectory;
  final Map<String, Set<String>> _recorded = {for (final l in languages) l: {}};
  final Map<String, Set<String>> _broken = {for (final l in languages) l: {}};
  Directory? _root;
  Directory? _packsRoot;
  bool _plus = false;

  /// 'standard', 'own' or 'pack:<code>'.
  String _choice = 'standard';
  bool _omitRoadNames = false;
  bool _loaded = false;
  final Map<String, InstalledVoicePack> _packs = {};
  final Map<String, Map<String, Set<String>>> _packBroken = {};

  bool get plus => _plus;

  /// The member's own recordings are the chosen voice.
  bool get enabled => _choice == 'own';
  bool get loaded => _loaded;
  @override
  bool get omitRoadNames => _omitRoadNames;

  /// The installed shared voice guidance uses, if one is chosen.
  String? get activePackCode {
    if (!_choice.startsWith('pack:')) return null;
    final code = _choice.substring(5);
    return _packs.containsKey(code) ? code : null;
  }

  VoiceChoice get choice => activePackCode != null
      ? VoiceChoice.shared
      : enabled
      ? VoiceChoice.own
      : VoiceChoice.standard;

  /// Installed shared voices, newest first.
  List<InstalledVoicePack> get installedPacks => List.unmodifiable(
    _packs.values.toList()
      ..sort((a, b) => b.installedAt.compareTo(a.installedAt)),
  );
  InstalledVoicePack? installedPack(String code) => _packs[code];

  /// True when guidance should use recorded clips: the member's own (with
  /// Plus) or an installed shared voice (free).
  bool get active => (enabled && _plus) || activePackCode != null;

  Set<String> recorded(String language) =>
      Set.unmodifiable(_recorded[language] ?? const <String>{});
  bool isBroken(String language, String id) =>
      _broken[language]?.contains(id) ?? false;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _choice =
          prefs.getString(activeVoiceKey) ??
          ((prefs.getBool(enabledKey) ?? false) ? 'own' : 'standard');
      _omitRoadNames = prefs.getBool(omitRoadNamesKey) ?? false;
      await _loadPacks();
      if (_choice.startsWith('pack:') && activePackCode == null) {
        _choice = 'standard';
      }
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

  /// Turns the member's own recordings on (Plus only) or off.
  Future<void> setEnabled(bool enabled) async {
    if (enabled) return useOwnVoice();
    if (this.enabled) await useStandardVoice();
  }

  Future<void> useStandardVoice() => _choose('standard');

  Future<void> useOwnVoice() async {
    if (_plus) await _choose('own');
  }

  /// Uses an installed shared voice; anyone can.
  Future<void> usePack(String code) async {
    if (_packs.containsKey(code)) await _choose('pack:$code');
  }

  Future<void> _choose(String choice) async {
    _choice = choice;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(activeVoiceKey, choice);
      await prefs.setBool(enabledKey, choice == 'own');
    } catch (_) {
      /* The choice still applies for this session. */
    }
  }

  Future<void> setOmitRoadNames(bool omit) async {
    _omitRoadNames = omit;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(omitRoadNamesKey, omit);
    } catch (_) {
      /* The choice still applies for this session. */
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
    final code = activePackCode;
    if (code != null) {
      final clips = _packs[code]!.clips[language] ?? const <String>{};
      return clips.difference(_packBroken[code]?[language] ?? const {});
    }
    final recorded = _recorded[language];
    if (recorded == null || recorded.isEmpty) return const {};
    return recorded.difference(_broken[language]!);
  }

  @override
  String? clipPath(String language, String phraseId) {
    final code = activePackCode;
    if (code == null) return recordingPath(language, phraseId);
    final root = _packsRoot;
    if (root == null ||
        !(_packs[code]!.clips[language]?.contains(phraseId) ?? false)) {
      return null;
    }
    return '${root.path}/$code/$language/$phraseId.m4a';
  }

  /// The member's own recording of [phraseId], for previews.
  String? recordingPath(String language, String phraseId) {
    final root = _root;
    if (root == null || !(_recorded[language]?.contains(phraseId) ?? false)) {
      return null;
    }
    return _finalPath(root, language, phraseId);
  }

  @override
  void reportBroken(String language, String phraseId) {
    final code = activePackCode;
    final broken = code == null
        ? _broken[language]
        : ((_packBroken[code] ??= {})[language] ??= {});
    if (broken?.add(phraseId) ?? false) notifyListeners();
  }

  /// The member's playable recordings, for sharing.
  List<({String language, String phraseId, String path})>
  shareableRecordings() {
    final root = _root;
    if (root == null) return const [];
    return [
      for (final language in languages)
        for (final phrase in voicePhrasesFor(language))
          if (_recorded[language]!.contains(phrase.id) &&
              !_broken[language]!.contains(phrase.id))
            (
              language: language,
              phraseId: phrase.id,
              path: _finalPath(root, language, phrase.id),
            ),
    ];
  }

  Future<Directory> _sharedRoot() async {
    final cached = _packsRoot;
    if (cached != null) return cached;
    final base = await _rootDirectory();
    return _packsRoot = Directory('${base.path}/custom_voice_packs');
  }

  static final _packCode = RegExp(r'^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{10}$');

  Future<void> _loadPacks() async {
    _packs.clear();
    final root = await _sharedRoot();
    if (!await root.exists()) return;
    await for (final entry in root.list()) {
      if (entry is! Directory) continue;
      final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (name.startsWith('.')) {
        // Unfinished installs and previews.
        await _deleteDirectory(entry);
        continue;
      }
      if (!_packCode.hasMatch(name)) continue;
      try {
        final info = jsonDecode(
          await File('${entry.path}/pack.json').readAsString(),
        );
        final clips = <String, Set<String>>{};
        for (final language in languages) {
          final ids = (info['clips']?[language] as List? ?? const [])
              .whereType<String>();
          for (final id in ids) {
            final file = File('${entry.path}/$language/$id.m4a');
            if (!(customVoicePhrase(id)?.availableIn(language) ?? false) ||
                !await file.exists() ||
                await file.length() < minimumPackClipBytes) {
              continue;
            }
            (clips[language] ??= {}).add(id);
          }
        }
        if (clips.isEmpty) continue;
        _packs[name] = InstalledVoicePack(
          code: name,
          name: info['name'] as String? ?? name,
          clips: clips,
          installedAt: DateTime.fromMillisecondsSinceEpoch(
            (info['installedAt'] as num?)?.toInt() ?? 0,
          ),
        );
      } catch (error) {
        debugPrint('Shared voice $name unreadable: $error');
      }
    }
  }

  /// Installs a shared voice from verified clip bytes (language → phrase id
  /// → audio), replacing an earlier install of the same code. Phrases this
  /// app version does not know are left out.
  Future<InstalledVoicePack> installPack({
    required String code,
    required String name,
    required Map<String, Map<String, Uint8List>> clips,
    DateTime? now,
  }) async {
    if (!_packCode.hasMatch(code)) throw ArgumentError.value(code, 'code');
    final root = await _sharedRoot();
    final staging = Directory(
      '${root.path}/.install-$code-${DateTime.now().microsecondsSinceEpoch}',
    );
    final installed = <String, Set<String>>{};
    try {
      for (final MapEntry(key: language, value: byId) in clips.entries) {
        if (!languages.contains(language)) continue;
        for (final MapEntry(key: id, value: bytes) in byId.entries) {
          if (!(customVoicePhrase(id)?.availableIn(language) ?? false) ||
              bytes.length < minimumPackClipBytes) {
            continue;
          }
          final file = File('${staging.path}/$language/$id.m4a');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes, flush: true);
          (installed[language] ??= {}).add(id);
        }
      }
      if (installed.isEmpty) {
        throw StateError('The shared voice has no usable recordings');
      }
      final installedAt = now ?? DateTime.now();
      await File('${staging.path}/pack.json').writeAsString(
        jsonEncode({
          'code': code,
          'name': name,
          'installedAt': installedAt.millisecondsSinceEpoch,
          'clips': {
            for (final MapEntry(:key, :value) in installed.entries)
              key: value.toList()..sort(),
          },
        }),
      );
      final target = Directory('${root.path}/$code');
      if (await target.exists()) await target.delete(recursive: true);
      await staging.rename(target.path);
      final pack = InstalledVoicePack(
        code: code,
        name: name,
        clips: installed,
        installedAt: installedAt,
      );
      _packs[code] = pack;
      _packBroken.remove(code);
      notifyListeners();
      return pack;
    } catch (_) {
      await _deleteDirectory(staging);
      rethrow;
    }
  }

  /// Deletes an installed shared voice and its files.
  Future<void> removePack(String code) async {
    final root = await _sharedRoot();
    await _deleteDirectory(Directory('${root.path}/$code'));
    _packs.remove(code);
    _packBroken.remove(code);
    if (_choice == 'pack:$code') {
      await _choose('standard');
    } else {
      notifyListeners();
    }
  }

  /// Saves a downloaded clip to play as a preview before installing.
  Future<String> writePreview(
    String code,
    String language,
    String phraseId,
    Uint8List bytes,
  ) async {
    final root = await _sharedRoot();
    final file = File('${root.path}/.preview/$code-$language-$phraseId.m4a');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> _deleteDirectory(Directory directory) async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (error) {
      debugPrint('Custom voice cleanup failed: $error');
    }
  }
}
