import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/data/parking_repository.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/drive/drive_engine.dart';
import 'package:waybi_mobile/theme/waybi_theme.dart';
import 'package:waybi_mobile/widgets/arrival_experience_panel.dart';
import 'package:waybi_mobile/widgets/navigation_overlay.dart';
import 'package:waybi_mobile/widgets/route_preview_sheet.dart';
import 'package:waybi_mobile/widgets/transit_trip_overlay.dart';
import 'package:waybi_mobile/widgets/trips_page.dart';

/// Every key surface at iPhone SE (375×667) and 4" (320×568) sizes, text
/// scale 1.0 / 1.5 / 2.0, light and dark, English and Chinese.
const sizes = [Size(375, 667), Size(320, 568)];
const scales = [1.0, 1.5, 2.0];

const parking = [
  ParkingPlace(
    id: 'p1',
    name: 'Downtown car park with a long descriptive name',
    address: '31 Customs Street West, Auckland Central',
    location: GeoPoint(-36.844, 174.765),
    distanceMeters: 180,
    source: 'Auckland Transport',
    totalSpaces: 1944,
    mobilitySpaces: 40,
  ),
  ParkingPlace(
    id: 'p2',
    name: 'Victoria Street car park',
    address: 'Victoria Street West',
    location: GeoPoint(-36.848, 174.762),
    distanceMeters: 1450,
    source: 'Auckland Transport',
  ),
];

RouteOption drive(String id, {int time = 2700, int jam = 0}) => RouteOption(
  id: id,
  mode: WaybiTravelMode.drive,
  durationSeconds: time,
  distanceMeters: 23400,
  provider: 'independent',
  points: const [GeoPoint(-36.85, 174.76), GeoPoint(-36.9, 174.8)],
  traffic: TrafficSummary(normal: 0, slow: 1, trafficJam: jam),
  trafficIntervals: const [],
  trafficDelaySeconds: 420,
  description: 'Via State Highway 1 and the Harbour Bridge',
  warnings: const ['This route includes a highway.'],
);

final transit = RouteOption.fromJson({
  'id': 'bus',
  'mode': 'transit',
  'durationSeconds': 3660,
  'distanceMeters': 12000,
  'transit': [
    {
      'lineName': 'NX1',
      'headsign': 'Britomart',
      'departureStop': 'Albany Station',
      'arrivalStop': 'Britomart',
    },
  ],
});

Widget app(Widget child, {required bool dark, required String lang}) =>
    MaterialApp(
      theme: WaybiTheme.lightFor(lang),
      darkTheme: WaybiTheme.darkFor(lang),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      locale: Locale(lang),
      supportedLocales: const [Locale('en'), Locale('zh')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: child,
    );

Future<void> layout(
  WidgetTester t,
  Size size,
  double scale,
  Widget child, {
  bool settle = true,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  await t.pumpWidget(child);
  await t.pump(const Duration(milliseconds: 400));
  if (settle) await t.pumpAndSettle();
}

/// Fails with the overflowing widget's diagnostics, not just its message.
void expectLaidOut(WidgetTester t) {
  final error = t.takeException();
  if (error is FlutterError) fail(error.toStringDeep());
  expect(error, isNull);
}

void main() {
  for (final size in sizes) {
    for (final scale in scales) {
      for (final dark in [false, true]) {
        for (final lang in ['en', 'zh']) {
          final label =
              '${size.width.toInt()}x${size.height.toInt()} @$scale '
              '${dark ? 'dark' : 'light'} $lang';

          testWidgets('route preview fits $label', (t) async {
            await layout(
              t,
              size,
              scale,
              app(
                dark: dark,
                lang: lang,
                Scaffold(
                  body: Align(
                    alignment: Alignment.bottomCenter,
                    child: RoutePreviewSheet(
                      destinationTitle: 'Auckland War Memorial Museum',
                      originTitle: 'Current location',
                      plan: RoutePlan(
                        options: [drive('a', jam: 1), drive('b', time: 3100)],
                        trafficAvailable: true,
                        provider: 'independent',
                        stopsApplied: 1,
                      ),
                      selectedMode: WaybiTravelMode.drive,
                      selectedRouteId: 'a',
                      busy: false,
                      stopCount: 1,
                      cameraCount: 2,
                      routeCameraSummaries: const {
                        'a': RouteCameraSummary(
                          count: 2,
                          types: ['Spot speed', 'Red light'],
                        ),
                      },
                      customOrigin: true,
                      parkingPlaces: parking,
                      selectedParkingId: 'p1',
                      finalDestinationTitle: 'Auckland Museum',
                      onParkingSelected: (_) {},
                      onDirectDestination: () {},
                      onModeChanged: (_) {},
                      onRouteSelected: (_) {},
                      onStart: () {},
                      onAddStop: () {},
                      onSave: () {},
                      isFavorite: false,
                      onFavorite: () {},
                      onReview: () {},
                      onClose: () {},
                      onFilterChanged: (_) {},
                      isChinese: lang == 'zh',
                    ),
                  ),
                ),
              ),
            );
            expectLaidOut(t);
          });

          testWidgets('arrival panel fits $label', (t) async {
            {
              await layout(
                t,
                size,
                scale,
                app(
                  dark: dark,
                  lang: lang,
                  Scaffold(
                    body: SingleChildScrollView(
                      padding: const EdgeInsets.all(14),
                      child: ArrivalExperiencePanel(
                        language: lang,
                        destinationTitle: 'Auckland War Memorial Museum',
                        destinationAddress: 'Auckland Domain, Parnell',
                        remainingMeters: 640,
                        parkingPlaces: parking,
                        parkingLoading: false,
                        onParkingSelected: (_) {},
                      ),
                    ),
                  ),
                ),
              );
              expectLaidOut(t);
            }
            await layout(
              t,
              size,
              scale,
              app(
                dark: dark,
                lang: lang,
                Scaffold(
                  body: ArrivalExperiencePanel(
                    language: lang,
                    destinationTitle: 'Museum',
                    remainingMeters: 640,
                    parkingPlaces: const [],
                    parkingLoading: true,
                    onParkingSelected: (_) {},
                  ),
                ),
              ),
              settle: false,
            );
            expectLaidOut(t);
          });

          testWidgets('navigation overlay fits $label', (t) async {
            final engine = DriveEngine()
              ..speedKph = 52
              ..speedLimitKph = 50;
            addTearDown(engine.dispose);
            await layout(
              t,
              size,
              scale,
              app(
                dark: dark,
                lang: lang,
                Scaffold(
                  body: NavigationOverlay(
                    engine: engine,
                    language: lang,
                    guidance: const NavigationGuidance(
                      instruction:
                          'Turn left onto Karangahape Road toward Ponsonby',
                      maneuverIcon: Icons.turn_left_rounded,
                      stepMeters: 240,
                      remainingMeters: 12400,
                      remainingSeconds: 1500,
                      thenInstruction: 'Keep right onto State Highway 16',
                    ),
                    destinationTitle: 'Te Whatu Stardome Observatory',
                    gpsAccuracy: 9,
                    voiceEnabled: true,
                    lanesEnabled: true,
                    onEnd: () {},
                    onRecenter: () {},
                    onOverview: () {},
                    northUp: false,
                    onCompassToggle: () {},
                    onReport: () {},
                    onSearchAlongRoute: () {},
                    onDirections: () {},
                    onShare: () {},
                    onSettings: () {},
                    onLayers: () {},
                    onVoiceToggle: () {},
                    onLanesToggle: () {},
                    offlineReady: true,
                  ),
                ),
              ),
            );
            expectLaidOut(t);
            await t.tap(find.byKey(const Key('navigationSheetHandle')));
            await t.pumpAndSettle();
            expectLaidOut(t);
          });

          testWidgets('transit trip fits $label', (t) async {
            await layout(
              t,
              size,
              scale,
              app(
                dark: dark,
                lang: lang,
                Scaffold(
                  body: TransitTripOverlay(
                    destinationTitle: 'Britomart Transport Centre',
                    route: transit,
                    gpsAccuracy: 12,
                    onEnd: () {},
                    onRecenter: () {},
                  ),
                ),
              ),
            );
            expectLaidOut(t);
          });

          testWidgets('trips page and Route Watch details fit $label', (
            t,
          ) async {
            final watch = RouteWatchItem(
              id: 'w',
              label: 'home-work',
              status: 'disrupted',
              lastCheckedAt: DateTime.now().subtract(
                const Duration(minutes: 5),
              ),
              events: [
                for (var i = 0; i < 5; i++)
                  RouteWatchEvent(
                    type: 'closure',
                    severity: 'major',
                    roadName: 'State Highway 1 Auckland Harbour Bridge $i',
                    impact: 'Lane closed northbound',
                    description: 'Two lanes closed for urgent maintenance; expect delays of up to 20 minutes.',
                  ),
              ],
            );
            final snapshot = TripsSnapshot(
              signedIn: true,
              isPlus: true,
              quickPlaces: const {
                'Home': TripDestination(
                  name: 'Home',
                  location: GeoPoint(-36.8, 174.7),
                ),
                'Work': TripDestination(
                  name: 'Work',
                  location: GeoPoint(-36.85, 174.76),
                ),
              },
              quickRoutes: {'Home': drive('h'), 'Work': drive('w', jam: 1)},
              routeWatches: {'home-work': watch},
              recent: const [
                TripDestination(
                  name: 'Auckland War Memorial Museum',
                  address: 'Auckland Domain, Parnell',
                  location: GeoPoint(-36.86, 174.77),
                ),
              ],
              history: [
                for (var i = 0; i < 4; i++)
                  TripHistoryItem(
                    destination: const TripDestination(
                      name: 'Sky Tower',
                      location: GeoPoint(-36.84, 174.76),
                    ),
                    mode: 'drive',
                    distanceMeters: 12000,
                    durationSeconds: 1600,
                    createdAt: DateTime.now().subtract(Duration(days: i * 4)),
                  ),
              ],
            );
            await layout(
              t,
              size,
              scale,
              app(
                dark: dark,
                lang: lang,
                TripsPage(language: lang, loader: () async => snapshot),
              ),
            );
            expectLaidOut(t);
            final details = find.byTooltip(
              lang == 'zh' ? '路线监控详情' : 'Route Watch details',
            );
            await t.scrollUntilVisible(
              details,
              120,
              scrollable: find.byType(Scrollable).first,
            );
            await t.ensureVisible(details);
            await t.pumpAndSettle();
            await t.tap(details);
            await t.pumpAndSettle();
            expectLaidOut(t);
            final last = find.text('State Highway 1 Auckland Harbour Bridge 4');
            await t.scrollUntilVisible(
              last,
              120,
              scrollable: find
                  .descendant(
                    of: find.byType(BottomSheet),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            expect(last, findsOneWidget);
            expectLaidOut(t);
          });
        }
      }
    }
  }

  for (final height in [300.0, 220.0, 140.0]) {
    testWidgets('navigation survives a ${height.toInt()} pt tall window', (
      t,
    ) async {
      // Android split screen or a short window with the keyboard up: the
      // sheet bounds used to clamp with lower > upper below 333 pt.
      final engine = DriveEngine();
      addTearDown(engine.dispose);
      await layout(
        t,
        Size(390, height),
        1,
        app(
          dark: false,
          lang: 'en',
          Scaffold(
            body: NavigationOverlay(
              engine: engine,
              destinationTitle: 'Wellington Railway Station',
              gpsAccuracy: 6,
              voiceEnabled: true,
              lanesEnabled: true,
              onEnd: () {},
              onRecenter: () {},
              onOverview: () {},
              northUp: true,
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
      );
      expectLaidOut(t);
      expect(find.byKey(const Key('navigationSheetHandle')), findsOneWidget);
    });
  }
}
