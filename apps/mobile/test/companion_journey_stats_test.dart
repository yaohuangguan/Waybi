import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/widgets/companion_journey_stats.dart';
import 'package:waybi_mobile/widgets/trips_page.dart';

void main() {
  const place = TripDestination(
    name: 'Piha',
    location: GeoPoint(-36.954, 174.469),
  );

  test(
    'totals recorded routes and guest kilometres without inventing distance',
    () {
      final snapshot = TripsSnapshot(
        quickPlaces: const {},
        quickRoutes: const {},
        recent: const [],
        history: const [
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
          TripHistoryItem(
            destination: place,
            mode: 'drive',
            distanceMeters: -500,
            durationSeconds: -120,
          ),
        ],
        guestDistanceMeters: 2500,
        guestTripCount: 2,
        guestDurationSeconds: 3000,
      );
      final stats = CompanionJourneyStats.fromSnapshot(snapshot);
      expect(stats.distanceMeters, 53500);
      expect(stats.kilometres, '53.5');
      expect(stats.tripCount, 5);
      expect(stats.durationSeconds, 7800);
      expect(stats.hours, '2.2');
    },
  );

  test('empty history uses zero, not a fabricated journey', () {
    final stats = CompanionJourneyStats.fromSnapshot(null);
    expect(stats.distanceMeters, 0);
    expect(stats.tripCount, 0);
    expect(stats.kilometres, '0.0');
  });
}
