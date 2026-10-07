import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/geo_math.dart';
import 'package:waybi_mobile/widgets/discover_memory.dart';
import 'package:waybi_mobile/widgets/trips_page.dart';

void main() {
  TripHistoryItem visit(String name, GeoPoint location, int day) =>
      TripHistoryItem(
        destination: TripDestination(name: name, location: location),
        mode: 'drive',
        distanceMeters: 1000,
        durationSeconds: 100,
        createdAt: DateTime.utc(2026, 10, day),
      );
  test(
    'rediscovery uses the most recent visit rather than an old duplicate',
    () {
      const a = GeoPoint(-36.8, 174.7), b = GeoPoint(-36.9, 174.7);
      final places = rediscoveryPlaces([
        visit('Park', a, 1),
        visit('Beach', b, 5),
        visit('Park', a, 7),
      ]);
      expect(places.map((p) => p.destination.name), ['Beach', 'Park']);
      expect(places.last.createdAt, DateTime.utc(2026, 10, 7));
    },
  );
  test('empty history does not invent an unexplored direction; duplicate visits count once', () {
    const origin = GeoPoint(35, 139);
    expect(leastVisitedDirection(visitedDirectionCounts(origin, [])), isNull);
    final counts = visitedDirectionCounts(origin, [
      visit('Local', origin, 1),
      visit('North', const GeoPoint(35.1, 139), 1),
      visit('North', const GeoPoint(35.1, 139), 2),
    ]);
    expect(counts[0], 1);
    expect(leastVisitedDirection(counts), 1);
    final center = directionSearchCenter(origin, 1);
    expect(
      distanceMeters(
        origin.latitude,
        origin.longitude,
        center.latitude,
        center.longitude,
      ),
      closeTo(8000, 1),
    );
  });
}
