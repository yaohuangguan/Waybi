import 'geometry.dart';

class MapRoutePath {
  const MapRoutePath({
    required this.id,
    required this.points,
    this.active = false,
    this.traversed = false,
    this.trail = false,
    this.revision,
    this.progressMeters,
    this.live = false,
  });

  final String id;
  final List<GeoPoint> points;
  final bool active;
  final bool traversed;
  final bool trail;

  /// Identity of [points]. Paths with the same [id] and a non-null revision
  /// are guaranteed to share geometry, so a renderer can compare and cache
  /// them in O(1) instead of comparing or hashing every point.
  final int? revision;

  /// For an active route: the first [progressMeters] have been driven. A
  /// renderer can draw that prefix as traversed without a split copy of the
  /// geometry, so the whole route need not be re-sent on every GPS fix.
  final double? progressMeters;

  /// Changes on nearly every update (the growing end of a trail). Renderers
  /// keep it out of their static route data and update it separately.
  final bool live;

  /// Whether [other] has the same geometry without comparing points.
  bool sameGeometry(MapRoutePath other) =>
      id == other.id &&
      (revision != null
          ? revision == other.revision
          : other.revision == null && identical(points, other.points));
}
