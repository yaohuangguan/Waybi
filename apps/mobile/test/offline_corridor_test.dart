import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_mobile/app/offline_corridor.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/road_event.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/drive/drive_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the next 6 km of the route, its steps and nearby road events are '
      'saved for offline guidance', () async {
    SharedPreferences.setMockInitialValues({});
    final drive = DriveEngine();
    addTearDown(drive.dispose);
    // 0.01° of longitude is ~890 m here: 20 points span ~17 km.
    final points = [
      for (var i = 0; i <= 20; i++) GeoPoint(-37.2, 174.9 + i * .01),
    ];
    final route = RouteOption(
      id: 'long',
      mode: WaybiTravelMode.drive,
      durationSeconds: 900,
      distanceMeters: 17000,
      points: points,
      provider: 'independent',
      traffic: const TrafficSummary(normal: 0, slow: 0, trafficJam: 0),
      trafficIntervals: const [],
      steps: [
        RouteStepInfo(
          instruction: 'Head east',
          distanceMeters: 3000,
          location: points[1],
          maneuverType: 'depart',
          roadName: 'Near road',
        ),
        RouteStepInfo(
          instruction: 'Turn right',
          distanceMeters: 300,
          location: points[15],
          maneuverType: 'turn',
          maneuverModifier: 'right',
          roadName: 'Far road',
        ),
      ],
    );
    drive.upcomingRoadEvents = const [
      RoadEvent(
        id: 'near',
        type: RoadEventType.roadworks,
        location: GeoPoint(-37.2, 174.93),
        source: RoadEventSource(provider: 'test', country: 'NZ', sourceId: 'x'),
        distanceFromDriver: 2500,
      ),
      RoadEvent(
        id: 'far',
        type: RoadEventType.roadworks,
        location: GeoPoint(-37.2, 175.05),
        source: RoadEventSource(provider: 'test', country: 'NZ', sourceId: 'x'),
        distanceFromDriver: 12000,
      ),
    ];
    final now = DateTime.utc(2026, 11, 27, 8);
    await saveOfflineCorridor(
      route: route,
      drive: drive,
      destination: 'Harbour',
      language: 'en',
      now: now,
    );
    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString(offlineCorridorKey)!) as Map;
    expect(saved['destination'], 'Harbour');
    expect(saved['routeId'], 'long');
    expect(saved['cachedAt'], now.toIso8601String());
    final geometry = saved['geometry'] as List;
    expect(geometry.length, inInclusiveRange(7, 10), reason: '~6 km ahead');
    expect((geometry.first as List).last, 174.9);
    expect((saved['steps'] as List).map((s) => (s as Map)['roadName']), [
      'Near road',
    ]);
    expect((saved['roadEvents'] as List).map((e) => (e as Map)['id']), [
      'near',
    ]);
    expect(saved['cameras'], isEmpty);
  });
}
