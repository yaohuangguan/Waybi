import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_friends/src/souvenir_art.dart';
import 'package:waybi_friends/src/souvenirs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('every collectible illustration is a non-empty local PNG', () async {
    final directory = Directory(
      Platform.environment['SOUVENIR_ART_DIRECTORY'] ?? 'assets/souvenirs',
    );
    if (Platform.environment['SOUVENIR_ART_DIRECTORY'] != null) {
      await directory.create(recursive: true);
      for (final kind in SouvenirKind.values) {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        SouvenirPainter(kind).paint(canvas, const ui.Size(384, 384));
        final picture = recorder.endRecording();
        final image = await picture.toImage(384, 384);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('${directory.path}/${kind.name}.png')
            .writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
      }
      final preview = Platform.environment['SOUVENIR_ART_PREVIEW'];
      if (preview != null) {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawColor(const ui.Color(0xFFF8F4E8), ui.BlendMode.src);
        for (var i = 0; i < SouvenirKind.values.length; i++) {
          canvas.save();
          canvas.translate((i % 5) * 150 + 10, (i ~/ 5) * 150 + 10);
          SouvenirPainter(SouvenirKind.values[i])
              .paint(canvas, const ui.Size(130, 130));
          canvas.restore();
        }
        final picture = recorder.endRecording();
        final image = await picture.toImage(
          750,
          ((SouvenirKind.values.length + 4) ~/ 5) * 150,
        );
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(preview).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
      }
    }
    final signatures = <String>{};
    for (final kind in SouvenirKind.values) {
      final bytes = await File('${directory.path}/${kind.name}.png')
          .readAsBytes();
      expect(bytes.length, greaterThan(1000));
      signatures.add(bytes.toString());
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 384);
      expect(frame.image.height, 384);
      frame.image.dispose();
      codec.dispose();
    }
    expect(signatures, hasLength(SouvenirKind.values.length));
  });
}
