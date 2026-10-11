import '../domain/geo_math.dart';
import '../domain/map_provider.dart';

/// Split at confirmed route progress, sharing the exact boundary coordinate.
List<MapRoutePath> navigationRoutePaths(
  String id,
  List<GeoPoint> points,
  double progressMeters,
) {
  if (points.length < 2) return const [];
  if (!progressMeters.isFinite || progressMeters <= 0) {
    return [MapRoutePath(id: id, points: points, active: true)];
  }
  var travelled = 0.0;
  for (var i = 1; i < points.length; i++) {
    final start = points[i - 1], end = points[i];
    final length = distanceMeters(
      start.latitude,
      start.longitude,
      end.latitude,
      end.longitude,
    );
    if (length > 0 && travelled + length > progressMeters) {
      final fraction = ((progressMeters - travelled) / length).clamp(0.0, 1.0);
      final longitudeDelta =
          (end.longitude - start.longitude + 540) % 360 - 180;
      final boundary = GeoPoint(
        start.latitude + (end.latitude - start.latitude) * fraction,
        (start.longitude + longitudeDelta * fraction + 540) % 360 - 180,
      );
      return [
        MapRoutePath(
          id: '$id:traversed',
          points: [...points.take(i), boundary],
          traversed: true,
        ),
        MapRoutePath(
          id: id,
          points: [boundary, ...points.skip(i)],
          active: true,
        ),
      ];
    }
    travelled += length;
  }
  return [MapRoutePath(id: '$id:traversed', points: points, traversed: true)];
}
