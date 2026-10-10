import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/navigation_lanes.dart';
import 'package:waybi_mobile/widgets/lane_arrow.dart';
import 'package:waybi_mobile/widgets/navigation_maneuver_icon.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('multi-direction lane is one connected pavement arrow with one stem', () async {
    const directions = {
      LaneArrowDirection.straight,
      LaneArrowDirection.left,
      LaneArrowDirection.right,
    };
    final recorder = ui.PictureRecorder();
    const LaneArrowPainter(
      directions,
      Colors.black,
    ).paint(Canvas(recorder), const Size(96, 96));
    final picture = recorder.endRecording();
    final image = await picture.toImage(96, 96);
    final bytes = (await image.toByteData())!.buffer.asUint8List();
    final pixels = <int>{
      for (var i = 0; i < 96 * 96; i++)
        if (bytes[i * 4 + 3] > 128) i,
    };
    // All arrowheads connect to the incoming stem, unlike adjacent text arrows.
    final reached = <int>{};
    final queue = [pixels.first];
    while (queue.isNotEmpty) {
      final pixel = queue.removeLast();
      if (!reached.add(pixel)) continue;
      for (final next in [
        pixel - 96,
        pixel + 96,
        if (pixel % 96 > 0) pixel - 1,
        if (pixel % 96 < 95) pixel + 1,
      ]) {
        if (pixels.contains(next) && !reached.contains(next)) queue.add(next);
      }
    }
    expect(reached.length, pixels.length);
    expect(
      pixels,
      containsAll([9 * 96 + 48, 36 * 96 + 9, 36 * 96 + 87, 81 * 96 + 48]),
    );
    expect(
      pixels.where((p) => p ~/ 96 == 81).every((p) => (p % 96 - 48).abs() <= 6),
      true,
    );
    image.dispose();
    picture.dispose();
  });

  test('native and OSRM exits use the same vector family and correct side', () {
    expect(
      navigationManeuverIcon('off ramp', 'slight left'),
      Icons.ramp_left_rounded,
    );
    expect(
      navigationManeuverIcon('offRampSlightLeft'),
      Icons.ramp_left_rounded,
    );
    expect(
      navigationManeuverIcon('off ramp', 'right'),
      Icons.ramp_right_rounded,
    );
    expect(
      navigationManeuverIcon('fork', 'slight right'),
      Icons.fork_right_rounded,
    );
    expect(
      navigationManeuverIcon('turn', 'slight left'),
      Icons.turn_slight_left_rounded,
    );
    expect(
      navigationManeuverIcon('turn', 'sharp right'),
      Icons.turn_sharp_right_rounded,
    );
    expect(navigationManeuverIcon('uTurnRight'), Icons.u_turn_right_rounded);
    expect(
      navigationManeuverIcon('off ramp', 'left').fontFamily,
      'MaterialIcons',
    );
  });

  testWidgets('lane glyph has spoken directions without any character arrows', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: LaneArrow(
            directions: {LaneArrowDirection.straight, LaneArrowDirection.left},
            color: Colors.black,
            language: 'zh',
          ),
        ),
      ),
    );
    expect(find.byType(Text), findsNothing);
    expect(find.bySemanticsLabel('直行或左转'), findsOneWidget);
  });

  test('render pavement arrow review sheet when requested', () async {
    final output = Platform.environment['WAYBI_NAV_PREVIEW'];
    if (output == null) return;
    final samples = [
      for (final direction in LaneArrowDirection.values) {direction},
      {LaneArrowDirection.straight, LaneArrowDirection.left},
      {LaneArrowDirection.straight, LaneArrowDirection.right},
      {
        LaneArrowDirection.straight,
        LaneArrowDirection.left,
        LaneArrowDirection.right,
      },
    ];
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawColor(const Color(0xFFF6F7F0), BlendMode.src);
    for (var i = 0; i < samples.length; i++) {
      canvas.save();
      canvas.translate(24.0 + i % 6 * 116, 24.0 + i ~/ 6 * 120);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, 92, 96),
          const Radius.circular(16),
        ),
        Paint()..color = const Color(0xFFD0F58A),
      );
      canvas.translate(14, 16);
      LaneArrowPainter(
        samples[i],
        const Color(0xFF20351C),
      ).paint(canvas, const Size(64, 64));
      canvas.restore();
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(720, 264);
    await File(output).writeAsBytes(
      (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
          .asUint8List(),
    );
    image.dispose();
    picture.dispose();
  });
}
