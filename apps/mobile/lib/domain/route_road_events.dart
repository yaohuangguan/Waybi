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
          match.offsetMeters > 35 ||
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
    if (best != null &&
        !(ramp &&
            RegExp(
              r'\b(?:on[ -]?ramp|off[ -]?ramp)\b',
              caseSensitive: false,
            ).hasMatch(event.roadName ?? '') &&
            !RegExp(
              r'\b(?:between|from|to)\b',
              caseSensitive: false,
            ).hasMatch(event.roadName ?? '') &&
            _onMainline(
              route,
              best.alongMeters,
              length,
              event.roadName ?? '',
            ))) {
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

bool _onMainline(
  RouteOption route,
  double along,
  double length,
  String rampName,
) {
  final total = route.steps.fold<double>(
    0,
    (sum, step) => sum + step.distanceMeters,
  );
  if (total <= 0) return false;
  var start = 0.0;
  for (final (index, step) in route.steps.indexed) {
    final end = start + step.distanceMeters * length / total;
    if (along >= start && along < end) {
      final type = step.maneuverType
          .replaceAll(RegExp(r'[^a-z]', caseSensitive: false), '')
          .toLowerCase();
      bool highway(String name) => RegExp(
        r'motorway|freeway|expressway|\b(?:SH|State Highway)\s*\d+',
        caseSensitive: false,
      ).hasMatch(name);
      final transfer =
          const ['onramp', 'offramp'].contains(type) &&
          index > 0 &&
          along - start > 35 &&
          highway(route.steps[index - 1].roadName) &&
          RegExp(
            r'\b(?:Rd|Road|St|Street|Dr|Drive|Ave|Avenue|Way)\b',
            caseSensitive: false,
          ).hasMatch(rampName);
      return highway(step.roadName) &&
          !RegExp(
            r'\b(?:on[ -]?ramp|off[ -]?ramp)\b',
            caseSensitive: false,
          ).hasMatch(step.roadName) &&
          (!const ['onramp', 'offramp', 'ramp'].contains(type) || transfer) &&
          (type != 'merge' || along - start > 35);
    }
    start = end;
  }
  return false;
}

/// Use the projected segment direction, not the signed motorway direction of
/// a curved ramp. The server validates this bounded set again after routing.
List<RouteExclusion> closureExclusions(
  RouteOption route,
  List<RoadEvent> events,
) {
  final exclusions = <RouteExclusion>[];
  for (final event in events.where(
    (e) => e.observation == RoadEventObservation.official,
  )) {
    for (final point
        in event.geometry.isEmpty ? [event.location] : event.geometry) {
      final projection = const RouteCameraMatcher().project(
        point,
        route.points,
      );
      if (projection?.point == null || projection!.offsetMeters > 35) continue;
      if (exclusions.any(
        (e) =>
            distanceMeters(
              e.location.latitude,
              e.location.longitude,
              projection.point!.latitude,
              projection.point!.longitude,
            ) <
            20,
      )) {
        continue;
      }
      exclusions.add(
        RouteExclusion(projection.point!, projection.bearingDegrees),
      );
      if (exclusions.length == 32) return exclusions;
    }
  }
  return exclusions;
}
