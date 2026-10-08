import '../drive/route_camera_matcher.dart';
import 'geo_math.dart';
import 'road_event.dart';
import 'route_option.dart';

/// Match official and reported closures against the whole remaining route,
/// rather than only the 1.5 km window used by driving announcements.
List<RoadEvent> routeClosures(
  RouteOption route,
  List<RoadEvent> events, {
  double progressMeters = 0,
  DateTime? now,
}) {
  if (route.mode != WaybiTravelMode.drive || route.points.length < 2) {
    return const [];
  }
  final at = now ?? DateTime.now();
  const matcher = RouteCameraMatcher();
  final cumulative = <double>[0];
  for (var i = 1; i < route.points.length; i++) {
    final a = route.points[i - 1], b = route.points[i];
    cumulative.add(
      cumulative.last +
          distanceMeters(a.latitude, a.longitude, b.latitude, b.longitude),
    );
  }
  final length = cumulative.last;
  if (length <= 0) return const [];
  final west = route.points
      .map((p) => p.longitude)
      .reduce((a, b) => a < b ? a : b);
  final east = route.points
      .map((p) => p.longitude)
      .reduce((a, b) => a > b ? a : b);
  final south = route.points
      .map((p) => p.latitude)
      .reduce((a, b) => a < b ? a : b);
  final north = route.points
      .map((p) => p.latitude)
      .reduce((a, b) => a > b ? a : b);
  final seen = <String>{}, matches = <RoadEvent>[];
  for (final event in events) {
    if (event.type != RoadEventType.roadClosure ||
        event.confidence < .5 ||
        event.observation == RoadEventObservation.inferred ||
        !seen.add(event.id)) {
      continue;
    }
    final points = event.geometry.isEmpty ? [event.location] : event.geometry;
    final ramp =
        RegExp(
          r'\b(?:on[ -]?ramp|off[ -]?ramp)\b',
          caseSensitive: false,
        ).hasMatch(
          [
            event.roadName,
            event.metadata['description'],
            event.metadata['comments'],
          ].join(' '),
        );
    RouteProjection? best;
    for (final p in points) {
      if (!p.isValid ||
          p.longitude < west - .01 ||
          p.longitude > east + .01 ||
          p.latitude < south - .002 ||
          p.latitude > north + .002) {
        continue;
      }
      final match = matcher.project(
        p,
        route.points,
        cumulativeMeters: cumulative,
        minAlongMeters: progressMeters - 15,
      );
      if (match == null ||
          match.offsetMeters > 65 ||
          match.alongMeters < progressMeters - 15) {
        continue;
      }
      if (!ramp &&
          event.headingDegrees != null &&
          angleDifference(event.headingDegrees!, match.bearingDegrees) > 55) {
        continue;
      }
      final arrival = at.add(
        Duration(
          seconds:
              (route.durationSeconds *
                      ((match.alongMeters - progressMeters) / length).clamp(
                        0,
                        1,
                      ))
                  .round(),
        ),
      );
      // Include a scheduled closure that will begin before we reach it, but
      // never keep an expired incident merely because it matches geometrically.
      if (!event.isCurrent(at) && !event.isCurrent(arrival)) continue;
      if (best == null || match.alongMeters < best.alongMeters) best = match;
    }
    if (best != null) {
      matches.add(
        event.withDistance(
          fromDriver: best.alongMeters - progressMeters,
          alongRoute: best.alongMeters - progressMeters,
        ),
      );
    }
  }
  matches.sort(
    (a, b) => a.distanceAlongRoute!.compareTo(b.distanceAlongRoute!),
  );
  return matches;
}
