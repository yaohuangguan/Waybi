import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/geo_math.dart';
import 'package:waybi_mobile/drive/route_display.dart';
import 'package:waybi_mobile/drive/drive_trail.dart';
import 'package:waybi_mobile/drive/navigation_location_filter.dart';

void main() {
  const a = GeoPoint(-36.86, 174.76), b = GeoPoint(-36.85, 174.76);
  final length = distanceMeters(
    a.latitude,
    a.longitude,
    b.latitude,
    b.longitude,
  );
  NavigationLocationFix fix(GeoPoint p, int seconds) => NavigationLocationFix(
    point: p,
    accuracyMeters: 6,
    speedMetresPerSecond: 15,
    timestamp: DateTime(2026).add(Duration(seconds: seconds)),
  );
  test('past and future routes share the confirmed progress boundary', () {
    final paths = navigationRoutePaths('r', [a, b], length / 2);
    expect(paths.length, 2);
    expect(paths.first.traversed, isTrue);
    expect(paths.last.active, isTrue);
    expect(paths.first.points.last, paths.last.points.first);
    expect(paths.first.points.last.latitude, closeTo(-36.855, .000001));
    expect(paths.last.points.last, b);
  });
  test('route start and completion do not create a false future path', () {
    expect(navigationRoutePaths('r', [a, b], 0).single.active, isTrue);
    expect(
      navigationRoutePaths('r', [a, b], length + 1).single.traversed,
      isTrue,
    );
  });
  test('Just Drive trail clears on exit and never bridges a GPS outage', () {
    final trail = DriveTrail();
    const nearby = GeoPoint(-36.8598, 174.76);
    trail.add(fix(a, 0));
    trail.add(fix(nearby, 2));
    trail.add(fix(b, 60));
    expect(trail.paths.length, 1);
    expect(trail.paths.single.points, [a, nearby]);
    trail.add(fix(const GeoPoint(-36.8498, 174.76), 62));
    expect(trail.paths.length, 2);
    expect(trail.paths.every((p) => p.trail), isTrue);
    trail.clear();
    expect(trail.paths, isEmpty);
  });
  test('stationary noise does not grow the trail, and memory is bounded', () {
    final trail = DriveTrail(maxPoints: 3);
    trail.add(fix(a, 0));
    trail.add(fix(a, 1));
    expect(trail.paths, isEmpty);
    for (var i = 1; i <= 6; i++) {
      trail.add(fix(GeoPoint(a.latitude + i * .0002, a.longitude), i * 2));
    }
    expect(trail.paths.expand((p) => p.points).length, lessThanOrEqualTo(3));
  });
  test('route split follows the short path across the date line', () {
    const start = GeoPoint(-17, 179.9), end = GeoPoint(-17, -179.9);
    final distance = distanceMeters(
      start.latitude,
      start.longitude,
      end.latitude,
      end.longitude,
    );
    final paths = navigationRoutePaths('pacific', [start, end], distance / 2);
    expect(paths.first.points.last.longitude.abs(), closeTo(180, .000001));
  });
  test('fresh stationary samples do not disconnect a later trail movement', () {
    final trail = DriveTrail()..add(fix(a, 0));
    for (var i = 1; i <= 30; i++) {
      trail.add(fix(a, i));
    }
    const nearby = GeoPoint(-36.8598, 174.76);
    trail.add(fix(nearby, 32));
    expect(trail.paths.single.points, [a, nearby]);
  });
}
