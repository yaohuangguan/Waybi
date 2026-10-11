import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/widgets/companion_journey_stats.dart';
import 'package:waybi_mobile/widgets/trips_page.dart';

void main() {
  const place = TripDestination(
    name: 'Piha',
    location: GeoPoint(-36.954, 174.469),
  );
  const history = [
    TripHistoryItem(
      destination: place,
      mode: 'drive',
      distanceMeters: 42000,
      durationSeconds: 3600,
    ),
    TripHistoryItem(
      destination: place,
      mode: 'drive',
      distanceMeters: 9000,
      durationSeconds: 1200,
    ),
  ];

  test(
    'signed-in lifetime totals supersede 100-row history and ignore guest data',
    () {
      final snapshot = TripsSnapshot(
        quickPlaces: const {},
        quickRoutes: const {},
        recent: const [],
        history: history,
        signedIn: true,
        lifetimeDistanceMeters: 1253500,
        lifetimeTripCount: 145,
        lifetimeDurationSeconds: 252000,
        guestDistanceMeters: 2500,
        guestTripCount: 2,
        guestDurationSeconds: 3000,
      );
      final stats = CompanionJourneyStats.fromSnapshot(snapshot);
      expect(stats.distanceMeters, 1253500);
      expect(stats.kilometres, '1254');
      expect(stats.tripCount, 145);
      expect(stats.durationSeconds, 252000);
      expect(stats.hours, '70.0');
    },
  );

  test('guest sees locally recorded totals, not signed-in history', () {
    final snapshot = TripsSnapshot(
      quickPlaces: const {},
      quickRoutes: const {},
      recent: const [],
      history: history,
      guestDistanceMeters: 2500,
      guestTripCount: 2,
      guestDurationSeconds: 3000,
    );
    final stats = CompanionJourneyStats.fromSnapshot(snapshot);
    expect(stats.distanceMeters, 2500);
    expect(stats.kilometres, '2.5');
    expect(stats.tripCount, 2);
    expect(stats.hours, '0.8');
  });

  test('empty history uses zero, not a fabricated journey', () {
    final stats = CompanionJourneyStats.fromSnapshot(null);
    expect(stats.distanceMeters, 0);
    expect(stats.tripCount, 0);
    expect(stats.kilometres, '0.0');
  });
}
