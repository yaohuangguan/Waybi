import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/domain/route_preference.dart';
import 'package:waybi_mobile/widgets/route_preview_sheet.dart';

RouteOption makeRoute(String id, int seconds, int metres) => RouteOption(
  id: id,
  mode: WaybiTravelMode.drive,
  durationSeconds: seconds,
  distanceMeters: metres,
  points: const [GeoPoint(-36.85, 174.76), GeoPoint(-36.86, 174.77)],
  provider: 'independent',
  traffic: const TrafficSummary(normal: 0, slow: 0, trafficJam: 0),
  trafficIntervals: const [],
);

void main() {
  testWidgets('route preview shows three preference-labelled alternatives', (
    tester,
  ) async {
    final routes = [
      makeRoute('fast', 600, 10000),
      makeRoute('balanced', 640, 9000),
      makeRoute('short', 700, 8000),
    ];
    WaybiTravelMode? requestedMode;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoutePreviewSheet(
            destinationTitle: 'Destination',
            originTitle: 'Current location',
            plan: RoutePlan(
              options: routes,
              trafficAvailable: true,
              provider: 'independent',
              stopsApplied: 0,
            ),
            selectedMode: WaybiTravelMode.drive,
            selectedRouteId: 'balanced',
            busy: false,
            stopCount: 0,
            cameraCount: 0,
            routeCameraSummaries: const {
              'fast': RouteCameraSummary(count: 2),
              'balanced': RouteCameraSummary(count: 0),
              'short': RouteCameraSummary(count: 1),
            },
            routePreferenceSummaries: const {
              'fast': RoutePreferenceSummary(
                cameraCount: 2,
                congestionScore: 400,
              ),
              'balanced': RoutePreferenceSummary(
                cameraCount: 0,
                congestionScore: 0,
              ),
              'short': RoutePreferenceSummary(
                cameraCount: 1,
                congestionScore: 200,
              ),
            },
            canRequestTransit: true,
            customOrigin: false,
            onModeChanged: (mode) => requestedMode = mode,
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

    expect(find.text('Recommended'), findsOneWidget);
    expect(find.text('Fastest'), findsOneWidget);
    expect(find.text('Shortest'), findsOneWidget);
    expect(find.text('Less traffic'), findsOneWidget);
    expect(find.text('0 cameras'), findsWidgets);
    expect(find.text('Load'), findsOneWidget);
    expect(find.text('No traffic data'), findsWidgets);
    expect(find.text('Light traffic'), findsNothing);
    expect(find.text('Clear'), findsNothing);

    await tester.tap(find.text('Transit'));
    await tester.pump();
    expect(requestedMode, WaybiTravelMode.transit);
  });
}
