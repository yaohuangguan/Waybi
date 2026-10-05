import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import '../domain/map_provider.dart';
import '../domain/route_option.dart';
import 'provider_contracts.dart';

class IndependentRoutingProvider implements RoutingProvider<RoutePlan> {
  IndependentRoutingProvider({http.Client? client})
    : _client = client ?? http.Client();
  final _slots = <String, Future<void>>{};
  final _lastRequest = <String, DateTime>{};
  final _pending = <Uri, Future<http.Response>>{};
  final http.Client _client;

  @override
  Future<RoutePlan> route({
    required GeoPoint origin,
    required GeoPoint destination,
    List<GeoPoint> stops = const [],
    required String language,
    WaybiTravelMode? mode,
  }) async {
    final points = _validatedPoints(origin, destination, stops);
    final modes = mode == null
        ? [WaybiTravelMode.drive, WaybiTravelMode.walk, WaybiTravelMode.bicycle]
        : [mode];
    final responses = await Future.wait([
      for (final selected in modes)
        selected == WaybiTravelMode.drive
            ? _fetchMode(points, mode: selected, language: language)
            : _optionalMode(points, selected, language),
    ]);
    final options = responses.expand((item) => item).toList();
    if (modes.contains(WaybiTravelMode.drive)) {
      final driving = _sensibleDrivingAlternatives(
        options.where((route) => route.mode == WaybiTravelMode.drive).toList(),
      );
      options.removeWhere((route) => route.mode == WaybiTravelMode.drive);
      options.insertAll(0, driving);
    }
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
    WaybiTravelMode mode,
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
    final sorted = [...routes]
      ..sort((a, b) {
        final byTime = a.durationSeconds.compareTo(b.durationSeconds);
        return byTime != 0
            ? byTime
            : a.distanceMeters.compareTo(b.distanceMeters);
      });
    final fastest = sorted.first.durationSeconds;
    final fastestDistance = sorted.first.distanceMeters;
    final shortest = sorted
        .map((route) => route.distanceMeters)
        .reduce((a, b) => a < b ? a : b);
    final filtered = sorted
        .where((route) {
          final timeOk = route.durationSeconds <= fastest * 1.18;
          final distanceOk =
              route.distanceMeters <= shortest * 1.28 &&
              route.distanceMeters <= fastestDistance * 1.35;
          return timeOk && distanceOk;
        })
        .take(3)
        .toList(growable: false);
    return filtered.isEmpty ? [sorted.first] : filtered;
  }

  Future<RouteOption> reroute({
    required GeoPoint origin,
    required GeoPoint destination,
    required WaybiTravelMode mode,
    List<GeoPoint> stops = const [],
    required String language,
    double? headingDegrees,
  }) async {
    final options = await _fetchMode(
      _validatedPoints(origin, destination, stops),
      mode: mode,
      language: language,
      alternatives: false,
      headingDegrees: headingDegrees,
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
    required WaybiTravelMode mode,
    required String language,
    bool alternatives = true,
    double? headingDegrees,
  }) async {
    final path = points
        .map((point) => '${point.longitude},${point.latitude}')
        .join(';');
    final base = switch (mode) {
      WaybiTravelMode.drive => const String.fromEnvironment(
        'KIWI_OSRM_CAR_URL',
        defaultValue: 'https://routing.openstreetmap.de/routed-car',
      ),
      WaybiTravelMode.walk => const String.fromEnvironment(
        'KIWI_OSRM_FOOT_URL',
        defaultValue: 'https://routing.openstreetmap.de/routed-foot',
      ),
      WaybiTravelMode.bicycle => const String.fromEnvironment(
        'KIWI_OSRM_BIKE_URL',
        defaultValue: 'https://routing.openstreetmap.de/routed-bike',
      ),
      WaybiTravelMode.transit => throw ArgumentError(
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
        if (headingDegrees != null && headingDegrees.isFinite)
          'bearings': [
            '${(headingDegrees % 360).round() % 360},90',
            for (var i = 1; i < points.length; i++) '',
          ].join(';'),
      },
    );
    final response = await _limitedGet(
      uri,
      timeout: Duration(seconds: alternatives ? 10 : 8),
    );
    if (response.statusCode != 200) {
      throw StateError(
        'Independent directions unavailable: ${response.statusCode}',
      );
    }
    final body =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
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

  Future<http.Response> _limitedGet(Uri uri, {required Duration timeout}) {
    return _pending.putIfAbsent(uri, () {
      final request = _get(uri, timeout);
      unawaited(
        request.then<void>(
          (_) => _pending.remove(uri),
          onError: (Object _) {
            _pending.remove(uri);
          },
        ),
      );
      return request;
    });
  }

  Future<http.Response> _get(Uri uri, Duration timeout) async {
    // Reserve request starts per host, never wait for another request's network
    // response. A slow walking preview cannot hold up an urgent driving reroute.
    final slot = (_slots[uri.host] ?? Future<void>.value()).then((_) async {
      final previous = _lastRequest[uri.host];
      if (previous != null) {
        final wait = 1100 - DateTime.now().difference(previous).inMilliseconds;
        if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
      }
      _lastRequest[uri.host] = DateTime.now();
    });
    _slots[uri.host] = slot;
    await slot;
    return _client
        .get(
          uri,
          headers: {
            if (!kIsWeb)
              'User-Agent':
                  'Waybi/1.0 (+https://github.com/yaohuangguan/Waybi)',
          },
        )
        .timeout(timeout);
  }

  void dispose() => _client.close();
}
