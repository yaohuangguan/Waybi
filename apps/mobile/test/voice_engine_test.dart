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

  test(
    'camera alert interrupts guidance and keeps the latest pending turn',
    () async {
      final tts = ControlledTts();
      final voice = VoiceEngine(tts: tts);
      await voice.initialize();
      final first = voice.guidance('Continue straight');
      await flush();
      final camera = voice.cameraAlert(
        distanceMeters: 300,
        cameraType: 'Spot speed',
        roadName: 'Queen Street',
      );
      await flush();
      expect(tts.spoken.length, 2);
      expect(tts.spoken.last, contains('Fixed speed camera'));
      await voice.guidance('Earlier turn');
      await voice.guidance('Turn left');
      await flush();
      expect(
        tts.spoken.length,
        2,
        reason: 'Turn guidance must not interrupt the camera',
      );
      tts.completeSpeech();
      await camera;
      await flush();
      expect(tts.spoken.last, 'Turn left');
      expect(tts.spoken, isNot(contains('Earlier turn')));
      tts.completeSpeech();
      await first;
      await voice.dispose();
    },
  );

  test(
    'mute cancels pending turns and prevents a camera starting after stop',
    () async {
      final tts = ControlledTts();
      final voice = VoiceEngine(tts: tts);
      await voice.initialize();
      tts.holdStop = true;
      final camera = voice.cameraAlert(
        distanceMeters: 800,
        cameraType: 'Spot speed',
        roadName: 'Queen Street',
      );
      await flush();
      await voice.guidance('Turn right');
      final mute = voice.stop();
      await flush();
      for (final stop in tts.stops) {
        stop.complete(1);
      }
      await camera;
      await mute;
      await flush();
      expect(tts.spoken, isEmpty);
      tts.holdStop = false;
      await voice.dispose();
    },
  );
}
