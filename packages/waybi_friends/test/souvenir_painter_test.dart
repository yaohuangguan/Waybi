import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_friends/src/souvenir_art.dart';
import 'package:waybi_friends/src/souvenirs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('every collectible can be regenerated as distinct visible artwork without a network or icon font', () async {
    final signatures = <String>{};
    for (final kind in SouvenirKind.values) {
      final recorder = ui.PictureRecorder();
      final painter = SouvenirPainter(kind);
      painter.paint(ui.Canvas(recorder), const ui.Size(128, 128));
      final picture = recorder.endRecording();
      final image = await picture.toImage(128, 128);
      final pixels = await image.toByteData();
      final bytes = pixels!.buffer.asUint8List();
      expect(
        [for (var i = 3; i < bytes.length; i += 4) bytes[i]]
            .any((alpha) => alpha > 0),
        isTrue,
        reason: kind.name,
      );
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      signatures.add(png!.buffer.asUint8List().toString());
      expect(painter.shouldRepaint(SouvenirPainter(kind)), isFalse);
      image.dispose();
      picture.dispose();
    }
    expect(
      signatures.length,
      SouvenirKind.values.length,
      reason: 'Collectibles must not silently share fallback artwork',
    );
    expect(
      const SouvenirPainter(SouvenirKind.map)
          .shouldRepaint(const SouvenirPainter(SouvenirKind.letter)),
      isTrue,
    );
  });
}
