import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:kiwi_lens_mobile/drive/voice_engine.dart';

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
    await camera;
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
    await camera;
    expect(tts.spoken, ['Turn left']);
    await voice.dispose();
  });
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
}
