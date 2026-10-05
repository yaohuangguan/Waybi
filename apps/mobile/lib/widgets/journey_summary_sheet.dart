import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/map_provider.dart';
import '../drive/journey_tracker.dart';
import '../drive/navigation_language.dart';
import '../theme/waybi_theme.dart';
import 'waybi_bird.dart';
import 'navigation_feedback_card.dart';
import '../data/navigation_feedback_repository.dart';

import 'package:waybi_friends/waybi_friends.dart';

class JourneySummarySheet extends StatelessWidget {
  const JourneySummarySheet({
    super.key,
    required this.summary,
    required this.language,
    this.reward,
    this.feedback,
  });
  final JourneySummary summary;
  final String language;
  final Future<JourneyMemory?>? reward;
  final NavigationFeedbackRepository? feedback;
  String _text(String en, String zh) => language == 'zh' ? zh : en;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const WaybiBird(size: 82),
          const SizedBox(height: 12),
          Text(
            summary.arrived
                ? _text('You made it!', '到啦！')
                : _text('Journey complete', '本次导航已结束'),
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(summary.destination, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          Row(
            children: [
              _stat(
                _text('Travelled', '行驶距离'),
                navigationMetres(summary.distanceMeters, language),
              ),
              _stat(
                _text('Journey time', '行程用时'),
                '${math.max(1, summary.elapsed.inMinutes)} ${_text('min', '分钟')}',
              ),
              _stat(_text('Cameras passed', '经过摄像头'), '${summary.cameraCount}'),
            ],
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _text('Your journey at a glance', '这次走过的路'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: SizedBox(
              height: 185,
              width: double.infinity,
              child: CustomPaint(
                painter: JourneyOverviewPainter(summary.points),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _text('A little kiwi, a good journey.', '小 kiwi 陪你，又完成了一段旅程。'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          NavigationFeedbackCard(
            tripId: '${summary.startedAt.microsecondsSinceEpoch}',
            language: language,
            repository: feedback,
          ),
          if (reward != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: FutureBuilder<JourneyMemory?>(
                future: reward,
                builder: (context, snapshot) {
                  final memory = snapshot.data;
                  if (memory == null) return const SizedBox.shrink();
                  return Column(
                    children: [
                      SouvenirReward(memory: memory),
                      TextButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => FriendsPage(language: language),
                          ),
                        ),
                        icon: const Icon(Icons.pets_rounded),
                        label: Text(_text('Visit Waybi & Friends', '去看看伙伴')),
                      ),
                    ],
                  );
                },
              ),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_text('Keep exploring', '继续探索')),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _stat(String label, String value) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    ),
  );
}

/// An overview of the user's GPS trace, independent of map tiles.
class JourneyOverviewPainter extends CustomPainter {
  JourneyOverviewPainter(this.points);
  final List<GeoPoint> points;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..isAntiAlias = true
      ..color = WaybiColors.ice;
    canvas.drawRect(Offset.zero & size, paint);
    paint
      ..color = WaybiColors.lightBorder
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    if (points.isEmpty) return;
    final latitude = points.map((p) => p.latitude);
    final longitude = points.map((p) => p.longitude);
    final minLat = latitude.reduce(math.min),
        maxLat = latitude.reduce(math.max);
    final minLon = longitude.reduce(math.min),
        maxLon = longitude.reduce(math.max);
    final aspect = math
        .cos((minLat + maxLat) / 2 * math.pi / 180)
        .abs()
        .clamp(.01, 1);
    final spanX = (maxLon - minLon) * aspect, spanY = maxLat - minLat;
    final scale = math.min(
      (size.width - 48) / math.max(spanX, .00001),
      (size.height - 48) / math.max(spanY, .00001),
    );
    Offset project(GeoPoint p) => Offset(
      size.width / 2 + (p.longitude - (minLon + maxLon) / 2) * aspect * scale,
      size.height / 2 - (p.latitude - (minLat + maxLat) / 2) * scale,
    );
    final path = Path()
      ..moveTo(project(points.first).dx, project(points.first).dy);
    for (final p in points.skip(1)) {
      final point = project(p);
      path.lineTo(point.dx, point.dy);
    }
    paint
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 12
      ..color = Colors.white;
    canvas.drawPath(path, paint);
    paint
      ..strokeWidth = 7
      ..color = WaybiColors.ocean;
    canvas.drawPath(path, paint);
    paint
      ..style = PaintingStyle.fill
      ..color = WaybiColors.deepOcean;
    canvas.drawCircle(project(points.first), 7, paint);
    paint.color = WaybiColors.sky;
    canvas.drawCircle(project(points.last), 10, paint);
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = WaybiColors.deepOcean;
    canvas.drawCircle(project(points.last), 10, paint);
  }

  @override
  bool shouldRepaint(JourneyOverviewPainter oldDelegate) =>
      oldDelegate.points != points;
}
