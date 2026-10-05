import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/data/parking_repository.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/road_event.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/widgets/arrival_experience_panel.dart';
import 'package:waybi_mobile/widgets/road_event_timeline.dart';
import 'package:waybi_mobile/widgets/route_preview_sheet.dart';

const _destination = GeoPoint(-36.8485, 174.7633);

void main() {
  test('route explanation follows the selected app language', () {
    const route = RouteOption(
      id: 'drive-1',
      mode: WaybiTravelMode.drive,
      durationSeconds: 600,
      distanceMeters: 3000,
      points: [_destination],
      provider: 'google',
      traffic: TrafficSummary(normal: 1, slow: 0, trafficJam: 0),
      trafficIntervals: [],
    );

    expect(routeExplanation(route, const [route], isChinese: true), '当前最快路线');
    expect(routeExplanation(route, const [route]), 'Fastest available route');
  });

  testWidgets('Chinese route deck localizes route and traffic chrome', (
    tester,
  ) async {
    const route = RouteOption(
      id: 'drive-1',
      mode: WaybiTravelMode.drive,
      durationSeconds: 600,
      distanceMeters: 3000,
      points: [_destination],
      provider: 'google',
      traffic: TrafficSummary(normal: 1, slow: 0, trafficJam: 0),
      trafficIntervals: [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoutePreviewSheet(
            destinationTitle: '奥克兰市中心',
            originTitle: '当前位置',
            plan: const RoutePlan(
              options: [route],
              trafficAvailable: true,
              provider: 'google',
              stopsApplied: 0,
            ),
            selectedMode: WaybiTravelMode.drive,
            selectedRouteId: route.id,
            busy: false,
            stopCount: 0,
            cameraCount: 2,
            routeCameraSummaries: const {
              'drive-1': RouteCameraSummary(
                count: 2,
                types: ['Spot speed', 'Red light'],
              ),
            },
            customOrigin: false,
            onModeChanged: (_) {},
            onRouteSelected: (_) {},
            onStart: () {},
            onAddStop: () {},
            onSave: () {},
            isFavorite: false,
            onFavorite: () {},
            onReview: () {},
            onClose: () {},
            isChinese: true,
          ),
        ),
      ),
    );

    expect(find.text('路线选项'), findsOneWidget);
    expect(find.textContaining('推荐路线'), findsOneWidget);
    expect(find.text('路况顺畅'), findsOneWidget);
    expect(find.textContaining('2 个摄像头 · 定点测速 + 闯红灯'), findsOneWidget);
    expect(find.text('行前摘要'), findsOneWidget);
    expect(find.text('预计到达 '), findsOneWidget);
    expect(find.text('交通 '), findsOneWidget);
    expect(find.text('摄像头 '), findsOneWidget);
    expect(find.text('停车 '), findsOneWidget);
    expect(find.text('添加途经点'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
  });

  testWidgets(
    'arrival panel exposes final approach and nearby parking in Chinese',
    (tester) async {
      const parking = ParkingPlace(
        id: 'parking-1',
        name: '终点停车楼',
        address: 'Queen Street',
        location: _destination,
        distanceMeters: 90,
        source: 'AT',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 375,
              child: ArrivalExperiencePanel(
                language: 'zh',
                destinationTitle: '奥克兰美术馆',
                destinationAddress: 'Wellesley Street East',
                remainingMeters: 280,
                parkingPlaces: const [parking],
                parkingLoading: false,
                onParkingSelected: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('最后一段 · 280 米'), findsOneWidget);
      expect(find.text('奥克兰美术馆'), findsOneWidget);
      expect(find.textContaining('入口 · Wellesley Street East'), findsOneWidget);
      expect(find.textContaining('终点停车楼 · 90 米'), findsOneWidget);
      expect(find.textContaining('到达后会自动接续最后步行'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('road-event deck follows Chinese navigation language', (
    tester,
  ) async {
    const event = RoadEvent(
      id: 'works-1',
      type: RoadEventType.roadworks,
      location: _destination,
      source: RoadEventSource(
        provider: 'NZTA',
        country: 'NZ',
        sourceId: 'works-1',
      ),
      distanceFromDriver: 350,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RoadEventTimeline(
            events: [event],
            language: 'zh',
            maneuverLabel: '继续直行',
            dark: false,
          ),
        ),
      ),
    );

    expect(find.text('当前'), findsOneWidget);
    expect(find.text('道路施工'), findsOneWidget);
    expect(find.text('350 米'), findsOneWidget);
  });

  testWidgets('collapsed road-event UI is a compact next-event strip', (
    tester,
  ) async {
    const event = RoadEvent(
      id: 'closure-1',
      type: RoadEventType.roadClosure,
      location: _destination,
      source: RoadEventSource(
        provider: 'NZTA',
        country: 'NZ',
        sourceId: 'closure-1',
      ),
      roadName: 'George Bolt Memorial Drive',
      distanceFromDriver: 1498,
      severity: RoadEventSeverity.warning,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RoadEventTimeline(
            events: [event],
            language: 'zh',
            dark: false,
            compact: true,
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('compactRoadEventStrip')), findsOneWidget);
    expect(find.textContaining('道路封闭'), findsOneWidget);
    expect(find.textContaining('1.5 公里'), findsOneWidget);
    expect(find.text('当前'), findsNothing);
  });
}
