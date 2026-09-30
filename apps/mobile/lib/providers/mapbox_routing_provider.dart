import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/map_provider.dart';
import '../domain/route_option.dart';
import 'provider_contracts.dart';

class MapboxRoutingProvider implements RoutingProvider<RoutePlan> {
  MapboxRoutingProvider(this.accessToken, {http.Client? client})
    : _client = client ?? http.Client();
  final String accessToken;
  final http.Client _client;

  @override
  Future<RoutePlan> route({
    required GeoPoint origin,
    required GeoPoint destination,
    List<GeoPoint> stops = const [],
    required String language,
  }) async {
    final points = _validatedPoints(origin, destination, stops);
    final responses = await Future.wait([
      _fetchMode(points, mode: KiwiTravelMode.drive, language: language),
      _optionalMode(points, KiwiTravelMode.walk, language),
      _optionalMode(points, KiwiTravelMode.bicycle, language),
    ]);
    final options = responses.expand((item) => item).toList(growable: false);
    if (options.isEmpty) throw StateError('No Mapbox routes available');
    return RoutePlan(
      options: options,
      trafficAvailable: false,
      provider: 'mapbox',
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
    if (accessToken.isEmpty) throw StateError('Mapbox token is not configured');
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
    // NZ is outside documented driving-traffic coverage.
    final profile = switch (mode) {
      KiwiTravelMode.drive => 'driving',
      KiwiTravelMode.walk => 'walking',
      KiwiTravelMode.bicycle => 'cycling',
      KiwiTravelMode.transit => throw ArgumentError(
        'Mapbox has no transit profile',
      ),
    };
    final response = await _client
        .get(
          Uri.https('api.mapbox.com', '/directions/v5/mapbox/$profile/$path', {
            'access_token': accessToken,
            'geometries': 'geojson',
            'overview': 'full',
            'alternatives': alternatives && points.length == 2
                ? 'true'
                : 'false',
            'steps': 'true',
            'language': language == 'zh' ? 'zh' : 'en',
            'banner_instructions': 'true',
            'voice_instructions': 'true',
            'voice_units': 'metric',
          }),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw StateError('Mapbox directions unavailable: ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['code'] != null && body['code'] != 'Ok') {
      throw StateError('Mapbox could not find a route');
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
            id: 'mapbox-${mode.name}-${entry.$1}',
            mode: mode,
            durationSeconds: (route['duration'] as num?)?.round() ?? 0,
            distanceMeters: (route['distance'] as num?)?.round() ?? 0,
            points: routePoints,
            waypoints: List.unmodifiable(points),
            provider: 'mapbox',
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

  void dispose() => _client.close();
}
