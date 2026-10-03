import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import '../domain/geo_math.dart';
import '../domain/map_provider.dart';
import '../domain/route_option.dart';
import 'provider_contracts.dart';

class IndependentRoutingProvider implements RoutingProvider<RoutePlan> {
  IndependentRoutingProvider({http.Client? client})
    : _client = client ?? http.Client();
  DateTime? _lastRequest;
  Future<void> _queue = Future<void>.value();
  final http.Client _client;

  @override
  Future<RoutePlan> route({
    required GeoPoint origin,
    required GeoPoint destination,
    List<GeoPoint> stops = const [],
    required String language,
  }) async {
    final points = _validatedPoints(origin, destination, stops);
    var driving = await _fetchMode(
      points,
      mode: KiwiTravelMode.drive,
      language: language,
    );
    if (stops.isEmpty && driving.length < 3) {
      driving = await _supplementDrivingAlternatives(points, driving, language);
    }
    final responses = [
      driving,
      await _optionalMode(points, KiwiTravelMode.walk, language),
      await _optionalMode(points, KiwiTravelMode.bicycle, language),
    ];
    final options = responses.expand((item) => item).toList(growable: false);
    if (options.isEmpty) throw StateError('No Independent routes available');
    return RoutePlan(
      options: options,
      trafficAvailable: false,
      provider: 'independent',
      stopsApplied: stops.length,
    );
  }

  Future<List<RouteOption>> _optionalMode(
    List<GeoPoint> points,
    KiwiTravelMode mode,
    String language,
  ) async {
    try {
      return await _fetchMode(points, mode: mode, language: language);
    } catch (_) {
      return const [];
    }
  }

  Future<List<RouteOption>> _supplementDrivingAlternatives(
    List<GeoPoint> logicalPoints,
    List<RouteOption> existing,
    String language,
  ) async {
    if (logicalPoints.length != 2 || existing.length >= 3) {
      return existing.take(3).toList(growable: false);
    }
    final origin = logicalPoints.first;
    final destination = logicalPoints.last;
    final directMeters = distanceMeters(
      origin.latitude,
      origin.longitude,
      destination.latitude,
      destination.longitude,
    );
    final lateralMeters = (directMeters * .16).clamp(280.0, 1600.0);
    final forwardBearing = bearingDegrees(
      origin.latitude,
      origin.longitude,
      destination.latitude,
      destination.longitude,
    );
    final midpoint = GeoPoint(
      (origin.latitude + destination.latitude) / 2,
      (origin.longitude + destination.longitude) / 2,
    );
    final result = existing.take(3).toList(growable: true);
    final fastest = result
        .map((route) => route.durationSeconds)
        .reduce(math.min);
    final shortest = result
        .map((route) => route.distanceMeters)
        .reduce(math.min);

    for (final factor in [1.0, -1.0, 1.65, -1.65]) {
      if (result.length >= 3) break;
      final via = _destinationPoint(
        midpoint,
        forwardBearing + (factor > 0 ? 90 : -90),
        lateralMeters * factor.abs(),
      );
      try {
        final candidateRoutes = await _fetchMode(
          [origin, via, destination],
          mode: KiwiTravelMode.drive,
          language: language,
          alternatives: false,
        );
        if (candidateRoutes.isEmpty) continue;
        final candidate = candidateRoutes.first;
        if (candidate.durationSeconds > fastest * 1.40 ||
            candidate.distanceMeters > shortest * 1.48) {
          continue;
        }
        final distinct = result.every(
          (route) =>
              (route.distanceMeters - candidate.distanceMeters).abs() >= 120 ||
              (route.durationSeconds - candidate.durationSeconds).abs() >= 25 ||
              _routeMidpointDistance(route, candidate) >= 100,
        );
        if (!distinct) continue;
        result.add(
          RouteOption(
            id: 'independent-drive-${result.length}',
            mode: candidate.mode,
            durationSeconds: candidate.durationSeconds,
            distanceMeters: candidate.distanceMeters,
            points: candidate.points,
            provider: candidate.provider,
            traffic: candidate.traffic,
            trafficIntervals: candidate.trafficIntervals,
            staticDurationSeconds: candidate.staticDurationSeconds,
            trafficDelaySeconds: candidate.trafficDelaySeconds,
            routeToken: candidate.routeToken,
            description: candidate.description.isEmpty
                ? 'Alternative ${result.length + 1}'
                : candidate.description,
            labels: candidate.labels,
            warnings: candidate.warnings,
            transit: candidate.transit,
            steps: candidate.steps,
            // The generated shaping point is not a user stop and must not be
            // preserved during rerouting.
            waypoints: List.unmodifiable(logicalPoints),
          ),
        );
      } catch (_) {
        // Public OSRM may reject a shaping point. Try the opposite side.
      }
    }
    return result.take(3).toList(growable: false);
  }

  GeoPoint _destinationPoint(GeoPoint start, double bearing, double distance) {
    const earthRadius = 6371008.8;
    final angular = distance / earthRadius;
    final theta = bearing * math.pi / 180;
    final lat1 = start.latitude * math.pi / 180;
    final lon1 = start.longitude * math.pi / 180;
    final lat2 = math.asin(
      math.sin(lat1) * math.cos(angular) +
          math.cos(lat1) * math.sin(angular) * math.cos(theta),
    );
    final lon2 =
        lon1 +
        math.atan2(
          math.sin(theta) * math.sin(angular) * math.cos(lat1),
          math.cos(angular) - math.sin(lat1) * math.sin(lat2),
        );
    return GeoPoint(lat2 * 180 / math.pi, lon2 * 180 / math.pi);
  }

  double _routeMidpointDistance(RouteOption a, RouteOption b) {
    if (a.points.isEmpty || b.points.isEmpty) return double.infinity;
    final aPoint = a.points[a.points.length ~/ 2];
    final bPoint = b.points[b.points.length ~/ 2];
    return distanceMeters(
      aPoint.latitude,
      aPoint.longitude,
      bPoint.latitude,
      bPoint.longitude,
    );
  }

  Future<RouteOption> reroute({
    required GeoPoint origin,
    required GeoPoint destination,
    required KiwiTravelMode mode,
    List<GeoPoint> stops = const [],
    required String language,
  }) async {
    final options = await _fetchMode(
      _validatedPoints(origin, destination, stops),
      mode: mode,
      language: language,
      alternatives: false,
    );
    if (options.isEmpty) throw StateError('No route from current location');
    return options.first;
  }

  List<GeoPoint> _validatedPoints(
    GeoPoint origin,
    GeoPoint destination,
    List<GeoPoint> stops,
  ) {
    final points = [origin, ...stops, destination];
    if (points.length > 25 || points.any((point) => !point.isValid)) {
      throw ArgumentError('Routes require 2–25 valid coordinates');
    }
    return points;
  }

  Future<List<RouteOption>> _fetchMode(
    List<GeoPoint> points, {
    required KiwiTravelMode mode,
    required String language,
    bool alternatives = true,
  }) async {
    final path = points
        .map((point) => '${point.longitude},${point.latitude}')
        .join(';');
    final base = switch (mode) {
      KiwiTravelMode.drive => const String.fromEnvironment(
        'KIWI_OSRM_CAR_URL',
        defaultValue: 'https://routing.openstreetmap.de/routed-car',
      ),
      KiwiTravelMode.walk => const String.fromEnvironment(
        'KIWI_OSRM_FOOT_URL',
        defaultValue: 'https://routing.openstreetmap.de/routed-foot',
      ),
      KiwiTravelMode.bicycle => const String.fromEnvironment(
        'KIWI_OSRM_BIKE_URL',
        defaultValue: 'https://routing.openstreetmap.de/routed-bike',
      ),
      KiwiTravelMode.transit => throw ArgumentError(
        'Practice has no transit profile',
      ),
    };
    // These endpoints each use a separate graph, with the same OSRM profile name.
    final uri = Uri.parse('$base/route/v1/driving/$path').replace(
      queryParameters: {
        'geometries': 'geojson',
        'overview': 'full',
        'steps': 'true',
        'alternatives': alternatives && points.length == 2 ? '3' : 'false',
      },
    );
    final response = await _limitedGet(uri);
    if (response.statusCode != 200) {
      throw StateError(
        'Independent directions unavailable: ${response.statusCode}',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['code'] != null && body['code'] != 'Ok') {
      throw StateError('Independent could not find a route');
    }
    final routes = body['routes'] as List<dynamic>? ?? const [];
    return routes
        .whereType<Map<String, dynamic>>()
        .indexed
        .map((entry) {
          final route = entry.$2;
          final coordinates =
              (route['geometry'] as Map<String, dynamic>?)?['coordinates']
                  as List<dynamic>? ??
              const [];
          final routePoints = coordinates
              .whereType<List<dynamic>>()
              .where(
                (pair) => pair.length >= 2 && pair[0] is num && pair[1] is num,
              )
              .map(
                (pair) => GeoPoint(
                  (pair[1] as num).toDouble(),
                  (pair[0] as num).toDouble(),
                ),
              )
              .where((point) => point.isValid)
              .toList(growable: false);
          var along = 0.0;
          final steps = <RouteStepInfo>[];
          for (final leg
              in (route['legs'] as List<dynamic>? ?? const [])
                  .whereType<Map<String, dynamic>>()) {
            for (final step
                in (leg['steps'] as List<dynamic>? ?? const [])
                    .whereType<Map<String, dynamic>>()) {
              final maneuver =
                  step['maneuver'] as Map<String, dynamic>? ?? const {};
              final point = maneuver['location'] as List<dynamic>? ?? const [];
              final distance = (step['distance'] as num?)?.toDouble() ?? 0;
              final intersections =
                  (step['intersections'] as List<dynamic>? ?? const [])
                      .whereType<Map<String, dynamic>>();
              final laneData = intersections.isEmpty
                  ? const <dynamic>[]
                  : intersections.first['lanes'] as List<dynamic>? ?? const [];
              if (point.length >= 2 && point[0] is num && point[1] is num) {
                steps.add(
                  RouteStepInfo(
                    instruction: maneuver['instruction']?.toString() ?? '',
                    distanceMeters: distance.round(),
                    durationSeconds:
                        (step['duration'] as num?)?.toDouble() ?? 0,
                    alongRouteMeters: along,
                    maneuverType: maneuver['type']?.toString() ?? '',
                    maneuverModifier: maneuver['modifier']?.toString() ?? '',
                    roadName: step['name']?.toString() ?? '',
                    location: GeoPoint(
                      (point[1] as num).toDouble(),
                      (point[0] as num).toDouble(),
                    ),
                    lanes: laneData
                        .whereType<Map<String, dynamic>>()
                        .map(
                          (lane) => RouteLane(
                            indications:
                                (lane['indications'] as List<dynamic>? ??
                                        const [])
                                    .whereType<String>()
                                    .toList(),
                            recommended:
                                lane['active'] == true || lane['valid'] == true,
                          ),
                        )
                        .toList(growable: false),
                  ),
                );
              }
              along += distance;
            }
          }
          final summaries = (route['legs'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map((leg) => leg['summary']?.toString() ?? '')
              .where((summary) => summary.isNotEmpty)
              .join(' · ');
          return RouteOption(
            id: 'independent-${mode.name}-${entry.$1}',
            mode: mode,
            durationSeconds: (route['duration'] as num?)?.round() ?? 0,
            distanceMeters: (route['distance'] as num?)?.round() ?? 0,
            points: routePoints,
            waypoints: List.unmodifiable(points),
            provider: 'independent',
            traffic: const TrafficSummary(normal: 0, slow: 0, trafficJam: 0),
            trafficIntervals: const [],
            steps: steps,
            description: summaries.isNotEmpty
                ? summaries
                : entry.$1 == 0
                ? 'Fastest'
                : 'Alternative ${entry.$1}',
          );
        })
        .where(
          (option) => option.points.length >= 2 && option.distanceMeters > 0,
        )
        .toList(growable: false);
  }

  Future<http.Response> _limitedGet(Uri uri) {
    final task = _queue.then((_) async {
      final previous = _lastRequest;
      if (previous != null) {
        final wait = 1100 - DateTime.now().difference(previous).inMilliseconds;
        if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
      }
      _lastRequest = DateTime.now();
      return _client
          .get(
            uri,
            headers: {
              if (!kIsWeb)
                'User-Agent':
                    'KiwiLens/1.0 (+https://github.com/yaohuangguan/kiwi-lens)',
            },
          )
          .timeout(const Duration(seconds: 15));
    });
    _queue = task.then<void>((_) {}, onError: (Object _) {});
    return task;
  }

  void dispose() => _client.close();
}
