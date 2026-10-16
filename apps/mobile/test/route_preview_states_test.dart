import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/domain/route_preference.dart';
import 'package:waybi_mobile/domain/road_event.dart';
import 'package:waybi_mobile/data/parking_repository.dart';
import 'package:waybi_mobile/widgets/route_preview_sheet.dart';

RouteOption option(
  String id, {
  int time = 3600,
  int distance = 20000,
  WaybiTravelMode mode = WaybiTravelMode.drive,
  int jam = 0,
  int slow = 0,
  int? delay,
  List<String> restricted = const [],
  List<TransitLeg> transit = const [],
}) => RouteOption(
  id: id,
  mode: mode,
  durationSeconds: time,
  distanceMeters: distance,
  provider: 'independent',
  points: const [GeoPoint(-37.2, 174.9), GeoPoint(-37.2, 174.91)],
  traffic: TrafficSummary(normal: 0, slow: slow, trafficJam: jam),
  trafficIntervals: const [],
  trafficDelaySeconds: delay,
  restrictedRoadIds: restricted,
  transit: transit,
  warnings: jam > 0 ? const ['This route includes a highway.'] : const [],
  description: 'Route $id',
);
const closure = RoadEvent(
  id: 'closure',
  type: RoadEventType.roadClosure,
  location: GeoPoint(-37.2, 174.9),
  source: RoadEventSource(provider: 'NZTA', country: 'NZ', sourceId: '1'),
  roadName: 'Closed ramp',
);
Future<void> show(
  WidgetTester t,
  List<RouteOption> routes, {
  bool zh = false,
  bool cameras = true,
  WaybiTravelMode mode = WaybiTravelMode.drive,
  String? selected,
  Map<String, List<RoadEvent>> closures = const {},
  VoidCallback? retry,
  ValueChanged<RoadEvent>? event,
  ValueChanged<RouteOption>? select,
  ValueChanged<RouteFilter>? filter,
  List<ParkingPlace> parking = const [],
  ValueChanged<ParkingPlace>? park,
  VoidCallback? direct,
  bool parkingLoading = false,
}) async {
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RoutePreviewSheet(
          destinationTitle: 'Test destination',
          originTitle: 'Start',
          plan: RoutePlan(
            options: routes,
            trafficAvailable: true,
            provider: 'independent',
            stopsApplied: 2,
          ),
          selectedMode: mode,
          selectedRouteId: selected ?? routes.firstOrNull?.id,
          busy: false,
          stopCount: 2,
          cameraCount: 3,
          routeCameraSummaries: {
            for (final r in routes)
              r.id: const RouteCameraSummary(
                count: 3,
                types: ['red light + speed', 'bus / transit lane', 'other'],
              ),
          },
          routeClosures: closures,
          cameraDataReady: cameras,
          onFilterChanged: filter,
          customOrigin: true,
          onModeChanged: (_) {},
          onRouteSelected: select ?? (_) {},
          onStart: () {},
          onAddStop: () {},
          onSave: () {},
          isFavorite: true,
          onFavorite: () {},
          onReview: () {},
          onClose: () {},
          onRetry: retry,
          onRoadEvent: event,
          isChinese: zh,
          parkingPlaces: parking,
          onParkingSelected: park,
          onDirectDestination: direct,
          parkingLoading: parkingLoading,
          finalDestinationTitle: parking.isEmpty ? null : 'Final destination',
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
}

Future<void> reveal(WidgetTester t, Finder f) async {
  await t.scrollUntilVisible(
    f,
    200,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 40,
  );
  await t.ensureVisible(f);
  await t.pumpAndSettle();
}

void main() {
  for (final zh in [false, true]) {
    testWidgets(
      'route card $zh explains heavy traffic, cameras, alternatives and filters',
      (t) async {
        final routes = [
          option('fast', jam: 2, delay: 120),
          option('slow', time: 7320, distance: 19000, slow: 1, delay: 90),
          option('long', time: 3630, distance: 21000),
        ];
        RouteOption? picked;
        RouteFilter? filtered;
        await show(
          t,
          routes,
          zh: zh,
          select: (r) => picked = r,
          filter: (f) => filtered = f,
        );
        expect(
          find.textContaining(zh ? '红灯 + 测速' : 'red light + speed'),
          findsWidgets,
        );
        expect(
          find.textContaining(zh ? '公交 / 专用车道' : 'bus / transit lane'),
          findsWidgets,
        );
        expect(
          find.textContaining(
            zh ? '前方有 2 段严重拥堵' : '2 heavy-traffic sections ahead',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            zh ? '路线包含高速公路路段' : 'This route includes a highway.',
          ),
          findsOneWidget,
        );
        final longCard = find.textContaining('Route long');
        await reveal(t, longCard);
        await t.tap(longCard);
        await t.pump();
        expect(picked!.id, 'long');
        final chip = find.widgetWithText(
          ChoiceChip,
          zh ? '距离最短' : 'Shortest first',
        );
        await reveal(t, chip);
        await t.tap(chip);
        await t.pump();
        expect(filtered, RouteFilter.shortest);
        final description = routeExplanation(routes[1], routes, isChinese: zh);
        expect(description, contains(zh ? '少走' : 'shorter'));
        expect(description, contains(zh ? '拥堵增加' : 'traffic delay'));
        expect(
          routeExplanation(routes[2], routes, isChinese: zh),
          contains(zh ? '多走' : 'longer'),
        );
      },
    );
    testWidgets(
      'restricted route $zh offers a detour and closure details while camera filters are unavailable',
      (t) async {
        var retries = 0;
        RoadEvent? opened;
        await show(
          t,
          [
            option('restricted', restricted: ['bus-road']),
          ],
          zh: zh,
          cameras: false,
          closures: const {
            'restricted': [closure],
          },
          retry: () => retries++,
          event: (e) => opened = e,
          filter: (_) {},
        );
        expect(
          find.text(
            zh ? '当前时段禁止普通汽车通行' : 'Bus-only road during restricted hours',
          ),
          findsOneWidget,
        );
        expect(
          find.text(zh ? '摄像头数据暂不可用' : 'Camera data unavailable'),
          findsOneWidget,
        );
        final chips = t
            .widgetList<ChoiceChip>(find.byType(ChoiceChip))
            .toList();
        expect(
          chips
              .where(
                (c) =>
                    (c.label as Text).data ==
                    (zh ? '避开已知摄像头' : 'No matched cameras'),
              )
              .single
              .onSelected,
          isNull,
        );
        final road = find.text('Closed ramp');
        await reveal(t, road);
        await t.tap(road);
        await t.pump();
        expect(opened?.id, 'closure');
        final detour = find.byKey(const Key('routeDetourButton'));
        await reveal(t, detour);
        await t.tap(detour);
        await t.pump();
        expect(retries, 1);
      },
    );
    testWidgets(
      'transit itinerary $zh displays transfers, route names and stops',
      (t) async {
        const legs = [
          TransitLeg(
            lineName: 'AirportLink',
            headsign: 'Puhinui',
            vehicleType: 'BUS',
            vehicleName: 'Bus',
            departureStop: 'Airport',
            arrivalStop: 'Puhinui',
            stopCount: 4,
          ),
          TransitLeg(
            lineName: 'Southern line',
            headsign: 'Britomart',
            vehicleType: 'RAIL',
            vehicleName: 'Train',
            departureStop: 'Puhinui',
            arrivalStop: 'Britomart',
            stopCount: 0,
          ),
        ];
        await show(
          t,
          [
            option(
              'transit',
              mode: WaybiTravelMode.transit,
              time: 7260,
              transit: legs,
            ),
          ],
          zh: zh,
          mode: WaybiTravelMode.transit,
        );
        expect(find.text('AirportLink → Puhinui'), findsOneWidget);
        expect(find.text('Southern line → Britomart'), findsOneWidget);
        expect(find.textContaining(zh ? '4 站' : '4 stops'), findsOneWidget);
        expect(
          find.textContaining(zh ? '2 小时 1 分钟' : '2 hr 1 min'),
          findsWidgets,
        );
      },
    );
    testWidgets(
      'parking alternatives $zh keep capacity, distance and direct destination actions usable',
      (t) async {
        const places = [
          ParkingPlace(
            id: 'p1',
            name: 'Near park',
            address: 'Park road',
            location: GeoPoint(-37.2, 174.91),
            distanceMeters: 50,
            source: 'AT',
            totalSpaces: 100,
            mobilitySpaces: 3,
          ),
          ParkingPlace(
            id: 'p2',
            name: 'Further park',
            address: '',
            location: GeoPoint(-37.2, 174.92),
            distanceMeters: 1500,
            source: 'AT',
          ),
        ];
        ParkingPlace? picked;
        var straight = 0;
        await show(
          t,
          [option('park')],
          zh: zh,
          parking: places,
          park: (p) => picked = p,
          direct: () => straight++,
        );
        final near = find.text('Near park');
        await reveal(t, near);
        await t.tap(near);
        await t.pump();
        expect(picked!.id, 'p1');
        expect(
          find.textContaining(zh ? '总车位 100' : '100 total spaces'),
          findsOneWidget,
        );
        final horizontal = find
            .byWidgetPredicate(
              (w) => w is ListView && w.scrollDirection == Axis.horizontal,
            )
            .last;
        await t.drag(horizontal, const Offset(-300, 0));
        await t.pumpAndSettle();
        expect(find.text('Further park'), findsOneWidget);
        expect(find.textContaining(zh ? '1.5 公里' : '1.5 km'), findsOneWidget);
        final button = find.text(
          zh ? '直接前往终点' : 'Route straight to destination',
        );
        await reveal(t, button);
        await t.tap(button);
        await t.pump();
        expect(straight, 1);
      },
    );
  }
  test('route explanations preserve seconds, exact hours and descriptions without alternatives', () {
    final fast = option('fast', time: 3600),
        near = option('near', time: 3630),
        long = option('long', time: 7200);
    expect(routeExplanation(near, [fast, near]), contains('+30s'));
    expect(routeExplanation(long, [fast, long]), contains('+1 hr'));
    expect(
      routeExplanation(long, [fast, long], isChinese: true),
      contains('1 小时'),
    );
    expect(routeExplanation(fast, []), 'Route fast');
  });
}
