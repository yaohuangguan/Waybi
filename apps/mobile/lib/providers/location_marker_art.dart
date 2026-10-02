import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/map_provider.dart';
import '../theme/kiwi_lens_theme.dart';
import '../widgets/kiwi_mascot.dart';

/// A small north-facing bird silhouette for the location puck. This is
/// separate from the Kiwi Lens brand mark; map-location art stays independent.
class LocationMarkerArt {
  static final Map<LocationMarkerStyle, Future<Uint8List>> _cache = {};

  static Future<Uint8List> png(LocationMarkerStyle style) =>
      _cache.putIfAbsent(style, () => _draw(style));

  static Future<Uint8List>? _glow;
  static Future<Uint8List>? _mascot;

  static Future<Uint8List> practicePng(LocationMarkerStyle style) =>
      style == LocationMarkerStyle.kiwi
      ? (_mascot ??= _drawMascot())
      : png(style);

  static Future<Uint8List> _drawMascot() async {
    final recorder = ui.PictureRecorder();
    KiwiMascotPainter().paint(Canvas(recorder), const Size(96, 96));
    return _export(recorder, 96);
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
            KiwiLensColors.sky.withValues(alpha: .35),
            KiwiLensColors.sky.withValues(alpha: .1),
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

  static Future<Uint8List> _draw(LocationMarkerStyle style) async {
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
