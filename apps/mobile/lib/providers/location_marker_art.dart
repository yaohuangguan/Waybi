import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/map_layer_settings.dart';
import '../domain/map_provider.dart';
import '../theme/waybi_theme.dart';
import '../widgets/waybi_bird.dart';

/// A small north-facing bird silhouette for the location puck. This is
/// separate from the Waybi brand mark; map-location art stays independent.
class LocationMarkerArt {
  static final Map<LocationMarkerStyle, Future<Uint8List>> _cache = {};

  static Future<Uint8List> png(LocationMarkerStyle style) =>
      _cache.putIfAbsent(style, () => _draw(style));

  static Future<Uint8List>? _glow;
  static Future<Uint8List>? _mascot;
  static final Map<CameraKind, Future<Uint8List>> _cameras = {};
  static Future<Uint8List>? _finishFlag;

  static Future<Uint8List> practicePng(LocationMarkerStyle style) =>
      style == LocationMarkerStyle.kiwi
      ? (_mascot ??= _drawMascot())
      : png(style);

  static Future<Uint8List> _drawMascot() async {
    final recorder = ui.PictureRecorder();
    WaybiBirdPainter().paint(Canvas(recorder), const Size(96, 96));
    return _export(recorder, 96);
  }

  static Future<Uint8List> cameraPng(CameraKind kind) =>
      _cameras.putIfAbsent(kind, () => _drawCamera(kind));

  static Future<Uint8List> _drawCamera(CameraKind kind) async {
    const size = 96.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..isAntiAlias = true;
    final background = switch (kind) {
      CameraKind.spotSpeed => const Color(0xFFD93025),
      CameraKind.averageSpeed => const Color(0xFFF29900),
      CameraKind.redLight => const Color(0xFFB3261E),
      CameraKind.dualRedLightSpeed => const Color(0xFF7E57C2),
      CameraKind.busLane => const Color(0xFF1976D2),
      CameraKind.other => const Color(0xFF687076),
    };
    paint.color = background;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(8, 8, 80, 80),
        const Radius.circular(24),
      ),
      paint,
    );

    paint.color = Colors.white;
    if (kind == CameraKind.busLane) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(24, 25, 48, 44),
          const Radius.circular(7),
        ),
        paint,
      );
      paint.color = background;
      canvas.drawRect(const Rect.fromLTWH(31, 32, 34, 15), paint);
      canvas.drawCircle(const Offset(34, 68), 5, paint);
      canvas.drawCircle(const Offset(62, 68), 5, paint);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(20, 32, 56, 37),
          const Radius.circular(8),
        ),
        paint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(31, 25, 23, 12),
          const Radius.circular(5),
        ),
        paint,
      );
      paint.color = background;
      if (kind == CameraKind.averageSpeed) {
        canvas.drawCircle(const Offset(40, 51), 8, paint);
        canvas.drawCircle(const Offset(58, 51), 8, paint);
      } else {
        canvas.drawCircle(const Offset(48, 51), 12, paint);
        paint.color = Colors.white;
        canvas.drawCircle(const Offset(48, 51), 6, paint);
      }
    }

    if (kind == CameraKind.redLight || kind == CameraKind.dualRedLightSpeed) {
      paint.color = const Color(0xFF202124);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(66, 18, 15, 31),
          const Radius.circular(5),
        ),
        paint,
      );
      for (final entry in const [
        (Offset(73.5, 25), Color(0xFFFF4D4D)),
        (Offset(73.5, 33.5), Color(0xFFFFC107)),
        (Offset(73.5, 42), Color(0xFF3DDC84)),
      ]) {
        paint.color = entry.$2;
        canvas.drawCircle(entry.$1, 3, paint);
      }
    }
    return _export(recorder, size.toInt());
  }

  static Future<Uint8List> finishFlagPng() => _finishFlag ??= _drawFinishFlag();

  static Future<Uint8List> _drawFinishFlag() async {
    const size = 96.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..isAntiAlias = true;

    paint.color = const Color(0xFF202124);
    paint.strokeWidth = 7;
    paint.strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(24, 14), const Offset(24, 83), paint);
    canvas.drawCircle(const Offset(24, 15), 5, paint);

    const left = 27.0;
    const top = 18.0;
    const cell = 12.0;
    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 4; col++) {
        paint.color = (row + col).isEven ? Colors.white : Colors.black;
        canvas.drawRect(
          Rect.fromLTWH(left + col * cell, top + row * cell, cell, cell),
          paint,
        );
      }
    }
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFF202124);
    canvas.drawRect(const Rect.fromLTWH(left, top, cell * 4, cell * 4), paint);
    return _export(recorder, size.toInt());
  }

  /// Rasterize the soft light once. Native GPU transforms it with the puck;
  /// Flutter no longer repaints a blurred 240px path on every animation frame.
  static Future<Uint8List> glowPng() => _glow ??= _drawGlow();
  static Future<Uint8List> _drawGlow() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(2);
    const center = Offset(120, 120);
    final path = Path()
      ..moveTo(120, 120)
      ..cubicTo(86, 89, 42, 37, 56, 24)
      ..quadraticBezierTo(120, -5, 184, 24)
      ..cubicTo(198, 37, 154, 89, 120, 120)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          radius: .9,
          colors: [
            WaybiColors.sky.withValues(alpha: .35),
            WaybiColors.sky.withValues(alpha: .1),
            Colors.transparent,
          ],
          stops: const [0, .5, 1],
        ).createShader(Rect.fromCircle(center: center, radius: 118))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    return _export(recorder, 480);
  }

  static Future<Uint8List> _export(
    ui.PictureRecorder recorder,
    int size,
  ) async {
    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  static Future<Uint8List> _drawCompanion(String name) async {
    final bytes = await rootBundle.load('assets/markers/$name.png');
    final codec = await ui.instantiateImageCodec(
      bytes.buffer.asUint8List(),
      targetWidth: 192,
      targetHeight: 192,
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // Keep the source character transparent for settings and the website.
    // Only the map puck gets a round backdrop, so it stays clear over roads.
    canvas.drawCircle(const Offset(48, 48), 45, Paint()..color = Colors.white);
    canvas.drawCircle(
      const Offset(48, 48),
      42,
      Paint()
        ..color = name == 'clover'
            ? const Color(0xFFFFE0E5)
            : const Color(0xFFDDF2FF),
    );
    canvas.drawImageRect(
      frame.image,
      Rect.fromLTWH(
        0,
        0,
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      ),
      const Rect.fromLTWH(8, 8, 80, 80),
      Paint()..filterQuality = FilterQuality.high,
    );
    frame.image.dispose();
    return _export(recorder, 96);
  }

  static Future<Uint8List> _draw(LocationMarkerStyle style) async {
    if (style == LocationMarkerStyle.cat) return _drawCompanion('clover');
    if (style == LocationMarkerStyle.dog) return _drawCompanion('sett');
    const size = 96.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..isAntiAlias = true;
    paint.color = Colors.white;
    canvas.drawCircle(const Offset(48, 48), 43, paint);
    paint.color = const Color(0xFF486B29);
    canvas.drawCircle(const Offset(48, 48), 38, paint);
    paint.color = Colors.white;

    switch (style) {
      case LocationMarkerStyle.kiwi:
        final body = Path()
          ..moveTo(47, 26)
          ..cubicTo(25, 29, 21, 58, 39, 68)
          ..cubicTo(54, 78, 73, 62, 69, 46)
          ..cubicTo(65, 34, 57, 27, 47, 26)
          ..close();
        canvas.drawPath(body, paint);
        final beak = Path()
          ..moveTo(48, 30)
          ..lineTo(48, 5)
          ..lineTo(54, 30)
          ..close();
        canvas.drawPath(beak, paint);
        paint.color = const Color(0xFF23351D);
        canvas.drawCircle(const Offset(58, 38), 2.8, paint);
        paint.strokeWidth = 4;
        canvas.drawLine(const Offset(37, 68), const Offset(33, 76), paint);
        canvas.drawLine(const Offset(56, 68), const Offset(60, 76), paint);
      case LocationMarkerStyle.cat:
      case LocationMarkerStyle.dog:
        throw StateError('Companion marker should load its bundled artwork');
      case LocationMarkerStyle.arrow:
        final arrow = Path()
          ..moveTo(48, 14)
          ..lineTo(67, 71)
          ..lineTo(48, 60)
          ..lineTo(29, 71)
          ..close();
        canvas.drawPath(arrow, paint);
      case LocationMarkerStyle.car:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(29, 22, 38, 52),
            const Radius.circular(10),
          ),
          paint,
        );
        paint.color = const Color(0xFF23351D);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(34, 32, 28, 17),
            const Radius.circular(4),
          ),
          paint,
        );
      case LocationMarkerStyle.classic:
        canvas.drawCircle(const Offset(48, 48), 16, paint);
    }
    final image = await recorder.endRecording().toImage(
      size.toInt(),
      size.toInt(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }
}
