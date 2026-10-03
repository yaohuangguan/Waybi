import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/map_layer_settings.dart';
import '../theme/waybi_theme.dart';

class CameraMarkerArt {
  static final Map<String, Future<Uint8List>> _cache = {};

  static Future<Uint8List> png(CameraKind kind, {required bool onRoute}) {
    final key = '${kind.name}:$onRoute';
    return _cache.putIfAbsent(key, () => _draw(kind, onRoute: onRoute));
  }

  static Color accent(CameraKind kind) => switch (kind) {
    CameraKind.spotSpeed => const Color(0xFF2F80ED),
    CameraKind.averageSpeed => const Color(0xFF11A6B7),
    CameraKind.redLight => const Color(0xFFE04F46),
    CameraKind.dualRedLightSpeed => const Color(0xFFF59E0B),
    CameraKind.busLane => const Color(0xFF5D8C3D),
    CameraKind.other => const Color(0xFF7C5CC4),
  };

  static String badge(CameraKind kind) => switch (kind) {
    CameraKind.spotSpeed => 'S',
    CameraKind.averageSpeed => 'AVG',
    CameraKind.redLight => 'R',
    CameraKind.dualRedLightSpeed => 'R+S',
    CameraKind.busLane => 'BUS',
    CameraKind.other => 'CAM',
  };

  static Future<Uint8List> _draw(
    CameraKind kind, {
    required bool onRoute,
  }) async {
    const width = 92.0;
    const height = 104.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..isAntiAlias = true;
    final accentColor = accent(kind);

    final shadow = Paint()
      ..isAntiAlias = true
      ..color = Colors.black.withValues(alpha: .22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(12, 8, 68, 72),
        const Radius.circular(20),
      ),
      shadow,
    );

    final pointer = Path()
      ..moveTo(36, 76)
      ..lineTo(46, 98)
      ..lineTo(56, 76)
      ..close();
    paint
      ..style = PaintingStyle.fill
      ..color = Colors.white;
    canvas.drawPath(pointer, paint);

    final bodyRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(10, 6, 72, 74),
      const Radius.circular(22),
    );
    paint.color = Colors.white;
    canvas.drawRRect(bodyRect, paint);

    if (onRoute) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = WaybiColors.sky;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(7.5, 3.5, 77, 79),
          const Radius.circular(24),
        ),
        paint,
      );
      paint.style = PaintingStyle.fill;
    }

    paint.color = const Color(0xFF17354B);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(14, 10, 64, 66),
        const Radius.circular(18),
      ),
      paint,
    );

    paint.color = accentColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(20, 16, 52, 5),
        const Radius.circular(2.5),
      ),
      paint,
    );

    // Camera body.
    paint.color = Colors.white;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(26, 29, 40, 25),
        const Radius.circular(7),
      ),
      paint,
    );
    final top = Path()
      ..moveTo(32, 29)
      ..lineTo(37, 23)
      ..lineTo(50, 23)
      ..lineTo(55, 29)
      ..close();
    canvas.drawPath(top, paint);

    paint.color = const Color(0xFF17354B);
    canvas.drawCircle(const Offset(46, 41.5), 8.5, paint);
    paint.color = accentColor;
    canvas.drawCircle(const Offset(46, 41.5), 5, paint);
    paint.color = Colors.white.withValues(alpha: .92);
    canvas.drawCircle(const Offset(43.5, 39), 1.8, paint);

    final badgeText = badge(kind);
    paint.color = accentColor;
    final badgeWidth = switch (badgeText.length) {
      <= 1 => 22.0,
      2 => 28.0,
      3 => 34.0,
      _ => 40.0,
    };
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: const Offset(46, 65),
          width: badgeWidth,
          height: 16,
        ),
        const Radius.circular(8),
      ),
      paint,
    );

    final paragraph =
        (ui.ParagraphBuilder(
                ui.ParagraphStyle(
                  textAlign: TextAlign.center,
                  fontSize: badgeText.length > 3 ? 7.5 : 8.5,
                  fontWeight: FontWeight.w800,
                ),
              )
              ..pushStyle(ui.TextStyle(color: Colors.white))
              ..addText(badgeText))
            .build()
          ..layout(ui.ParagraphConstraints(width: badgeWidth));
    canvas.drawParagraph(paragraph, Offset(46 - badgeWidth / 2, 60.5));

    paint.color = const Color(0xFF17354B);
    canvas.drawCircle(const Offset(46, 84), 4.5, paint);

    final image = await recorder.endRecording().toImage(
      width.toInt(),
      height.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }
}
