import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_conditions.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/domain/route_preference.dart';
import 'package:waybi_mobile/providers/independent_routing_provider.dart';

Map<String, dynamic> evidence({
  int penalty = 600,
  String status = 'live',
  int heavy = 2000,
  int moderate = 0,
}) => {
  'expiresAt': DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
  'trafficStatus': status,
  'coveredMeters': 3000,
  'heavyMeters': heavy,
  'moderateMeters': moderate,
  'rankingPenalty': penalty,
  'incidentIds': ['incident'],
  'roadworkIds': ['works'],
};
Map<String, dynamic> row(
  String id,
  int seconds,
  Map<String, dynamic>? conditions,
) => {
  'id': id,
  'mode': 'drive',
  'provider': 'independent',
  'routingEngine': 'valhalla',
  'durationSeconds': seconds,
  'distanceMeters': 10000,
  'coordinates': [
    [174.76, -36.85],
    [174.77, -36.86],
  ],
  'conditions': conditions,
};

void main() {
  test(
    'conditions retain source evidence and never manufacture measured delays',
    () {
      final route = RouteOption.fromJson(row('heavy', 600, evidence()));
      expect(route.durationSeconds, 600);
      expect(route.trafficDelaySeconds, isNull);
      expect(route.conditions!.currentPenalty, 600);
      expect(route.conditions!.incidentIds, ['incident']);
      expect(route.conditions!.roadworkIds, ['works']);
      expect(route.conditions!.coveredMeters, 3000);
      expect(route.hasTrafficData, true);
      expect(route.hasHeavyTraffic, true);
      expect(route.hasSlowTraffic, false);
      expect(route.conditions!.trafficLabel(true), '部分路段拥堵');
      expect(route.conditions!.trafficLabel(false), 'Heavy sections');
    },
  );
  test('partial slow, clear and uncovered traffic labels never imply whole-route coverage', () {
    for (final (status, moderate, zh, en) in [
      ('live', 1000, '部分路段缓行', 'Slow sections'),
      ('live', 0, '已知路段顺畅', 'Known sections clear'),
      ('unavailable', 0, '路况未覆盖', 'Traffic not covered'),
      ('stale', 0, '路况已过期', 'Traffic outdated'),
    ]) {
      final route = RouteOption.fromJson(
        row(
          'route',
          600,
          evidence(status: status, heavy: 0, moderate: moderate),
        ),
      );
      expect(route.conditions!.trafficLabel(true), zh);
      expect(route.conditions!.trafficLabel(false), en);
      expect(route.hasSlowTraffic, status == 'live' && moderate > 0);
      expect(route.hasHeavyTraffic, false);
    }
    final uncovered = RouteConditions.fromJson({
      ...evidence(),
      'coveredMeters': 0,
    });
    expect(uncovered.hasTraffic, false);
    expect(uncovered.trafficLabel(true), '路况未覆盖');
  });
  test('old, malformed and missing assessments expire without suppressing legacy routes', () {
    final expired = RouteOption.fromJson(
      row('old', 600, {
        ...evidence(),
        'expiresAt': DateTime.now()
            .subtract(const Duration(seconds: 1))
            .toIso8601String(),
      }),
    );
    expect(expired.conditions!.currentPenalty, 0);
    expect(expired.hasTrafficData, false);
    expect(expired.hasHeavyTraffic, false);
    expect(expired.hasSlowTraffic, false);
    expect(expired.conditions!.trafficLabel(false), 'Traffic outdated');
    final empty = RouteConditions.fromJson({});
    expect(empty.expiresAt, isNull);
    expect(empty.currentPenalty, 0);
    expect(empty.hasTraffic, false);
    expect(empty.incidentIds, isEmpty);
    expect(empty.roadworkIds, isEmpty);
    expect(
      RouteConditions.fromJson({...evidence(), 'rankingPenalty': 9999})
          .rankingPenalty,
      1800,
    );
    final legacy = RouteOption.fromJson(row('legacy', 600, null));
    expect(legacy.conditions, isNull);
    expect(legacy.hasHeavyTraffic, false);
    expect(legacy.hasSlowTraffic, false);
  });
  test('known congestion or incidents can favour a longer clear option without changing ETA badges', () {
    final heavy = RouteOption.fromJson(row('heavy', 600, evidence()));
    final clear = RouteOption.fromJson(
      row('clear', 850, evidence(penalty: 0, heavy: 0)),
    );
    expect(recommendedRoute([heavy, clear], const {})?.id, 'clear');
    final preferences = assessRoutePreferences([heavy, clear], const {});
    expect(preferences['heavy']!.fastest, true);
    expect(preferences['clear']!.leastTraffic, false);
    final stale = RouteOption.fromJson(
      row('heavy', 600, {...evidence(), 'expiresAt': '2000-01-01T00:00:00Z'}),
    );
    expect(recommendedRoute([stale, clear], const {})?.id, 'heavy');
  });
  test('shipping proxy preserves conditions when adding requested waypoints and ranking routes', () async {
    final provider = IndependentRoutingProvider(
      useWaybiProxy: true,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'options': [
              row('heavy', 600, evidence()),
              row('clear', 850, evidence(penalty: 0, heavy: 0)),
            ],
          }),
          200,
        ),
      ),
    );
    addTearDown(provider.dispose);
    final plan = await provider.route(
      origin: const GeoPoint(-36.85, 174.76),
      destination: const GeoPoint(-36.86, 174.77),
      language: 'zh',
      mode: WaybiTravelMode.drive,
    );
    expect(plan.options.first.id, 'clear');
    expect(plan.options.last.conditions!.heavyMeters, 2000);
    expect(plan.options.first.waypoints.length, 2);
    expect(plan.options.first.routingEngine, 'valhalla');
  });
}
