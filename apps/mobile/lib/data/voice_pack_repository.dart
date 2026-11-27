import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'http_guard.dart';

/// Error codes the voice-pack API sends (see the Worker's `voice_packs.ts`).
abstract final class VoicePackErrorCode {
  static const limit = 'VOICE_PACK_LIMIT';
  static const notFound = 'VOICE_PACK_NOT_FOUND';
  static const unavailable = 'VOICE_SHARING_UNAVAILABLE';
  static const consentRequired = 'CONSENT_REQUIRED';
  static const tooLarge = 'VOICE_PACK_TOO_LARGE';
  static const invalidClip = 'INVALID_CLIP';
  static const integrity = 'CLIP_INTEGRITY';
  static const purgeFailed = 'VOICE_PACK_PURGE_FAILED';
}

/// One recording in a shared voice pack's manifest.
class VoicePackClip {
  const VoicePackClip({
    required this.bytes,
    required this.contentType,
    required this.sha256,
  });

  factory VoicePackClip.fromJson(Map<String, dynamic> json) => VoicePackClip(
    bytes: (json['bytes'] as num?)?.toInt() ?? 0,
    contentType: json['contentType'] as String? ?? '',
    sha256: (json['sha256'] as String? ?? '').toLowerCase(),
  );

  final int bytes;
  final String contentType;
  final String sha256;
}

/// A shared voice: what the owner sees in "My shared voices", and with
/// [clips] what anyone with the code can install.
class SharedVoicePack {
  const SharedVoicePack({
    required this.code,
    required this.name,
    required this.languages,
    required this.clipCount,
    required this.totalBytes,
    required this.createdAt,
    required this.importCount,
    required this.url,
    this.clips = const {},
  });

  factory SharedVoicePack.fromJson(Map<String, dynamic> json) {
    final clips = <String, Map<String, VoicePackClip>>{};
    final raw = json['clips'];
    if (raw is Map) {
      for (final MapEntry(:key, :value) in raw.entries) {
        if (key is! String || value is! Map) continue;
        clips[key] = {
          for (final clip in value.entries)
            if (clip.key is String && clip.value is Map<String, dynamic>)
              clip.key as String: VoicePackClip.fromJson(
                clip.value as Map<String, dynamic>,
              ),
        };
      }
    }
    final code = json['code'] as String? ?? '';
    return SharedVoicePack(
      code: code,
      name: json['name'] as String? ?? '',
      languages: (json['languages'] as List? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      clipCount: (json['clipCount'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['createdAt'] as num?)?.toInt() ?? 0,
      ),
      importCount: (json['importCount'] as num?)?.toInt() ?? 0,
      url: json['url'] as String? ?? VoicePackRepository.shareLink(code),
      clips: clips,
    );
  }

  final String code;
  final String name;
  final List<String> languages;
  final int clipCount;
  final int totalBytes;
  final DateTime createdAt;
  final int importCount;
  final String url;

  /// language → phrase id → clip. Empty in the owner's list.
  final Map<String, Map<String, VoicePackClip>> clips;

  /// "ABCDE FGHJK", easier to read aloud or type.
  String get displayCode => VoicePackRepository.formatCode(code);
}

/// One of the member's recordings to upload.
class VoicePackUploadClip {
  const VoicePackUploadClip({
    required this.language,
    required this.phraseId,
    required this.bytes,
    this.contentType = 'audio/mp4',
  });
  final String language;
  final String phraseId;
  final Uint8List bytes;
  final String contentType;
}

/// Talks to the Worker's `/api/voice-packs` endpoints. Uploading needs a
/// signed-in Plus member; looking up and downloading a pack needs only its
/// code.
class VoicePackRepository {
  VoicePackRepository({
    http.Client? client,
    String? Function()? session,
    this._baseUrl = workerBaseUrl,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _session = session ?? (() => null);

  final http.Client _client;
  final bool _ownsClient;
  final String? Function() _session;
  final String _baseUrl;
  final RateLimitGate _gate = RateLimitGate();

  static const maxClipBytes = 256 * 1024;
  static const codeLength = 10;
  static const _alphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  static const uploadTimeout = Duration(seconds: 90);
  static const requestTimeout = Duration(seconds: 15);

  /// The code in [input]: a code typed with spaces or dashes in any case,
  /// or a pasted `waybi.co/voice/…` link. Null if it cannot be a code.
  static String? normalizeCode(String input) {
    var raw = input.trim();
    final link = RegExp(
      r'/voice/([^/?#]+)',
      caseSensitive: false,
    ).firstMatch(raw);
    if (link != null) raw = Uri.decodeComponent(link.group(1)!);
    final code = raw.replaceAll(RegExp(r'[\s-]+'), '').toUpperCase();
    if (code.length != codeLength) return null;
    return code.split('').every(_alphabet.contains) ? code : null;
  }

  static String formatCode(String code) => code.length == codeLength
      ? '${code.substring(0, 5)} ${code.substring(5)}'
      : code;

  static String shareLink(String code) => '$workerBaseUrl/voice/$code';

  Map<String, String> _headers({bool write = false}) {
    final session = _session();
    return {
      if (session != null) 'cookie': 'waybi_session=$session',
      if (write) 'x-waybi-client': 'mobile',
    };
  }

  Uri _uri(String path) => Uri.parse('$_baseUrl/api/voice-packs$path');

  Future<http.Response> _send(
    String method,
    String path, {
    bool write = false,
    Duration timeout = requestTimeout,
  }) async {
    _gate.check();
    final request = http.Request(method, _uri(path))
      ..headers.addAll(_headers(write: write));
    final response = await http.Response.fromStream(
      await _client.send(request).timeout(timeout),
    ).timeout(timeout);
    _gate.observe(response);
    return response;
  }

  Map<String, dynamic> _json(http.Response response, String unavailable) {
    final body = decodeJsonResponse(
      response,
      unavailable: unavailable,
      accept: const {200, 201},
    );
    if (body is! Map<String, dynamic>) {
      throw ApiException(unavailable, statusCode: response.statusCode);
    }
    return body;
  }

  /// Uploads [clips] as a new shared voice. [onProgress] reports bytes sent.
  Future<SharedVoicePack> upload({
    required String name,
    required bool consent,
    required List<VoicePackUploadClip> clips,
    void Function(int sent, int total)? onProgress,
  }) async {
    _gate.check();
    final request = http.MultipartRequest('POST', _uri(''))
      ..headers.addAll(_headers(write: true))
      ..fields['manifest'] = jsonEncode({
        'name': name.trim(),
        'consent': consent,
        'clips': [
          for (final clip in clips)
            {
              'language': clip.language,
              'phraseId': clip.phraseId,
              'contentType': clip.contentType,
              'bytes': clip.bytes.length,
              'sha256': sha256.convert(clip.bytes).toString(),
            },
        ],
      });
    for (final clip in clips) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'clip:${clip.language}:${clip.phraseId}',
          clip.bytes,
          filename: '${clip.phraseId}.m4a',
        ),
      );
    }
    final total = request.contentLength;
    final body = request.finalize();
    final streamed = http.StreamedRequest('POST', request.url)
      ..headers.addAll(request.headers)
      ..contentLength = total;
    var sent = 0;
    onProgress?.call(0, total);
    body.listen(
      (chunk) {
        sent += chunk.length;
        onProgress?.call(sent, total);
        streamed.sink.add(chunk);
      },
      onError: streamed.sink.addError,
      onDone: streamed.sink.close,
      cancelOnError: true,
    );
    final response = await http.Response.fromStream(
      await _client.send(streamed).timeout(uploadTimeout),
    ).timeout(uploadTimeout);
    _gate.observe(response);
    return SharedVoicePack.fromJson(
      (_json(response, 'Your voice could not be shared right now.')['pack']
              as Map<String, dynamic>?) ??
          const {},
    );
  }

  /// The signed-in member's active shared voices.
  Future<List<SharedVoicePack>> mine() async {
    final body = _json(
      await _send('GET', '/mine'),
      'Your shared voices could not be loaded.',
    );
    return (body['packs'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SharedVoicePack.fromJson)
        .toList(growable: false);
  }

  /// The pack for a code or link, with its clip manifest.
  Future<SharedVoicePack> fetch(String codeOrLink) async {
    final code = normalizeCode(codeOrLink);
    if (code == null) {
      throw ApiException(
        'That is not a voice code.',
        statusCode: 404,
        code: VoicePackErrorCode.notFound,
      );
    }
    final body = _json(
      await _send('GET', '/$code'),
      'This voice could not be loaded.',
    );
    return SharedVoicePack.fromJson(
      body['pack'] as Map<String, dynamic>? ?? const {},
    );
  }

  /// Downloads one clip and checks it against the manifest's size and
  /// SHA-256, so a damaged or swapped file is never installed.
  Future<Uint8List> downloadClip(
    SharedVoicePack pack,
    String language,
    String phraseId,
  ) async {
    final expected = pack.clips[language]?[phraseId];
    if (expected == null) {
      throw ApiException(
        'This recording is not in the voice.',
        statusCode: 404,
        code: VoicePackErrorCode.notFound,
      );
    }
    final response = await _send(
      'GET',
      '/${pack.code}/clips/$language/$phraseId',
    );
    if (response.statusCode != 200) {
      throw apiError(response, fallback: 'This voice could not be downloaded.');
    }
    final bytes = response.bodyBytes;
    if (bytes.length > maxClipBytes ||
        bytes.length != expected.bytes ||
        sha256.convert(bytes).toString() != expected.sha256) {
      throw ApiException(
        'A recording in this voice was damaged. Please try again.',
        statusCode: response.statusCode,
        code: VoicePackErrorCode.integrity,
      );
    }
    return bytes;
  }

  /// Counts one completed install. Failures are ignored.
  Future<void> recordImport(String code) async {
    try {
      await _send('POST', '/$code/import', write: true);
    } catch (_) {
      /* The install count is informational only. */
    }
  }

  /// Stops sharing [code] and deletes its recordings from Waybi.
  Future<void> revoke(String code) async {
    final response = await _send('DELETE', '/$code', write: true);
    _json(response, 'This voice could not be revoked right now.');
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
