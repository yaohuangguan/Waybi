import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'room_life.dart';

/// Parts are painted separately around their own pivots. The room's positions
/// come from RoomLife; this painter only adds footfalls, tails, wings and blinks.
class CharacterRig extends CustomPainter {
  const CharacterRig({
    required this.pose,
    required this.seconds,
    this.reducedMotion = false,
  });
  final FriendPose pose;
  final double seconds;
  final bool reducedMotion;

  static const ink = Color(0xFF283C29);
  static const cream = Color(0xFFFFF6E9);
  static const cat = Color(0xFF96948A);
  static const stripe = Color(0xFF54584F);
  static const ginger = Color(0xFFF3A43D);
  static const pink = Color(0xFFF69A96);

  double get time => reducedMotion ? 1 : seconds;
  double get gait => reducedMotion || !pose.moving
      ? 0
      : math.sin(time * (pose.activity == FriendActivity.running ? 16 : 10));
  bool get asleep => pose.activity == FriendActivity.sleeping;
  bool get seated =>
      pose.activity == FriendActivity.sitting ||
      pose.activity == FriendActivity.watching ||
      asleep;
  bool get blink => asleep || (!reducedMotion && time % 4.7 < .15);

  void oval(Canvas c, Rect r, Color color) =>
      c.drawOval(r, Paint()..color = color);
  void path(Canvas c, Path p, Color color) =>
      c.drawPath(p, Paint()..color = color);
  void line(Canvas c, Path p, Color color, double width) => c.drawPath(
    p,
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round,
  );

  void joint(Canvas c, Offset pivot, double angle, void Function() draw) {
    c.save();
    c.translate(pivot.dx, pivot.dy);
    c.rotate(angle);
    draw();
    c.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    oval(canvas, const Rect.fromLTWH(13, 89, 77, 8), const Color(0x1C5A4230));
    if (!pose.facingRight) {
      canvas.translate(100, 0);
      canvas.scale(-1, 1);
    }
    final bounce = reducedMotion
        ? 0.0
        : pose.moving
        ? -gait.abs() * (pose.activity == FriendActivity.running ? 3.5 : 1.8)
        : math.sin(time * 2.2) * .45;
    canvas.translate(0, bounce);
    switch (pose.kind) {
      case FriendKind.waybi:
        _bird(canvas);
      case FriendKind.clover:
        _cat(canvas);
      case FriendKind.sett:
        _dog(canvas);
    }
    canvas.restore();
  }

  void _leg(
    Canvas c,
    double x,
    double y,
    double angle,
    Color color, {
    double length = 19,
  }) {
    joint(c, Offset(x, y), angle, () {
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(-4, 0, 9, length),
          const Radius.circular(5),
        ),
        Paint()..color = color,
      );
      oval(c, Rect.fromLTWH(-5, length - 5, 14, 8), cream);
    });
  }

  void _eye(Canvas c, double x, double y, {double radius = 6}) {
    if (blink) {
      line(
        c,
        Path()
          ..moveTo(x - radius, y)
          ..quadraticBezierTo(x, y + 3, x + radius, y),
        ink,
        2.4,
      );
    } else {
      oval(c, Rect.fromCircle(center: Offset(x, y), radius: radius), ink);
      oval(
        c,
        Rect.fromCircle(
          center: Offset(x + radius * .3, y - radius * .35),
          radius: radius * .25,
        ),
        Colors.white,
      );
    }
  }

  void _cat(Canvas c) {
    final crouch = asleep
        ? 11.0
        : seated
        ? 3.0
        : 0.0;
    joint(
      c,
      const Offset(22, 68),
      reducedMotion ? -.12 : math.sin(time * 2.5) * .23,
      () {
        line(
          c,
          Path()
            ..moveTo(0, 8)
            ..cubicTo(-24, 0, -20, -25, -9, -29),
          cat,
          11,
        );
        line(
          c,
          Path()
            ..moveTo(-18, -6)
            ..lineTo(-16, -10),
          stripe,
          8,
        );
        line(
          c,
          Path()
            ..moveTo(-19, -19)
            ..lineTo(-15, -24),
          stripe,
          8,
        );
      },
    );
    _leg(c, 35, 72, -gait * .45, stripe, length: seated ? 13 : 19);
    _leg(c, 68, 70, gait * .45, stripe, length: seated ? 16 : 21);
    oval(c, Rect.fromLTWH(22, 49 + crouch, 53, 38 - crouch * .4), cat);
    oval(c, Rect.fromLTWH(51, 50 + crouch, 27, 35 - crouch * .4), cream);
    line(
      c,
      Path()
        ..moveTo(30, 52 + crouch)
        ..lineTo(35, 62 + crouch),
      stripe,
      5,
    );
    line(
      c,
      Path()
        ..moveTo(39, 50 + crouch)
        ..lineTo(44, 60 + crouch),
      stripe,
      5,
    );
    _leg(c, 27, 75, gait * .45, cat, length: seated ? 13 : 18);
    _leg(c, 60, 72, -gait * .45, cat, length: seated ? 17 : 21);
    joint(
      c,
      Offset(63, 44 + crouch),
      asleep
          ? .15
          : reducedMotion
          ? 0
          : math.sin(time * 1.7) * .018,
      () {
        path(
          c,
          Path()
            ..moveTo(-25, -5)
            ..lineTo(-24, -34)
            ..quadraticBezierTo(-20, -39, -4, -20)
            ..close(),
          cat,
        );
        path(
          c,
          Path()
            ..moveTo(10, -20)
            ..quadraticBezierTo(28, -39, 30, -34)
            ..lineTo(32, -5)
            ..close(),
          cat,
        );
        path(
          c,
          Path()
            ..moveTo(-21, -16)
            ..lineTo(-21, -30)
            ..lineTo(-9, -19)
            ..close(),
          pink,
        );
        path(
          c,
          Path()
            ..moveTo(16, -19)
            ..lineTo(27, -30)
            ..lineTo(28, -14)
            ..close(),
          pink,
        );
        oval(c, const Rect.fromLTWH(-30, -25, 65, 51), cat);
        oval(c, const Rect.fromLTWH(-28, 1, 62, 26), cream);
        path(
          c,
          Path()
            ..moveTo(2, -14)
            ..quadraticBezierTo(-2, -12, -5, 10)
            ..lineTo(12, 10)
            ..quadraticBezierTo(7, -12, 2, -14)
            ..close(),
          cream,
        );
        for (final x in [-11.0, 0.0, 11.0]) {
          line(
            c,
            Path()
              ..moveTo(x, -23)
              ..lineTo(x + 3, -14),
            stripe,
            4.2,
          );
        }
        line(
          c,
          Path()
            ..moveTo(-27, -1)
            ..lineTo(-18, 1),
          stripe,
          4,
        );
        line(
          c,
          Path()
            ..moveTo(30, -1)
            ..lineTo(23, 1),
          stripe,
          4,
        );
        _eye(c, -13, -1, radius: 8);
        _eye(c, 20, -1, radius: 8);
        path(
          c,
          Path()
            ..moveTo(0, 8)
            ..quadraticBezierTo(5, 5, 10, 8)
            ..lineTo(5, 13)
            ..close(),
          pink,
        );
        line(
          c,
          Path()
            ..moveTo(5, 13)
            ..quadraticBezierTo(5, 20, -1, 19)
            ..moveTo(5, 13)
            ..quadraticBezierTo(5, 20, 12, 18),
          ink,
          2.3,
        );
      },
    );
  }

  void _dog(Canvas c) {
    final crouch = seated ? 4.0 : 0.0;
    joint(
      c,
      const Offset(19, 64),
      reducedMotion ? .1 : math.sin(time * 8) * .36,
      () {
        line(
          c,
          Path()
            ..moveTo(0, 4)
            ..cubicTo(-15, -11, -8, -22, 1, -16),
          cream,
          11,
        );
        line(
          c,
          Path()
            ..moveTo(-3, -15)
            ..lineTo(1, -16),
          ginger,
          8,
        );
      },
    );
    _leg(c, 34, 73, -gait * .52, const Color(0xFFD58A30), length: 17);
    _leg(c, 72, 72, gait * .52, const Color(0xFFD58A30), length: 19);
    oval(c, Rect.fromLTWH(15, 49 + crouch, 65, 38), ginger);
    oval(c, Rect.fromLTWH(54, 48 + crouch, 26, 38), cream);
    _leg(c, 24, 74, gait * .52, ginger, length: 19 - crouch);
    _leg(c, 63, 72, -gait * .52, cream, length: 21 - crouch);
    joint(
      c,
      Offset(65, 39 + crouch),
      reducedMotion ? 0 : math.sin(time * 2) * .026,
      () {
        path(
          c,
          Path()
            ..moveTo(-24, -4)
            ..quadraticBezierTo(-36, -44, -22, -35)
            ..lineTo(-2, -17)
            ..close(),
          ginger,
        );
        path(
          c,
          Path()
            ..moveTo(13, -18)
            ..quadraticBezierTo(37, -48, 37, -35)
            ..lineTo(31, -1)
            ..close(),
          ginger,
        );
        path(
          c,
          Path()
            ..moveTo(-25, -16)
            ..lineTo(-24, -29)
            ..lineTo(-10, -17)
            ..close(),
          pink,
        );
        path(
          c,
          Path()
            ..moveTo(22, -16)
            ..lineTo(32, -29)
            ..lineTo(30, -8)
            ..close(),
          pink,
        );
        oval(c, const Rect.fromLTWH(-30, -22, 66, 53), ginger);
        oval(c, const Rect.fromLTWH(-26, 4, 62, 27), cream);
        path(
          c,
          Path()
            ..moveTo(-4, -22)
            ..quadraticBezierTo(6, -16, 8, 4)
            ..lineTo(24, 13)
            ..lineTo(-14, 15)
            ..quadraticBezierTo(4, 2, -4, -22)
            ..close(),
          cream,
        );
        _eye(c, -14, -2, radius: 6);
        _eye(c, 23, -3, radius: 6);
        oval(c, const Rect.fromLTWH(5, 9, 15, 10), ink);
        line(
          c,
          Path()
            ..moveTo(12, 19)
            ..quadraticBezierTo(13, 30, 0, 25)
            ..moveTo(12, 19)
            ..quadraticBezierTo(14, 30, 27, 24),
          ink,
          2.5,
        );
        oval(
          c,
          Rect.fromLTWH(11, 25, 8, reducedMotion ? 9 : 9 + math.sin(time * 4)),
          pink,
        );
      },
    );
  }

  void _bird(Canvas c) {
    const dark = Color(0xFF29451E),
        wing = Color(0xFF819F53),
        gold = Color(0xFFE6AC4C);
    for (var i = 0; i < 2; i++) {
      joint(c, Offset(32 + i * 24, 73), gait * (i == 0 ? .48 : -.48), () {
        line(
          c,
          Path()
            ..moveTo(0, 0)
            ..lineTo(-3, 17)
            ..lineTo(8, 17),
          gold,
          5,
        );
      });
    }
    oval(c, const Rect.fromLTWH(13, 40, 65, 41), dark);
    oval(c, const Rect.fromLTWH(52, 12, 37, 42), dark);
    path(
      c,
      Path()
        ..moveTo(83, 31)
        ..lineTo(100, 40)
        ..lineTo(83, 41)
        ..close(),
      gold,
    );
    if (blink) {
      line(
        c,
        Path()
          ..moveTo(66, 28)
          ..lineTo(77, 28),
        cream,
        2.5,
      );
    } else {
      oval(c, const Rect.fromLTWH(64, 21, 16, 17), Colors.white);
      oval(c, const Rect.fromLTWH(70, 25, 8, 9), ink);
    }
    oval(c, const Rect.fromLTWH(74, 40, 10, 6), const Color(0xFFEFBAA5));
    final flap = reducedMotion
        ? 0.0
        : pose.backpack
        ? math.sin(time * 12) * .45 - .25
        : math.sin(time * 2) * .055;
    joint(
      c,
      const Offset(43, 58),
      flap,
      () => oval(c, const Rect.fromLTWH(-22, -11, 37, 21), wing),
    );
    if (pose.backpack) {
      c.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(13, 41, 19, 28),
          const Radius.circular(6),
        ),
        Paint()..color = const Color(0xFFC89360),
      );
      c.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(15, 48, 15, 12),
          const Radius.circular(3),
        ),
        Paint()..color = const Color(0xFFE6BA86),
      );
      line(
        c,
        Path()
          ..moveTo(28, 41)
          ..quadraticBezierTo(40, 46, 33, 65),
        const Color(0xFF9A6744),
        3,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CharacterRig oldDelegate) =>
      oldDelegate.pose != pose ||
      oldDelegate.seconds != seconds ||
      oldDelegate.reducedMotion != reducedMotion;
}
