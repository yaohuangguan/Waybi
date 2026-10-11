import 'dart:math' as math;

import '../domain/geo_math.dart';
import '../domain/map_provider.dart';
import 'trips_page.dart';

String destinationIdentity(TripDestination place) =>
    '${place.name.trim().toLowerCase()}:${place.location.latitude.toStringAsFixed(4)}:${place.location.longitude.toStringAsFixed(4)}';

List<TripHistoryItem> rediscoveryPlaces(List<TripHistoryItem> history) {
  final latest = <String, TripHistoryItem>{};
  for (final trip in history) {
    final key = destinationIdentity(trip.destination);
    final previous = latest[key];
    if (previous == null ||
        (trip.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).isAfter(
          previous.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        )) {
      latest[key] = trip;
    }
  }
  return latest.values.toList()..sort(
    (a, b) => (a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
      b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    ),
  );
}

Map<int, int> visitedDirectionCounts(
  GeoPoint? origin,
  List<TripHistoryItem> history,
) {
  if (origin == null) return const {};
  final counts = <int, int>{0: 0, 1: 0, 2: 0, 3: 0};
  final cells = <String>{};
  for (final trip in history) {
    final p = trip.destination.location;
    if (distanceMeters(
          origin.latitude,
          origin.longitude,
          p.latitude,
          p.longitude,
        ) <
        500) {
      continue;
    }
    final cell = '${(p.latitude * 50).round()}:${(p.longitude * 50).round()}';
    if (!cells.add(cell)) continue;
    final bearing = bearingDegrees(
      origin.latitude,
      origin.longitude,
      p.latitude,
      p.longitude,
    );
    final sector = ((bearing + 45) ~/ 90) % 4;
    counts[sector] = counts[sector]! + 1;
  }
  return counts;
}

int? leastVisitedDirection(Map<int, int> counts) {
  if (counts.isEmpty || counts.values.every((count) => count == 0)) return null;
  var best = 0;
  for (var i = 1; i < 4; i++) {
    if (counts[i]! < counts[best]!) best = i;
  }
  return best;
}

GeoPoint directionSearchCenter(GeoPoint origin, int sector) {
  const angularDistance = 8000 / 6371008.8;
  final bearing = sector * math.pi / 2;
  final latitude = origin.latitude * math.pi / 180;
  final longitude = origin.longitude * math.pi / 180;
  final lat = math.asin(
    math.sin(latitude) * math.cos(angularDistance) +
        math.cos(latitude) * math.sin(angularDistance) * math.cos(bearing),
  );
  final lon =
      longitude +
      math.atan2(
        math.sin(bearing) * math.sin(angularDistance) * math.cos(latitude),
        math.cos(angularDistance) - math.sin(latitude) * math.sin(lat),
      );
  return GeoPoint(lat * 180 / math.pi, (lon * 180 / math.pi + 540) % 360 - 180);
}
