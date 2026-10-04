import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/drive/navigation_location_filter.dart';
import 'package:waybi_mobile/drive/navigation_motion.dart';

NavigationLocationFix fix(
  double latitude,
  double longitude,
  int seconds, {
  double speed = 0,
  double accuracy = 5,
}) => NavigationLocationFix(
  point: GeoPoint(latitude, longitude),
  accuracyMeters: accuracy,
  speedMetresPerSecond: speed,
  timestamp: DateTime(2026).add(Duration(seconds: seconds)),
);

void main() {
  test('frequent small movements accumulate and stopped estimates expire', () {
    final motion = NavigationMotionEstimator();
    NavigationMotion? moving;
    for (var i = 0; i <= 12; i++) {
      moving = motion.update(
        NavigationLocationFix(
          point: GeoPoint(-36.85 + i * .000024, 174.76),
          accuracyMeters: 5,
          speedMetresPerSecond: 0,
          timestamp: DateTime(2026).add(Duration(milliseconds: i * 200)),
        ),
      );
    }
    expect(moving!.speedMetresPerSecond, inInclusiveRange(12, 14));
    expect(moving.heading, closeTo(0, 1));
    final stopped = motion.update(
      NavigationLocationFix(
        point: const GeoPoint(-36.849712, 174.76),
        accuracyMeters: 5,
        speedMetresPerSecond: 0,
        timestamp: DateTime(2026).add(const Duration(seconds: 5)),
      ),
    );
    expect(stopped.speedMetresPerSecond, 0);
  });
  test(
    'consistent moving fixes recover speed and course when OS reports zero',
    () {
      final motion = NavigationMotionEstimator();
      expect(motion.update(fix(-36.85, 174.76, 0)).speedMetresPerSecond, 0);
      expect(motion.update(fix(-36.84988, 174.76, 1)).speedMetresPerSecond, 0);
      final moving = motion.update(fix(-36.84976, 174.76, 2));
      expect(moving.speedMetresPerSecond, inInclusiveRange(12, 14));
      expect(moving.heading, closeTo(0, 1));
    },
  );
  test('stationary jitter and alternating jumps do not create motion', () {
    final motion = NavigationMotionEstimator();
    for (var i = 0; i < 6; i++) {
      final m = motion.update(fix(-36.85 + (i.isEven ? 0 : .00004), 174.76, i));
      expect(m.speedMetresPerSecond, 0);
    }
    motion.reset();
    for (var i = 0; i < 6; i++) {
      final m = motion.update(fix(-36.85 + (i.isEven ? 0 : .0003), 174.76, i));
      expect(m.speedMetresPerSecond, 0);
    }
  });
  test(
    'bad accuracy, duplicates and an outage cannot manufacture travel speed',
    () {
      final motion = NavigationMotionEstimator();
      motion.update(fix(-36.85, 174.76, 0));
      motion.update(fix(-36.84988, 174.76, 1));
      expect(motion.update(fix(-36.84976, 174.76, 1)).speedMetresPerSecond, 0);
      expect(
        motion
            .update(fix(-36.84964, 174.76, 2, accuracy: 80))
            .speedMetresPerSecond,
        0,
      );
      expect(motion.update(fix(-36.84, 174.76, 30)).speedMetresPerSecond, 0);
    },
  );
  test('reported walking motion is usable and missing course stays absent', () {
    final motion = NavigationMotionEstimator();
    final moving = motion.update(fix(-36.85, 174.76, 0, speed: 1), heading: 90);
    expect(moving.speedMetresPerSecond, 1);
    expect(moving.heading, 90);
    expect(
      motion.update(fix(-36.84998, 174.76, 1, speed: 1), heading: -1).heading,
      isNull,
    );
  });
}
