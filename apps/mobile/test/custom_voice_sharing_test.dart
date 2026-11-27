import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_mobile/data/http_guard.dart';
import 'package:waybi_mobile/data/voice_pack_repository.dart';
import 'package:waybi_mobile/drive/custom_voice.dart';
import 'package:waybi_mobile/widgets/custom_voice_page.dart';
import 'package:waybi_mobile/widgets/voice_pack_import_page.dart';
import 'package:waybi_mobile/widgets/voice_pack_share_page.dart';

import 'custom_voice_test.dart' show FakeClipPlayer, FakeRecorder;

const code = 'ABCDEFGHJK';

Uint8List clip([int seed = 1]) => Uint8List.fromList(List.filled(900, seed));

SharedVoicePack sharedPack({
  String packCode = code,
  String name = 'Grandma',
  int imports = 0,
  Map<String, Map<String, VoicePackClip>>? clips,
}) => SharedVoicePack(
  code: packCode,
  name: name,
  languages: const ['en', 'zh'],
  clipCount: 6,
  totalBytes: 5400,
  createdAt: DateTime(2026, 11, 1),
  importCount: imports,
  url: 'https://waybi.co/voice/$packCode',
  clips:
      clips ??
      {
        'en': {
          for (final id in [
            'turn_left',
            'in_300',
            'arrived',
            'conn_onto',
            'from_the_future',
          ])
            id: const VoicePackClip(
              bytes: 900,
              contentType: 'audio/mp4',
              sha256: 'x',
            ),
        },
        'zh': {
          'turn_left': const VoicePackClip(
            bytes: 900,
            contentType: 'audio/mp4',
            sha256: 'x',
          ),
        },
        'fr': {
          'turn_left': const VoicePackClip(
            bytes: 900,
            contentType: 'audio/mp4',
            sha256: 'x',
          ),
        },
      },
);

class FakeVoicePacks extends VoicePackRepository {
  FakeVoicePacks()
    : super(client: MockClient((_) async => http.Response('', 500)));
  List<SharedVoicePack> mineList = [];
  Object? mineError;
  Object? uploadError;
  Object? fetchError;
  Object? revokeError;
  Object? downloadError;
  SharedVoicePack fetched = sharedPack();
  List<VoicePackUploadClip>? uploaded;
  String? uploadedName;
  final revoked = <String>[];
  final imports = <String>[];
  final downloads = <String>[];
  int mineCalls = 0;
  Completer<void>? holdUpload;
  Completer<void>? holdDownloads;

  @override
  Future<SharedVoicePack> upload({
    required String name,
    required bool consent,
    required List<VoicePackUploadClip> clips,
    void Function(int sent, int total)? onProgress,
  }) async {
    onProgress?.call(50, 100);
    if (holdUpload case final hold?) await hold.future;
    if (uploadError case final error?) throw error;
    uploaded = clips;
    uploadedName = name;
    final pack = sharedPack(name: name.trim(), clips: const {});
    mineList = [pack];
    return pack;
  }

  @override
  Future<List<SharedVoicePack>> mine() async {
    mineCalls++;
    if (mineError case final error?) throw error;
    return mineList;
  }

  @override
  Future<SharedVoicePack> fetch(String codeOrLink) async {
    if (fetchError case final error?) throw error;
    if (VoicePackRepository.normalizeCode(codeOrLink) == null) {
      throw ApiException('bad', statusCode: 404, code: 'VOICE_PACK_NOT_FOUND');
    }
    return fetched;
  }

  @override
  Future<Uint8List> downloadClip(
    SharedVoicePack pack,
    String language,
    String phraseId,
  ) async {
    downloads.add('$language/$phraseId');
    if (holdDownloads case final hold?) await hold.future;
    if (downloadError case final error?) throw error;
    return clip(phraseId.length);
  }

  @override
  Future<void> recordImport(String code) async => imports.add(code);

  @override
  Future<void> revoke(String code) async {
    if (revokeError case final error?) throw error;
    revoked.add(code);
    mineList = mineList.where((pack) => pack.code != code).toList();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late CustomVoiceController voice;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = Directory.systemTemp.createTempSync('waybi-voice-share-');
    voice = CustomVoiceController(rootDirectory: () async => root);
    await voice.load();
  });
  tearDown(() {
    voice.dispose();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> saveOwn(String language, String id, {int bytes = 2048}) async {
    final draft = await voice.draftPath(language);
    await File(draft).writeAsBytes(List.filled(bytes, 4));
    await voice.saveClip(language, id, draft);
  }

  group('installed shared voices', () {
    test(
      'anyone can install and use a shared voice; removing deletes it',
      () async {
        expect(voice.plus, isFalse);
        final pack = await voice.installPack(
          code: code,
          name: 'Grandma',
          clips: {
            'en': {
              'turn_left': clip(),
              'conn_onto': clip(2),
              'not_a_phrase': clip(3),
              'merge': Uint8List(10),
            },
            'zh': {'conn_onto': clip(), 'conn_located': clip()},
            'fr': {'turn_left': clip()},
          },
          now: DateTime(2026, 11, 2),
        );
        expect(pack.clips, {
          'en': {'turn_left', 'conn_onto'},
          'zh': {'conn_located'},
        });
        expect(pack.clipCount, 3);
        expect(pack.languages, ['en', 'zh']);
        expect(
          voice.playable('en'),
          isEmpty,
          reason: 'Installed but not chosen',
        );

        await voice.usePack(code);
        expect(voice.choice, VoiceChoice.shared);
        expect(voice.active, isTrue, reason: 'Shared voices are free to use');
        expect(voice.playable('en'), {'turn_left', 'conn_onto'});
        final path = voice.clipPath('en', 'turn_left')!;
        expect(File(path).readAsBytesSync(), clip());
        expect(voice.clipPath('en', 'merge'), isNull);
        expect(voice.recordingPath('en', 'turn_left'), isNull);

        voice.reportBroken('en', 'turn_left');
        expect(voice.playable('en'), {'conn_onto'});
        expect(
          voice.isBroken('en', 'turn_left'),
          isFalse,
          reason: 'Own clips untouched',
        );

        final restored = CustomVoiceController(rootDirectory: () async => root);
        addTearDown(restored.dispose);
        await restored.load();
        expect(restored.activePackCode, code);
        expect(restored.installedPack(code)!.name, 'Grandma');
        expect(
          restored.installedPack(code)!.installedAt,
          DateTime(2026, 11, 2),
        );
        expect(restored.playable('en'), {'turn_left', 'conn_onto'});

        await voice.removePack(code);
        expect(
          Directory('${root.path}/custom_voice_packs/$code').existsSync(),
          isFalse,
        );
        expect(voice.choice, VoiceChoice.standard);
        expect(voice.installedPacks, isEmpty);
        final reloaded = CustomVoiceController(rootDirectory: () async => root);
        addTearDown(reloaded.dispose);
        await reloaded.load();
        expect(reloaded.choice, VoiceChoice.standard);
      },
    );

    test('own recordings, choices and leftovers', () async {
      SharedPreferences.setMockInitialValues({
        CustomVoiceController.enabledKey: true,
      });
      final legacy = CustomVoiceController(rootDirectory: () async => root);
      addTearDown(legacy.dispose);
      await legacy.load();
      expect(legacy.enabled, isTrue, reason: 'Earlier "use my voice" is kept');
      expect(legacy.active, isFalse, reason: 'Waits for Plus');
      legacy.setPlus(true);
      expect(legacy.active, isTrue);
      await legacy.setEnabled(false);
      expect(legacy.choice, VoiceChoice.standard);
      await legacy.setEnabled(false);
      await legacy.useOwnVoice();
      expect(legacy.choice, VoiceChoice.own);
      await legacy.usePack('MISSING234');
      expect(legacy.choice, VoiceChoice.own, reason: 'Not installed');

      voice.setPlus(true);
      await saveOwn('en', 'turn_left');
      await saveOwn('en', 'merge');
      await saveOwn('zh', 'conn_located');
      voice.reportBroken('en', 'merge');
      expect(
        voice.shareableRecordings().map((r) => '${r.language}/${r.phraseId}'),
        ['en/turn_left', 'zh/conn_located'],
      );

      await voice.installPack(
        code: code,
        name: 'A',
        clips: {
          'en': {'turn_left': clip()},
        },
        now: DateTime(2026),
      );
      await voice.installPack(
        code: 'BCDEFGHJKM',
        name: 'B',
        clips: {
          'en': {'turn_left': clip()},
        },
        now: DateTime(2027),
      );
      expect(voice.installedPacks.map((p) => p.name), ['B', 'A']);
      await voice.installPack(
        code: code,
        name: 'A2',
        clips: {
          'en': {'merge': clip()},
        },
      );
      expect(voice.installedPack(code)!.clips, {
        'en': {'merge'},
      });
      await voice.usePack('BCDEFGHJKM');
      await voice.removePack(code);
      expect(
        voice.activePackCode,
        'BCDEFGHJKM',
        reason: 'Removing another pack keeps the choice',
      );

      await expectLater(
        voice.installPack(code: 'bad', name: 'x', clips: const {}),
        throwsArgumentError,
      );
      await expectLater(
        voice.installPack(
          code: 'CDEFGHJKMN',
          name: 'x',
          clips: {
            'en': {'nope': clip()},
          },
        ),
        throwsStateError,
      );
      final preview = await voice.writePreview(
        code,
        'en',
        'turn_left',
        clip(5),
      );
      expect(File(preview).readAsBytesSync(), clip(5));

      final packs = Directory('${root.path}/custom_voice_packs');
      Directory('${packs.path}/DEFGHJKMNP').createSync();
      File('${packs.path}/DEFGHJKMNP/pack.json').writeAsStringSync('{oops');
      Directory('${packs.path}/not-a-code').createSync();
      File('${packs.path}/stray.txt').writeAsStringSync('x');
      Directory('${packs.path}/EFGHJKMNPQ/en').createSync(recursive: true);
      File('${packs.path}/EFGHJKMNPQ/pack.json').writeAsStringSync(
        jsonEncode({
          'name': 'Empty',
          'clips': {
            'en': ['turn_left'],
          },
        }),
      );
      final fresh = CustomVoiceController(rootDirectory: () async => root);
      addTearDown(fresh.dispose);
      await fresh.load();
      expect(fresh.installedPacks.map((p) => p.code), ['BCDEFGHJKM']);
      expect(
        Directory('${packs.path}/.preview').existsSync(),
        isFalse,
        reason: 'Previews and unfinished installs are cleared',
      );
      expect(
        packs.listSync().whereType<Directory>().any(
          (d) => d.path.contains('.install-'),
        ),
        isFalse,
      );
    });
  });

  group('pages', () {
    late FakeVoicePacks sharing;
    late List<String> played;
    String? clipboard;

    setUp(() {
      sharing = FakeVoicePacks();
      played = [];
      clipboard = null;
    });

    Future<void> act(WidgetTester tester, Future<void> Function() body) async {
      await tester.runAsync(() async {
        await body();
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pump();
    }

    Finder key(String value) => find.byKey(ValueKey(value));

    Future<void> open(
      WidgetTester tester, {
      String language = 'en',
      bool signedIn = true,
    }) async {
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboard = (call.arguments as Map)['text'] as String?;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CustomVoicePage(
                    controller: voice,
                    language: language,
                    recorder: FakeRecorder.new,
                    player: () => FakeClipPlayer(played),
                    sharing: sharing,
                    signedIn: signedIn,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await act(tester, () async {});
      await tester.pumpAndSettle();
    }

    testWidgets('a Plus member shares their voice and gets a code and link', (
      tester,
    ) async {
      voice.setPlus(true);
      await open(tester);
      expect(
        tester.widget<FilledButton>(key('custom-voice-share')).onPressed,
        isNull,
      );
      expect(find.text('Record some phrases first.'), findsOneWidget);
      await tester.runAsync(() async {
        await saveOwn('en', 'turn_left');
        await saveOwn('zh', 'conn_located');
      });
      await tester.pump();

      await act(tester, () async => tester.tap(key('custom-voice-share')));
      await tester.pumpAndSettle();
      expect(find.byType(VoicePackSharePage), findsOneWidget);
      expect(
        find.text('Shares 1 English and 1 Chinese recordings.'),
        findsOneWidget,
      );
      FilledButton submit() =>
          tester.widget<FilledButton>(key('voice-share-submit'));
      expect(submit().onPressed, isNull);
      await tester.enterText(key('voice-share-name'), 'Grandma');
      await tester.pump();
      expect(submit().onPressed, isNull, reason: 'Consent is required');
      await tester.tap(key('voice-share-consent'));
      await tester.pump();

      sharing.uploadError = ApiException(
        'full',
        statusCode: 409,
        code: 'VOICE_PACK_LIMIT',
      );
      await act(tester, () async => tester.tap(key('voice-share-submit')));
      for (
        var i = 0;
        i < 100 &&
            find.byKey(const ValueKey('voice-share-error')).evaluate().isEmpty;
        i++
      ) {
        await act(
          tester,
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(
        find.text('You already share 5 voices. Revoke one to share another.'),
        findsOneWidget,
      );
      sharing.uploadError = null;
      await act(tester, () async => tester.tap(key('voice-share-submit')));
      for (var i = 0; i < 100 && sharing.uploadedName == null; i++) {
        await act(
          tester,
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(sharing.uploadedName, 'Grandma');
      expect(
        sharing.uploaded!.map((clip) => '${clip.language}/${clip.phraseId}'),
        ['en/turn_left', 'zh/conn_located'],
      );
      expect(sharing.uploaded!.first.bytes.length, 2048);
      expect(find.text('ABCDE FGHJK'), findsOneWidget);
      expect(find.text('https://waybi.co/voice/$code'), findsOneWidget);
      // Fake-time taps, so the confirmation messages run on test timers.
      await tester.tap(key('voice-share-copy-link'));
      await tester.pump();
      expect(clipboard, 'https://waybi.co/voice/$code');
      await tester.tap(key('voice-share-copy-code'));
      await tester.pumpAndSettle();
      expect(clipboard, code);
      expect(find.text('Code copied'), findsOneWidget);

      await act(tester, () async => tester.tap(key('voice-share-done')));
      await tester.pumpAndSettle();
      expect(key('custom-voice-shared-$code'), findsOneWidget);
      expect(find.text('ABCDE FGHJK · installed 0 times'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('revoking a share code, and a list that fails to load', (
      tester,
    ) async {
      voice.setPlus(true);
      sharing.mineError = ApiException(
        'x',
        statusCode: 503,
        code: 'VOICE_SHARING_UNAVAILABLE',
      );
      await open(tester, language: 'zh');
      expect(find.text('语音分享暂时不可用，请稍后重试。'), findsOneWidget);
      sharing.mineError = null;
      sharing.mineList = [sharedPack(imports: 4)];
      await act(
        tester,
        () async => tester.tap(key('custom-voice-shared-retry')),
      );
      expect(find.text('ABCDE FGHJK · 已安装 4 次'), findsOneWidget);

      await tester.tap(key('custom-voice-revoke-$code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(sharing.revoked, isEmpty);

      sharing.revokeError = ApiException(
        'x',
        statusCode: 503,
        code: 'VOICE_PACK_PURGE_FAILED',
      );
      await tester.tap(key('custom-voice-revoke-$code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('停止分享'));
      await tester.pumpAndSettle();
      expect(find.text('代码已撤销，但部分录音尚未删除，请重试。'), findsOneWidget);
      // Let the message close before the next one replaces it.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      sharing.revokeError = null;
      await tester.tap(key('custom-voice-revoke-$code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('停止分享'));
      await tester.pumpAndSettle();
      expect(sharing.revoked, [code]);
      expect(key('custom-voice-shared-$code'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('anyone can look up, preview and install a shared voice', (
      tester,
    ) async {
      await open(tester, signedIn: false);
      expect(sharing.mineCalls, 0, reason: 'Signed-out users have no codes');
      expect(key('custom-voice-share'), findsNothing);
      expect(
        tester.widget<SwitchListTile>(key('custom-voice-omit-roads')).onChanged,
        isNull,
      );

      await act(tester, () async => tester.tap(key('custom-voice-import')));
      await tester.pumpAndSettle();
      expect(find.byType(VoicePackImportPage), findsOneWidget);
      await tester.enterText(key('voice-import-code'), 'hello');
      await tester.pump();
      await act(tester, () async => tester.tap(key('voice-import-look-up')));
      expect(
        find.text(
          'Enter the 10-character code or paste the link you were sent.',
        ),
        findsOneWidget,
      );
      sharing.fetchError = ApiException(
        'gone',
        statusCode: 404,
        code: 'VOICE_PACK_NOT_FOUND',
      );
      await tester.enterText(
        key('voice-import-code'),
        'https://waybi.co/voice/$code',
      );
      await act(tester, () async => tester.tap(key('voice-import-look-up')));
      expect(
        find.text(
          'That voice code isn’t valid or has been revoked. Check it, or ask for a new one.',
        ),
        findsOneWidget,
      );
      sharing.fetchError = null;
      await act(tester, () async => tester.tap(key('voice-import-look-up')));
      expect(find.text('Grandma'), findsOneWidget);
      expect(find.text('5 phrases · English · 中文'), findsOneWidget);
      expect(key('voice-import-preview-en-turn_left'), findsOneWidget);
      expect(key('voice-import-preview-en-in_300'), findsOneWidget);
      expect(key('voice-import-preview-en-arrived'), findsOneWidget);

      await act(
        tester,
        () async => tester.tap(
          find.descendant(
            of: key('voice-import-preview-en-turn_left'),
            matching: find.byType(IconButton),
          ),
        ),
      );
      for (var i = 0; i < 100 && played.isEmpty; i++) {
        await act(
          tester,
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(find.byKey(const ValueKey('voice-import-error')), findsNothing);
      expect(played.single, 'clip:$code-en-turn_left.m4a');

      sharing.downloadError = ApiException(
        'bad',
        statusCode: 200,
        code: 'CLIP_INTEGRITY',
      );
      await act(tester, () async => tester.tap(key('voice-import-install')));
      expect(
        find.text('A recording was damaged in transfer. Please try again.'),
        findsOneWidget,
      );
      expect(voice.installedPacks, isEmpty);

      sharing.downloadError = null;
      sharing.downloads.clear();
      await act(tester, () async => tester.tap(key('voice-import-install')));
      for (
        var i = 0;
        i < 100 && find.byType(VoicePackImportPage).evaluate().isNotEmpty;
        i++
      ) {
        await act(
          tester,
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.pumpAndSettle();
      expect(sharing.downloads.toSet(), {
        'en/turn_left',
        'en/in_300',
        'en/arrived',
        'en/conn_onto',
        'zh/turn_left',
      });
      expect(sharing.imports, [code]);
      expect(voice.activePackCode, code);
      expect(find.text('Guidance now uses “Grandma”'), findsOneWidget);
      expect(key('custom-voice-use-pack-$code'), findsOneWidget);
      expect(
        find.text('Shared voice · 5 phrases · ABCDE FGHJK'),
        findsOneWidget,
      );
      expect(
        tester.widget<SwitchListTile>(key('custom-voice-omit-roads')).onChanged,
        isNotNull,
      );

      await act(
        tester,
        () async => tester.tap(key('custom-voice-use-standard')),
      );
      expect(voice.choice, VoiceChoice.standard);
      await act(
        tester,
        () async => tester.tap(key('custom-voice-use-pack-$code')),
      );
      expect(voice.choice, VoiceChoice.shared);
      expect(
        tester
            .widget<RadioListTile<String>>(key('custom-voice-use-own'))
            .enabled,
        isFalse,
      );

      await act(
        tester,
        () async => tester.tap(key('custom-voice-remove-pack-$code')),
      );
      await tester.pumpAndSettle();
      await act(tester, () async => tester.tap(find.text('Remove')));
      await tester.pumpAndSettle();
      expect(voice.installedPacks, isEmpty);
      expect(voice.choice, VoiceChoice.standard);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets(
      'a pasted link looks up straight away; installed voices update',
      (tester) async {
        await tester.runAsync(
          () => voice.installPack(
            code: code,
            name: 'Grandma',
            clips: {
              'en': {'turn_left': clip()},
            },
          ),
        );
        tester.view.physicalSize = const Size(900, 3000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        sharing.fetched = sharedPack(
          clips: {
            'zh': {
              for (final id in ['左', 'conn_located', 'merge', 'ramp'])
                id: const VoicePackClip(
                  bytes: 900,
                  contentType: 'audio/mp4',
                  sha256: 'x',
                ),
            },
          },
        );
        await tester.pumpWidget(
          MaterialApp(
            home: VoicePackImportPage(
              controller: voice,
              repository: sharing,
              language: 'zh',
              initialCode: code,
              player: () => FakeClipPlayer(played)..hold = Completer<void>(),
            ),
          ),
        );
        await act(tester, () async {});
        expect(find.text('3 条短语 · 中文'), findsOneWidget);
        expect(find.text('更新并使用这个语音'), findsOneWidget);
        expect(key('voice-import-preview-zh-merge'), findsOneWidget);
        expect(
          key('voice-import-preview-zh-conn_located'),
          findsNothing,
          reason: 'Preferred phrases are previewed first',
        );
        final play = find.descendant(
          of: key('voice-import-preview-zh-merge'),
          matching: find.byType(IconButton),
        );
        await act(tester, () async => tester.tap(play));
        expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
        await act(tester, () async => tester.tap(play));
        expect(find.byIcon(Icons.stop_rounded), findsNothing);
      },
    );

    testWidgets('progress while uploading and installing, and preview errors', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      voice.setPlus(true);
      await tester.runAsync(() => saveOwn('en', 'turn_left'));
      sharing.holdUpload = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: VoicePackSharePage(
            controller: voice,
            repository: sharing,
            language: 'zh',
          ),
        ),
      );
      await tester.enterText(key('voice-share-name'), '我的声音');
      await tester.tap(key('voice-share-consent'));
      await tester.pump();
      await act(tester, () async => tester.tap(key('voice-share-submit')));
      expect(find.text('正在上传…'), findsOneWidget);
      sharing.holdUpload!.complete();
      for (var i = 0; i < 100 && sharing.uploadedName == null; i++) {
        await act(
          tester,
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(find.text('“我的声音”已可以分享'), findsOneWidget);

      sharing.fetched = sharedPack(
        clips: {
          'zh': {
            for (final id in ['conn_located', 'ramp', 'ferry', 'depart'])
              id: const VoicePackClip(
                bytes: 900,
                contentType: 'audio/mp4',
                sha256: 'x',
              ),
          },
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: VoicePackImportPage(
            controller: voice,
            repository: sharing,
            language: 'en',
            player: () => FakeClipPlayer(played),
          ),
        ),
      );
      await tester.enterText(key('voice-import-code'), code);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await act(tester, () async {});
      expect(find.text('4 phrases · 中文'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('voice-import-preview-zh-conn_located')),
        findsOneWidget,
        reason: 'Without preferred phrases the first ones are previewed',
      );
      sharing.downloadError = ApiException('x', statusCode: 404);
      await act(
        tester,
        () async => tester.tap(
          find.descendant(
            of: key('voice-import-preview-zh-ramp'),
            matching: find.byType(IconButton),
          ),
        ),
      );
      expect(find.text('That item is no longer available.'), findsOneWidget);
      sharing.downloadError = null;
      sharing.holdDownloads = Completer<void>();
      await act(tester, () async => tester.tap(key('voice-import-install')));
      expect(find.text('Installing…'), findsOneWidget);
      sharing.holdDownloads!.complete();
      for (var i = 0; i < 100 && voice.installedPacks.isEmpty; i++) {
        await act(
          tester,
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(voice.installedPack(code)!.clipCount, 4);
    });

    test('a chosen voice that is no longer installed falls back', () async {
      SharedPreferences.setMockInitialValues({
        CustomVoiceController.activeVoiceKey: 'pack:$code',
      });
      final stale = CustomVoiceController(rootDirectory: () async => root);
      addTearDown(stale.dispose);
      await stale.load();
      expect(stale.choice, VoiceChoice.standard);
    });
  });
}
