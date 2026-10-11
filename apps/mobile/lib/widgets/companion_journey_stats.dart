import 'trips_page.dart';

/// Recorded navigation only. Never infer distance from straight-line destinations.
class CompanionJourneyStats {
  const CompanionJourneyStats({
    required this.distanceMeters,
    required this.tripCount,
    required this.durationSeconds,
  });

  factory CompanionJourneyStats.fromSnapshot(TripsSnapshot? snapshot) {
    final history = snapshot?.history ?? const <TripHistoryItem>[];
    final recorded = CompanionJourneyStats.fromHistory(history);
    if (snapshot?.signedIn == true) {
      return CompanionJourneyStats(
        distanceMeters:
            snapshot?.lifetimeDistanceMeters ?? recorded.distanceMeters,
        tripCount: snapshot?.lifetimeTripCount ?? recorded.tripCount,
        durationSeconds:
            snapshot?.lifetimeDurationSeconds ?? recorded.durationSeconds,
      );
    }
    return CompanionJourneyStats(
      distanceMeters: snapshot?.guestDistanceMeters ?? 0,
      tripCount: snapshot?.guestTripCount ?? 0,
      durationSeconds: snapshot?.guestDurationSeconds ?? 0,
    );
  }

  factory CompanionJourneyStats.fromHistory(List<TripHistoryItem> history) {
    var distance = 0;
    var duration = 0;
    for (final trip in history) {
      if (trip.distanceMeters > 0) distance += trip.distanceMeters;
      if (trip.durationSeconds > 0) duration += trip.durationSeconds;
    }
    return CompanionJourneyStats(
      distanceMeters: distance,
      tripCount: history.length,
      durationSeconds: duration,
    );
  }

  final int distanceMeters;
  final int tripCount;
  final int durationSeconds;

  String get kilometres {
    final km = distanceMeters / 1000;
    return km < 100 ? km.toStringAsFixed(1) : km.round().toString();
  }

  String get hours => (durationSeconds / 3600).toStringAsFixed(1);
}
