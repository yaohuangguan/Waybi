import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/transit_lane.dart';
import 'package:waybi_mobile/domain/transit_lane_map.dart';

TransitLane makeLane(String id, TransitSchedule schedule) => TransitLane(
  id: id,
  roadName: 'Symonds Street',
  kind: 'Bus',
  schedule: schedule,
  points: const [GeoPoint(-36.858, 174.763), GeoPoint(-36.857, 174.763)],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'full bundled Auckland snapshot renders published line geometry offline',
    () async {
      final snapshot = jsonDecode(
        await rootBundle.loadString('assets/data/transit-lanes.json'),
      ) as Map<String, dynamic>;
      final lanes = (snapshot['lanes'] as List)
          .cast<Map<String, dynamic>>()
          .map(TransitLane.fromJson)
          .toList();
      expect(lanes.length, greaterThanOrEqualTo(350));
      final source = transitLaneFeatureCollection(
        lanes,
        DateTime.utc(2026, 10, 9, 4),
      );
      final features = source['features'] as List;
      expect(features.length, greaterThanOrEqualTo(350));
      expect(
        features.every(
          (feature) => (feature['geometry'] as Map)['type'] == 'LineString',
        ),
        isTrue,
      );
    },
  );

  test(
    'official line features distinguish active, inactive and unknown hours',
    () {
      const weekdays = TransitSchedule(
        days: [1, 2, 3, 4, 5],
        windows: [
          [420, 1140],
        ],
        known: true,
      );
      const unknown = TransitSchedule(days: [], windows: [], known: false);
      final lanes = [
        makeLane('active', weekdays),
        makeLane('unknown', unknown),
      ];
      final active = transitLaneFeatureCollection(
        lanes,
        DateTime.utc(
          2026,
          10,
          9,
          6,
        ), // Friday 19:00 NZDT is exclusive; test 18:00 below.
      );
      final inactiveFeatures = active['features'] as List;
      expect(
        (inactiveFeatures.first['properties'] as Map)['laneStatus'],
        'inactive',
      );
      expect(
        (inactiveFeatures.last['properties'] as Map)['laneStatus'],
        'unknown',
      );

      final during = transitLaneFeatureCollection(
        lanes,
        DateTime.utc(2026, 10, 9, 4),
      );
      final features = during['features'] as List;
      expect((features.first['properties'] as Map)['laneStatus'], 'active');
      expect(features.first['id'], 'transit:active');
      expect((features.first['geometry'] as Map)['coordinates'], [
        [174.763, -36.858],
        [174.763, -36.857],
      ]);
      expect((features.last['properties'] as Map)['laneStatus'], 'unknown');
    },
  );

  test('lanes missing line geometry are never rendered', () {
    final empty = TransitLane(
      id: 'invalid',
      roadName: '',
      kind: 'Bus',
      schedule: const TransitSchedule(days: [], windows: [], known: false),
      points: const [GeoPoint(-36.85, 174.76)],
    );
    expect(
      (transitLaneFeatureCollection([empty], DateTime.now())['features']
          as List),
      isEmpty,
    );
  });
}
