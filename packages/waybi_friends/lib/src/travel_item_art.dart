import 'package:flutter/material.dart';

import 'models.dart';

/// Painted item art works without platform emoji fonts or downloaded assets.
class TravelItemArt extends StatelessWidget {
  const TravelItemArt({super.key, required this.item, this.size = 40});

  final TravelItem item;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: item.name,
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _ItemPainter(item.id)),
    ),
  );
}

class _ItemPainter extends CustomPainter {
  const _ItemPainter(this.id);
  final String id;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48, size.height / 48);
    final outline = Paint()
      ..color = const Color(0xFF394A35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void shape(Path path, Color color) {
      canvas.drawPath(path, Paint()..color = color);
      canvas.drawPath(path, outline);
    }

    void roundRect(Rect rect, double radius, Color color) {
      final path = Path()
        ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
      shape(path, color);
    }

    switch (id) {
      case 'camera':
        roundRect(
          const Rect.fromLTWH(7, 11, 12, 10),
          3,
          const Color(0xFF93A783),
        );
        roundRect(
          const Rect.fromLTWH(4, 17, 40, 25),
          6,
          const Color(0xFFB9C9A7),
        );
        canvas.drawCircle(
          const Offset(26, 29),
          9,
          Paint()..color = const Color(0xFFFAF7EC),
        );
        canvas.drawCircle(const Offset(26, 29), 9, outline);
        canvas.drawCircle(
          const Offset(26, 29),
          5,
          Paint()..color = const Color(0xFF607D82),
        );
        canvas.drawCircle(
          const Offset(24, 27),
          1.6,
          Paint()..color = Colors.white,
        );
        roundRect(const Rect.fromLTWH(9, 22, 5, 4), 1, const Color(0xFFF4D57E));
      case 'snack':
        shape(
          Path()
            ..moveTo(7, 38)
            ..lineTo(40, 38)
            ..lineTo(21, 7)
            ..quadraticBezierTo(19, 5, 17, 9)
            ..close(),
          const Color(0xFFD8A15F),
        );
        shape(
          Path()
            ..moveTo(7, 32)
            ..lineTo(40, 32)
            ..lineTo(40, 36)
            ..lineTo(7, 36)
            ..close(),
          const Color(0xFF8AA462),
        );
        shape(
          Path()
            ..moveTo(7, 29)
            ..lineTo(40, 29)
            ..lineTo(38, 32)
            ..lineTo(9, 32)
            ..close(),
          const Color(0xFFDB8C6D),
        );
        shape(
          Path()
            ..moveTo(8, 28)
            ..lineTo(38, 28)
            ..lineTo(21, 7)
            ..quadraticBezierTo(19, 5, 17, 9)
            ..close(),
          const Color(0xFFF6E3AE),
        );
        for (final point in [
          const Offset(18, 16),
          const Offset(23, 22),
          const Offset(15, 24),
        ]) {
          canvas.drawCircle(
            point,
            1.2,
            Paint()..color = const Color(0xFFD4AA6E),
          );
        }
      case 'umbrella':
        canvas.drawPath(
          Path()
            ..moveTo(24, 5)
            ..lineTo(24, 37)
            ..quadraticBezierTo(24, 44, 18, 42)
            ..quadraticBezierTo(15, 41, 15, 37),
          outline,
        );
        shape(
          Path()
            ..moveTo(4, 25)
            ..quadraticBezierTo(7, 9, 24, 8)
            ..quadraticBezierTo(41, 9, 44, 25)
            ..quadraticBezierTo(37, 21, 31, 25)
            ..quadraticBezierTo(24, 21, 17, 25)
            ..quadraticBezierTo(10, 21, 4, 25)
            ..close(),
          const Color(0xFFF3C765),
        );
        canvas.drawPath(
          Path()
            ..moveTo(24, 8)
            ..quadraticBezierTo(16, 15, 17, 25)
            ..moveTo(24, 8)
            ..quadraticBezierTo(32, 15, 31, 25),
          outline..color = const Color(0xFFB48D42),
        );
      case 'toy':
        canvas.drawCircle(
          const Offset(24, 24),
          18,
          Paint()..color = const Color(0xFFBED76E),
        );
        canvas.drawCircle(const Offset(24, 24), 18, outline);
        final seam = Paint()
          ..color = const Color(0xFFFCF7DA)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3;
        canvas.drawPath(
          Path()
            ..moveTo(11, 12)
            ..cubicTo(29, 10, 8, 38, 30, 40)
            ..moveTo(29, 8)
            ..cubicTo(13, 20, 42, 17, 40, 33),
          seam,
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ItemPainter oldDelegate) => id != oldDelegate.id;
}
