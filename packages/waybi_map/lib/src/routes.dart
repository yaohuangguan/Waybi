import 'geometry.dart';

class MapRoutePath {
  const MapRoutePath({
    required this.id,
    required this.points,
    this.active = false,
    this.traversed = false,
    this.trail = false,
  });

  final String id;
  final List<GeoPoint> points;
  final bool active;
  final bool traversed;
  final bool trail;
}
