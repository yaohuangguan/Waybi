import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/domain/route_preference.dart';
import 'package:waybi_mobile/domain/road_event.dart';
import 'package:waybi_mobile/domain/route_road_events.dart';
import 'package:waybi_mobile/providers/independent_routing_provider.dart';
import 'package:waybi_mobile/widgets/route_preview_sheet.dart';

RouteOption route(
  String id,
  int seconds,
  int metres, {
  List<String> closures = const [],
  List<RouteStepInfo> steps = const [],
}) => RouteOption(
  id: id,
  mode: WaybiTravelMode.drive,
  durationSeconds: seconds,
  distanceMeters: metres,
  points: const [GeoPoint(-36.85, 174.76), GeoPoint(-36.83, 174.76)],
  provider: 'independent',
  traffic: const TrafficSummary(normal: 0, slow: 0, trafficJam: 0),
  trafficIntervals: const [],
  closureIds: closures,
  steps: steps,
);
void main() {
  final fast = route('fast', 600, 10000);
  final short = route('short', 750, 8000);
  final clear = route('clear', 800, 11000);
  final routes = [fast, short, clear];
  const summaries = {
    'fast': RoutePreferenceSummary(cameraCount: 2),
    'short': RoutePreferenceSummary(cameraCount: 1),
    'clear': RoutePreferenceSummary(cameraCount: 0),
  };
  test('time, distance and camera filters use available routes without inventing an empty match', () {
    expect(
      filterRoutes(routes, RouteFilter.fastest, summaries).first.id,
      'fast',
    );
    expect(
      filterRoutes(routes, RouteFilter.shortest, summaries).first.id,
      'short',
    );
    expect(
      filterRoutes(routes, RouteFilter.avoidCameras, summaries).single.id,
      'clear',
    );
    expect(
      filterRoutes(routes, RouteFilter.withCameras, summaries).map((r) => r.id),
      ['fast', 'short'],
    );
    expect(
      filterRoutes([fast, short], RouteFilter.avoidCameras, summaries),
      isEmpty,
    );
    expect(filterRoutes(routes, RouteFilter.avoidCameras, const {}), isEmpty);
    expect(
      filterRoutes(
        routes,
        RouteFilter.fastest,
        summaries,
        blockedIds: {'fast'},
      ).first.id,
      'short',
    );
  });
  test('ramp closures do not close a through motorway and exclusions retain actual direction', () {
    const closure = RoadEvent(
      id: 'ramp',
      type: RoadEventType.roadClosure,
      location: GeoPoint(-36.84, 174.76),
      roadName: 'SH20 Queenstown Rd On-ramp Southbound',
      source: RoadEventSource(
        provider: 'NZTA',
        country: 'NZ',
        sourceId: 'ramp',
      ),
    );
    final through = route(
      'through',
      200,
      2200,
      steps: const [
        RouteStepInfo(
          instruction: '',
          distanceMeters: 2200,
          location: GeoPoint(-36.85, 174.76),
          roadName: 'Southwestern Motorway',
          maneuverType: 'depart',
        ),
      ],
    );
    expect(routeClosures(through, const [closure]), isEmpty);
    final transfer = route(
      'transfer',
      200,
      2000,
      steps: const [
        RouteStepInfo(
          instruction: '',
          distanceMeters: 500,
          location: GeoPoint(-36.85, 174.76),
          roadName: 'Northwestern Motorway',
          maneuverType: 'depart',
        ),
        RouteStepInfo(
          instruction: '',
          distanceMeters: 1500,
          location: GeoPoint(-36.845, 174.76),
          roadName: 'Southwestern Motorway',
          maneuverType: 'off ramp',
        ),
      ],
    );
    expect(routeClosures(transfer, const [closure]), isEmpty);
    expect(routeClosures(clear, const [closure]), hasLength(1));
    final exclusions = closureExclusions(clear, const [closure]);
    expect(exclusions.single.headingDegrees, closeTo(0, .1));
  });
  test(
    'signed closure direction on a curve preserves the opposite carriageway',
    () {
      const points = [GeoPoint(-36.91, 174.73), GeoPoint(-36.916, 174.75)];
      RouteOption curved(List<GeoPoint> geometry) => RouteOption(
        id: 'curve',
        mode: WaybiTravelMode.drive,
        durationSeconds: 200,
        distanceMeters: 2000,
        points: geometry,
        provider: 'independent',
        traffic: const TrafficSummary(normal: 0, slow: 0, trafficJam: 0),
        trafficIntervals: const [],
      );
      const event = RoadEvent(
        id: 'curve',
        type: RoadEventType.roadClosure,
        location: GeoPoint(-36.913, 174.74),
        roadName: 'SH20 Full Closure Southbound',
        headingDegrees: 180,
        source: RoadEventSource(
          provider: 'NZTA',
          country: 'NZ',
          sourceId: 'curve',
        ),
      );
      expect(routeClosures(curved(points), const [event]), hasLength(1));
      expect(
        routeClosures(curved(points.reversed.toList()), const [event]),
        isEmpty,
      );
    },
  );
  test('closure retry carries bounded exclusions and stop order through the free Waybi proxy', () async {
    final provider = IndependentRoutingProvider(
      useWaybiProxy: true,
      proxyBaseUrl: 'https://waybi.test',
      client: MockClient((request) async {
        expect(request.url.queryParameters['provider'], 'independent');
        expect(request.url.queryParameters['avoid'], '174.76,-36.84,180.0');
        expect(request.url.queryParameters['stops'], '174.77,-36.85');
        return http.Response(
          jsonEncode({
            'options': [
              {
                'id': 'detour',
                'mode': 'drive',
                'provider': 'independent',
                'durationSeconds': 200,
                'distanceMeters': 2200,
                'coordinates': [
                  [174.76, -36.85],
                  [174.78, -36.83],
                ],
                'traffic': {},
                'steps': [],
              },
            ],
          }),
          200,
        );
      }),
    );
    addTearDown(provider.dispose);
    final result = await provider.route(
      origin: const GeoPoint(-36.85, 174.76),
      destination: const GeoPoint(-36.83, 174.78),
      stops: const [GeoPoint(-36.85, 174.77)],
      language: 'en',
      mode: WaybiTravelMode.drive,
      avoid: const [RouteExclusion(GeoPoint(-36.84, 174.76), 180)],
    );
    expect(result.options.single.waypoints, hasLength(3));
  });
  testWidgets(
    'blocked preview offers a working detour action and keeps its result visible',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoutePreviewSheet(
              destinationTitle: 'Airport',
              originTitle: 'Current location',
              plan: RoutePlan(
                options: [
                  route('closed', 600, 10000, closures: ['ramp']),
                ],
                trafficAvailable: false,
                provider: 'independent',
                stopsApplied: 0,
              ),
              selectedMode: WaybiTravelMode.drive,
              selectedRouteId: 'closed',
              busy: false,
              stopCount: 0,
              cameraCount: 0,
              customOrigin: false,
              statusMessage: 'No verified detour. Retry or add a stop.',
              onRetry: () => calls++,
              onModeChanged: (_) {},
              onRouteSelected: (_) {},
              onStart: () {},
              onAddStop: () {},
              onSave: () {},
              isFavorite: false,
              onFavorite: () {},
              onReview: () {},
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('routeRecoveryStatus')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('routeDetourButton')));
      await tester.tap(find.byKey(const Key('routeDetourButton')));
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'camera filtering exposes an empty result and an available reset',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      RouteFilter? requested;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoutePreviewSheet(
              destinationTitle: 'Airport',
              originTitle: 'Current location',
              plan: RoutePlan(
                options: [fast, short],
                trafficAvailable: false,
                provider: 'independent',
                stopsApplied: 0,
              ),
              selectedMode: WaybiTravelMode.drive,
              selectedRouteId: 'fast',
              filter: RouteFilter.avoidCameras,
              onFilterChanged: (v) => requested = v,
              routePreferenceSummaries: summaries,
              busy: false,
              stopCount: 0,
              cameraCount: 0,
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
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('routeFilterEmpty')), findsOneWidget);
      await tester.ensureVisible(find.text('Show all routes'));
      await tester.tap(find.text('Show all routes'));
      expect(requested, RouteFilter.recommended);
      expect(tester.takeException(), isNull);
    },
  );
}
