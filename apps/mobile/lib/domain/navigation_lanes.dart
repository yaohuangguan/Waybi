import 'route_option.dart';

String? laneSymbol(String indication) {
  final value = indication.toLowerCase();
  if (value.contains('uturn') || value.contains('u_turn')) return '↶';
  if (value.contains('left')) return value.contains('slight') ? '↖' : '←';
  if (value.contains('right')) return value.contains('slight') ? '↗' : '→';
  if (value == 'straight' || value == 'through') return '↑';
  return null;
}

bool laneSupportsManeuver(Iterable<String> indications, String maneuver) {
  final value = maneuver.toLowerCase();
  if (value.contains('uturn') || value.contains('u_turn')) {
    return indications.any((s) => laneSymbol(s) == '↶');
  }
  if (value.contains('left')) {
    return indications.any((s) => s.toLowerCase().contains('left'));
  }
  if (value.contains('right')) {
    return indications.any((s) => s.toLowerCase().contains('right'));
  }
  if (value == 'straight' || value.contains('straight')) {
    return indications.any((s) => laneSymbol(s) == '↑');
  }
  // Merges and roundabouts need provider-specific recommendations.
  return true;
}

List<RouteLane> maneuverRouteLanes(Map<String, dynamic> step) {
  final intersections = (step['intersections'] as List<dynamic>? ?? const [])
      .whereType<Map<String, dynamic>>();
  if (intersections.isEmpty) return const [];
  final intersection = intersections.first;
  final maneuver = step['maneuver'] as Map<String, dynamic>? ?? const {};
  final at = maneuver['location'] as List<dynamic>?;
  final location = intersection['location'] as List<dynamic>?;
  if (at != null &&
      location != null &&
      at.length >= 2 &&
      location.length >= 2 &&
      at.take(2).every((v) => v is num) &&
      location.take(2).every((v) => v is num) &&
      (((at[0] as num) - (location[0] as num)).abs() > .00001 ||
          ((at[1] as num) - (location[1] as num)).abs() > .00001)) {
    return const [];
  }
  return parseRouteLanes(intersection['lanes'] as List<dynamic>? ?? const []);
}

List<RouteLane> parseRouteLanes(List<dynamic> data) => data
    .whereType<Map<String, dynamic>>()
    .map(
      (lane) => RouteLane(
        indications: (lane['indications'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        recommended: lane['active'] is bool
            ? lane['active'] == true
            : lane['valid'] == true,
      ),
    )
    .toList(growable: false);
