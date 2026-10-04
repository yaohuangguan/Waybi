import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'souvenirs.dart';

/// The bundled PNG illustrations are rendered from this code, so every
/// collectible has local artwork and works offline without font fallback.
class SouvenirIllustration extends StatelessWidget {
  const SouvenirIllustration({super.key, required this.item, this.size = 100});
  final SouvenirItem item;
  final double size;
  @override
  Widget build(BuildContext context) => Image.asset(
    item.asset,
    width: size,
    height: size,
    fit: BoxFit.contain,
    semanticLabel: item.name,
    filterQuality: FilterQuality.high,
  );
}

class SouvenirPainter extends CustomPainter {
  const SouvenirPainter(this.kind);
  final SouvenirKind kind;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64, size.height / 64);
    const ink = Color(0xFF596148),
        paper = Color(0xFFF5E4BE),
        moss = Color(0xFF92AB71),
        gold = Color(0xFFD3A66D);
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void shape(Path path, Color color) {
      canvas.drawPath(path, Paint()..color = color);
      canvas.drawPath(path, stroke);
    }

    void rect(
      double x,
      double y,
      double w,
      double h,
      Color color, {
      double r = 3,
    }) => shape(
      Path()..addRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r)),
      ),
      color,
    );
    void circle(double x, double y, double r, Color color) => shape(
      Path()..addOval(Rect.fromCircle(center: Offset(x, y), radius: r)),
      color,
    );
    void line(List<Offset> points, {Color? color, double? width}) {
      final p = Path()..addPolygon(points, false);
      canvas.drawPath(
        p,
        Paint()
          ..color = color ?? ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = width ?? 1.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    void boat(double x, double y) {
      shape(
        Path()
          ..moveTo(x, y)
          ..lineTo(x + 20, y)
          ..lineTo(x + 16, y + 6)
          ..lineTo(x + 4, y + 6)
          ..close(),
        const Color(0xFF7897A0),
      );
      rect(x + 5, y - 7, 10, 7, paper, r: 1);
      line([
        Offset(x - 1, y + 9),
        Offset(x + 8, y + 10),
        Offset(x + 21, y + 9),
      ], color: const Color(0xFF7897A0));
    }

    canvas.drawOval(
      const Rect.fromLTWH(12, 53, 40, 5),
      Paint()..color = const Color(0x14606445),
    );
    switch (kind) {
      case SouvenirKind.letter:
        rect(13, 8, 35, 33, const Color(0xFFFFF9E8), r: 2);
        for (var y = 15.0; y < 30; y += 5) {
          line(
            [Offset(20, y), Offset(42, y)],
            color: const Color(0xFFA6AF94),
            width: 1,
          );
        }
        rect(7, 25, 50, 30, paper, r: 4);
        shape(
          Path()
            ..moveTo(8, 27)
            ..lineTo(32, 44)
            ..lineTo(56, 27)
            ..close(),
          const Color(0xFFF9EDCE),
        );
        line([const Offset(8, 53), const Offset(24, 40)]);
        line([const Offset(56, 53), const Offset(40, 40)]);
        circle(32, 42, 6, const Color(0xFFCF8976));
        circle(32, 42, 3.2, const Color(0xFFE8B49C));
        rect(42, 11, 6, 7, moss, r: 1);
      case SouvenirKind.map:
        shape(
          Path()
            ..moveTo(6, 16)
            ..lineTo(23, 10)
            ..lineTo(41, 16)
            ..lineTo(58, 10)
            ..lineTo(58, 47)
            ..lineTo(41, 54)
            ..lineTo(23, 48)
            ..lineTo(6, 54)
            ..close(),
          paper,
        );
        shape(
          Path()
            ..moveTo(7, 33)
            ..quadraticBezierTo(22, 18, 35, 32)
            ..quadraticBezierTo(45, 39, 57, 25)
            ..lineTo(57, 35)
            ..quadraticBezierTo(43, 48, 31, 39)
            ..quadraticBezierTo(20, 28, 7, 42)
            ..close(),
          const Color(0xFFA6CBD0),
        );
        line([const Offset(23, 11), const Offset(23, 47)], color: gold);
        line([const Offset(41, 17), const Offset(41, 52)], color: gold);
        line(
          [
            const Offset(12, 45),
            const Offset(19, 38),
            const Offset(29, 43),
            const Offset(43, 24),
          ],
          color: const Color(0xFFA6835C),
          width: 2,
        );
        circle(43, 24, 3.5, const Color(0xFFCD8977));
        circle(13, 23, 4, moss);
      case SouvenirKind.scroll:
        rect(13, 13, 38, 35, paper, r: 1);
        rect(9, 8, 44, 9, const Color(0xFFE7CAA0), r: 4);
        rect(11, 45, 44, 10, const Color(0xFFE7CAA0), r: 4);
        circle(13, 12.5, 3.7, paper);
        circle(51, 50, 4, paper);
        line([
          const Offset(20, 36),
          const Offset(20, 31),
          const Offset(25, 31),
          const Offset(25, 25),
          const Offset(29, 25),
          const Offset(29, 33),
          const Offset(34, 33),
          const Offset(34, 22),
          const Offset(38, 22),
          const Offset(38, 35),
          const Offset(45, 35),
        ], color: const Color(0xFF839679));
        line(
          [const Offset(20, 41), const Offset(42, 41)],
          color: gold,
          width: 1,
        );
      case SouvenirKind.cookie:
        circle(36, 31, 19, const Color(0xFFE4C28C));
        circle(26, 37, 18, const Color(0xFFF1D399));
        for (final p in [
          const Offset(19, 29),
          const Offset(32, 31),
          const Offset(24, 42),
          const Offset(38, 39),
        ]) {
          circle(p.dx, p.dy, 2.7, const Color(0xFFA66E6F));
        }
        for (final p in [
          const Offset(15, 39),
          const Offset(30, 45),
          const Offset(25, 23),
        ]) {
          circle(p.dx, p.dy, 1, const Color(0xFFD2A572));
        }
      case SouvenirKind.bun:
        shape(
          Path()
            ..moveTo(9, 39)
            ..cubicTo(9, 9, 55, 9, 55, 39)
            ..quadraticBezierTo(52, 54, 32, 53)
            ..quadraticBezierTo(12, 52, 9, 39)
            ..close(),
          const Color(0xFFE2AD71),
        );
        shape(
          Path()
            ..moveTo(11, 33)
            ..cubicTo(17, 12, 47, 12, 53, 33)
            ..quadraticBezierTo(31, 43, 11, 33)
            ..close(),
          const Color(0xFFF5D49E),
        );
        for (var x = 23.0; x <= 39; x += 8) {
          line(
            [Offset(x, 22), Offset(x - 3, 31)],
            color: const Color(0xFFC68B5C),
            width: 3,
          );
        }
      case SouvenirKind.shell:
        shape(
          Path()
            ..moveTo(32, 53)
            ..cubicTo(15, 45, 3, 26, 12, 21)
            ..quadraticBezierTo(11, 13, 21, 14)
            ..quadraticBezierTo(26, 6, 32, 13)
            ..quadraticBezierTo(39, 6, 43, 14)
            ..quadraticBezierTo(54, 13, 52, 22)
            ..cubicTo(63, 28, 48, 46, 32, 53)
            ..close(),
          const Color(0xFFE8BDA7),
        );
        for (var x = 14.0; x <= 50; x += 9) {
          canvas.drawPath(
            Path()
              ..moveTo(32, 50)
              ..quadraticBezierTo(x, 34, x, 20),
            stroke..color = const Color(0xFFC99C88),
          );
        }
      case SouvenirKind.glass:
        shape(
          Path()
            ..moveTo(10, 35)
            ..lineTo(18, 20)
            ..quadraticBezierTo(26, 17, 27, 29)
            ..lineTo(23, 45)
            ..quadraticBezierTo(13, 49, 10, 35)
            ..close(),
          const Color(0xFF97C2BE),
        );
        shape(
          Path()
            ..moveTo(31, 23)
            ..quadraticBezierTo(45, 15, 53, 27)
            ..lineTo(48, 39)
            ..lineTo(34, 37)
            ..close(),
          const Color(0xFFADCACD),
        );
        shape(
          Path()
            ..moveTo(28, 42)
            ..lineTo(37, 38)
            ..quadraticBezierTo(47, 44, 41, 51)
            ..lineTo(29, 52)
            ..close(),
          const Color(0xFFA8BA8B),
        );
        line(
          [const Offset(16, 29), const Offset(18, 24)],
          color: const Color(0xFFDBECE1),
          width: 2,
        );
        line(
          [const Offset(39, 25), const Offset(45, 23)],
          color: const Color(0xFFE8F0DE),
          width: 2,
        );
      case SouvenirKind.feather:
        shape(
          Path()
            ..moveTo(16, 50)
            ..cubicTo(11, 27, 30, 8, 48, 11)
            ..cubicTo(54, 32, 38, 48, 16, 50)
            ..close(),
          paper,
        );
        line(
          [const Offset(12, 56), const Offset(44, 16)],
          color: const Color(0xFFAD9B7C),
          width: 2,
        );
        for (var i = 0; i < 4; i++) {
          final x = 22.0 + i * 5, y = 43.0 - i * 6;
          line(
            [Offset(x, y), Offset(x - 7, y - 8)],
            color: const Color(0xFFCABD9D),
            width: 1,
          );
          line(
            [Offset(x, y), Offset(x + 10, y - 1)],
            color: const Color(0xFFCABD9D),
            width: 1,
          );
        }
      case SouvenirKind.ticket:
        rect(6, 17, 52, 32, paper, r: 3);
        rect(6, 17, 12, 32, const Color(0xFFB7CECD), r: 3);
        for (var y = 22.0; y < 47; y += 5) {
          line([Offset(20, y), Offset(20, y + 2)], color: gold, width: 1);
        }
        boat(27, 29);
        line(
          [const Offset(27, 42), const Offset(48, 42)],
          color: gold,
          width: 1,
        );
      case SouvenirKind.button:
        circle(32, 32, 21, const Color(0xFF90ADBB));
        circle(32, 32, 16, const Color(0xFFBDD0D4));
        for (final p in [
          const Offset(27, 27),
          const Offset(37, 27),
          const Offset(27, 37),
          const Offset(37, 37),
        ]) {
          circle(p.dx, p.dy, 2.5, const Color(0xFFF5F0DB));
        }
        line([
          const Offset(27, 27),
          const Offset(37, 37),
        ], color: const Color(0xFF8C9E99));
        line([
          const Offset(37, 27),
          const Offset(27, 37),
        ], color: const Color(0xFF8C9E99));
      case SouvenirKind.acorn:
        shape(
          Path()
            ..moveTo(16, 30)
            ..lineTo(48, 30)
            ..quadraticBezierTo(48, 48, 32, 55)
            ..quadraticBezierTo(16, 48, 16, 30)
            ..close(),
          gold,
        );
        shape(
          Path()
            ..moveTo(12, 30)
            ..quadraticBezierTo(14, 14, 32, 14)
            ..quadraticBezierTo(50, 14, 52, 30)
            ..close(),
          const Color(0xFF9C9973),
        );
        line([const Offset(32, 14), const Offset(34, 8)], color: ink, width: 3);
        for (var x = 20.0; x < 47; x += 8) {
          line([
            Offset(x, 21),
            Offset(x - 3, 27),
          ], color: const Color(0xFFC0BA93));
        }
      case SouvenirKind.clover:
        for (final p in [
          const Offset(23, 23),
          const Offset(40, 23),
          const Offset(32, 37),
        ]) {
          shape(
            Path()
              ..moveTo(p.dx, p.dy + 8)
              ..cubicTo(p.dx - 18, p.dy, p.dx - 10, p.dy - 11, p.dx, p.dy - 5)
              ..cubicTo(p.dx + 11, p.dy - 12, p.dx + 17, p.dy, p.dx, p.dy + 8)
              ..close(),
            moss,
          );
        }
        line(
          [const Offset(32, 35), const Offset(33, 52), const Offset(27, 56)],
          color: const Color(0xFF71935B),
          width: 2,
        );
      case SouvenirKind.twig:
        line(
          [const Offset(13, 53), const Offset(39, 12)],
          color: const Color(0xFFAC916D),
          width: 6,
        );
        line(
          [const Offset(21, 40), const Offset(11, 30)],
          color: const Color(0xFFAC916D),
          width: 4,
        );
        line(
          [const Offset(31, 25), const Offset(47, 28)],
          color: const Color(0xFFAC916D),
          width: 4,
        );
        line(
          [const Offset(13, 52), const Offset(38, 13)],
          color: const Color(0xFFDCC5A0),
          width: 1.5,
        );
      case SouvenirKind.stone:
        shape(
          Path()
            ..moveTo(8, 43)
            ..quadraticBezierTo(6, 24, 23, 18)
            ..quadraticBezierTo(43, 10, 55, 29)
            ..quadraticBezierTo(63, 44, 47, 51)
            ..quadraticBezierTo(23, 59, 8, 43)
            ..close(),
          const Color(0xFF989D95),
        );
        shape(
          Path()
            ..moveTo(13, 33)
            ..quadraticBezierTo(25, 14, 43, 22)
            ..quadraticBezierTo(37, 35, 13, 33)
            ..close(),
          const Color(0xFFB8BDB0),
        );
        circle(44, 40, 1.3, const Color(0xFF777E74));
        circle(23, 45, 1.1, const Color(0xFF777E74));
      case SouvenirKind.leaf:
        shape(
          Path()
            ..moveTo(17, 50)
            ..quadraticBezierTo(10, 17, 49, 10)
            ..quadraticBezierTo(55, 43, 17, 50)
            ..close(),
          const Color(0xFFB3B879),
        );
        line(
          [const Offset(11, 56), const Offset(43, 17)],
          color: const Color(0xFF85945C),
          width: 2,
        );
        for (var i = 0; i < 4; i++) {
          final x = 23.0 + i * 5, y = 42.0 - i * 6;
          line(
            [Offset(x, y), Offset(x + 13, y - 2)],
            color: const Color(0xFF8C995F),
            width: 1,
          );
        }
      case SouvenirKind.flower:
        line(
          [const Offset(32, 26), const Offset(31, 54)],
          color: const Color(0xFF93A878),
          width: 2.5,
        );
        shape(
          Path()
            ..moveTo(31, 45)
            ..quadraticBezierTo(12, 42, 16, 32)
            ..quadraticBezierTo(28, 29, 31, 45)
            ..close(),
          moss,
        );
        for (var i = 0; i < 6; i++) {
          final a = i * math.pi / 3;
          circle(
            32 + 11 * math.cos(a),
            23 + 11 * math.sin(a),
            8,
            const Color(0xFFE0AD99),
          );
        }
        circle(32, 23, 7, const Color(0xFFEBCB85));
      case SouvenirKind.vial:
        rect(22, 9, 20, 10, const Color(0xFFC7A37B), r: 2);
        rect(25, 19, 14, 9, const Color(0xFFDCE7D7), r: 1);
        rect(17, 25, 30, 30, const Color(0xFFC4D6CF), r: 6);
        rect(20, 38, 24, 14, const Color(0xFF817E73), r: 3);
        rect(23, 32, 18, 12, paper, r: 2);
        line(
          [const Offset(23, 29), const Offset(22, 35)],
          color: const Color(0xFFF8F7E6),
          width: 2,
        );
        circle(32, 38, 2, gold);
      case SouvenirKind.stamp:
        rect(14, 10, 36, 44, const Color(0xFFFFF7DF), r: 1);
        rect(19, 15, 26, 32, const Color(0xFFAAC1A0), r: 1);
        for (var y = 13.0; y <= 51; y += 6) {
          circle(14, y, 1.6, const Color(0xFFF5F0E0));
          circle(50, y, 1.6, const Color(0xFFF5F0E0));
        }
        circle(32, 32, 8, const Color(0xFF73895B));
        circle(39, 25, 4, const Color(0xFF73895B));
        line(
          [const Offset(40, 28), const Offset(47, 31)],
          color: ink,
          width: 2,
        );
        line([const Offset(30, 40), const Offset(29, 43)], color: ink);
        circle(40, 24, 1, paper);
      case SouvenirKind.token:
        circle(32, 32, 23, const Color(0xFFD0AB68));
        circle(32, 32, 18, const Color(0xFFECD4A0));
        boat(22, 32);
        circle(32, 18, 1.4, gold);
        circle(32, 46, 1.4, gold);
      case SouvenirKind.fern:
        line(
          [const Offset(16, 54), const Offset(40, 10)],
          color: const Color(0xFF648857),
          width: 2,
        );
        for (var i = 0; i < 6; i++) {
          final x = 20.0 + i * 3.2, y = 46.0 - i * 6;
          shape(
            Path()
              ..moveTo(x, y)
              ..quadraticBezierTo(x - 17, y - 2, x - 10, y - 9)
              ..quadraticBezierTo(x - 1, y - 6, x, y)
              ..close(),
            moss,
          );
          shape(
            Path()
              ..moveTo(x, y)
              ..quadraticBezierTo(x + 15, y + 4, x + 17, y - 4)
              ..quadraticBezierTo(x + 7, y - 6, x, y)
              ..close(),
            moss,
          );
        }
      case SouvenirKind.keepsake:
        rect(13, 22, 38, 31, paper, r: 4);
        rect(10, 19, 44, 9, moss, r: 3);
        rect(29, 20, 6, 33, moss, r: 1);
        canvas.drawPath(
          Path()
            ..moveTo(32, 20)
            ..cubicTo(6, 16, 20, 1, 32, 20)
            ..cubicTo(43, 0, 59, 17, 32, 20),
          stroke
            ..color = const Color(0xFF8CA275)
            ..strokeWidth = 3,
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(SouvenirPainter oldDelegate) => kind != oldDelegate.kind;
}
