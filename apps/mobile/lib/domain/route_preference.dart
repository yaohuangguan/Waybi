import 'route_option.dart';

/// Prefer a comparable legal alternative to an unnecessary reversal. This
/// changes ranking only: the routing engine still owns access/turn restrictions.
double drivingManeuverPenalty(RouteOption route) {
  if (route.mode != WaybiTravelMode.drive) return 0;
  var reversals = 0;
  for (final step in route.steps) {
    final type = step.maneuverType.toLowerCase().replaceAll(
      RegExp(r'[^a-z]'),
      '',
    );
    final modifier = step.maneuverModifier.toLowerCase().replaceAll(
      RegExp(r'[^a-z]'),
      '',
    );
    if (type == 'depart' || type == 'arrive') continue;
    if (type.contains('uturn') || modifier.contains('uturn')) reversals++;
  }
  return (reversals.clamp(0, 2) * 90).toDouble();
}

class RoutePreferenceSummary {
  const RoutePreferenceSummary({
    this.cameraCount = 0,
    this.congestionScore = 0,
  });

  final int cameraCount;
  final int congestionScore;
}

class RoutePreferenceAssessment {
  const RoutePreferenceAssessment({
    required this.score,
    required this.recommended,
    required this.fastest,
    required this.shortest,
    required this.leastTraffic,
    required this.zeroCameras,
  });

  final double score;
  final bool recommended;
  final bool fastest;
  final bool shortest;
  final bool leastTraffic;
  final bool zeroCameras;
}

Map<String, RoutePreferenceAssessment> assessRoutePreferences(
  List<RouteOption> routes,
  Map<String, RoutePreferenceSummary> summaries,
) {
  if (routes.isEmpty) return const {};

  final durations = routes
      .map((route) => route.durationSeconds.toDouble())
      .toList(growable: false);
  final distances = routes
      .map((route) => route.distanceMeters.toDouble())
      .toList(growable: false);
  final congestion = routes
      .map(
        (route) =>
            (summaries[route.id]?.congestionScore ?? _nativeCongestion(route))
                .toDouble(),
      )
      .toList(growable: false);
  final cameras = routes
      .map((route) => (summaries[route.id]?.cameraCount ?? 0).toDouble())
      .toList(growable: false);

  double minOf(List<double> values) => values.reduce((a, b) => a < b ? a : b);
  double maxOf(List<double> values) => values.reduce((a, b) => a > b ? a : b);
  double normalized(double value, List<double> values) {
    final min = minOf(values);
    final max = maxOf(values);
    if ((max - min).abs() < 0.001) return 0;
    return (value - min) / (max - min);
  }

  final fastestDuration = minOf(durations);
  final candidateIds = <String>{
    for (var i = 0; i < routes.length; i++)
      if (durations[i] <= fastestDuration * 1.15 &&
          durations[i] <= fastestDuration + 120)
        routes[i].id,
  };
  final scores = <String, double>{};
  for (var i = 0; i < routes.length; i++) {
    // Default routing is experience-first: ETA dominates. Traffic may break a
    // close tie, but cameras are informational and must never create detours.
    final score =
        durations[i] +
        drivingManeuverPenalty(routes[i]) +
        normalized(congestion[i], congestion) * 30 +
        normalized(distances[i], distances) * 8;
    scores[routes[i].id] = score;
  }

  final eligibleScores = scores.entries
      .where((entry) => candidateIds.contains(entry.key))
      .toList(growable: false);
  final recommendedId =
      (eligibleScores.isEmpty ? scores.entries : eligibleScores)
          .reduce((a, b) => a.value <= b.value ? a : b)
          .key;
  final fastest = minOf(durations);
  final shortest = minOf(distances);
  final leastTraffic = minOf(congestion);
  final distanceVaries = (maxOf(distances) - shortest).abs() >= 1;
  final trafficVaries = (maxOf(congestion) - leastTraffic).abs() >= 1;

  return {
    for (var i = 0; i < routes.length; i++)
      routes[i].id: RoutePreferenceAssessment(
        score: scores[routes[i].id]!,
        recommended: routes[i].id == recommendedId,
        fastest: durations[i] == fastest,
        shortest: distanceVaries && distances[i] == shortest,
        leastTraffic: trafficVaries && congestion[i] == leastTraffic,
        zeroCameras: cameras[i] == 0,
      ),
  };
}

RouteOption? recommendedRoute(
  List<RouteOption> routes,
  Map<String, RoutePreferenceSummary> summaries,
) {
  final assessments = assessRoutePreferences(routes, summaries);
  for (final route in routes) {
    if (assessments[route.id]?.recommended == true) return route;
  }
  return routes.isEmpty ? null : routes.first;
}

int _nativeCongestion(RouteOption route) {
  final delay = route.trafficDelaySeconds ?? 0;
  return delay + route.traffic.trafficJam * 300 + route.traffic.slow * 90;
}

enum RouteFilter { recommended, fastest, shortest, avoidCameras, withCameras }

/// Filters the legal alternatives already returned by the engine. No network
/// requests and no claim that an unmatched camera count means total coverage.
List<RouteOption> filterRoutes(
  List<RouteOption> routes,
  RouteFilter filter,
  Map<String, RoutePreferenceSummary> summaries, {
  Set<String> blockedIds = const {},
}) {
  final result = routes
      .where(
        (route) => switch (filter) {
          RouteFilter.avoidCameras => summaries[route.id]?.cameraCount == 0,
          RouteFilter.withCameras =>
            (summaries[route.id]?.cameraCount ?? 0) > 0,
          _ => true,
        },
      )
      .toList();
  bool blocked(RouteOption route) =>
      route.blockedForDriving || blockedIds.contains(route.id);
  final legal = result.where((route) => !blocked(route)).toList();
  final preferred = recommendedRoute(legal, summaries)?.id;
  result.sort((a, b) {
    if (a.id == b.id) return 0;
    if (blocked(a) != blocked(b)) return blocked(a) ? 1 : -1;
    int order;
    switch (filter) {
      case RouteFilter.shortest:
        order = a.distanceMeters.compareTo(b.distanceMeters);
      case RouteFilter.recommended:
        order = a.id == preferred
            ? -1
            : b.id == preferred
            ? 1
            : 0;
      case RouteFilter.avoidCameras ||
          RouteFilter.withCameras ||
          RouteFilter.fastest:
        order = a.durationSeconds.compareTo(b.durationSeconds);
    }
    if (order != 0) return order;
    final duration = a.durationSeconds.compareTo(b.durationSeconds);
    return duration != 0
        ? duration
        : a.distanceMeters.compareTo(b.distanceMeters);
  });
  return result;
}
