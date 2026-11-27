import 'package:flutter/material.dart';

import '../theme/waybi_theme.dart';

/// The Waybi mascot. Decorative by default (screen readers skip it); pass
/// a localized [semanticLabel] where the bird carries meaning.
class WaybiBird extends StatelessWidget {
  const WaybiBird({super.key, this.size = 64, this.semanticLabel});
  final double size;
  final String? semanticLabel;
  @override
  Widget build(BuildContext context) {
    final bird = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: WaybiBirdPainter()),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: bird);
    return Semantics(label: semanticLabel, image: true, child: bird);
  }
}

/// The same painter is used for the splash mascot and exported launcher assets.
class WaybiBirdPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 100);
    final paint = Paint()..isAntiAlias = true;
    paint.color = WaybiColors.sky;
    canvas.drawCircle(const Offset(50, 50), 47, paint);
    paint.color = WaybiColors.deepOcean;
    canvas.drawOval(const Rect.fromLTWH(17, 34, 55, 43), paint);
    canvas.drawCircle(const Offset(67, 36), 16, paint);
    paint.color = const Color(0xFFE4A850);
    canvas.drawPath(
      Path()
        ..moveTo(77, 35)
        ..lineTo(99, 44)
        ..lineTo(77, 42)
        ..close(),
      paint,
    );
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 4;
    paint.strokeCap = StrokeCap.round;
    for (final x in [35.0, 53.0]) {
      canvas.drawLine(Offset(x, 74), Offset(x - 3, 86), paint);
      canvas.drawLine(Offset(x - 3, 86), Offset(x + 5, 86), paint);
    }
    paint.style = PaintingStyle.fill;
    paint.color = Colors.white;
    canvas.drawCircle(const Offset(71, 31), 5, paint);
    paint.color = WaybiColors.midnightOcean;
    canvas.drawCircle(const Offset(72, 31), 2.5, paint);
    paint.color = const Color(0xFFEDB7A3);
    canvas.drawOval(const Rect.fromLTWH(69, 39, 8, 5), paint);
    paint.color = WaybiColors.sky.withValues(alpha: .5);
    canvas.drawOval(const Rect.fromLTWH(29, 45, 25, 15), paint);
  }

  @override
  bool shouldRepaint(WaybiBirdPainter oldDelegate) => false;
}
