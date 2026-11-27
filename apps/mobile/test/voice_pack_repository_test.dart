import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waybi_mobile/data/http_guard.dart';
import 'package:waybi_mobile/data/voice_pack_repository.dart';
import 'package:waybi_mobile/widgets/friendly_error.dart';

Uint8List audio(int size, [int seed = 1]) =>
    Uint8List.fromList(List.filled(size, seed));

Map<String, dynamic> packJson({
  String code = 'ABCDEFGHJK',
  Map<String, dynamic>? clips,
}) => {
  'code': code,
  'name': 'Grandma',
  'languages': ['en', 'zh'],
  'clipCount': 2,
  'totalBytes': 3072,
  'createdAt': 1764000000000,
  'importCount': 3,
  'url': 'https://waybi.co/voice/$code',
  'clips': ?clips,
};

http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  test('codes are normalized from typing or a pasted link', () {
    expect(VoicePackRepository.normalizeCode(' abcde-fghjk '), 'ABCDEFGHJK');
    expect(
      VoicePackRepository.normalizeCode(
        'Try my voice: https://waybi.co/voice/ABCDE%20FGHJK?ref=x',
      ),
      'ABCDEFGHJK',
    );
    expect(VoicePackRepository.normalizeCode('ABCDEFGHJ0'), isNull);
    expect(VoicePackRepository.normalizeCode('short'), isNull);
    expect(VoicePackRepository.formatCode('ABCDEFGHJK'), 'ABCDE FGHJK');
    expect(VoicePackRepository.formatCode('odd'), 'odd');
    expect(
      VoicePackRepository.shareLink('ABCDEFGHJK'),
      'https://waybi.co/voice/ABCDEFGHJK',
    );
  });

  test(
    'upload sends a signed-in multipart manifest and reports progress',
    () async {
      late http.Request sent;
      final client = MockClient((request) async {
        sent = request;
        return jsonResponse({'pack': packJson()}, 201);
      });
      final repository = VoicePackRepository(
        client: client,
        session: () => 'a' * 64,
        baseUrl: 'https://w.test',
      );
      final progress = <double>[];
      final clips = [
        VoicePackUploadClip(
          language: 'en',
          phraseId: 'turn_left',
          bytes: audio(2048),
        ),
        VoicePackUploadClip(
          language: 'zh',
          phraseId: 'conn_toward',
          bytes: audio(1024, 2),
        ),
      ];
      final pack = await repository.upload(
        name: '  Grandma ',
        consent: true,
        clips: clips,
        onProgress: (done, total) => progress.add(done / total),
      );
      expect(sent.method, 'POST');
      expect(sent.url.toString(), 'https://w.test/api/voice-packs');
      expect(sent.headers['cookie'], 'waybi_session=${'a' * 64}');
      expect(sent.headers['x-waybi-client'], 'mobile');
      expect(sent.headers['content-type'], startsWith('multipart/form-data'));
      final body = latin1.decode(sent.bodyBytes);
      expect(body, contains('name="clip:en:turn_left"'));
      expect(body, contains('name="clip:zh:conn_toward"'));
      final manifestStart = body.indexOf('{"name"');
      final manifest = jsonDecode(
        body.substring(manifestStart, body.indexOf('\r\n', manifestStart)),
      );
      expect(manifest['name'], 'Grandma');
      expect(manifest['consent'], isTrue);
      expect(manifest['clips'][0], {
        'language': 'en',
        'phraseId': 'turn_left',
        'contentType': 'audio/mp4',
        'bytes': 2048,
        'sha256': sha256.convert(audio(2048)).toString(),
      });
      expect(progress.first, 0);
      expect(progress.last, 1);
      expect(pack.code, 'ABCDEFGHJK');
      expect(pack.displayCode, 'ABCDE FGHJK');
      expect(pack.importCount, 3);
      expect(pack.clips, isEmpty);
      expect(pack.createdAt.millisecondsSinceEpoch, 1764000000000);
      repository.dispose();
    },
  );

  test(
    'server errors keep their codes and rate limits hold later calls',
    () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        if (request.method == 'POST') {
          return jsonResponse({
            'error': 'You already share 5 voice packs.',
            'code': 'VOICE_PACK_LIMIT',
          }, 409);
        }
        return http.Response(
          jsonEncode({'error': 'Too many requests', 'code': 'RATE_LIMITED'}),
          429,
          headers: {'retry-after': '30'},
        );
      });
      final repository = VoicePackRepository(client: client);
      final limit = repository.upload(
        name: 'Me',
        consent: true,
        clips: [
          VoicePackUploadClip(
            language: 'en',
            phraseId: 'merge',
            bytes: audio(800),
          ),
        ],
      );
      await expectLater(
        limit,
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'VOICE_PACK_LIMIT')
              .having((e) => e.statusCode, 'status', 409),
        ),
      );
      try {
        await limit;
      } catch (error) {
        expect(friendlyErrorMessage(error, 'zh'), '你已分享 5 个语音。撤销一个后才能再分享。');
      }
      await expectLater(
        repository.mine(),
        throwsA(isA<RateLimitedException>()),
      );
      final before = calls;
      await expectLater(
        repository.mine(),
        throwsA(isA<RateLimitedException>()),
      );
      expect(
        calls,
        before,
        reason: 'The back-off is honoured without a request',
      );
    },
  );

  test(
    'fetch, download with integrity checks, import count and revoke',
    () async {
      final good = audio(1500, 3);
      final requests = <String>[];
      final client = MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        final path = request.url.path;
        if (path.endsWith('/mine')) {
          return jsonResponse({
            'packs': [packJson(), 'junk'],
          });
        }
        if (path == '/api/voice-packs/ABCDEFGHJK') {
          if (request.method == 'DELETE') return jsonResponse({'ok': true});
          return jsonResponse({
            'pack': packJson(
              clips: {
                'en': {
                  'turn_left': {
                    'bytes': good.length,
                    'contentType': 'audio/mp4',
                    'sha256': sha256.convert(good).toString().toUpperCase(),
                  },
                  'merge': {
                    'bytes': 10,
                    'contentType': 'audio/mp4',
                    'sha256': 'x',
                  },
                  'missing': {
                    'bytes': 10,
                    'contentType': 'audio/mp4',
                    'sha256': 'x',
                  },
                },
                'zh': 'junk',
              },
            ),
          });
        }
        if (path.endsWith('/clips/en/turn_left')) {
          return http.Response.bytes(good, 200);
        }
        if (path.endsWith('/clips/en/merge')) {
          return http.Response.bytes(audio(10), 200);
        }
        if (path.endsWith('/import')) throw http.ClientException('offline');
        return jsonResponse({
          'error': 'Gone',
          'code': 'VOICE_PACK_NOT_FOUND',
        }, 404);
      });
      final repository = VoicePackRepository(
        client: client,
        session: () => 's' * 64,
      );
      expect((await repository.mine()).single.name, 'Grandma');

      await expectLater(
        repository.fetch('nope'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'VOICE_PACK_NOT_FOUND',
          ),
        ),
      );
      final pack = await repository.fetch('https://waybi.co/voice/abcde-fghjk');
      expect(pack.clips['en']!.keys, ['turn_left', 'merge', 'missing']);
      expect(pack.clips.containsKey('zh'), isFalse);
      expect(await repository.downloadClip(pack, 'en', 'turn_left'), good);
      await expectLater(
        repository.downloadClip(pack, 'en', 'merge'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'CLIP_INTEGRITY'),
        ),
      );
      await expectLater(
        repository.downloadClip(pack, 'en', 'missing'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
      );
      await expectLater(
        repository.downloadClip(pack, 'zh', 'turn_left'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'VOICE_PACK_NOT_FOUND',
          ),
        ),
      );
      await repository.recordImport(pack.code);
      await repository.revoke(pack.code);
      expect(
        requests,
        containsAll([
          'POST /api/voice-packs/ABCDEFGHJK/import',
          'DELETE /api/voice-packs/ABCDEFGHJK',
        ]),
      );
      expect(
        SharedVoicePack.fromJson({'code': 'ABCDEFGHJK'}).url,
        'https://waybi.co/voice/ABCDEFGHJK',
      );
    },
  );

  test('an HTML error page becomes a friendly error', () async {
    final repository = VoicePackRepository(
      client: MockClient((_) async => http.Response('<html>502</html>', 502)),
    );
    await expectLater(
      repository.fetch('ABCDEFGHJK'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 502)),
    );
    final ok = VoicePackRepository(
      client: MockClient((_) async => jsonResponse(['not', 'a', 'map'])),
    );
    await expectLater(ok.mine(), throwsA(isA<ApiException>()));
    for (final code in [
      'VOICE_PACK_NOT_FOUND',
      'VOICE_SHARING_UNAVAILABLE',
      'CONSENT_REQUIRED',
      'VOICE_PACK_TOO_LARGE',
      'INVALID_CLIP',
      'CLIP_INTEGRITY',
      'VOICE_PACK_PURGE_FAILED',
      'VOICE_PACK_DELETE_FAILED',
    ]) {
      final error = ApiException('x', statusCode: 400, code: code);
      expect(friendlyErrorMessage(error, 'en'), isNot('x'), reason: code);
      expect(friendlyErrorMessage(error, 'zh'), matches(RegExp(r'[一-鿿]')));
    }
  });
}
