import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_mobile/drive/custom_voice.dart';
import 'package:waybi_mobile/drive/voice_take_session.dart';
import 'package:waybi_mobile/widgets/custom_voice_guided_page.dart';
import 'package:waybi_mobile/widgets/custom_voice_page.dart';

import 'custom_voice_test.dart' show FakeClipPlayer, FakeRecorder, tallView;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late CustomVoiceController voice;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = Directory.systemTemp.createTempSync('waybi-voice-ux-');
    voice = CustomVoiceController(rootDirectory: () async => root);
    await voice.load();
  });
  tearDown(() {
    voice.dispose();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> act(WidgetTester tester, Future<void> Function() body) async {
    await tester.runAsync(() async {
      await body();
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });
    await tester.pump();
  }

  Future<void> recordAll(
    WidgetTester tester,
    String language, {
    Set<String> except = const {},
  }) => tester.runAsync(() async {
    for (final phrase in voicePhrasesFor(language)) {
      if (except.contains(phrase.id)) continue;
      final draft = await voice.draftPath(language);
      await File(draft).writeAsBytes(List.filled(2048, 1));
      await voice.saveClip(language, phrase.id, draft);
    }
  });

  Finder key(String value) => find.byKey(ValueKey(value));

  Widget app({String language = 'en', FakeRecorder? recorder}) => MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CustomVoicePage(
              controller: voice,
              language: language,
              recorder: () => recorder ?? FakeRecorder(),
              player: () => FakeClipPlayer([]),
            ),
          ),
        ),
        child: const Text('open'),
      ),
    ),
  );

  Future<void> open(WidgetTester tester, Widget widget) async {
    // Tall enough for every phrase row to be built.
    tester.view.physicalSize = const Size(900, 9000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(widget);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('progress per group, the road-name option and a complete pack', (
    tester,
  ) async {
    final total = voicePhrasesFor('en').length;
    await open(tester, app());
    expect(
      find.text(
        '0 of $total recorded — unrecorded phrases use the standard voice',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('custom-voice-record-missing')),
      findsNothing,
      reason: 'Free users cannot record',
    );
    final omit = tester.widget<SwitchListTile>(key('custom-voice-omit-roads'));
    expect(omit.onChanged, isNull);

    voice.setPlus(true);
    await tester.pump();
    await act(tester, () async => tester.tap(key('custom-voice-omit-roads')));
    expect(voice.omitRoadNames, isTrue);
    expect(find.text('Record missing phrases ($total)'), findsOneWidget);
    expect(
      tester.widget<Text>(key('custom-voice-group-connector')).data,
      '0 of 3',
    );

    await recordAll(tester, 'en', except: {'conn_on'});
    await tester.pump();
    expect(
      find.text(
        '${total - 1} of $total recorded — unrecorded phrases use the standard voice',
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(key('custom-voice-group-connector')).data,
      '2 of 3',
    );
    expect(
      tester.widget<Text>(key('custom-voice-group-camera')).data,
      '6 of 6',
    );

    await recordAll(tester, 'en');
    await tester.pump();
    expect(
      find.text(
        'All $total phrases recorded — every fixed word is in your voice',
      ),
      findsOneWidget,
    );
    expect(key('custom-voice-record-missing'), findsNothing);

    await act(tester, () async => tester.tap(find.text('中文')));
    expect(
      find.textContaining('已录 0 / ${voicePhrasesFor('zh').length} 条'),
      findsNothing,
      reason: 'Page text follows the app language',
    );
    expect(
      find.textContaining('0 of ${voicePhrasesFor('zh').length} recorded'),
      findsOneWidget,
    );
    expect(find.text('“位于”'), findsOneWidget);
    expect(
      find.text('“onto”'),
      findsNothing,
      reason: 'English-only words are not offered in Chinese',
    );
  });

  testWidgets('record missing phrases steps through only what is missing', (
    tester,
  ) async {
    voice.setPlus(true);
    await recordAll(tester, 'en', except: {'conn_onto', 'well_done', 'merge'});
    await tester.runAsync(() async => voice.reportBroken('en', 'turn_left'));
    final recorder = FakeRecorder();
    await open(tester, app(recorder: recorder));
    expect(
      find.text('Record missing phrases (4)'),
      findsOneWidget,
      reason: 'An unplayable recording counts as missing',
    );
    await act(
      tester,
      () async => tester.tap(key('custom-voice-record-missing')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CustomVoiceGuidedPage), findsOneWidget);
    expect(find.text('Phrase 1 of 4 · Turns'), findsOneWidget);
    expect(find.text('“Turn left”'), findsOneWidget);

    // Record, listen, then keep and move on.
    await act(
      tester,
      () async => tester.tap(key('custom-voice-guided-record')),
    );
    expect(find.text('Recording… tap stop when done'), findsOneWidget);
    await act(
      tester,
      () async => tester.tap(key('custom-voice-guided-record')),
    );
    expect(
      find.text('Listen back, then keep it or record again.'),
      findsOneWidget,
    );
    await act(tester, () async => tester.tap(key('custom-voice-guided-play')));
    await act(tester, () async => tester.tap(key('custom-voice-guided-keep')));
    expect(voice.isBroken('en', 'turn_left'), isFalse);
    expect(find.text('Phrase 2 of 4 · Turns'), findsOneWidget);
    expect(find.text('“Merge ahead”'), findsOneWidget);

    // A take can be redone before keeping it.
    await act(
      tester,
      () async => tester.tap(key('custom-voice-guided-record')),
    );
    await act(
      tester,
      () async => tester.tap(key('custom-voice-guided-record')),
    );
    await act(
      tester,
      () async => tester.tap(key('custom-voice-guided-retake')),
    );
    expect(find.text('Recording… tap stop when done'), findsOneWidget);
    await act(
      tester,
      () async => tester.tap(key('custom-voice-guided-record')),
    );
    recorder.bytes = 10;
    await act(
      tester,
      () async => tester.tap(key('custom-voice-guided-retake')),
    );
    await act(
      tester,
      () async => tester.tap(key('custom-voice-guided-record')),
    );
    await act(tester, () async => tester.tap(key('custom-voice-guided-keep')));
    expect(
      find.text('That take was too short to use. Please record again.'),
      findsOneWidget,
    );
    expect(
      find.text('Phrase 2 of 4 · Turns'),
      findsOneWidget,
      reason: 'A failed take stays put',
    );
    recorder.bytes = 4096;

    await act(tester, () async => tester.tap(key('custom-voice-guided-skip')));
    expect(find.text('Phrase 3 of 4 · Connecting words'), findsOneWidget);
    expect(find.text('As in: Turn left onto Queen Street'), findsOneWidget);
    await act(
      tester,
      () async => tester.tap(key('custom-voice-guided-record')),
    );
    await act(
      tester,
      () async => tester.tap(key('custom-voice-guided-record')),
    );
    await act(tester, () async => tester.tap(key('custom-voice-guided-keep')));
    await act(tester, () async => tester.tap(key('custom-voice-guided-skip')));

    expect(key('custom-voice-guided-done'), findsOneWidget);
    expect(
      find.text(
        'You recorded 2 of 4 phrases. Skipped phrases keep using the standard voice.',
      ),
      findsOneWidget,
    );
    await act(tester, () async => tester.tap(key('custom-voice-guided-close')));
    await tester.pumpAndSettle();
    expect(find.text('Record missing phrases (2)'), findsOneWidget);
    expect(voice.recorded('en'), containsAll(['turn_left', 'conn_onto']));
    expect(voice.recorded('en'), isNot(contains('merge')));
  });

  testWidgets('the guided page in Chinese, and losing Plus mid-take', (
    tester,
  ) async {
    voice.setPlus(true);
    tallView(tester);
    final phrases = [
      customVoicePhrase('conn_located')!,
      customVoicePhrase('time_hour')!,
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: CustomVoiceGuidedPage(
          controller: voice,
          language: 'zh',
          pack: 'zh',
          phrases: phrases,
          recorder: FakeRecorder.new,
          player: () => FakeClipPlayer([]),
        ),
      ),
    );
    expect(find.text('第 1 / 2 条 · 连接词'), findsOneWidget);
    expect(find.text('用在：300 米后有定点测速摄像头，位于 Queen Street。'), findsOneWidget);
    await act(
      tester,
      () async => tester.tap(key('custom-voice-guided-record')),
    );
    expect(find.text('录音中…读完点停止'), findsOneWidget);
    voice.setPlus(false);
    await act(tester, () async {});
    expect(find.text('录音中…读完点停止'), findsNothing);
    expect(
      tester.widget<FilledButton>(key('custom-voice-guided-record')).onPressed,
      isNull,
    );
    await act(tester, () async => tester.tap(key('custom-voice-guided-skip')));
    expect(find.text('用在：周一至周五 7 点 30 分至 9 点 30 分'), findsOneWidget);
  });

  test('examples show how glue words are used', () {
    expect(
      voicePhraseExample('dist_in', 'en'),
      'In 650 m, Turn left onto Queen Street',
    );
    expect(
      voicePhraseExample('dist_kilometres', 'zh'),
      '1.7 公里后，左转，驶向 Queen Street',
    );
    expect(
      voicePhraseExample('conn_on', 'en'),
      'In 300 metres, speed camera on Queen Street.',
    );
    expect(
      voicePhraseExample('time_to', 'en'),
      'Monday to Friday, 07:30 to 09:30',
    );
    expect(voicePhraseExample('turn_left', 'en'), isNull);
  });

  test('a take session reports problems and cleans up', () async {
    final issues = <VoiceTakeIssue>[];
    final recorder = FakeRecorder()..permission = false;
    final session = VoiceTakeSession(
      voice: voice,
      language: 'en',
      recorder: () => recorder,
      player: () => FakeClipPlayer([])..failing.add('.m4a'),
      maxRecording: const Duration(milliseconds: 20),
      onIssue: issues.add,
    );
    await session.record('merge');
    expect(issues, isEmpty, reason: 'Not Plus: nothing happens');
    voice.setPlus(true);
    await session.record('merge');
    expect(issues, [VoiceTakeIssue.microphoneDenied]);
    recorder.permission = true;
    await session.record('merge');
    expect(session.busy, isTrue);
    // The auto-stop timer fires after 20 ms, then the take is written to
    // disk; poll rather than assume how long that takes on a busy machine.
    await _until(() => !session.busy);
    expect(session.busy, isFalse, reason: 'Recording stops on its own');
    expect(session.draft?.id, 'merge');
    await session.play('merge', session.draft!.path, draft: true);
    expect(issues.last, VoiceTakeIssue.unplayable);
    expect(
      voice.isBroken('en', 'merge'),
      isFalse,
      reason: 'A draft is never flagged',
    );
    expect(await session.keepDraft(), isTrue);
    expect(await session.keepDraft(), isFalse);
    await session.play('merge', null);
    await session.record('arrived');
    final draftDir = Directory('${root.path}/custom_voice/drafts');
    session.dispose();
    await _until(() => draftDir.listSync().whereType<File>().isEmpty);
    expect(
      draftDir.listSync().whereType<File>(),
      isEmpty,
      reason: 'Disposing cancels the recording in progress',
    );
    expect(voiceTakeIssueText(VoiceTakeIssue.couldNotStart, true), '无法开始录音。');
    expect(voicePhraseGroupTitle(VoicePhraseGroup.trip, true), '行程消息');
  });
}

/// Polls [done] for up to five seconds of real time.
Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 250 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
