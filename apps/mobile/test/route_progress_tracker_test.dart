import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/drive/route_progress_tracker.dart';

void main() {
  test(
    'out-of-order and moderately inaccurate fixes cannot advance a turn',
    () {
      final tracker = RouteProgressTracker(const [
        GeoPoint(-36.86, 174.76),
        GeoPoint(-36.85, 174.76),
      ]);
      final now = DateTime(2026);
      final first = tracker.update(const GeoPoint(-36.859, 174.76), time: now)!;
      expect(
        tracker.update(
          const GeoPoint(-36.851, 174.76),
          time: now.subtract(const Duration(seconds: 1)),
        ),
        isNull,
      );
      expect(
        tracker.update(
          const GeoPoint(-36.851, 174.76),
          time: now.add(const Duration(seconds: 1)),
          accuracyMeters: 50,
        ),
        isNull,
      );
      final good = tracker.update(
        const GeoPoint(-36.8589, 174.76),
        time: now.add(const Duration(seconds: 2)),
      )!;
      expect(good.alongMeters - first.alongMeters, lessThan(20));
    },
  );
  test(
    'visible road projection follows curved geometry instead of GPS offset',
    () {
      final tracker = RouteProgressTracker(const [
        GeoPoint(-36.86, 174.76),
        GeoPoint(-36.859, 174.76),
        GeoPoint(-36.859, 174.761),
      ]);
      final now = DateTime(2026, 10, 3);
      final first = tracker.update(
        const GeoPoint(-36.8595, 174.7601),
        time: now,
        speedKph: 30,
      )!;
      expect(first.offsetMeters, greaterThan(5));
      expect(first.point!.longitude, closeTo(174.76, .000001));
      final bend = tracker.update(
        const GeoPoint(-36.85905, 174.7605),
        time: now.add(const Duration(seconds: 5)),
        speedKph: 30,
      )!;
      expect(bend.point!.latitude, closeTo(-36.859, .000001));
      expect(bend.bearingDegrees, closeTo(90, 1));
    },
  );

  test(
    'route crossing stays on current traversal instead of jumping ahead',
    () {
      final tracker = RouteProgressTracker(const [
        GeoPoint(-36.86, 174.76),
        GeoPoint(-36.85, 174.76),
        GeoPoint(-36.85, 174.761),
        GeoPoint(-36.86, 174.761),
        GeoPoint(-36.86, 174.76),
        GeoPoint(-36.85, 174.76),
      ]);
      final now = DateTime(2026);
      final first = tracker.update(const GeoPoint(-36.859, 174.76), time: now)!;
      final second = tracker.update(
        const GeoPoint(-36.8589, 174.76001),
        time: now.add(const Duration(seconds: 1)),
      )!;
      expect(second.alongMeters, greaterThanOrEqualTo(first.alongMeters));
      expect(second.alongMeters, lessThan(200));
    },
  );
  test('poor accuracy cannot advance route progress', () {
    final tracker = RouteProgressTracker(const [
      GeoPoint(-36.86, 174.76),
      GeoPoint(-36.85, 174.76),
    ]);
    final now = DateTime(2026);
    expect(
      tracker.update(
        const GeoPoint(-36.85, 174.76),
        time: now,
        accuracyMeters: 200,
      ),
      isNull,
    );
    final progress = tracker.update(const GeoPoint(-36.86, 174.76), time: now)!;
    expect(progress.alongMeters, closeTo(0, 1));
  });
  test('GPS jitter does not increase remaining distance', () {
    final tracker = RouteProgressTracker(const [
      GeoPoint(-36.86, 174.76),
      GeoPoint(-36.85, 174.76),
    ]);
    final now = DateTime(2026);
    // Progress starts at the route origin, then follows the car along it.
    tracker.update(const GeoPoint(-36.86, 174.76), time: now);
    final first = tracker.update(
      const GeoPoint(-36.855, 174.76),
      time: now.add(const Duration(seconds: 1)),
    )!;
    final jitter = tracker.update(
      const GeoPoint(-36.8551, 174.76),
      time: now.add(const Duration(seconds: 2)),
    )!;
    expect(jitter.alongMeters, first.alongMeters);
  });
  test('driving backwards beyond the corridor exposes deviation', () {
    final tracker = RouteProgressTracker(const [
      GeoPoint(-36.86, 174.76),
      GeoPoint(-36.85, 174.76),
    ]);
    final now = DateTime(2026);
    tracker.update(const GeoPoint(-36.86, 174.76), time: now);
    tracker.update(
      const GeoPoint(-36.855, 174.76),
      time: now.add(const Duration(seconds: 1)),
    );
    final reversed = tracker.update(
      const GeoPoint(-36.856, 174.76),
      time: now.add(const Duration(seconds: 3)),
    )!;
    expect(reversed.offsetMeters, greaterThan(35));
  });

  test(
    'the first fix of a new out-and-back route cannot snap to the return leg',
    () {
      // Out 500 m north on one carriageway, U-turn, and back 5 m to the east.
      final tracker = RouteProgressTracker(const [
        GeoPoint(-36.86, 174.76),
        GeoPoint(-36.8555, 174.76),
        GeoPoint(-36.8555, 174.76006),
        GeoPoint(-36.86, 174.76006),
      ]);
      final now = DateTime(2026);
      // Noise puts the first fix nearer the return carriageway.
      final first = tracker.update(
        const GeoPoint(-36.8598, 174.76005),
        time: now,
        accuracyMeters: 10,
      )!;
      expect(first.alongMeters, lessThan(150));
      expect(first.offsetMeters, lessThan(10));
      final next = tracker.update(
        const GeoPoint(-36.8594, 174.76001),
        time: now.add(const Duration(seconds: 2)),
        speedKph: 40,
      )!;
      expect(next.alongMeters, lessThan(150), reason: 'U-turn still ahead');
    },
  );

  test('the first-fix window widens with elapsed time and speed', () {
    final tracker = RouteProgressTracker(const [
      GeoPoint(-36.86, 174.76),
      GeoPoint(-36.85, 174.76),
    ]);
    final now = DateTime(2026);
    // 550 m along: outside the 170 m window for a fresh route.
    final early = tracker.update(
      const GeoPoint(-36.855, 174.76),
      time: now,
      speedKph: 50,
    )!;
    expect(early.offsetMeters, greaterThan(35));
    expect(tracker.committed, isNull);
    final later = tracker.update(
      const GeoPoint(-36.8549, 174.76),
      time: now.add(const Duration(seconds: 30)),
      speedKph: 50,
    )!;
    expect(later.offsetMeters, lessThan(5));
    expect(tracker.committed, isNotNull);
    expect(
      RouteProgressTracker.geometryLength(tracker.points),
      tracker.totalMeters,
    );
  });
}
