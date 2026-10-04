import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/drive/navigation_location_filter.dart';

void main() {
  const home = GeoPoint(-36.8485, 174.7633);

  NavigationLocationFix fix(
    GeoPoint point, {
    double accuracy = 8,
    double speed = 0,
    int seconds = 0,
  }) => NavigationLocationFix(
    point: point,
    accuracyMeters: accuracy,
    speedMetresPerSecond: speed,
    timestamp: DateTime(2026, 10, 3, 9).add(Duration(seconds: seconds)),
  );

  test('stationary navigation rejects a 100 metre indoor GPS jump', () {
    final filter = NavigationLocationFilter(
      anchor: home,
      clock: () => DateTime(2026, 10, 3, 9, 0, 4),
    );
    final drift = fix(
      const GeoPoint(-36.8476, 174.7633),
      accuracy: 22,
      speed: 0,
    );

    expect(filter.accept(drift), isNull);
    expect(filter.accepted, isNull);
  });

  test('accurate nearby stationary fixes are accepted and held', () {
    final filter = NavigationLocationFilter(
      anchor: home,
      clock: () => DateTime(2026, 10, 3, 9, 0, 4),
    );
    final first = fix(const GeoPoint(-36.84848, 174.76331), accuracy: 7);
    final jitter = fix(
      const GeoPoint(-36.84844, 174.76334),
      accuracy: 9,
      seconds: 1,
    );

    expect(filter.accept(first), isNull);
    expect(filter.accept(jitter), same(jitter));
  });

  test('one apparently accurate stationary fix does not release the puck', () {
    final filter = NavigationLocationFilter(
      clock: () => DateTime(2026, 10, 3, 9, 0, 4),
    );
    final first = fix(home, accuracy: 6, speed: 0);

    expect(filter.accept(first), isNull);
    expect(filter.accepted, isNull);
  });

  test('poor accuracy is rejected before it can move the puck', () {
    final filter = NavigationLocationFilter(
      anchor: home,
      clock: () => DateTime(2026, 10, 3, 9, 0, 4),
    );
    expect(
      filter.accept(fix(const GeoPoint(-36.8485, 174.7633), accuracy: 55)),
      isNull,
    );
  });

  test('plausible moving fixes remain accepted', () {
    final filter = NavigationLocationFilter(
      anchor: home,
      clock: () => DateTime(2026, 10, 3, 9, 0, 4),
    );
    final first = fix(home, accuracy: 6, speed: 10);
    final next = fix(
      const GeoPoint(-36.84805, 174.7633),
      accuracy: 7,
      speed: 12,
      seconds: 4,
    );

    expect(filter.accept(first), isNotNull);
    expect(filter.accept(next), isNotNull);
  });

  test('stale, future and duplicate fixes cannot move navigation', () {
    final now = DateTime(2026, 10, 3, 9);
    final filter = NavigationLocationFilter(clock: () => now);
    expect(filter.accept(fix(home, seconds: -15, speed: 10)), isNull);
    expect(filter.accept(fix(home, seconds: 6, speed: 10)), isNull);
    expect(filter.accept(fix(home, speed: 10)), isNotNull);
    expect(filter.accept(fix(home, speed: 10)), isNull);
  });

  test(
    'a stale anchor is replaced only after three precise consistent fixes',
    () {
      var now = DateTime(2026, 10, 3, 9);
      final filter = NavigationLocationFilter(anchor: home, clock: () => now);
      const actual = GeoPoint(-36.84795, 174.7633);
      for (var i = 0; i < 3; i++) {
        now = DateTime(2026, 10, 3, 9).add(Duration(seconds: i));
        final accepted = filter.accept(fix(actual, seconds: i, accuracy: 6));
        expect(accepted != null, i == 2);
      }
      expect(filter.accepted!.point, actual);
    },
  );

  test('navigation recovers from a GPS outage instead of holding forever', () {
    var now = DateTime(2026, 10, 3, 9);
    final filter = NavigationLocationFilter(anchor: home, clock: () => now);
    filter.accept(fix(home, speed: 10));
    const actual = GeoPoint(-36.84795, 174.7633);
    for (var i = 12; i < 15; i++) {
      now = DateTime(2026, 10, 3, 9).add(Duration(seconds: i));
      final accepted = filter.accept(fix(actual, seconds: i, accuracy: 6));
      expect(accepted != null, i == 14);
    }
    expect(filter.accepted!.point, actual);
  });

  test('a distant route origin cannot permanently block actual GPS', () {
    var now = DateTime(2026, 10, 3, 9);
    final filter = NavigationLocationFilter(anchor: home, clock: () => now);
    const actual = GeoPoint(-36.8114218, 174.6048637);
    for (var i = 0; i < 3; i++) {
      now = DateTime(2026, 10, 3, 9).add(Duration(seconds: i));
      final accepted = filter.accept(fix(actual, seconds: i, accuracy: 6));
      expect(accepted != null, i == 2);
    }
    expect(filter.accepted!.point, actual);
  });

  test('duplicate stationary samples cannot release the initial marker', () {
    final filter = NavigationLocationFilter(
      clock: () => DateTime(2026, 10, 3, 9),
    );
    expect(filter.accept(fix(home)), isNull);
    expect(filter.accept(fix(home)), isNull);
  });

  test(
    'confirmed fresh browse fix transfers without another stationary wait',
    () {
      final now = DateTime(2026, 10, 3, 9);
      final filter = NavigationLocationFilter(clock: () => now);
      final reliable = fix(home, seconds: -1, accuracy: 7);
      filter.reset(anchor: home, trustedFix: reliable);
      final next = fix(home, accuracy: 8);
      expect(filter.accept(next), same(next));
    },
  );

  test(
    'stale and imprecise transferred fixes cannot bypass GPS validation',
    () {
      final now = DateTime(2026, 10, 3, 9);
      for (final seed in [fix(home, seconds: -11), fix(home, accuracy: 80)]) {
        final filter = NavigationLocationFilter(clock: () => now);
        filter.reset(anchor: home, trustedFix: seed);
        expect(filter.accepted, isNull);
        expect(filter.accept(fix(home)), isNull);
      }
    },
  );

  test(
    'returning after a long background gap can reacquire a different city',
    () {
      var now = DateTime(2026, 10, 3, 9);
      final filter = NavigationLocationFilter(clock: () => now);
      filter.accept(fix(home, speed: 10));
      const actual = GeoPoint(-41.2866, 174.7756);
      for (var i = 3600; i < 3603; i++) {
        now = DateTime(2026, 10, 3, 9).add(Duration(seconds: i));
        final accepted = filter.accept(fix(actual, seconds: i, accuracy: 6));
        expect(accepted != null, i == 3602);
      }
      expect(filter.accepted!.point, actual);
    },
  );
}
