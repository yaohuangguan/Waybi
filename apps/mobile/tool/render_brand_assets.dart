// Export the actual splash painter; keep app and PWA icons in sync with it.
// From apps/mobile: flutter test tool/render_brand_assets.dart
// Then: dart run flutter_launcher_icons
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_lens_mobile/theme/kiwi_lens_theme.dart';
import 'package:kiwi_lens_mobile/widgets/kiwi_mascot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('export splash mascot as opaque launcher and PWA icons', () async {
    const pixels = 1024;
    const edge = 52.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(KiwiLensColors.lightBackground, BlendMode.src);
    canvas.translate(edge, edge);
    KiwiMascotPainter().paint(
      canvas,
      const Size(pixels - edge * 2, pixels - edge * 2),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(pixels, pixels);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Could not encode the Kiwi icon');
    final png = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    File('assets/icon/app_icon.png').writeAsBytesSync(png);
    File('../web/public/brand/kiwi-lens-icon.png').writeAsBytesSync(png);
    image.dispose();
    picture.dispose();
  });
}
