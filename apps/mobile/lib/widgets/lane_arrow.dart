import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/navigation_lanes.dart';

/// One pavement marking per lane. All branches share the same incoming stem;
/// no text/font fallback (including platform emoji) participates in rendering.
class LaneArrow extends StatelessWidget {
  const LaneArrow({
    super.key,
    required this.directions,
    required this.color,
    this.size = 32,
    this.language = 'en',
  });

  final Set<LaneArrowDirection> directions;
  final Color color;
  final double size;
  final String language;

  @override
  Widget build(BuildContext context) => Semantics(
    label: directions.isEmpty
        ? (language == 'zh' ? '车道方向信息暂缺' : 'Lane direction unavailable')
        : directions
              .map((direction) => direction.label(language))
              .join(language == 'zh' ? '或' : ' or '),
    child: CustomPaint(
      size: Size.square(size),
      painter: LaneArrowPainter(directions, color),
    ),
  );
}

class LaneArrowPainter extends CustomPainter {
  const LaneArrowPainter(this.directions, this.color);
  final Set<LaneArrowDirection> directions;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 40, size.height / 40);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Unspecified markings still occupy a real lane. Show its boundaries and
    // a neutral dash, rather than a transparent tile or an invented turn arrow.
    if (directions.isEmpty) {
      stroke.strokeWidth = 2.5;
      for (final x in [10.0, 30.0]) {
        for (final y in [5.0, 17.0, 29.0]) {
          canvas.drawLine(Offset(x, y), Offset(x, y + 6), stroke);
        }
      }
      canvas.drawLine(const Offset(17, 20), const Offset(23, 20), stroke);
      canvas.restore();
      return;
    }
    final fill = Paint()..color = color;
    // The incoming part is drawn once, even for straight + left + right.
    canvas.drawLine(const Offset(20, 36), const Offset(20, 22), stroke);
    for (final direction in directions) {
      canvas.save();
      if (const {
        LaneArrowDirection.right,
        LaneArrowDirection.slightRight,
        LaneArrowDirection.sharpRight,
        LaneArrowDirection.uTurnRight,
      }.contains(direction)) {
        canvas.translate(40, 0);
        canvas.scale(-1, 1);
      }
      final path = Path()..moveTo(20, 22);
      late final List<Offset> head;
      switch (direction) {
        case LaneArrowDirection.straight:
          path.lineTo(20, 8);
          head = const [Offset(20, 2), Offset(14, 11), Offset(26, 11)];
        case LaneArrowDirection.left || LaneArrowDirection.right:
          path
            ..quadraticBezierTo(20, 14, 12, 14)
            ..lineTo(8, 14);
          head = const [Offset(2, 14), Offset(11, 8), Offset(11, 20)];
        case LaneArrowDirection.slightLeft || LaneArrowDirection.slightRight:
          path
            ..quadraticBezierTo(20, 18, 16, 14)
            ..lineTo(9, 7);
          head = const [Offset(4, 2), Offset(5, 13), Offset(15, 3)];
        case LaneArrowDirection.sharpLeft || LaneArrowDirection.sharpRight:
          path
            ..quadraticBezierTo(20, 12, 13, 17)
            ..lineTo(9, 21);
          head = const [Offset(4, 26), Offset(15, 24), Offset(5, 14)];
        case LaneArrowDirection.uTurnLeft || LaneArrowDirection.uTurnRight:
          path
            ..lineTo(20, 12)
            ..cubicTo(20, 2, 5, 2, 5, 12)
            ..lineTo(5, 21);
          head = const [Offset(5, 29), Offset(.5, 20), Offset(9.5, 20)];
      }
      canvas.drawPath(path, stroke);
      canvas.drawPath(Path()..addPolygon(head, true), fill);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(LaneArrowPainter oldDelegate) =>
      oldDelegate.color != color ||
      !setEquals(oldDelegate.directions, directions);
}
