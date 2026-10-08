import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/drive/navigation_location_filter.dart';
import 'package:waybi_mobile/drive/route_origin_location.dart';

void main() {
  final now = DateTime(2026, 10, 9, 10);
  const point = GeoPoint(-36.89291, 174.82898);
  NavigationLocationFix fix({
    double accuracy = 5,
    int age = 0,
    GeoPoint location = point,
  }) => NavigationLocationFix(
    point: location,
    accuracyMeters: accuracy,
    speedMetresPerSecond: 0,
    timestamp: now.subtract(Duration(seconds: age)),
  );
  test(
    'a stationary first fix can plan without releasing the navigation puck',
    () {
      final filter = NavigationLocationFilter(clock: () => now);
      final origin = RouteOriginLocation(clock: () => now);
      final observation = fix();
      final accepted = filter.accept(observation);
      expect(accepted, isNull);
      origin.update(observation, confirmed: accepted != null);
      expect(origin.point, point);
      expect(filter.accepted, isNull);
    },
  );
  test(
    'stale, imprecise and invalid OS coordinates cannot start a preview',
    () {
      for (final observation in [
        fix(age: 11),
        fix(accuracy: 55),
        fix(accuracy: double.nan),
        fix(location: const GeoPoint(100, 200)),
      ]) {
        final origin = RouteOriginLocation(clock: () => now)
          ..update(observation, confirmed: false);
        expect(origin.point, isNull);
      }
    },
  );
  test(
    'unconfirmed jumps do not replace a confirmed origin and old fixes expire',
    () {
      var time = now;
      final origin = RouteOriginLocation(clock: () => time)
        ..update(fix(), confirmed: true);
      origin.update(
        fix(location: const GeoPoint(-36.89, 174.83)),
        confirmed: false,
      );
      expect(origin.point, point);
      time = time.add(const Duration(seconds: 31));
      expect(origin.point, isNull);
    },
  );
}
