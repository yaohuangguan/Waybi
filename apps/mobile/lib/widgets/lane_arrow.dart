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
    label: directions
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
    canvas.scale(size.width / 32, size.height / 32);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    if (directions.isEmpty) {
      canvas.drawCircle(const Offset(16, 16), 2, fill);
    } else {
      // The incoming part is drawn once, even for straight + left + right.
      canvas.drawLine(const Offset(16, 29), const Offset(16, 18), stroke);
      for (final direction in directions) {
        canvas.save();
        if (const {
          LaneArrowDirection.right,
          LaneArrowDirection.slightRight,
          LaneArrowDirection.sharpRight,
          LaneArrowDirection.uTurnRight,
        }.contains(direction)) {
          canvas.translate(32, 0);
          canvas.scale(-1, 1);
        }
        final path = Path()..moveTo(16, 18);
        late final List<Offset> head;
        switch (direction) {
          case LaneArrowDirection.straight:
            path.lineTo(16, 7);
            head = const [Offset(16, 2), Offset(10.5, 10), Offset(21.5, 10)];
          case LaneArrowDirection.left || LaneArrowDirection.right:
            path
              ..quadraticBezierTo(16, 12, 10, 12)
              ..lineTo(7, 12);
            head = const [Offset(2, 12), Offset(10, 6.5), Offset(10, 17.5)];
          case LaneArrowDirection.slightLeft || LaneArrowDirection.slightRight:
            path
              ..quadraticBezierTo(16, 15, 13, 12)
              ..lineTo(7, 6);
            head = const [Offset(3, 2), Offset(4.5, 11.5), Offset(12.5, 3.5)];
          case LaneArrowDirection.sharpLeft || LaneArrowDirection.sharpRight:
            path
              ..quadraticBezierTo(16, 10, 10, 14)
              ..lineTo(7, 17);
            head = const [Offset(3, 21), Offset(12.5, 19.5), Offset(4.5, 11.5)];
          case LaneArrowDirection.uTurnLeft || LaneArrowDirection.uTurnRight:
            path
              ..lineTo(16, 10)
              ..cubicTo(16, 2, 4, 2, 4, 10)
              ..lineTo(4, 15);
            head = const [Offset(4, 22), Offset(.5, 14), Offset(8.5, 14)];
        }
        canvas.drawPath(path, stroke);
        canvas.drawPath(Path()..addPolygon(head, true), fill);
        canvas.restore();
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(LaneArrowPainter oldDelegate) =>
      oldDelegate.color != color ||
      !setEquals(oldDelegate.directions, directions);
}
