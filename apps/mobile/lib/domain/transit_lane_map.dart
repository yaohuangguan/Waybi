import 'transit_lane.dart';
import 'transit_review_corridor.dart';

/// Visual-only official lane overlay. Do not use its style to decide road
/// legality; navigation uses directed geometry and schedule checks separately.
Map<String, dynamic> transitLaneFeatureCollection(
  List<TransitLane> lanes,
  DateTime now, [
  List<TransitReviewCorridor> reviewCorridors = const [],
]) => {
  'type': 'FeatureCollection',
  'features': [
    // Show only provisional centreline hints, never a legal lane restriction.
    for (final corridor in reviewCorridors)
      {
        'type': 'Feature',
        'id': 'review:${corridor.id}',
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            for (final point in corridor.points)
              [point.longitude, point.latitude],
          ],
        },
        'properties': {
          'kind': 'review-corridor',
          'roadName': corridor.roadName,
          'laneStatus': 'candidate',
        },
      },
    for (final lane in lanes)
      if (lane.points.length >= 2)
        {
          'type': 'Feature',
          'id': 'transit:${lane.id}',
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              for (final point in lane.points)
                [point.longitude, point.latitude],
            ],
          },
          'properties': {
            'kind': lane.kind,
            'roadName': lane.roadName,
            'laneStatus': switch (lane.schedule.activeAt(now)) {
              true => 'active',
              false => 'inactive',
              null => 'unknown',
            },
          },
        },
  ],
};
