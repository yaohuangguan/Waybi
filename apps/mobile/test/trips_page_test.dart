import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_lens_mobile/domain/map_provider.dart';
import 'package:kiwi_lens_mobile/domain/route_option.dart';
import 'package:kiwi_lens_mobile/widgets/trips_page.dart';

void main() {
  testWidgets(
    'Trips shows live commute, recent destination and history in Chinese',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const home = TripDestination(
        name: 'Home',
        address: 'Auckland CBD',
        location: GeoPoint(-36.8485, 174.7633),
      );
      const work = TripDestination(
        name: 'Work',
        address: 'Newmarket',
        location: GeoPoint(-36.87, 174.77),
      );
      const route = RouteOption(
        id: 'home-drive',
        mode: KiwiTravelMode.drive,
        durationSeconds: 900,
        staticDurationSeconds: 720,
        trafficDelaySeconds: 180,
        distanceMeters: 6200,
        points: [GeoPoint(-36.8485, 174.7633), GeoPoint(-36.87, 174.77)],
        provider: 'google',
        traffic: TrafficSummary(normal: 10, slow: 2, trafficJam: 0),
        trafficIntervals: [],
      );
      final snapshot = TripsSnapshot(
        quickPlaces: const {'Home': home, 'Work': work},
        quickRoutes: const {'Home': route},
        recent: const [
          TripDestination(
            name: 'Auckland Art Gallery',
            location: GeoPoint(-36.8514, 174.7663),
          ),
        ],
        history: [
          TripHistoryItem(
            destination: const TripDestination(
              name: 'Mission Bay',
              location: GeoPoint(-36.85, 174.83),
            ),
            mode: 'drive',
            distanceMeters: 7800,
            durationSeconds: 1100,
            createdAt: DateTime.now().subtract(const Duration(hours: 2)),
          ),
        ],
        signedIn: true,
        isPlus: true,
        smartCommuteRoutes: const {'home-work': route},
        routeWatches: const {
          'home-work': RouteWatchItem(
            id: 'watch-home-work',
            label: 'home-work',
            status: 'warning',
            baselineDurationSeconds: 600,
            baselineDistanceMeters: 6200,
            events: [
              RouteWatchEvent(
                type: 'roadworks',
                severity: 'warning',
                description: 'Road works near the motorway',
                impact: 'Delays',
                roadName: 'SH1',
              ),
            ],
          ),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: TripsPage(language: 'zh', loader: () async => snapshot),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('行程'), findsWidgets);
      expect(find.text('更快出发'), findsOneWidget);
      expect(find.text('15 分钟'), findsOneWidget);
      expect(find.text('智能通勤'), findsOneWidget);
      expect(find.text('有警告'), findsOneWidget);
      expect(find.text('当前 15 分钟 · 比平时多 5 分钟 · 建议提前 5 分钟出发'), findsOneWidget);
      expect(find.text('行程洞察'), findsOneWidget);
      expect(find.text('7.8 km'), findsOneWidget);
      expect(find.text('平均 · 18 分钟'), findsOneWidget);
      expect(find.text('最长 · 19 分钟'), findsOneWidget);
      expect(find.textContaining('Mission Bay'), findsWidgets);
      expect(find.text('家 → 公司'), findsOneWidget);
      expect(find.text('公司 → 家'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('最近目的地'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('最近目的地'), findsOneWidget);
      expect(find.text('Auckland Art Gallery'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('行程记录'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('行程记录'), findsOneWidget);
      expect(find.text('Mission Bay'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('free user sees Plus locks instead of Smart Commute controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const home = TripDestination(
      name: 'Home',
      location: GeoPoint(-36.8485, 174.7633),
    );
    const work = TripDestination(
      name: 'Work',
      location: GeoPoint(-36.87, 174.77),
    );
    final snapshot = TripsSnapshot(
      quickPlaces: const {'Home': home, 'Work': work},
      quickRoutes: const {},
      recent: const [],
      history: [
        TripHistoryItem(
          destination: const TripDestination(
            name: 'Mission Bay',
            location: GeoPoint(-36.85, 174.83),
          ),
          mode: 'drive',
          distanceMeters: 7800,
          durationSeconds: 1100,
          createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      ],
      signedIn: true,
      isPlus: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TripsPage(language: 'zh', loader: () async => snapshot),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('智能通勤'), findsOneWidget);
    expect(find.text('Plus 专属'), findsWidgets);
    expect(find.textContaining('提前出发建议和后台路线监控'), findsOneWidget);
    expect(find.text('行程洞察'), findsOneWidget);
    expect(find.textContaining('近 30 天行程趋势'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
