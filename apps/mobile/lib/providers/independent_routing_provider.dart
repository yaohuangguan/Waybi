import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

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
    final driving = _sensibleDrivingAlternatives(
      await _fetchMode(points, mode: KiwiTravelMode.drive, language: language),
    );
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

  List<RouteOption> _sensibleDrivingAlternatives(List<RouteOption> routes) {
    if (routes.length <= 1) return routes;
    final fastest = routes
        .map((route) => route.durationSeconds)
        .reduce((a, b) => a < b ? a : b);
    final shortest = routes
        .map((route) => route.distanceMeters)
        .reduce((a, b) => a < b ? a : b);
    final filtered = routes
        .where(
          (route) =>
              route.durationSeconds <= fastest * 1.30 &&
              route.distanceMeters <= shortest * 1.35,
        )
        .take(3)
        .toList(growable: false);
    return filtered.isEmpty ? [routes.first] : filtered;
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
