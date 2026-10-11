import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_mobile/data/transit_lane_repository.dart';
import 'package:waybi_mobile/domain/transit_lane.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/widgets/navigation_transit_alert.dart';
import 'package:waybi_mobile/widgets/navigation_overlay.dart';
import 'package:waybi_mobile/drive/drive_engine.dart';

const peak = TransitSchedule(
  days: [1, 2, 3, 4, 5],
  windows: [
    [420, 600],
    [960, 1140],
  ],
  known: true,
);
RouteOption route(TransitLane lane, {bool reverse = false}) => RouteOption(
  id: 'lane',
  mode: WaybiTravelMode.drive,
  durationSeconds: 60,
  distanceMeters: 200,
  points: reverse ? lane.points.reversed.toList() : lane.points,
  provider: 'independent',
  traffic: const TrafficSummary(normal: 0, slow: 0, trafficJam: 0),
  trafficIntervals: const [],
  steps: [
    RouteStepInfo(
      instruction: 'Continue',
      distanceMeters: 200,
      location: lane.points.first,
      roadName: lane.roadName,
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> raw;
  late TransitLaneSnapshot snapshot;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    raw = jsonDecode(
      await rootBundle.loadString('assets/data/transit-lanes.json'),
    ) as Map<String, dynamic>;
    snapshot = TransitLaneSnapshot(raw);
  });

  test('published Symonds lane is 24/7 and matches northbound, preserving ordinary traffic', () {
    final lane = snapshot.lanes.firstWhere((l) => l.id == 'at:svl:69:0');
    final matches = matchTransitLanes(route(lane), [lane]);
    expect(matches, hasLength(1));
    expect(matchTransitLanes(route(lane, reverse: true), [lane]), isEmpty);
    expect(
      transitRoadBlocks(route(lane), matches, DateTime.utc(2026, 10, 8, 19)),
      isEmpty,
    );
    expect(lane.schedule.label('zh'), contains('全天生效'));
    expect(snapshot.lanes.where((l) => !l.schedule.known), hasLength(90));
  });

  test('NZ times and weekday boundaries are independent of the phone timezone, including DST', () {
    expect(
      peak.activeAt(DateTime.utc(2026, 10, 8, 18)),
      true,
    ); // Friday 07:00 NZDT.
    expect(
      peak.activeAt(DateTime.utc(2026, 10, 8, 21)),
      false,
    ); // 10:00 exclusive.
    expect(peak.activeAt(DateTime.utc(2026, 10, 9, 19)), false); // Saturday.
    expect(peak.activeAt(DateTime.utc(2026, 7, 9, 19)), true); // 07:00 NZST.
    expect(
      peak.activeDuring(
        DateTime.utc(2026, 10, 8, 17, 59, 50),
        DateTime.utc(2026, 10, 8, 18, 0, 10),
      ),
      true,
    );
    expect(peak.label('zh'), contains('周一至周五 07:00–10:00、16:00–19:00'));
    expect(peak.label('en'), contains('Monday to Friday'));
    const night = TransitSchedule(
      days: [1, 2, 3, 4, 5],
      windows: [
        [1320, 120],
      ],
      known: true,
    );
    expect(
      night.activeAt(DateTime.utc(2026, 10, 9, 12)),
      true,
    ); // Friday's window ends Saturday 02:00.
    expect(night.activeAt(DateTime.utc(2026, 10, 9, 13)), false);
  });

  test('verified whole-road restriction blocks ordinary cars only during its active traversal', () {
    final lane = snapshot.lanes.firstWhere((l) => l.wholeRoad);
    final r = route(lane), matches = matchTransitLanes(route(lane), [lane]);
    expect(
      transitRoadBlocks(r, matches, DateTime.utc(2026, 10, 8, 19)),
      hasLength(1),
    );
    expect(
      transitRoadBlocks(r, matches, DateTime.utc(2026, 10, 10, 19)),
      isEmpty,
    );
    final nearby = RouteOption(
      id: 'nearby',
      mode: r.mode,
      durationSeconds: 60,
      distanceMeters: 200,
      points: r.points
          .map((p) => GeoPoint(p.latitude, p.longitude + .001))
          .toList(),
      provider: r.provider,
      traffic: r.traffic,
      trafficIntervals: const [],
    );
    expect(matchTransitLanes(nearby, [lane]), isEmpty);
    expect(
      snapshot.lanes
          .where((l) => l.kind == 'BusOnly')
          .every((l) => !l.wholeRoad),
      true,
    );
  });

  test('a stale or offline snapshot triggers at most one check per device per week', () async {
    var now = snapshot.checkedAt.add(const Duration(days: 8)), requests = 0;
    final repository = TransitLaneRepository(
      clock: () => now,
      seedLoader: () async => jsonEncode(raw),
      client: MockClient((_) async {
        requests++;
        return http.Response('offline', 503);
      }),
    );
    await repository.refresh();
    await repository.refresh();
    final reopened = TransitLaneRepository(
      clock: () => now,
      seedLoader: () async => jsonEncode(raw),
      client: MockClient((_) async {
        requests++;
        return http.Response('offline', 503);
      }),
    );
    await reopened.refresh();
    expect(requests, 1);
    now = now.add(const Duration(days: 6));
    await reopened.refresh();
    expect(requests, 1);
    now = now.add(const Duration(days: 1));
    await reopened.refresh();
    expect(requests, 2);
  });

  test('a fresh bundled snapshot needs no network and concurrent refreshes coalesce', () async {
    var requests = 0;
    final repository = TransitLaneRepository(
      clock: () => snapshot.checkedAt.add(const Duration(days: 1)),
      seedLoader: () async => jsonEncode(raw),
      client: MockClient((_) async {
        requests++;
        return http.Response(jsonEncode(raw), 200);
      }),
    );
    await Future.wait([repository.refresh(), repository.refresh()]);
    expect(requests, 0);
  });

  for (final language in ['zh', 'en']) {
    testWidgets(
      'complete $language navigation fits with the active lane strip',
      (tester) async {
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final lane = snapshot.lanes.firstWhere((l) => l.id == 'at:svl:69:0');
        final engine = DriveEngine();
        addTearDown(engine.dispose);
        engine.upcomingTransitLane = TransitLaneNotice(
          match: TransitLaneMatch(lane: lane, startMeters: 200, endMeters: 380),
          distanceMeters: 200,
          turningLeft: true,
        );
        final capture = GlobalKey();
        const dir = String.fromEnvironment('WAYBI_TEST_CAPTURE_DIR');
        const fontPath = String.fromEnvironment('WAYBI_TEST_FONT_PATH');
        if (dir.isNotEmpty) {
          await tester.runAsync(() async {
            if (fontPath.isNotEmpty) {
              final font = FontLoader('PreviewFont')
                ..addFont(
                  File(fontPath)
                      .readAsBytes()
                      .then((v) => ByteData.sublistView(v)),
                );
              await font.load();
            }
            final icons = FontLoader('MaterialIcons')
              ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
            await icons.load();
          });
        }
        await tester.pumpWidget(
          MaterialApp(
            theme: dir.isEmpty ? null : ThemeData(fontFamily: 'PreviewFont'),
            home: Scaffold(
              backgroundColor: const Color(0xFFE8EDDF),
              body: RepaintBoundary(
                key: capture,
                child: NavigationOverlay(
                  engine: engine,
                  language: language,
                  destinationTitle: 'Waterloo Quadrant',
                  gpsAccuracy: 8,
                  voiceEnabled: true,
                  lanesEnabled: true,
                  northUp: false,
                  guidance: NavigationGuidance(
                    instruction: language == 'zh'
                        ? '左转进入 Waterloo Quadrant'
                        : 'Turn left onto Waterloo Quadrant',
                    maneuverIcon: Icons.turn_left_rounded,
                    stepMeters: 180,
                    remainingMeters: 2300,
                    remainingSeconds: 420,
                  ),
                  onEnd: () {},
                  onRecenter: () {},
                  onOverview: () {},
                  onCompassToggle: () {},
                  onReport: () {},
                  onSearchAlongRoute: () {},
                  onDirections: () {},
                  onShare: () {},
                  onSettings: () {},
                  onLayers: () {},
                  onVoiceToggle: () {},
                  onLanesToggle: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(lane.schedule.label(language)), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        if (dir.isNotEmpty) {
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final picture = await boundary.toImage(pixelRatio: 2),
                png = await picture.toByteData(format: ui.ImageByteFormat.png);
            await Directory(dir).create(recursive: true);
            await File('$dir/bus-navigation-$language.png')
                .writeAsBytes(png!.buffer.asUint8List());
            picture.dispose();
          });
        }
      },
    );
    testWidgets(
      'compact $language reminder shows hours without asserting GPS lane occupancy',
      (tester) async {
        tester.view.physicalSize = const Size(375, 667);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final lane = TransitLane(
          id: 'peak',
          roadName: 'Symonds Street',
          kind: 'Bus',
          schedule: peak,
          points: const [],
        );
        final notice = TransitLaneNotice(
          match: TransitLaneMatch(lane: lane, startMeters: 100, endMeters: 200),
          distanceMeters: 100,
          turningLeft: true,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NavigationTransitAlert(notice: notice, language: language),
            ),
          ),
        );
        expect(find.text(peak.label(language)), findsOneWidget);
        expect(find.text(notice.instruction(language)), findsOneWidget);
        expect(
          notice.speech(language),
          contains(language == 'zh' ? '周一至周五' : 'Monday to Friday'),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
