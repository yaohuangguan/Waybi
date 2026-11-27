import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_mobile/drive/custom_voice.dart';
import 'package:waybi_mobile/drive/voice_clip_player.dart';
import 'package:waybi_mobile/drive/voice_engine.dart';
import 'package:waybi_mobile/drive/voice_recorder.dart';
import 'package:waybi_mobile/widgets/custom_voice_page.dart';

class RecordingTts extends FlutterTts {
  final spoken = <String>[];
  final events = <String>[];
  @override
  Future<dynamic> setLanguage(String language) async => 1;
  @override
  Future<dynamic> setSpeechRate(double rate) async => 1;
  @override
  Future<dynamic> setVolume(double volume) async => 1;
  @override
  Future<dynamic> awaitSpeakCompletion(bool enabled) async => 1;
  @override
  Future<void> setAudioAttributesForNavigation() async {}
  @override
  Future<dynamic> autoStopSharedSession(bool enabled) async => 1;
  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    spoken.add(text);
    events.add('tts:$text');
    return 1;
  }

  @override
  Future<dynamic> stop() async => 1;
}

class FakeClipPlayer implements VoiceClipPlayer {
  FakeClipPlayer(this.events);
  final List<String> events;
  final failing = <String>{};
  Completer<void>? hold;
  int stops = 0;

  @override
  Future<void> play(String path) async {
    final name = path.split('/').last;
    events.add('clip:$name');
    if (hold != null) await hold!.future;
    if (failing.any(path.endsWith)) throw StateError('corrupt clip');
  }

  @override
  Future<void> stop() async {
    stops++;
    final pending = hold;
    hold = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(StateError('stopped'));
    }
  }

  @override
  Future<void> dispose() async {}
}

class FakeClips implements CustomVoiceClips {
  FakeClips(this.ids);
  Set<String> ids;
  final broken = <String>[];
  @override
  Set<String> playable(String language) => ids;
  @override
  String? clipPath(String language, String phraseId) =>
      '/clips/$language/$phraseId.m4a';
  @override
  void reportBroken(String language, String phraseId) {
    broken.add(phraseId);
    ids = ids.difference({phraseId});
  }
}

class FakeRecorder implements VoiceRecorder {
  bool permission = true;
  bool failStart = false;
  bool emptyStop = false;
  String? path;
  int bytes = 4096;
  @override
  Future<bool> requestPermission() async => permission;
  @override
  Future<void> start(String path) async {
    if (failStart) throw StateError('no microphone');
    this.path = path;
  }

  @override
  Future<String?> stop() async {
    final target = path;
    if (target == null || emptyStop) return null;
    await File(target).writeAsBytes(List.filled(bytes, 1));
    return target;
  }

  @override
  Future<void> cancel() async {}
  @override
  Future<void> dispose() async {}
}

List<String> describe(List<VoiceSegment> segments) => [
  for (final segment in segments)
    switch (segment) {
      ClipSegment(:final phraseId) => 'clip:$phraseId',
      TtsSegment(:final text) => 'tts:$text',
    },
];

Future<String> writeDraft(Directory dir, String name, int bytes) async {
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(List.filled(bytes, 7));
  return file.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('phrase planning', () {
    test('no recordings keeps the sentence for standard TTS unchanged', () {
      expect(
        describe(
          planCustomVoice('In 300 m, Turn left onto Queen St', 'en', {}),
        ),
        ['tts:In 300 m, Turn left onto Queen St'],
      );
    });

    test('distance and maneuver use clips and the road name uses TTS', () {
      expect(
        describe(
          planCustomVoice('In 300 m, Turn left onto Queen St', 'en', {
            'in_300',
            'turn_left',
          }),
        ),
        ['clip:in_300', 'clip:turn_left', 'tts:onto Queen St'],
      );
    });

    test('distances snap only when close to a recorded distance', () {
      expect(
        describe(
          planCustomVoice('In 287 m, Keep right', 'en', {
            'in_300',
            'keep_right',
          }),
        ),
        ['clip:in_300', 'clip:keep_right'],
      );
      expect(
        describe(
          planCustomVoice('In 1.2 km, Keep right', 'en', {
            'in_1000',
            'in_1500',
            'keep_right',
          }),
        ),
        ['tts:In 1.2 km,', 'clip:keep_right'],
      );
      expect(
        describe(
          planCustomVoice('In 2.0 km, Merge ahead', 'en', {'in_2000', 'merge'}),
        ),
        ['clip:in_2000', 'clip:merge'],
      );
    });

    test('words inside road names never trigger a clip', () {
      expect(
        describe(
          planCustomVoice('Continue straight toward Keep Left Road', 'en', {
            'keep_left',
          }),
        ),
        ['tts:Continue straight toward Keep Left Road'],
      );
      expect(describe(planCustomVoice('Turn lefty', 'en', {'turn_left'})), [
        'tts:Turn lefty',
      ]);
    });

    test('longest phrase wins and matching ignores case', () {
      expect(
        describe(
          planCustomVoice('at the roundabout, take exit 2 toward SH1', 'en', {
            'roundabout_exit_2',
            'roundabout',
          }),
        ),
        ['clip:roundabout_exit_2', 'tts:toward SH1'],
      );
      expect(
        describe(
          planCustomVoice('Turn sharp left', 'en', {'sharp_left', 'turn_left'}),
        ),
        ['clip:sharp_left'],
      );
    });

    test('Chinese guidance, camera and arrival sentences', () {
      expect(
        describe(
          planCustomVoice('300 米后，左转，驶向 皇后街', 'zh', {'in_300', 'turn_left'}),
        ),
        ['clip:in_300', 'clip:turn_left', 'tts:驶向 皇后街'],
      );
      expect(
        describe(
          planCustomVoice('前方 450 米有定点测速摄像头，位于皇后街。', 'zh', {'camera_speed'}),
        ),
        ['tts:前方 450 米有定点测速摄像头，位于皇后街。'],
        reason: 'A clip only starts a clause, never mid-sentence',
      );
      expect(describe(planCustomVoice('已到达目的地，这段旅程辛苦啦！', 'zh', {'arrived'})), [
        'clip:arrived',
        'tts:这段旅程辛苦啦！',
      ]);
    });

    test('English camera alert keeps the distance and road in TTS', () {
      expect(
        describe(
          planCustomVoice(
            'Fixed speed camera in 450 metres on Queen St.',
            'en',
            {'camera_speed', 'in_500'},
          ),
        ),
        ['clip:camera_speed', 'tts:in 450 metres on Queen St.'],
      );
    });

    test('every phrase prompt plans to its own clip', () {
      for (final phrase in customVoicePhrases) {
        for (final language in CustomVoiceController.languages) {
          expect(
            describe(
              planCustomVoice(phrase.prompt(language), language, {phrase.id}),
            ),
            ['clip:${phrase.id}'],
            reason: '${phrase.id} ($language)',
          );
        }
      }
    });
  });

  group('voice engine fallback', () {
    late RecordingTts tts;
    late List<String> events;
    late FakeClipPlayer player;

    setUp(() {
      tts = RecordingTts();
      events = tts.events;
      player = FakeClipPlayer(events);
    });

    test('plays clips in order and speaks the rest with TTS', () async {
      final voice = VoiceEngine(
        tts: tts,
        customVoice: FakeClips({'in_300', 'turn_left'}),
        clipPlayer: () => player,
      );
      await voice.guidance('In 300 m, Turn left onto Queen St');
      expect(events, [
        'clip:in_300.m4a',
        'clip:turn_left.m4a',
        'tts:onto Queen St',
      ]);
    });

    test('a corrupt clip is spoken by TTS and skipped afterwards', () async {
      final clips = FakeClips({'in_300', 'turn_left'});
      player.failing.add('turn_left.m4a');
      final voice = VoiceEngine(
        tts: tts,
        customVoice: clips,
        clipPlayer: () => player,
      );
      await voice.guidance('In 300 m, Turn left');
      expect(events, [
        'clip:in_300.m4a',
        'clip:turn_left.m4a',
        'tts:Turn left',
      ]);
      expect(clips.broken, ['turn_left']);
      events.clear();
      await voice.guidance('Turn left');
      expect(events, ['tts:Turn left']);
    });

    test('inactive custom voice uses the standard voice only', () async {
      final voice = VoiceEngine(
        tts: tts,
        customVoice: FakeClips({}),
        clipPlayer: () => fail('No clip player without clips'),
      );
      await voice.guidance('Turn left');
      expect(events, ['tts:Turn left']);
    });

    test('an urgent turn interrupts an alert clip without marking it broken',
        () async {
      final clips = FakeClips({'in_300', 'turn_left'});
      player.hold = Completer<void>();
      final voice = VoiceEngine(
        tts: tts,
        customVoice: clips,
        clipPlayer: () => player,
      );
      final alert = voice.roadAlert(() => 'In 300 m, Turn left onto Queen St');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(events, ['clip:in_300.m4a']);
      final turn = voice.turnPrompt(() => 'Turn right', urgent: true);
      expect(await alert, isFalse);
      expect(await turn, isTrue);
      expect(player.stops, greaterThan(0));
      expect(clips.broken, isEmpty);
      expect(events, ['clip:in_300.m4a', 'tts:Turn right']);
    });

    test('stop cancels a playing clip without marking it broken', () async {
      final clips = FakeClips({'turn_left'});
      player.hold = Completer<void>();
      final voice = VoiceEngine(
        tts: tts,
        customVoice: clips,
        clipPlayer: () => player,
      );
      final speech = voice.guidance('Turn left onto Queen St');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await voice.stop();
      await speech;
      expect(player.stops, greaterThan(0));
      expect(clips.broken, isEmpty);
      expect(tts.spoken, isEmpty);
    });

    test(
      'iOS prepares the ducking audio session before each segment',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        const channel = MethodChannel('waybi/navigation_audio');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              events.add(call.method);
              return null;
            });
        addTearDown(() {
          debugDefaultTargetPlatformOverride = null;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });
        final voice = VoiceEngine(
          tts: tts,
          customVoice: FakeClips({'turn_left'}),
          clipPlayer: () => player,
        );
        await voice.guidance('Turn left onto Queen St');
        expect(events, [
          'prepare',
          'clip:turn_left.m4a',
          'prepare',
          'tts:onto Queen St',
          'release',
        ]);
      },
    );
  });

  group('Plus gating and storage', () {
    late Directory root;
    late CustomVoiceController voice;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      root = await Directory.systemTemp.createTemp('waybi-voice-');
      voice = CustomVoiceController(rootDirectory: () async => root);
      await voice.load();
    });
    tearDown(() async {
      voice.dispose();
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('clips play only for an active Plus member', () async {
      final draft = await voice.draftPath('en');
      await File(draft).writeAsBytes(List.filled(4096, 1));
      expect(await voice.saveClip('en', 'turn_left', draft), isTrue);
      expect(voice.recorded('en'), {'turn_left'});
      expect(voice.playable('en'), isEmpty, reason: 'Not Plus yet');

      await voice.setEnabled(true);
      expect(voice.enabled, isFalse, reason: 'Free users cannot switch it on');

      voice.setPlus(true);
      await voice.setEnabled(true);
      expect(voice.playable('en'), {'turn_left'});
      expect(voice.playable('zh'), isEmpty);

      voice.setPlus(false);
      expect(voice.playable('en'), isEmpty, reason: 'Plus lapsed');
      expect(voice.recorded('en'), {'turn_left'}, reason: 'Files are kept');
    });

    test('tiny or unknown recordings are rejected', () async {
      final tiny = await writeDraft(root, 'tiny.m4a', 10);
      expect(await voice.saveClip('en', 'turn_left', tiny), isFalse);
      expect(File(tiny).existsSync(), isFalse);
      final good = await writeDraft(root, 'good.m4a', 4096);
      expect(await voice.saveClip('en', 'not_a_phrase', good), isFalse);
    });

    test(
      'broken clips are skipped until re-recorded; delete removes files',
      () async {
        voice.setPlus(true);
        await voice.setEnabled(true);
        await voice.saveClip(
          'zh',
          'arrived',
          await writeDraft(root, 'a.m4a', 4096),
        );
        voice.reportBroken('zh', 'arrived');
        expect(voice.playable('zh'), isEmpty);
        await voice.saveClip(
          'zh',
          'arrived',
          await writeDraft(root, 'b.m4a', 4096),
        );
        expect(voice.playable('zh'), {'arrived'});

        final path = voice.clipPath('zh', 'arrived')!;
        expect(File(path).existsSync(), isTrue);
        await voice.deleteClip('zh', 'arrived');
        expect(File(path).existsSync(), isFalse);
        expect(voice.playable('zh'), isEmpty);

        await voice.saveClip(
          'en',
          'merge',
          await writeDraft(root, 'c.m4a', 4096),
        );
        await voice.deleteAll();
        expect(voice.recorded('en'), isEmpty);
        expect(Directory('${root.path}/custom_voice').existsSync(), isFalse);
      },
    );

    test(
      'load restores recordings and the switch, ignoring bad files',
      () async {
        voice.setPlus(true);
        await voice.setEnabled(true);
        await voice.saveClip(
          'en',
          'keep_left',
          await writeDraft(root, 'k.m4a', 4096),
        );
        await File('${root.path}/custom_voice/en/turn_right.m4a')
            .writeAsBytes([1]);
        await File('${root.path}/custom_voice/en/unknown.m4a')
            .writeAsBytes(List.filled(4096, 1));

        final restored = CustomVoiceController(rootDirectory: () async => root);
        addTearDown(restored.dispose);
        await restored.load();
        expect(restored.recorded('en'), {'keep_left'});
        expect(restored.enabled, isTrue);
        expect(restored.playable('en'), isEmpty, reason: 'Waits for Plus');
        restored.setPlus(true);
        expect(restored.playable('en'), {'keep_left'});
      },
    );
  });

  group('custom voice page', () {
    late Directory root;
    late CustomVoiceController voice;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      root = Directory.systemTemp.createTempSync('waybi-voice-page-');
      voice = CustomVoiceController(rootDirectory: () async => root);
    });
    tearDown(() {
      voice.dispose();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    testWidgets('free users see the upsell and cannot record', (tester) async {
      var openedPlus = false;
      await tester.pumpWidget(
        MaterialApp(
          home: CustomVoicePage(
            controller: voice,
            language: 'en',
            onOpenPlus: () => openedPlus = true,
            recorder: () => fail('Free users must not reach the microphone'),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('custom-voice-upsell')), findsOneWidget);
      final toggle = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('custom-voice-enabled')),
      );
      expect(toggle.onChanged, isNull);
      final record = tester.widget<IconButton>(
        find.byKey(const ValueKey('custom-voice-record-in_50')),
      );
      expect(record.onPressed, isNull);
      await tester.tap(find.text('See Waybi Plus'));
      expect(openedPlus, isTrue);
    });

    testWidgets('Plus members record, keep, re-record and delete a phrase', (
      tester,
    ) async {
      voice.setPlus(true);
      final recorder = FakeRecorder();
      await tester.pumpWidget(
        MaterialApp(
          home: CustomVoicePage(
            controller: voice,
            language: 'en',
            recorder: () => recorder,
            player: () => FakeClipPlayer([]),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('custom-voice-upsell')), findsNothing);
      final recordButton = find.byKey(
        const ValueKey('custom-voice-record-in_50'),
      );
      await tester.runAsync(() async {
        await tester.tap(recordButton);
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(find.text('Recording… tap stop when done'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(recordButton);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(find.text('New take — keep it?'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('custom-voice-keep-in_50')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(voice.recorded('en'), {'in_50'});
      expect(find.byTooltip('Re-record'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(
          find.byKey(const ValueKey('custom-voice-delete-in_50')),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(voice.recorded('en'), isEmpty);
    });

    testWidgets('declined microphone permission explains how to allow it', (
      tester,
    ) async {
      voice.setPlus(true);
      final recorder = FakeRecorder()..permission = false;
      await tester.pumpWidget(
        MaterialApp(
          home: CustomVoicePage(
            controller: voice,
            language: 'zh',
            recorder: () => recorder,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('custom-voice-record-in_50')));
      await tester.pump();
      expect(find.textContaining('麦克风权限已关闭'), findsOneWidget);
      expect(recorder.path, isNull);
    });
  });
}
