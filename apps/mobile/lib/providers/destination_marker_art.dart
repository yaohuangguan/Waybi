import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A compact Formula-1-inspired chequered finish flag used for route endpoints.
class DestinationMarkerArt {
  static Future<Uint8List>? _cache;

  static Future<Uint8List> png() => _cache ??= _draw();

  static Future<Uint8List> _draw() async {
    const width = 96.0;
    const height = 112.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..isAntiAlias = true;

    // White halo keeps the flag readable on satellite and dark maps.
    paint
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(27, 14), const Offset(27, 98), paint);

    paint
      ..color = const Color(0xFF202124)
      ..strokeWidth = 5;
    canvas.drawLine(const Offset(27, 14), const Offset(27, 98), paint);

    const flagLeft = 30.0;
    const flagTop = 17.0;
    const cell = 12.0;
    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 4; col++) {
        paint
          ..style = PaintingStyle.fill
          ..color = (row + col).isEven ? Colors.white : const Color(0xFF202124);
        canvas.drawRect(
          Rect.fromLTWH(
            flagLeft + col * cell,
            flagTop + row * cell,
            cell,
            cell,
          ),
          paint,
        );
      }
    }

    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white;
    canvas.drawRect(
      const Rect.fromLTWH(
        flagLeft - 2,
        flagTop - 2,
        cell * 4 + 4,
        cell * 4 + 4,
      ),
      paint,
    );
    paint
      ..strokeWidth = 1.5
      ..color = const Color(0xFF202124);
    canvas.drawRect(
      const Rect.fromLTWH(flagLeft, flagTop, cell * 4, cell * 4),
      paint,
    );

    paint
      ..style = PaintingStyle.fill
      ..color = Colors.white;
    canvas.drawCircle(const Offset(27, 99), 8, paint);
    paint.color = const Color(0xFF202124);
    canvas.drawCircle(const Offset(27, 99), 5, paint);

    final image = await recorder.endRecording().toImage(
      width.toInt(),
      height.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }
}
