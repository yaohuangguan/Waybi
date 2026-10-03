import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/drive/journey_tracker.dart';

void main() {
  final start = DateTime(2026, 10, 1);
  const target = GeoPoint(-36.85, 174.76);
  JourneyTracker tracker() => JourneyTracker(
    target: target,
    destination: 'Waybi Cafe',
    startedAt: start,
  );
  test(
    'arrival requires two fresh fixes inside the exact ten metre radius',
    () {
      final trip = tracker();
      expect(
        trip.update(
          const GeoPoint(-36.85014, 174.76),
          accuracyMeters: 5,
          time: start,
        ),
        isFalse,
      );
      expect(
        trip.update(
          target,
          accuracyMeters: 5,
          time: start.add(const Duration(seconds: 1)),
        ),
        isFalse,
      );
      expect(
        trip.update(
          target,
          accuracyMeters: 5,
          time: start.add(const Duration(seconds: 2)),
        ),
        isTrue,
      );
      trip.finish(arrived: true);
      expect(
        trip.update(
          target,
          accuracyMeters: 5,
          time: start.add(const Duration(seconds: 3)),
        ),
        isFalse,
      );
    },
  );
  test('bad accuracy, duplicate and stale fixes cannot trigger arrival', () {
    final trip = tracker();
    expect(trip.update(target, accuracyMeters: 100, time: start), isFalse);
    expect(
      trip.update(
        target,
        accuracyMeters: 5,
        time: start.subtract(const Duration(seconds: 30)),
      ),
      isFalse,
    );
    expect(trip.update(target, accuracyMeters: 5, time: start), isFalse);
    expect(trip.update(target, accuracyMeters: 5, time: start), isFalse);
    expect(
      trip.update(
        target,
        accuracyMeters: 5,
        time: start.add(const Duration(seconds: 1)),
      ),
      isFalse,
    );
  });
  test(
    'arrival depends on exact GPS rather than a road-snapped SDK endpoint',
    () {
      final trip = tracker();
      expect(trip.update(target, accuracyMeters: 5, time: start), isFalse);
      expect(
        trip.update(
          target,
          accuracyMeters: 5,
          time: start.add(const Duration(seconds: 1)),
        ),
        isTrue,
      );
    },
  );
  test('summary records GPS distance and unique passed cameras', () {
    final trip = tracker();
    trip.update(
      const GeoPoint(-36.851, 174.76),
      accuracyMeters: 5,
      time: start,
    );
    trip.update(
      target,
      accuracyMeters: 5,
      time: start.add(const Duration(seconds: 10)),
    );
    trip.cameraPassed('a');
    trip.cameraPassed('a');
    trip.cameraPassed('b');
    final summary = trip.finish(
      arrived: true,
      time: start.add(const Duration(seconds: 20)),
    );
    expect(summary.distanceMeters, closeTo(111.2, 1));
    expect(summary.elapsed.inSeconds, 20);
    expect(summary.cameraCount, 2);
    expect(summary.points.length, 2);
    expect(() => summary.points.clear(), throwsUnsupportedError);
  });
}
