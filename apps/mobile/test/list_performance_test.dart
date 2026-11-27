import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/road_event.dart';
import 'package:waybi_mobile/widgets/discover_page.dart';
import 'package:waybi_mobile/widgets/trips_page.dart';

RoadEvent event(
  String id,
  RoadEventType type,
  double lat, {
  bool major = false,
}) => RoadEvent(
  id: id,
  type: type,
  location: GeoPoint(lat, 174.7633),
  roadName: id,
  severity: major ? RoadEventSeverity.critical : RoadEventSeverity.advisory,
  source: RoadEventSource(provider: 'NZTA', country: 'NZ', sourceId: id),
);

void main() {
  testWidgets('trip history builds tiles on demand', (t) async {
    final snapshot = TripsSnapshot(
      quickPlaces: const {},
      quickRoutes: const {},
      recent: const [],
      history: [
        for (var i = 0; i < 300; i++)
          TripHistoryItem(
            destination: TripDestination(
              name: 'Stop $i',
              location: const GeoPoint(-36.85, 174.76),
            ),
            mode: 'drive',
            distanceMeters: 1000 + i,
            durationSeconds: 600,
            createdAt: DateTime.now().subtract(Duration(hours: i)),
          ),
      ],
    );
    await t.pumpWidget(
      MaterialApp(
        home: TripsPage(language: 'en', loader: () async => snapshot),
      ),
    );
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('300 trips'), 300);
    expect(find.text('300 trips'), findsOneWidget);
    final built = find.textContaining(RegExp(r'^Stop \d+$')).evaluate().length;
    expect(built, lessThan(60), reason: 'only visible history tiles build');
    await t.enterText(
      find.byKey(const ValueKey('trip-history-search')),
      'Stop 29',
    );
    await t.pumpAndSettle();
    expect(find.text('11 trips'), findsOneWidget);
  });

  testWidgets('nearby road events sort by severity then distance', (t) async {
    final roads = DiscoverRoadSnapshot(
      status: 'live',
      checkedAt: DateTime.now(),
      officialCoverage: const ['NZ'],
      events: [
        event('Far works', RoadEventType.roadworks, -36.95),
        event('Near works', RoadEventType.roadworks, -36.86),
        event('Closure', RoadEventType.roadClosure, -36.99, major: true),
        event('Too far', RoadEventType.roadworks, -37.5),
      ],
    );
    await t.pumpWidget(
      MaterialApp(
        home: DiscoverPage(
          language: 'zh',
          loader: () async => const TripsSnapshot(
            quickPlaces: {},
            quickRoutes: {},
            recent: [],
            history: [],
          ),
          roadLoader: () async => roads,
          origin: const GeoPoint(-36.8485, 174.7633),
        ),
      ),
    );
    await t.pumpAndSettle();
    final order = [
      'Closure',
      'Near works',
      'Far works',
    ].map((name) => t.getTopLeft(find.text(name)).dy).toList();
    expect(order, orderedEquals([...order]..sort()));
    expect(find.text('Too far'), findsNothing);
    expect(find.textContaining('道路施工 · 1.3 公里'), findsOneWidget);
  });
}
