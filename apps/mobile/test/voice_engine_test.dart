import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:waybi_mobile/drive/voice_engine.dart';

class ControlledTts extends FlutterTts {
  final spoken = <String>[];
  final stops = <Completer<dynamic>>[];
  Completer<dynamic>? speaking;
  bool holdStop = false;

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
  Future<dynamic> speak(String text, {bool focus = false}) {
    expect(speaking, isNull, reason: 'Speech must never overlap');
    spoken.add(text);
    speaking = Completer<dynamic>();
    return speaking!.future;
  }

  void completeSpeech() {
    final pending = speaking;
    speaking = null;
    if (pending != null && !pending.isCompleted) pending.complete(1);
  }

  @override
  Future<dynamic> stop() {
    completeSpeech();
    if (!holdStop) return Future<dynamic>.value(1);
    final stop = Completer<dynamic>();
    stops.add(stop);
    return stop.future;
  }
}

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final entry in {
    'red light': '红灯摄像头',
    'red light + speed': '红灯及测速摄像头',
    'spot speed': '定点测速摄像头',
    'average speed': '区间测速摄像头',
    'bus lane': '专用车道摄像头',
  }.entries) {
    test('Chinese voice names ${entry.key} as a camera', () async {
      final tts = ControlledTts();
      final voice = VoiceEngine(tts: tts);
      await voice.setLanguage('zh-CN');
      final alert = voice.cameraAlert(
        distanceMeters: 150,
        cameraType: entry.key,
        roadName: 'Symonds Street',
      );
      await flush();
      expect(tts.spoken.single, '前方 150 米有${entry.value}，位于Symonds Street。');
      tts.completeSpeech();
      expect(await alert, true);
      await voice.dispose();
    });
  }
  test('camera waits for guidance completion and never overlaps', () async {
    final tts = ControlledTts();
    final voice = VoiceEngine(tts: tts);
    final turn = voice.guidance('Turn left');
    await flush();
    final camera = voice.cameraAlert(
      distanceMeters: 300,
      cameraType: 'Spot speed',
      roadName: 'Queen Street',
    );
    final next = voice.guidance('Continue straight');
    await flush();
    expect(tts.spoken, ['Turn left']);
    tts.completeSpeech();
    await turn;
    await flush();
    expect(tts.spoken.last, contains('Fixed speed camera'));
    tts.completeSpeech();
    expect(await camera, true);
    await flush();
    expect(tts.spoken.last, 'Continue straight');
    tts.completeSpeech();
    await next;
    await voice.dispose();
  });
  test('mute cancels current speech and all pending alerts', () async {
    final tts = ControlledTts();
    final voice = VoiceEngine(tts: tts);
    final turn = voice.guidance('Turn right');
    await flush();
    final camera = voice.cameraAlert(
      distanceMeters: 800,
      cameraType: 'Spot speed',
      roadName: 'Queen Street',
    );
    await voice.stop();
    await turn;
    await camera;
    expect(tts.spoken, ['Turn right']);
    final resumed = voice.guidance('Resumed');
    await flush();
    expect(tts.spoken.last, 'Resumed');
    tts.completeSpeech();
    await resumed;
    await voice.dispose();
  });
  test('queued camera is skipped after it has been passed', () async {
    final tts = ControlledTts();
    final voice = VoiceEngine(tts: tts);
    var relevant = true;
    final turn = voice.guidance('Turn left');
    await flush();
    final camera = voice.cameraAlert(
      distanceMeters: 300,
      cameraType: 'Spot speed',
      roadName: 'Queen Street',
      stillRelevant: () => relevant,
    );
    relevant = false;
    tts.completeSpeech();
    await turn;
    expect(await camera, false);
    expect(tts.spoken, ['Turn left']);
    await voice.dispose();
  });
  test('queued camera uses distance at playback and names dual or unknown cameras truthfully', () async {
    final tts = ControlledTts();
    final voice = VoiceEngine(tts: tts);
    var distance = 800;
    final turn = voice.guidance('Turn left');
    await flush();
    final alert = voice.cameraAlert(
      distanceMeters: 800,
      cameraType: 'red-light + speed',
      roadName: 'Green Lane East',
      currentDistanceMeters: () => distance,
    );
    distance = 476;
    tts.completeSpeech();
    await turn;
    await flush();
    expect(tts.spoken.last, contains('Red-light + speed camera in 476 metres'));
    tts.completeSpeech();
    expect(await alert, true);
    final unknown = voice.cameraAlert(
      distanceMeters: 300,
      cameraType: 'unconfirmed',
      roadName: '',
    );
    await flush();
    expect(tts.spoken.last, 'Safety camera in 300 metres.');
    tts.completeSpeech();
    await unknown;
    await voice.dispose();
  });
  test(
    'audio failure is observable and the next reminder can still play',
    () async {
      final tts = ControlledTts();
      final voice = VoiceEngine(tts: tts);
      final alert = voice.cameraAlert(
        distanceMeters: 300,
        cameraType: 'Spot speed',
        roadName: 'Queen Street',
      );
      final failed = expectLater(alert, throwsStateError);
      await flush();
      final speaking = tts.speaking!;
      tts.speaking = null;
      speaking.complete(0);
      await failed;
      final retry = voice.cameraAlert(
        distanceMeters: 250,
        cameraType: 'Spot speed',
        roadName: 'Queen Street',
      );
      await flush();
      expect(tts.spoken.last, contains('250 metres'));
      tts.completeSpeech();
      expect(await retry, true);
      await voice.dispose();
    },
  );
  test('resuming waits for the pending native stop to finish', () async {
    final tts = ControlledTts();
    final voice = VoiceEngine(tts: tts);
    final first = voice.guidance('Original');
    await flush();
    tts.holdStop = true;
    final stopped = voice.stop();
    final resumed = voice.guidance('Resumed');
    await flush();
    expect(tts.spoken, ['Original']);
    tts.stops.single.complete(1);
    await stopped;
    await first;
    await flush();
    expect(tts.spoken, ['Original', 'Resumed']);
    tts.completeSpeech();
    await resumed;
    tts.holdStop = false;
    await voice.dispose();
  });
  test('lane reminder waits for the turn and discards a restriction that has ended', () async {
    final tts = ControlledTts();
    final queued = VoiceEngine(tts: tts);
    final turn = queued.guidance('Turn left onto Waterloo Quadrant');
    await flush();
    var active = true;
    final lane = queued.roadAlert(
      () => 'Bus lane. Active 24 hours, every day.',
      stillRelevant: () => active,
    );
    await flush();
    expect(tts.spoken, hasLength(1));
    active = false;
    tts.completeSpeech();
    await turn;
    expect(await lane, false);
    expect(tts.spoken, hasLength(1));
    final retry = queued.roadAlert(
      () => 'Bus lane. Monday to Friday, 07:00 to 10:00.',
    );
    await flush();
    expect(tts.spoken.last, contains('Monday to Friday'));
    tts.completeSpeech();
    expect(await retry, true);
    await queued.dispose();
  });
}
