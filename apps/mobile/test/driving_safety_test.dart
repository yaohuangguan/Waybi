import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart'
    show
        NavInfo,
        StepInfo,
        DrivingSide,
        Lane,
        LaneDirection,
        LaneShape,
        Maneuver,
        NavState;
import 'package:waybi_mobile/domain/road_event.dart';
import 'package:waybi_mobile/domain/safety_camera.dart';
import 'package:waybi_mobile/drive/camera_alert_lifecycle.dart';
import 'package:waybi_mobile/data/parking_repository.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/navigation_lanes.dart';
import 'package:waybi_mobile/drive/drive_engine.dart';
import 'package:waybi_mobile/theme/waybi_theme.dart';
import 'package:waybi_mobile/widgets/arrival_experience_panel.dart';
import 'package:waybi_mobile/widgets/drive_hud.dart';
import 'package:waybi_mobile/widgets/driving_motion.dart';
import 'package:waybi_mobile/widgets/hold_to_end_button.dart';
import 'package:waybi_mobile/widgets/navigation_overlay.dart';
import 'package:waybi_mobile/widgets/speed_readout.dart';

import 'support/hold.dart';

Widget host(Widget child, {String lang = 'en', bool a11y = false}) =>
    MaterialApp(
      theme: WaybiTheme.lightFor(lang),
      locale: Locale(lang),
      supportedLocales: const [Locale('en'), Locale('zh')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(accessibleNavigation: a11y),
        child: child!,
      ),
      home: Scaffold(body: child),
    );

HoldToEndButton endButton(VoidCallback onEnd) => HoldToEndButton(
  key: const Key('end'),
  label: 'End',
  holdHint: 'Hold to end',
  confirmTitle: 'End navigation?',
  confirmAction: 'End',
  cancelAction: 'Keep navigating',
  onEnd: onEnd,
);

double fontSizeOf(WidgetTester t, Finder text) =>
    t.renderObject<RenderParagraph>(text).text.style!.fontSize!;

NavigationOverlay overlay(
  DriveEngine engine, {
  NavigationGuidance? guidance,
  Widget? arrival,
}) => NavigationOverlay(
  engine: engine,
  guidance: guidance,
  destinationTitle: 'Auckland Museum',
  gpsAccuracy: 7,
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
  arrivalPanel: arrival,
);

const parking = [
  ParkingPlace(
    id: 'p1',
    name: 'Domain car park',
    address: 'Domain Drive',
    location: GeoPoint(-36.86, 174.77),
    distanceMeters: 120,
    source: 'AT',
  ),
  ParkingPlace(
    id: 'p2',
    name: 'Stanley Street',
    address: 'Stanley Street',
    location: GeoPoint(-36.85, 174.78),
    distanceMeters: 640,
    source: 'AT',
  ),
];

void main() {
  group('hold to end', () {
    testWidgets('a tap explains, a hold ends, sliding off cancels', (t) async {
      var ended = 0;
      await t.pumpWidget(host(Center(child: endButton(() => ended++))));
      await t.tap(find.byKey(const Key('end')));
      await t.pump();
      expect(ended, 0);
      expect(find.text('Hold to end'), findsOneWidget);

      // Releasing early or dragging away never ends the trip.
      final early = await t.startGesture(
        t.getCenter(find.byKey(const Key('end'))),
      );
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      await early.up();
      await t.pump(const Duration(seconds: 2));
      expect(ended, 0);
      final slide = await t.startGesture(
        t.getCenter(find.byKey(const Key('end'))),
      );
      await t.pump(const Duration(milliseconds: 200));
      await slide.moveBy(const Offset(0, 200));
      await t.pump(const Duration(seconds: 2));
      await slide.up();
      expect(ended, 0);

      await holdToEnd(t, find.byKey(const Key('end')));
      expect(ended, 1);
      expect(
        t.getSize(find.byKey(const Key('end'))).height,
        greaterThanOrEqualTo(48),
      );
    });

    testWidgets('screen-reader activation asks to confirm', (t) async {
      var ended = 0;
      await t.pumpWidget(
        host(Center(child: endButton(() => ended++)), a11y: true),
      );
      final semantics = t.ensureSemantics();
      expect(
        t.getSemantics(find.byKey(const Key('end'))),
        matchesSemantics(
          label: 'End',
          hint: 'Hold to end',
          isButton: true,
          hasTapAction: true,
          hasLongPressAction: true,
        ),
      );
      final node = t.getSemantics(find.byKey(const Key('end')));
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await t.pumpAndSettle();
      expect(find.text('End navigation?'), findsOneWidget);
      await t.tap(find.text('Keep navigating'));
      await t.pumpAndSettle();
      expect(ended, 0);
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'End'));
      await t.pumpAndSettle();
      expect(ended, 1);
      node.owner!.performAction(node.id, SemanticsAction.longPress);
      expect(ended, 2);
      semantics.dispose();
    });

    testWidgets('without a screen reader a semantic tap only shows the hint', (
      t,
    ) async {
      var ended = 0;
      await t.pumpWidget(host(Center(child: endButton(() => ended++))));
      final semantics = t.ensureSemantics();
      final node = t.getSemantics(find.byKey(const Key('end')));
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await t.pump();
      expect(find.text('Hold to end'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(ended, 0);
      semantics.dispose();
    });
  });

  testWidgets('Just Drive HUD is glanceable, localized and hold-to-end', (
    t,
  ) async {
    final engine = DriveEngine()
      ..speedKph = 63
      ..speedLimitKph = 50;
    addTearDown(engine.dispose);
    var stopped = 0;
    await t.pumpWidget(
      host(
        DriveHud(engine: engine, onStop: () => stopped++),
        lang: 'zh',
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('自由驾驶'), findsOneWidget);
    expect(find.text('摄像头'), findsOneWidget);
    expect(find.bySemanticsLabel('限速 50 公里/时'), findsOneWidget);
    expect(find.bySemanticsLabel('当前速度 63 公里/时，已超速'), findsOneWidget);
    expect(find.byKey(const ValueKey('overSpeedIcon')), findsOneWidget);
    expect(fontSizeOf(t, find.text('63')), greaterThanOrEqualTo(24));
    expect(fontSizeOf(t, find.text('摄像头')), greaterThanOrEqualTo(12));
    expect(fontSizeOf(t, find.text('公里/时')), greaterThanOrEqualTo(12));
    for (final text in ['SPEED', 'LIMIT', 'REMAIN', 'End drive']) {
      expect(find.textContaining(text), findsNothing);
    }
    await t.tap(find.byKey(const Key('driveEndButton')));
    await t.pump();
    expect(stopped, 0);
    await holdToEnd(t, find.byKey(const Key('driveEndButton')));
    expect(stopped, 1);
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('unknown limits show a neutral roundel', (t) async {
    await t.pumpWidget(host(const SpeedLimitSign(limitKph: null)));
    expect(find.text('—'), findsOneWidget);
    expect(find.bySemanticsLabel('Speed limit unknown'), findsOneWidget);
  });

  testWidgets('turn banner uses the driving type scale', (t) async {
    final engine = DriveEngine();
    addTearDown(engine.dispose);
    await t.pumpWidget(
      host(
        overlay(
          engine,
          guidance: NavigationGuidance(
            instruction: 'Turn left onto Queen Street',
            thenInstruction: 'Keep right',
            maneuverIcon: Icons.turn_left_rounded,
            stepMeters: 120,
            remainingMeters: 3400,
            remainingSeconds: 600,
            lanes: const [
              NavigationLane({LaneArrowDirection.left}, true),
              NavigationLane({}, false),
            ],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(fontSizeOf(t, find.text('120 m')), greaterThanOrEqualTo(28));
    expect(
      fontSizeOf(t, find.text('Turn left onto Queen Street')),
      greaterThanOrEqualTo(18),
    );
    expect(
      fontSizeOf(t, find.text('Then · Keep right')),
      greaterThanOrEqualTo(16),
    );
    expect(
      fontSizeOf(t, find.byKey(const Key('navigationLaneDataNotice'))),
      greaterThanOrEqualTo(16),
    );
    expect(fontSizeOf(t, find.text('3.4 km').first), greaterThanOrEqualTo(16));
  });

  for (final moving in [true, false]) {
    testWidgets(
      'trip tools ${moving ? 'are limited while moving' : 'are all available when stopped'}',
      (t) async {
        final engine = DriveEngine()..speedKph = moving ? 62 : 0;
        addTearDown(engine.dispose);
        await t.pumpWidget(host(overlay(engine)));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('navigationSheetHandle')));
        await t.pumpAndSettle();
        expect(find.text('Add a report'), findsOneWidget);
        expect(find.text('Directions'), findsOneWidget);
        expect(find.text('Preview route'), findsOneWidget);
        expect(find.text('Settings'), moving ? findsNothing : findsOneWidget);
        expect(
          find.text('Share ETA snapshot'),
          moving ? findsNothing : findsOneWidget,
        );
        expect(
          find.byKey(const Key('navigationToolsLocked')),
          moving ? findsOneWidget : findsNothing,
        );
        if (moving) {
          await t.ensureVisible(
            find.byKey(const Key('navigationPassengerUnlock')),
          );
          await t.tap(find.byKey(const Key('navigationPassengerUnlock')));
          await t.pumpAndSettle();
          expect(find.text('Settings'), findsOneWidget);
          expect(find.text('Search along route'), findsOneWidget);
        }
      },
    );
  }

  testWidgets('motion state follows the engine with hysteresis', (t) async {
    final engine = DriveEngine()..speedKph = 0;
    addTearDown(engine.dispose);
    late bool seen;
    await t.pumpWidget(
      host(
        overlay(
          engine,
          arrival: Builder(
            builder: (context) {
              seen = DrivingMotion.of(context);
              return const SizedBox(height: 10);
            },
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('arrivalSummary')));
    await t.pumpAndSettle();
    expect(seen, isFalse);
    engine
      ..speedKph = 30
      ..notifyListeners();
    await t.pump();
    expect(seen, isTrue);
    engine
      ..speedKph = 5
      ..notifyListeners();
    await t.pump();
    expect(seen, isTrue, reason: 'a crawl in traffic stays "moving"');
    engine
      ..speedKph = 1
      ..notifyListeners();
    await t.pump();
    expect(seen, isFalse);
    expect(DrivingMotion.next(false, 7), isFalse);
    expect(DrivingMotion.next(false, 8), isTrue);
  });

  for (final moving in [true, false]) {
    testWidgets(
      'arrival parking ${moving ? 'is one large action while moving' : 'lists options when stopped'}',
      (t) async {
        ParkingPlace? picked;
        await t.pumpWidget(
          host(
            SingleChildScrollView(
              child: ArrivalExperiencePanel(
                language: 'en',
                destinationTitle: 'Auckland Museum',
                remainingMeters: 420,
                parkingPlaces: parking,
                parkingLoading: false,
                isMoving: moving,
                onParkingSelected: (p) => picked = p,
              ),
            ),
          ),
        );
        if (moving) {
          final park = find.byKey(const Key('arrivalParkNearest'));
          expect(t.getSize(park).height, greaterThanOrEqualTo(56));
          expect(find.textContaining('Stanley Street'), findsNothing);
          expect(
            find.text('More parking options appear when you stop.'),
            findsOneWidget,
          );
          await t.tap(park);
          expect(picked?.id, 'p1');
        } else {
          expect(find.byKey(const Key('arrivalParkNearest')), findsNothing);
          final second = find.widgetWithText(
            OutlinedButton,
            'Stanley Street · 640 m',
          );
          expect(t.getSize(second).height, greaterThanOrEqualTo(48));
          await t.tap(second);
          expect(picked?.id, 'p2');
        }
      },
    );
  }

  testWidgets('arrival panel reads motion from the navigation overlay', (
    t,
  ) async {
    await t.pumpWidget(
      host(
        DrivingMotion(
          moving: true,
          child: ArrivalExperiencePanel(
            language: 'zh',
            destinationTitle: '奥克兰博物馆',
            remainingMeters: 300,
            parkingPlaces: parking,
            parkingLoading: false,
            selectedParkingTitle: null,
            onParkingSelected: (_) {},
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('arrivalParkNearest')), findsOneWidget);
    expect(find.text('停车后可查看更多停车选项。'), findsOneWidget);
  });

  testWidgets('native guidance HUD shows the step, lanes, passed camera and '
      'road events in the driving scale', (t) async {
    final engine = DriveEngine()
      ..speedKph = 40
      ..speedLimitKph = 50
      ..navInfo = NavInfo(
        currentStep: StepInfo(
          distanceFromPrevStepMeters: 0,
          timeFromPrevStepSeconds: 0,
          drivingSide: DrivingSide.left,
          exitNumber: null,
          fullInstructions: '左转进入 Queen Street',
          fullRoadName: 'Queen Street',
          simpleRoadName: 'Queen St',
          roundaboutTurnNumber: null,
          stepNumber: 1,
          lanes: [
            Lane(
              laneDirections: [
                LaneDirection(
                  laneShape: LaneShape.normalLeft,
                  isRecommended: true,
                ),
              ],
            ),
            Lane(
              laneDirections: [
                LaneDirection(
                  laneShape: LaneShape.straight,
                  isRecommended: false,
                ),
              ],
            ),
          ],
          maneuver: Maneuver.values.first,
          maneuverImage: null,
          lanesImage: null,
        ),
        remainingSteps: const [],
        routeChanged: false,
        distanceToCurrentStepMeters: 180,
        distanceToFinalDestinationMeters: 4200,
        distanceToNextDestinationMeters: 4200,
        timeToCurrentStepSeconds: 20,
        timeToFinalDestinationSeconds: 600,
        timeToNextDestinationSeconds: 600,
        navState: NavState.enroute,
      )
      ..passedCamera = const SafetyCamera(
        id: 'c',
        name: 'Camera',
        region: 'Auckland',
        suburb: 'CBD',
        location: 'Hobson Street',
        type: 'Red light',
        latitude: -36.85,
        longitude: 174.76,
      )
      ..cameraAlertState = const CameraAlertState(CameraAlertPhase.passed)
      ..upcomingRoadEvents = const [
        RoadEvent(
          id: 'works',
          type: RoadEventType.roadworks,
          location: GeoPoint(-36.85, 174.76),
          source: RoadEventSource(
            provider: 'NZTA',
            country: 'NZ',
            sourceId: 'w',
          ),
          distanceFromDriver: 600,
        ),
      ];
    addTearDown(engine.dispose);
    await t.pumpWidget(
      host(
        DriveHud(engine: engine, onStop: () {}),
        lang: 'zh',
      ),
    );
    await t.pumpAndSettle();
    expect(fontSizeOf(t, find.text('180 米')), greaterThanOrEqualTo(28));
    expect(
      fontSizeOf(t, find.text('左转进入 Queen Street')),
      greaterThanOrEqualTo(18),
    );
    expect(find.text('已通过摄像头 · Hobson Street'), findsOneWidget);
    expect(find.text('剩余'), findsOneWidget);
    expect(find.text('4.2 公里'), findsOneWidget);
    expect(find.text('道路施工'), findsOneWidget);
    expect(find.bySemanticsLabel('限速 50 公里/时'), findsOneWidget);
  });
}
