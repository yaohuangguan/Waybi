import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/app/road_alerts.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/road_event.dart';
import 'package:waybi_mobile/domain/safety_camera.dart';
import 'package:waybi_mobile/drive/drive_engine.dart';

const source = RoadEventSource(
  provider: 'test',
  country: 'NZ',
  sourceId: 'fixture',
);

RoadEvent event(
  String id, {
  RoadEventType type = RoadEventType.incident,
  RoadEventSeverity severity = RoadEventSeverity.warning,
  double? along = 900,
  Map<String, Object?> metadata = const {},
}) => RoadEvent(
  id: id,
  type: type,
  location: const GeoPoint(-37.2, 174.91),
  source: source,
  severity: severity,
  distanceAlongRoute: along,
  metadata: metadata,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DriveEngine drive;
  late List<({String id, String title, String body})> shown;
  late bool displayed;
  late Object? failure;
  late DateTime now;
  late ({bool cameras, bool incidents, bool community}) settings;
  late int permissionRequests;

  RoadAlerts alerts({String language = 'en'}) => RoadAlerts(
    settings: () => settings,
    language: () => language,
    clock: () => now,
    present: ({required id, required title, required body}) async {
      if (failure != null) throw failure!;
      shown.add((id: id, title: title, body: body));
      return displayed;
    },
    requestPermission: () async {
      permissionRequests++;
      if (failure != null) throw failure!;
    },
  );

  setUp(() {
    drive = DriveEngine();
    addTearDown(drive.dispose);
    drive.active = true;
    shown = [];
    displayed = true;
    failure = null;
    now = DateTime(2026, 11, 27, 8);
    settings = (cameras: true, incidents: true, community: true);
    permissionRequests = 0;
  });

  test('a camera within 800 m and enabled events within 1.5 km, once per '
      'trip', () async {
    final road = alerts(language: 'zh');
    drive
      ..upcomingCamera = const SafetyCamera(
        id: 'cam',
        name: 'Fixed camera',
        region: 'Auckland',
        suburb: 'CBD',
        location: 'Queen Street',
        type: 'Fixed speed camera',
        latitude: -37.2,
        longitude: 174.905,
      )
      ..upcomingCameraDistanceMeters = 420
      ..upcomingRoadEvents = [
        event('crash'),
        event('minor', severity: RoadEventSeverity.information),
        event('far', along: 2400),
        event('unknown-distance', along: null),
        event('camera-event', type: RoadEventType.safetyCamera),
        event(
          'report',
          severity: RoadEventSeverity.information,
          metadata: {'userReported': true, 'reporterName': 'Sam'},
        ),
      ];
    await road.check(drive);
    expect(shown.map((s) => s.id), ['camera:cam', 'crash', 'report']);
    expect(shown.first.body, contains('420 米'));
    expect(shown.last.body, contains('Sam 报告'));
    await road.check(drive);
    expect(shown, hasLength(3), reason: 'each alert once per trip');
    road.newTrip();
    await road.check(drive);
    expect(shown, hasLength(6));
    drive.active = false;
    await road.check(drive);
    expect(shown, hasLength(6));
  });

  test('switched-off alert types stay quiet', () async {
    settings = (cameras: false, incidents: false, community: false);
    final road = alerts();
    drive
      ..upcomingCameraDistanceMeters = 300
      ..upcomingRoadEvents = [
        event('crash'),
        event('report', metadata: {'userReported': true}),
      ];
    await road.check(drive);
    expect(shown, isEmpty);
    await road.prepare();
    expect(permissionRequests, 0);
  });

  test(
    'a notification the system did not show is retried after 20 s',
    () async {
      final road = alerts();
      displayed = false;
      await road.show(id: 'a', title: 'A', body: 'a');
      await road.show(id: 'a', title: 'A', body: 'a');
      expect(shown, hasLength(1));
      now = now.add(const Duration(seconds: 21));
      displayed = true;
      await road.show(id: 'a', title: 'A', body: 'a');
      expect(shown, hasLength(2));
      await road.show(id: 'a', title: 'A', body: 'a');
      expect(shown, hasLength(2));

      failure = StateError('plugin');
      await road.show(id: 'b', title: 'B', body: 'b');
      failure = null;
      await road.show(id: 'b', title: 'B', body: 'b');
      expect(shown.where((s) => s.id == 'b'), isEmpty, reason: 'backing off');
    },
  );

  test('permission is requested only when an alert type is on', () async {
    final road = alerts();
    await road.prepare();
    expect(permissionRequests, 1);
    failure = StateError('denied');
    await road.prepare();
    expect(permissionRequests, 2);
  });
}
