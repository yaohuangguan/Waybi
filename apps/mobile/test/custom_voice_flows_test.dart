import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_mobile/drive/custom_voice.dart';
import 'package:waybi_mobile/drive/voice_clip_player.dart';
import 'package:waybi_mobile/drive/voice_engine.dart';
import 'package:waybi_mobile/drive/voice_recorder.dart';
import 'package:waybi_mobile/widgets/custom_voice_page.dart';

import 'custom_voice_test.dart'
    show FakeClipPlayer, FakeClips, FakeRecorder, RecordingTts, tallView;

class ThrowingClips extends FakeClips {
  ThrowingClips() : super({'turn_left'});
  @override
  Set<String> playable(String language) => throw StateError('index broken');
}

class TrackingPlayer extends FakeClipPlayer {
  TrackingPlayer(super.events);
  bool disposed = false;
  @override
  Future<void> dispose() async => disposed = true;
}

class FakeAudioPlayer implements AudioPlayer {
  final calls = <String>[];
  final _complete = StreamController<void>.broadcast();
  final _state = StreamController<PlayerState>.broadcast();
  PlayerState? endWith;

  @override
  Stream<void> get onPlayerComplete => _complete.stream;
  @override
  Stream<PlayerState> get onPlayerStateChanged => _state.stream;
  @override
  Future<void> setAudioContext(AudioContext ctx) async =>
      calls.add('context:${ctx.android.usageType.name}');
  @override
  Future<void> setReleaseMode(ReleaseMode releaseMode) async =>
      calls.add('release:${releaseMode.name}');
  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    calls.add('play:${(source as DeviceFileSource).path}');
    scheduleMicrotask(() {
      if (endWith == PlayerState.stopped) {
        _state.add(PlayerState.stopped);
      } else {
        _complete.add(null);
      }
    });
  }

  @override
  Future<void> stop() async => calls.add('stop');
  @override
  Future<void> dispose() async => calls.add('dispose');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAudioRecorder implements AudioRecorder {
  final calls = <String>[];
  RecordConfig? config;
  @override
  Future<bool> hasPermission({bool request = true}) async => true;
  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    this.config = config;
    calls.add('start:$path');
  }

  @override
  Future<String?> stop() async => 'done.m4a';
  @override
  Future<void> cancel() async => calls.add('cancel');
  @override
  Future<void> dispose() async => calls.add('dispose');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('platform wrappers', () {
    test(
      'clip player uses navigation audio and completes with the clip',
      () async {
        final audio = FakeAudioPlayer();
        final player = AudioplayersClipPlayer(player: audio);
        await player.play('/clips/en/turn_left.m4a');
        await player.play('/clips/en/merge.m4a');
        expect(audio.calls, [
          'context:assistanceNavigationGuidance',
          'release:stop',
          'play:/clips/en/turn_left.m4a',
          'play:/clips/en/merge.m4a',
        ]);
        audio.endWith = PlayerState.stopped;
        await expectLater(player.play('/clips/en/x.m4a'), throwsStateError);
        await player.stop();
        await player.dispose();
        expect(audio.calls.skip(5), ['stop', 'dispose']);
        expect(
          AudioplayersClipPlayer.navigationContext.android.audioFocus,
          AndroidAudioFocus.gainTransientMayDuck,
        );
      },
    );

    test('recorder records mono AAC and forwards lifecycle calls', () async {
      final audio = FakeAudioRecorder();
      final recorder = RecordVoiceRecorder(recorder: audio);
      expect(await recorder.requestPermission(), isTrue);
      await recorder.start('/drafts/a.m4a');
      expect(audio.config?.encoder, AudioEncoder.aacLc);
      expect(audio.config?.numChannels, 1);
      expect(await recorder.stop(), 'done.m4a');
      await recorder.cancel();
      await recorder.dispose();
      expect(audio.calls, ['start:/drafts/a.m4a', 'cancel', 'dispose']);
    });
  });

  group('engine safety', () {
    test('a failing clip index falls back to TTS', () async {
      final tts = RecordingTts();
      final voice = VoiceEngine(tts: tts, customVoice: ThrowingClips());
      await voice.guidance('Turn left');
      expect(tts.spoken, ['Turn left']);
    });

    test('dispose releases the clip player', () async {
      final tts = RecordingTts();
      final player = TrackingPlayer(tts.events);
      final voice = VoiceEngine(
        tts: tts,
        customVoice: FakeClips({'turn_left'}),
        clipPlayer: () => player,
      );
      await voice.guidance('Turn left');
      await voice.dispose();
      expect(player.disposed, isTrue);
    });

    test('segments compare by value', () {
      expect(const ClipSegment('a', 'A'), const ClipSegment('a', 'A'));
      expect(
        const ClipSegment('a', 'A').hashCode,
        const ClipSegment('a', 'A').hashCode,
      );
      expect(const TtsSegment('x'), const TtsSegment('x'));
      expect(const TtsSegment('x').hashCode, const TtsSegment('x').hashCode);
      expect('${const ClipSegment('a', 'A')}', 'Clip(a)');
      expect('${const TtsSegment('x')}', 'Tts(x)');
    });
  });

  group('recording page flows', () {
    late Directory root;
    late CustomVoiceController voice;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      root = Directory.systemTemp.createTempSync('waybi-voice-flow-');
      voice = CustomVoiceController(rootDirectory: () async => root);
      await voice.load();
      voice.setPlus(true);
    });
    tearDown(() {
      voice.dispose();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    Future<void> act(WidgetTester tester, Future<void> Function() body) async {
      await tester.runAsync(() async {
        await body();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
    }

    Finder key(String value) => find.byKey(ValueKey(value));

    Widget page({
      required VoiceRecorder recorder,
      required VoiceClipPlayer player,
    }) => MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CustomVoicePage(
                controller: voice,
                language: 'en',
                recorder: () => recorder,
                player: () => player,
              ),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    );

    Future<void> open(WidgetTester tester, Widget app) async {
      tallView(tester);
      await tester.pumpWidget(app);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('draft preview, discard, short take, toggle and pack switch', (
      tester,
    ) async {
      final recorder = FakeRecorder();
      final events = <String>[];
      await open(
        tester,
        page(recorder: recorder, player: FakeClipPlayer(events)),
      );
      final record = key('custom-voice-record-in_50');

      await act(tester, () async => tester.tap(record));
      await act(tester, () async => tester.tap(record));
      await act(
        tester,
        () async => tester.tap(key('custom-voice-play-draft-in_50')),
      );
      expect(events.single, startsWith('clip:en-'));
      await act(
        tester,
        () async => tester.tap(key('custom-voice-discard-in_50')),
      );
      expect(find.text('New take — keep it?'), findsNothing);
      expect(voice.recorded('en'), isEmpty);

      recorder.bytes = 10;
      await act(tester, () async => tester.tap(record));
      await act(tester, () async => tester.tap(record));
      await act(tester, () async => tester.tap(key('custom-voice-keep-in_50')));
      expect(
        find.text('That take was too short to use. Please record again.'),
        findsOneWidget,
      );

      await act(tester, () async => tester.tap(key('custom-voice-use-own')));
      expect(voice.enabled, isTrue);
      await act(
        tester,
        () async => tester.tap(key('custom-voice-use-standard')),
      );
      expect(voice.enabled, isFalse);
      await act(tester, () async => tester.tap(key('custom-voice-use-own')));

      await act(tester, () async => tester.tap(record));
      await act(tester, () async => tester.tap(find.text('中文')));
      expect(find.text('“50 米后”'), findsOneWidget);
      expect(find.text('Recording… tap stop when done'), findsNothing);
    });

    testWidgets('recording errors are explained', (tester) async {
      final recorder = FakeRecorder()..failStart = true;
      await open(tester, page(recorder: recorder, player: FakeClipPlayer([])));
      final record = key('custom-voice-record-in_100');
      await act(tester, () async => tester.tap(record));
      expect(find.text('Recording could not start.'), findsOneWidget);

      recorder
        ..failStart = false
        ..emptyStop = true;
      await act(tester, () async => tester.tap(record));
      await act(tester, () async => tester.tap(record));
      expect(find.text('Nothing was recorded. Try again.'), findsOneWidget);
    });

    testWidgets(
      'unplayable clips are flagged, playback stops, delete all clears',
      (tester) async {
        await tester.runAsync(() async {
          for (final id in ['arrived', 'merge']) {
            final draft = await voice.draftPath('en');
            await File(draft).writeAsBytes(List.filled(4096, 1));
            await voice.saveClip('en', id, draft);
          }
        });

        final player = FakeClipPlayer([])..failing.add('arrived.m4a');
        await open(tester, page(recorder: FakeRecorder(), player: player));
        await tester.scrollUntilVisible(
          key('custom-voice-play-arrived'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await act(
          tester,
          () async => tester.tap(key('custom-voice-play-arrived')),
        );
        expect(voice.isBroken('en', 'arrived'), isTrue);
        expect(find.text('Can’t be played — please re-record'), findsOneWidget);

        player.hold = Completer<void>();
        final merge = key('custom-voice-play-merge');
        await tester.scrollUntilVisible(
          merge,
          -300,
          scrollable: find.byType(Scrollable).first,
        );
        await act(tester, () async => tester.tap(merge));
        expect(find.byTooltip('Play'), findsWidgets);
        await act(tester, () async => tester.tap(merge));
        expect(player.stops, greaterThan(0));

        await act(
          tester,
          () async => tester.tap(key('custom-voice-delete-all')),
        );
        await tester.pumpAndSettle();
        await act(tester, () async => tester.tap(find.text('Delete')));
        for (var i = 0; i < 5 && voice.recorded('en').isNotEmpty; i++) {
          await act(
            tester,
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
        }
        expect(voice.recorded('en'), isEmpty);
      },
    );

    testWidgets('leaving the page discards an unsaved take', (tester) async {
      final recorder = FakeRecorder();
      await open(tester, page(recorder: recorder, player: FakeClipPlayer([])));
      final record = key('custom-voice-record-in_50');
      await act(tester, () async => tester.tap(record));
      await act(tester, () async => tester.tap(record));
      final draft = recorder.path!;
      expect(File(draft).existsSync(), isTrue);
      await tester.pageBack();
      await tester.pumpAndSettle();
      for (var i = 0; i < 10 && File(draft).existsSync(); i++) {
        await act(
          tester,
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(File(draft).existsSync(), isFalse);
    });
  });
}
