import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/road_event.dart';

/// The same recognisable event symbols are used by both map providers.
abstract final class RoadEventMarkerArt {
  static IconData icon(RoadEventType type) => switch (type) {
    RoadEventType.incident => Icons.car_crash_rounded,
    RoadEventType.roadworks => Icons.construction_rounded,
    RoadEventType.roadClosure => Icons.block_rounded,
    RoadEventType.congestion => Icons.traffic_rounded,
    RoadEventType.flooding => Icons.water_rounded,
    RoadEventType.slip => Icons.landslide_rounded,
    RoadEventType.laneMerge => Icons.merge_rounded,
    RoadEventType.sharpCurve => Icons.turn_sharp_right_rounded,
    _ => Icons.warning_rounded,
  };
  static Color color(RoadEventType type) => switch (type) {
    RoadEventType.incident ||
    RoadEventType.roadClosure => const Color(0xffc9342e),
    RoadEventType.flooding => const Color(0xff147ab8),
    RoadEventType.slip => const Color(0xff875339),
    _ => const Color(0xffa75b08),
  };
  static final _cache = <RoadEventType, Future<Uint8List>>{};
  static Future<Uint8List> png(RoadEventType type) =>
      _cache.putIfAbsent(type, () => _render(type));
  static Future<Uint8List> _render(RoadEventType type) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(7, 5, 82, 82),
          const Radius.circular(23),
        ),
      );
    canvas.drawShadow(outline, Colors.black, 4, true);
    canvas.drawPath(outline, Paint()..color = Colors.white);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(13, 11, 70, 70),
        const Radius.circular(18),
      ),
      Paint()..color = color(type),
    );
    final glyph = icon(type);
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(glyph.codePoint),
        style: TextStyle(
          fontFamily: glyph.fontFamily,
          package: glyph.fontPackage,
          fontSize: 48,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset((96 - painter.width) / 2, (92 - painter.height) / 2),
    );
    painter.dispose();
    final picture = recorder.endRecording();
    final image = await picture.toImage(96, 96);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}
