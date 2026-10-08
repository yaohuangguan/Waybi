import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/navigation_lanes.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/widgets/navigation_overlay.dart';

void main() {
  test('right turn never highlights a straight-only lane', () {
    final lanes = routeNavigationLanes(
      const RouteStepInfo(
        instruction: '',
        distanceMeters: 33,
        location: GeoPoint(-36.9, 174.8),
        maneuverModifier: 'right',
        lanes: [
          RouteLane(indications: ['left'], recommended: false),
          RouteLane(indications: ['right'], recommended: true),
          RouteLane(indications: ['straight'], recommended: true),
          RouteLane(indications: ['right'], recommended: false),
        ],
      ),
    );
    expect(lanes.map((lane) => lane.recommended), [false, true, false, false]);
  });
  test(
    'left turn highlights compatible lanes, not all valid through lanes',
    () {
      final lanes = routeNavigationLanes(
        const RouteStepInfo(
          instruction: '',
          distanceMeters: 222,
          location: GeoPoint(-36.9, 174.8),
          maneuverModifier: 'left',
          lanes: [
            RouteLane(indications: ['straight', 'left'], recommended: true),
            RouteLane(indications: ['straight'], recommended: true),
          ],
        ),
      );
      expect(lanes.map((lane) => lane.recommended), [true, false]);
      expect(laneSymbol('unknown'), isNull);
      expect(laneSymbol('uTurnRight'), '↶');
    },
  );
  test(
    'direct OSRM parser selects only maneuver lanes and honors active false',
    () {
      final lanes = maneuverRouteLanes({
        'intersections': [
          {
            'lanes': [
              {
                'indications': ['right'],
                'valid': true,
                'active': false,
              },
            ],
          },
          {
            'lanes': List.filled(5, {
              'indications': ['straight'],
              'valid': true,
            }),
          },
        ],
      });
      expect(lanes.length, 1);
      expect(lanes.single.recommended, false);
      expect(
        maneuverRouteLanes({
          'intersections': [
            {},
            {'lanes': []},
          ],
        }),
        isEmpty,
      );
    },
  );
}
