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
    final first = tracker.update(const GeoPoint(-36.855, 174.76), time: now)!;
    final jitter = tracker.update(
      const GeoPoint(-36.8551, 174.76),
      time: now.add(const Duration(seconds: 1)),
    )!;
    expect(jitter.alongMeters, first.alongMeters);
  });
  test('driving backwards beyond the corridor exposes deviation', () {
    final tracker = RouteProgressTracker(const [
      GeoPoint(-36.86, 174.76),
      GeoPoint(-36.85, 174.76),
    ]);
    final now = DateTime(2026);
    tracker.update(const GeoPoint(-36.855, 174.76), time: now);
    final reversed = tracker.update(
      const GeoPoint(-36.856, 174.76),
      time: now.add(const Duration(seconds: 2)),
    )!;
    expect(reversed.offsetMeters, greaterThan(35));
  });
}
