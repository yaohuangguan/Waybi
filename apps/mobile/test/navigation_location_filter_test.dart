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
    final filter = NavigationLocationFilter(anchor: home);
    final drift = fix(
      const GeoPoint(-36.8476, 174.7633),
      accuracy: 22,
      speed: 0,
    );

    expect(filter.accept(drift), isNull);
    expect(filter.accepted, isNull);
  });

  test('accurate nearby stationary fixes are accepted and held', () {
    final filter = NavigationLocationFilter(anchor: home);
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
    final filter = NavigationLocationFilter();
    final first = fix(home, accuracy: 6, speed: 0);

    expect(filter.accept(first), isNull);
    expect(filter.accepted, isNull);
  });

  test('poor accuracy is rejected before it can move the puck', () {
    final filter = NavigationLocationFilter(anchor: home);
    expect(
      filter.accept(fix(const GeoPoint(-36.8485, 174.7633), accuracy: 55)),
      isNull,
    );
  });

  test('plausible moving fixes remain accepted', () {
    final filter = NavigationLocationFilter(anchor: home);
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
}
