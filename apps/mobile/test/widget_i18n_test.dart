import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart'
    show LatLng;
import 'package:waybi_mobile/domain/map_layer_settings.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/widgets/explore_search.dart';
import 'package:waybi_mobile/widgets/map_layer_sheet.dart';
import 'package:waybi_mobile/widgets/transit_trip_overlay.dart';
import 'package:waybi_mobile/widgets/trips_page.dart';
import 'package:waybi_mobile/widgets/waybi_format.dart';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('transit trip speaks Chinese', (t) async {
    await t.pumpWidget(
      host(
        TransitTripOverlay(
          language: 'zh',
          destinationTitle: 'Britomart',
          route: RouteOption.fromJson({
            'id': 'bus',
            'mode': 'transit',
            'durationSeconds': 3660,
            'distanceMeters': 12000,
          }),
          gpsAccuracy: 9,
          onEnd: () {},
          onRecenter: () {},
        ),
      ),
    );
    expect(find.text('公交行程'), findsOneWidget);
    expect(find.text('1 小时 1 分钟'), findsOneWidget);
    expect(find.text('结束行程'), findsOneWidget);
    expect(find.byTooltip('回到当前位置'), findsOneWidget);
    expect(find.textContaining('12 公里 · 预计'), findsOneWidget);
    expect(find.textContaining('GPS ±9 米'), findsOneWidget);
  });

  testWidgets('add-stop origin placeholder is localized before lookup', (
    t,
  ) async {
    await t.pumpWidget(
      host(
        ExploreSearch(
          language: 'zh',
          currentLocation: const LatLng(latitude: -36.85, longitude: 174.76),
          onSelected: (_) {},
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('正在定位当前位置…'), findsOneWidget);
    expect(find.text('Locating current position…'), findsNothing);
  });

  testWidgets('trips use day-month dates and localized units', (t) async {
    final old = DateTime.now().subtract(const Duration(days: 20));
    final snapshot = TripsSnapshot(
      isPlus: true,
      signedIn: true,
      quickPlaces: const {},
      quickRoutes: const {},
      recent: const [],
      history: [
        TripHistoryItem(
          destination: const TripDestination(
            name: 'Piha',
            location: GeoPoint(-36.95, 174.47),
          ),
          mode: 'drive',
          distanceMeters: 42000,
          durationSeconds: 3600,
          createdAt: old,
        ),
      ],
    );
    await t.pumpWidget(
      MaterialApp(
        home: TripsPage(language: 'zh', loader: () async => snapshot),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Plus · 近 30 天'), findsOneWidget);
    expect(find.text('42.0 公里'), findsOneWidget);
    expect(find.text('1.0 小时'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Piha'), 300);
    expect(
      find.textContaining(formatShortDate(old, 'zh')),
      findsOneWidget,
      reason: '月日, not US month/day',
    );
  });

  testWidgets('map layers do not promise a tap action that toggles', (t) async {
    await t.pumpWidget(
      host(
        MapLayerSheet(
          settings: const MapLayerSettings(),
          onChanged: (_) {},
          mapProvider: MapProvider.independent,
          language: 'en',
          transitLaneCount: 361,
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Bus & transit lanes'), 200);
    expect(find.textContaining('361 Auckland lanes'), findsOneWidget);
    expect(find.textContaining('Tap for details'), findsNothing);
  });
}
