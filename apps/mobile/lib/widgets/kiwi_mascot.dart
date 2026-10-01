import 'package:flutter/material.dart';

import '../theme/kiwi_lens_theme.dart';

class KiwiMascot extends StatelessWidget {
  const KiwiMascot({super.key, this.size = 64});
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Kiwi Lens kiwi bird',
    image: true,
    child: SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: KiwiMascotPainter()),
    ),
  );
}

/// The same painter is used for the splash mascot and exported launcher assets.
class KiwiMascotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 100);
    final paint = Paint()..isAntiAlias = true;
    paint.color = KiwiLensColors.sky;
    canvas.drawCircle(const Offset(50, 50), 47, paint);
    paint.color = KiwiLensColors.deepOcean;
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
    paint.color = KiwiLensColors.midnightOcean;
    canvas.drawCircle(const Offset(72, 31), 2.5, paint);
    paint.color = const Color(0xFFEDB7A3);
    canvas.drawOval(const Rect.fromLTWH(69, 39, 8, 5), paint);
    paint.color = KiwiLensColors.sky.withValues(alpha: .5);
    canvas.drawOval(const Rect.fromLTWH(29, 45, 25, 15), paint);
  }

  @override
  bool shouldRepaint(KiwiMascotPainter oldDelegate) => false;
}
