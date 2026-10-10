import 'route_option.dart';

enum LaneArrowDirection {
  straight,
  left,
  right,
  slightLeft,
  slightRight,
  sharpLeft,
  sharpRight,
  uTurnLeft,
  uTurnRight;

  String label(String language) => language == 'zh'
      ? switch (this) {
          straight => '直行',
          left => '左转',
          right => '右转',
          slightLeft => '向左前方',
          slightRight => '向右前方',
          sharpLeft => '向左急转',
          sharpRight => '向右急转',
          uTurnLeft => '向左掉头',
          uTurnRight => '向右掉头',
        }
      : switch (this) {
          straight => 'Straight',
          left => 'Left',
          right => 'Right',
          slightLeft => 'Slight left',
          slightRight => 'Slight right',
          sharpLeft => 'Sharp left',
          sharpRight => 'Sharp right',
          uTurnLeft => 'U-turn left',
          uTurnRight => 'U-turn right',
        };
}

LaneArrowDirection? laneDirection(String indication) {
  final value = indication.toLowerCase().replaceAll(RegExp(r'[ _-]'), '');
  if (value.contains('uturn')) {
    return value.contains('right')
        ? LaneArrowDirection.uTurnRight
        : LaneArrowDirection.uTurnLeft;
  }
  if (value.contains('left')) {
    return value.contains('slight')
        ? LaneArrowDirection.slightLeft
        : value.contains('sharp')
        ? LaneArrowDirection.sharpLeft
        : LaneArrowDirection.left;
  }
  if (value.contains('right')) {
    return value.contains('slight')
        ? LaneArrowDirection.slightRight
        : value.contains('sharp')
        ? LaneArrowDirection.sharpRight
        : LaneArrowDirection.right;
  }
  if (value == 'straight' || value == 'through') {
    return LaneArrowDirection.straight;
  }
  return null;
}

Set<LaneArrowDirection> laneDirections(Iterable<String> indications) =>
    indications.map(laneDirection).whereType<LaneArrowDirection>().toSet();

bool laneSupportsManeuver(Iterable<String> indications, String maneuver) {
  final value = maneuver.toLowerCase();
  if (value.contains('uturn') || value.contains('u_turn')) {
    return indications.any(
      (s) => switch (laneDirection(s)) {
        LaneArrowDirection.uTurnLeft || LaneArrowDirection.uTurnRight => true,
        _ => false,
      },
    );
  }
  if (value.contains('left')) {
    return indications.any((s) => s.toLowerCase().contains('left'));
  }
  if (value.contains('right')) {
    return indications.any((s) => s.toLowerCase().contains('right'));
  }
  if (value == 'straight' || value.contains('straight')) {
    return indications.any(
      (s) => laneDirection(s) == LaneArrowDirection.straight,
    );
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
