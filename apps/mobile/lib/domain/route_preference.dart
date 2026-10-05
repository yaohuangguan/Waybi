import 'route_option.dart';

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
      if (durations[i] <= fastestDuration * 1.15) routes[i].id,
  };
  final scores = <String, double>{};
  for (var i = 0; i < routes.length; i++) {
    // Default routing is experience-first: ETA dominates. Traffic may break a
    // close tie, but cameras are informational and must never create detours.
    final score =
        normalized(durations[i], durations) * .72 +
        normalized(congestion[i], congestion) * .20 +
        normalized(distances[i], distances) * .08;
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
