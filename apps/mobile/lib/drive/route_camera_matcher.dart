import 'dart:math' as math;

import '../domain/geo_math.dart';
import '../domain/map_provider.dart';
import '../domain/route_geometry.dart';
import '../domain/route_option.dart';
import '../domain/safety_camera.dart';

class RouteProjection {
  const RouteProjection({
    required this.alongMeters,
    required this.offsetMeters,
    required this.bearingDegrees,
    this.point,
  });
  final double alongMeters;
  final double offsetMeters;
  final double bearingDegrees;
  final GeoPoint? point;
}

class RouteCameraMatch {
  const RouteCameraMatch({
    required this.camera,
    required this.alongMeters,
    required this.offsetMeters,
    required this.highConfidence,
    this.pass = 0,
  });
  final SafetyCamera camera;
  final double alongMeters;
  final double offsetMeters;
  final bool highConfidence;

  /// 0 for the first time the route passes this camera, 1 for the second…
  final int pass;

  /// Identity of this pass for alert de-duplication. The first pass keeps the
  /// camera id, so a reroute before the camera does not announce it again.
  String get alertKey => pass == 0 ? camera.id : '${camera.id}#${pass + 1}';

  RouteCameraMatch withPass(int value) => value == pass
      ? this
      : RouteCameraMatch(
          camera: camera,
          alongMeters: alongMeters,
          offsetMeters: offsetMeters,
          highConfidence: highConfidence,
          pass: value,
        );
}

/// A narrow route corridor limits alerts from adjacent roads. Only
/// high-confidence matches can trigger automatic speech.
class RouteCameraMatcher {
  const RouteCameraMatcher();

  RouteProjection? project(
    GeoPoint point,
    List<GeoPoint> route, {
    double minAlongMeters = 0,
    double maxAlongMeters = double.infinity,
    List<double>? cumulativeMeters,
    double? headingDegrees,
  }) {
    if (route.length < 2) return null;
    // Share one cumulative-distance array per route list instead of
    // re-measuring every segment with haversine on each projection.
    final cumulative = cumulativeMeters ?? RouteGeometry.of(route).cumulative;
    RouteProjection? best;
    var bestScore = double.infinity;
    var low = 0, high = cumulative.length - 1;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (cumulative[middle] < minAlongMeters) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    final firstSegment = math.max(0, low - 1);
    for (var index = firstSegment; index < route.length - 1; index++) {
      final travelled = cumulative[index];
      if (travelled > maxAlongMeters) break;
      final segmentLength = cumulative[index + 1] - travelled;
      if (segmentLength <= 0 || travelled + segmentLength < minAlongMeters) {
        continue;
      }
      final start = route[index];
      final end = route[index + 1];
      final latitudeRadians = (start.latitude + end.latitude) * math.pi / 360;
      final metresPerLongitude = 111320 * math.cos(latitudeRadians);
      const metresPerLatitude = 110540.0;
      final x = (point.longitude - start.longitude) * metresPerLongitude;
      final y = (point.latitude - start.latitude) * metresPerLatitude;
      final dx = (end.longitude - start.longitude) * metresPerLongitude;
      final dy = (end.latitude - start.latitude) * metresPerLatitude;
      final lengthSquared = dx * dx + dy * dy;
      final minFraction = ((minAlongMeters - travelled) / segmentLength).clamp(
        0.0,
        1.0,
      );
      final maxFraction = ((maxAlongMeters - travelled) / segmentLength).clamp(
        0.0,
        1.0,
      );
      final fraction = lengthSquared == 0
          ? 0.0
          : ((x * dx + y * dy) / lengthSquared).clamp(minFraction, maxFraction);
      final offsetX = x - fraction * dx, offsetY = y - fraction * dy;
      final offset = math.sqrt(offsetX * offsetX + offsetY * offsetY);
      final along = travelled + segmentLength * fraction;
      // The heading penalty is never negative, so a farther segment cannot win.
      // Skipping the bearing trigonometry keeps whole-route scans cheap.
      if (offset >= bestScore ||
          along < minAlongMeters ||
          along > maxAlongMeters) {
        continue;
      }
      final bearing = bearingDegrees(
        start.latitude,
        start.longitude,
        end.latitude,
        end.longitude,
      );
      final score =
          offset +
          (headingDegrees == null
              ? 0
              : angleDifference(headingDegrees, bearing) / 180 * 25);
      if (score < bestScore) {
        bestScore = score;
        best = RouteProjection(
          alongMeters: travelled + segmentLength * fraction,
          offsetMeters: offset,
          bearingDegrees: bearing,
          point: GeoPoint(
            start.latitude + (end.latitude - start.latitude) * fraction,
            start.longitude + (end.longitude - start.longitude) * fraction,
          ),
        );
      }
    }
    return best;
  }

  List<RouteCameraMatch> match(RouteOption route, List<SafetyCamera> cameras) {
    if (route.points.length < 2 || cameras.isEmpty) return const [];
    final geometry = RouteGeometry.of(route.points);
    final scale = route.distanceMeters > 0
        ? geometry.totalMeters / route.distanceMeters
        : 1.0;
    final positions = routeStepPositions(route, geometry);
    final stepPositions = [
      for (var i = 0; i < route.steps.length; i++)
        (
          road: route.steps[i].roadName.isNotEmpty
              ? route.steps[i].roadName
              : route.steps[i].instruction,
          begin: positions[i],
          length: route.steps[i].distanceMeters * scale,
        ),
    ];
    var south = 90.0, north = -90.0, west = 180.0, east = -180.0;
    for (final point in route.points) {
      south = math.min(south, point.latitude);
      north = math.max(north, point.latitude);
      west = math.min(west, point.longitude);
      east = math.max(east, point.longitude);
    }
    // ~65 m corridor plus margin; a camera outside the route box cannot match.
    const margin = .002;
    final longitudeMargin =
        margin /
        math.max(
          .2,
          math.cos(math.max(south.abs(), north.abs()) * math.pi / 180),
        );
    final matches = <RouteCameraMatch>[];
    for (final camera in cameras) {
      if (camera.latitude < south - margin ||
          camera.latitude > north + margin ||
          camera.longitude < west - longitudeMargin ||
          camera.longitude > east + longitudeMargin) {
        continue;
      }
      final point = GeoPoint(camera.latitude, camera.longitude);
      for (final projection in _passes(point, geometry)) {
        if (!_directionMatches(camera.location, projection.bearingDegrees)) {
          continue;
        }
        final sameRoad = stepPositions.any(
          (step) =>
              projection.alongMeters >= step.begin - 50 &&
              projection.alongMeters <= step.begin + step.length + 50 &&
              _roadMatches(camera.location, step.road),
        );
        final isRedLight = camera.type.toLowerCase().contains('red light');
        final maxOffset = sameRoad
            ? 65.0
            : isRedLight
            ? 18.0
            : 28.0;
        if (projection.offsetMeters > maxOffset) continue;
        matches.add(
          RouteCameraMatch(
            camera: camera,
            alongMeters: projection.alongMeters,
            offsetMeters: projection.offsetMeters,
            highConfidence:
                projection.offsetMeters <= 18 ||
                (sameRoad && projection.offsetMeters <= 40),
          ),
        );
      }
    }
    matches.sort((a, b) => a.alongMeters.compareTo(b.alongMeters));
    return [
      for (final match in matches)
        match.withPass(
          matches
              .where(
                (other) =>
                    other.camera.id == match.camera.id &&
                    other.alongMeters < match.alongMeters,
              )
              .length,
        ),
    ];
  }

  /// Every separate pass of the route by [point] (≥150 m apart along the
  /// route), nearest first. An out-and-back passes the same camera twice.
  List<RouteProjection> _passes(GeoPoint point, RouteGeometry geometry) {
    const separation = 150.0, corridor = 65.0;
    final passes = <RouteProjection>[];
    final windows = <(double, double)>[(0, double.infinity)];
    while (windows.isNotEmpty && passes.length < 4) {
      final (from, to) = windows.removeLast();
      if (to - from <= 0) continue;
      final best = geometry.project(
        point,
        minAlongMeters: from,
        maxAlongMeters: to,
      );
      if (best == null || best.offsetMeters > corridor) continue;
      // A window edge is not a pass: the road simply continues away from it.
      final atEdge =
          (from > 0 && best.alongMeters <= from + 1) ||
          (to.isFinite && best.alongMeters >= to - 1);
      if (!atEdge) passes.add(best);
      windows
        ..add((from, best.alongMeters - separation))
        ..add((best.alongMeters + separation, to));
    }
    passes.sort((a, b) => a.offsetMeters.compareTo(b.offsetMeters));
    return passes;
  }

  RouteCameraMatch? upcoming(
    GeoPoint position,
    List<GeoPoint> route,
    List<RouteCameraMatch> matches,
  ) {
    final progress = project(position, route);
    if (progress == null || progress.offsetMeters > 100) return null;
    for (final match in matches) {
      final ahead = match.alongMeters - progress.alongMeters;
      if (match.highConfidence && ahead >= -15 && ahead <= 1200) return match;
    }
    return null;
  }

  bool _directionMatches(String location, double routeBearing) {
    final value = location.toLowerCase();
    double? bearing;
    if (RegExp(r'\b(nb|northbound)\b').hasMatch(value)) bearing = 0;
    if (RegExp(r'\b(eb|eastbound)\b').hasMatch(value)) bearing = 90;
    if (RegExp(r'\b(sb|southbound)\b').hasMatch(value)) bearing = 180;
    if (RegExp(r'\b(wb|westbound)\b').hasMatch(value)) bearing = 270;
    return bearing == null || angleDifference(bearing, routeBearing) <= 55;
  }

  bool _roadMatches(String cameraLocation, String instruction) {
    final cameraRoad = _normalise(
      cameraLocation.split(RegExp(r'\band\b|/')).first,
    );
    return cameraRoad.length >= 3 &&
        _normalise(instruction).contains(cameraRoad);
  }

  String _normalise(String value) => value
      .toLowerCase()
      .replaceAllMapped(
        RegExp(r'state highway\s*(\d+)'),
        (match) => 'sh${match.group(1) ?? ''}',
      )
      .replaceAll(
        RegExp(
          r'\b(road|rd|street|st|avenue|ave|drive|dr|lane|ln|camera|northbound|southbound|eastbound|westbound|nb|sb|eb|wb)\b',
        ),
        '',
      )
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}
