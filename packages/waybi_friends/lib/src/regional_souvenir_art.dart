import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'souvenirs.dart';

/// Original local artwork, matching the small paper objects in the room.
void paintRegionalSouvenir(Canvas c, SouvenirKind kind) {
  const ink = Color(0xFF596148),
      paper = Color(0xFFFFF3D9),
      gold = Color(0xFFD3A66D),
      green = Color(0xFF91AD78),
      blue = Color(0xFF8DBBC7),
      pink = Color(0xFFDEA193);
  final pen = Paint()
    ..color = ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.4
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  void shape(Path p, Color color) {
    c.drawPath(p, Paint()..color = color);
    c.drawPath(p, pen);
  }

  void box(
    double x,
    double y,
    double w,
    double h,
    Color color, [
    double r = 2,
  ]) => shape(
    Path()..addRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r)),
    ),
    color,
  );
  void oval(double x, double y, double w, double h, Color color) =>
      shape(Path()..addOval(Rect.fromLTWH(x, y, w, h)), color);
  void line(List<Offset> points, [Color? color, double width = 1.4]) =>
      c.drawPath(
        Path()..addPolygon(points, false),
        Paint()
          ..color = color ?? ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
  switch (kind) {
    case SouvenirKind.croissant:
      oval(6, 42, 52, 14, paper);
      shape(
        Path()
          ..moveTo(12, 40)
          ..quadraticBezierTo(8, 10, 31, 14)
          ..quadraticBezierTo(55, 7, 54, 39)
          ..lineTo(44, 35)
          ..quadraticBezierTo(43, 24, 32, 26)
          ..quadraticBezierTo(20, 23, 21, 39)
          ..close(),
        gold,
      );
      for (var i = 0; i < 4; i++) {
        line(
          [Offset(20 + i * 7, 16), Offset(19 + i * 7, 28)],
          const Color(0xFFAD804C),
          2,
        );
      }
    case SouvenirKind.mochi:
      oval(7, 41, 50, 14, paper);
      for (var i = 0; i < 3; i++) {
        oval(11 + i * 14, 27 - i % 2 * 8, 16, 19, i.isEven ? pink : green);
        line([
          Offset(16 + i * 14, 39 - i % 2 * 8),
          Offset(22 + i * 14, 39 - i % 2 * 8),
        ], paper);
      }
    case SouvenirKind.pretzel:
      final path = Path()
        ..moveTo(16, 45)
        ..cubicTo(55, 43, 55, 10, 33, 17)
        ..cubicTo(10, 3, 7, 39, 47, 46)
        ..cubicTo(60, 39, 30, 30, 16, 45);
      c.drawPath(
        path,
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round,
      );
      c.drawPath(
        path,
        Paint()
          ..color = gold
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round,
      );
      for (final p in [
        const Offset(19, 24),
        const Offset(36, 20),
        const Offset(45, 30),
        const Offset(26, 39),
      ]) {
        oval(p.dx, p.dy, 2, 2, paper);
      }
    case SouvenirKind.pavlova:
      oval(7, 43, 50, 13, blue);
      box(14, 28, 36, 18, paper, 6);
      oval(14, 23, 36, 13, Colors.white);
      for (var i = 0; i < 3; i++) {
        oval(18 + i * 10, 19 + i % 2 * 2, 8, 10, pink);
        line([Offset(20 + i * 10, 20), Offset(22 + i * 10, 17)], green, 2);
      }
    case SouvenirKind.tea:
    case SouvenirKind.teaScroll:
      box(15, 13, 34, 38, green, 5);
      box(13, 10, 38, 7, gold);
      box(21, 25, 22, 17, paper);
      shape(
        Path()
          ..moveTo(26, 38)
          ..quadraticBezierTo(22, 26, 39, 27)
          ..quadraticBezierTo(39, 40, 26, 38)
          ..close(),
        green,
      );
      if (kind == SouvenirKind.teaScroll) {
        box(6, 45, 49, 8, paper, 4);
        line([const Offset(15, 49), const Offset(45, 49)], gold);
      }
    case SouvenirKind.dumpling:
      oval(8, 35, 48, 19, gold);
      box(8, 29, 48, 15, gold);
      oval(8, 23, 48, 17, paper);
      for (var i = 0; i < 3; i++) {
        oval(14 + i * 12, 24 - i % 2 * 5, 12, 12, paper);
        for (var j = 0; j < 3; j++) {
          line(
            [
              Offset(17 + i * 12 + j * 2, 26 - i % 2 * 5),
              Offset(20 + i * 12, 30 - i % 2 * 5),
            ],
            gold,
            1,
          );
        }
      }
      for (var i = 0; i < 8; i++) {
        line(
          [Offset(11 + i * 6, 39), Offset(11 + i * 6, 47)],
          const Color(0xFFAE865C),
          1,
        );
      }
    case SouvenirKind.koala:
      oval(10, 39, 44, 13, gold);
      oval(19, 29, 28, 19, const Color(0xFFADB0AA));
      oval(10, 13, 17, 20, const Color(0xFFADB0AA));
      oval(40, 13, 17, 20, const Color(0xFFADB0AA));
      oval(17, 16, 33, 28, const Color(0xFFBBBDB7));
      oval(23, 26, 4, 4, ink);
      oval(40, 26, 4, 4, ink);
      oval(30, 28, 9, 12, ink);
      line([const Offset(47, 47), const Offset(49, 28)], green, 3);
    default:
      box(5, 9, 54, 45, paper, 3);
      box(9, 13, 46, 32, blue, 1);
      oval(44, 17, 6, 6, const Color(0xFFFFE7A2));
      line([const Offset(10, 44), const Offset(54, 44)], green, 3);
      switch (kind) {
        case SouvenirKind.eiffel:
          shape(
            Path()
              ..moveTo(32, 17)
              ..lineTo(19, 43)
              ..lineTo(25, 43)
              ..quadraticBezierTo(32, 28, 39, 43)
              ..lineTo(45, 43)
              ..close(),
            gold,
          );
          line([const Offset(23, 34), const Offset(41, 34)]);
          line([const Offset(27, 27), const Offset(37, 27)]);
          line([const Offset(32, 15), const Offset(32, 35)]);
        case SouvenirKind.torii:
          line([const Offset(18, 42), const Offset(18, 25)], pink, 5);
          line([const Offset(46, 42), const Offset(46, 25)], pink, 5);
          line(
            [const Offset(12, 21), const Offset(32, 23), const Offset(52, 21)],
            ink,
            4,
          );
          line([const Offset(15, 29), const Offset(49, 29)], pink, 4);
        case SouvenirKind.bigBen:
          box(25, 22, 14, 23, gold, 0);
          shape(
            Path()
              ..moveTo(24, 22)
              ..lineTo(32, 14)
              ..lineTo(40, 22)
              ..close(),
            ink,
          );
          oval(27, 25, 10, 10, paper);
          line([
            const Offset(32, 27),
            const Offset(32, 30),
            const Offset(35, 32),
          ]);
          for (var i = 0; i < 3; i++) {
            line([Offset(28 + i * 4, 38), Offset(28 + i * 4, 43)], ink, 1);
          }
        case SouvenirKind.liberty:
          box(24, 40, 17, 5, gold, 0);
          shape(
            Path()
              ..moveTo(28, 40)
              ..lineTo(30, 28)
              ..lineTo(25, 20)
              ..lineTo(28, 19)
              ..lineTo(34, 28)
              ..lineTo(38, 40)
              ..close(),
            green,
          );
          oval(30, 23, 7, 7, green);
          line([const Offset(26, 20), const Offset(26, 17)], gold, 3);
          line(
            [
              const Offset(29, 24),
              const Offset(31, 20),
              const Offset(34, 23),
              const Offset(37, 20),
              const Offset(38, 24),
            ],
            green,
            1,
          );
        case SouvenirKind.palm:
          line([const Offset(32, 43), const Offset(35, 25)], gold, 4);
          for (var i = 0; i < 5; i++) {
            final angle = math.pi + i * .55;
            line(
              [
                const Offset(35, 25),
                Offset(35 + math.cos(angle) * 14, 25 + math.sin(angle) * 8),
              ],
              green,
              3,
            );
          }
          line(
            [
              const Offset(12, 39),
              const Offset(23, 37),
              const Offset(44, 39),
              const Offset(53, 37),
            ],
            paper,
            2,
          );
        case SouvenirKind.hollywood:
          box(11, 29, 42, 13, green);
          for (var i = 0; i < 5; i++) {
            final x = 16 + i * 8.0;
            line([Offset(x, 33), Offset(x, 38)], paper, 2);
          }
          line(
            [const Offset(14, 28), const Offset(30, 21), const Offset(52, 28)],
            green,
            3,
          );
          shape(
            Path()
              ..moveTo(44, 16)
              ..lineTo(46, 19)
              ..lineTo(50, 19)
              ..lineTo(47, 22)
              ..lineTo(48, 26)
              ..lineTo(44, 24)
              ..lineTo(40, 26)
              ..lineTo(41, 22)
              ..lineTo(38, 19)
              ..lineTo(42, 19)
              ..close(),
            gold,
          );
        case SouvenirKind.skyTower:
          line([const Offset(32, 43), const Offset(32, 18)], paper, 4);
          oval(25, 24, 14, 5, ink);
          line([const Offset(32, 18), const Offset(32, 15)], ink);
          for (var i = 0; i < 4; i++) {
            box(13 + i * 10, 36 - i % 2 * 5, 7, 8 + i % 2 * 5, green, 0);
          }
        case SouvenirKind.operaHouse:
          shape(
            Path()
              ..moveTo(15, 41)
              ..quadraticBezierTo(19, 27, 26, 24)
              ..lineTo(29, 41)
              ..close(),
            paper,
          );
          shape(
            Path()
              ..moveTo(24, 41)
              ..quadraticBezierTo(30, 22, 37, 18)
              ..lineTo(40, 41)
              ..close(),
            paper,
          );
          shape(
            Path()
              ..moveTo(36, 41)
              ..quadraticBezierTo(43, 30, 49, 27)
              ..lineTo(51, 41)
              ..close(),
            paper,
          );
          line([const Offset(13, 44), const Offset(52, 44)], gold, 3);
        case SouvenirKind.orientalPearl:
          line([const Offset(24, 43), const Offset(24, 19)], ink, 2);
          oval(19, 22, 10, 10, pink);
          oval(21, 35, 6, 6, pink);
          box(37, 22, 7, 22, paper, 0);
          box(46, 28, 6, 16, green, 0);
          line([const Offset(40, 22), const Offset(40, 18)], ink);
        case SouvenirKind.shenzhen:
          shape(
            Path()
              ..moveTo(27, 43)
              ..lineTo(30, 22)
              ..lineTo(34, 15)
              ..lineTo(38, 22)
              ..lineTo(41, 43)
              ..close(),
            paper,
          );
          for (var i = 0; i < 4; i++) {
            line([Offset(30, 28 + i * 4), Offset(38, 28 + i * 4)], blue, 1);
          }
          box(13, 31, 10, 13, green, 0);
          box(44, 34, 8, 10, green, 0);
        case SouvenirKind.greatWall:
          shape(
            Path()
              ..moveTo(10, 43)
              ..lineTo(18, 34)
              ..lineTo(27, 38)
              ..lineTo(36, 26)
              ..lineTo(53, 33)
              ..lineTo(53, 39)
              ..lineTo(38, 33)
              ..lineTo(29, 44)
              ..lineTo(19, 40)
              ..lineTo(12, 45)
              ..close(),
            gold,
          );
          box(33, 23, 8, 9, paper, 0);
          for (var i = 0; i < 3; i++) {
            box(33 + i * 3, 21, 2, 3, paper, 0);
          }
        case SouvenirKind.palace:
          box(17, 32, 30, 11, pink, 0);
          shape(
            Path()
              ..moveTo(12, 31)
              ..quadraticBezierTo(27, 29, 32, 23)
              ..quadraticBezierTo(37, 29, 52, 31)
              ..close(),
            gold,
          );
          line([const Offset(23, 43), const Offset(23, 34)], gold, 2);
          line([const Offset(41, 43), const Offset(41, 34)], gold, 2);
          box(28, 35, 8, 8, gold, 0);
        default:
          break;
      }
      line([const Offset(12, 49), const Offset(36, 49)], gold, 1);
      box(45, 47, 7, 5, green, 1);
  }
}
