import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/drive/drive_engine.dart';
import 'package:waybi_mobile/domain/navigation_lanes.dart';
import 'package:waybi_mobile/widgets/lane_arrow.dart';
import 'package:waybi_mobile/widgets/navigation_overlay.dart';

void main() {
  test('navigation distances never show negative metres', () {
    expect(navigationDistanceLabel(-25), '0 m');
    expect(navigationDistanceLabel(1500), '1.5 km');
  });
  testWidgets('compact navigation layout fits a small iPhone and expands', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final engine = DriveEngine();
    var recenterCount = 0;
    var overviewCount = 0;
    final insets = <double>[];
    final bottomInsets = <double>[];
    addTearDown(engine.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: NavigationOverlay(
                  engine: engine,
                  onTopInsetChanged: insets.add,
                  onBottomInsetChanged: bottomInsets.add,
                  destinationTitle:
                      'Te Whatu Stardome Observatory & Planetarium',
                  gpsAccuracy: 18,
                  voiceEnabled: true,
                  lanesEnabled: true,
                  onEnd: () {},
                  onRecenter: () => recenterCount += 1,
                  onOverview: () => overviewCount += 1,
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('End'), findsOneWidget);
    expect(insets, hasLength(1));
    expect(
      insets.single,
      greaterThan(
        tester
            .getRect(find.byKey(const Key('navigationGuidanceHeader')))
            .bottom,
      ),
    );
    expect(bottomInsets.single, greaterThan(100));
    expect(bottomInsets.single, lessThan(667 * .45 + 15));
    expect(find.text('GPS ±18 m'), findsOneWidget);
    expect(find.byTooltip('Route overview'), findsOneWidget);
    expect(find.text('Add a report'), findsNothing);

    await tester.tap(find.text('GPS ±18 m'));
    await tester.pump();
    expect(recenterCount, 0);

    await tester.tap(find.byTooltip('Route overview'));
    await tester.pump();
    expect(recenterCount, 0);
    expect(overviewCount, 1);

    // Drag from destination content, well outside the small handle.
    final start = tester.getCenter(
      find.text('Te Whatu Stardome Observatory & Planetarium'),
    );
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(0, -45));
    await tester.pump();
    expect(
      tester.getRect(find.byKey(const Key('navigationSheetHandle'))).top,
      lessThan(start.dy - 40),
    );
    await gesture.moveBy(const Offset(0, -110));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Add a report'), findsOneWidget);
    expect(insets.last, lessThan(insets.first));
    expect(bottomInsets.last, greaterThan(bottomInsets.first));
    expect(bottomInsets.last, lessThan(667 * .45 + 15));

    await tester.drag(
      find.byKey(const Key('navigationSheetHandle')),
      const Offset(0, 170),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add a report'), findsNothing);
  });

  for (final allUnspecified in [false, true]) {
    testWidgets(
      'partial lane data stays visible at phone width ($allUnspecified)',
      (tester) async {
        tester.view.physicalSize = const Size(375, 667);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final engine = DriveEngine();
        addTearDown(engine.dispose);
        final lanes = [
          NavigationLane(
            allUnspecified ? {} : {LaneArrowDirection.slightLeft},
            true,
          ),
          const NavigationLane({}, false),
          const NavigationLane({}, false),
          const NavigationLane({}, false),
        ];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NavigationOverlay(
                engine: engine,
                guidance: NavigationGuidance(
                  instruction: 'Take the left exit',
                  maneuverIcon: Icons.ramp_left_rounded,
                  stepMeters: 105,
                  remainingMeters: 4100,
                  remainingSeconds: 360,
                  lanes: lanes,
                ),
                destinationTitle: 'Tai Ping Asian Supermarket Mt Wellington',
                gpsAccuracy: 2,
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
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(LaneArrow), findsNWidgets(4));
        expect(find.text('Some lane directions unavailable'), findsOneWidget);
        for (var i = 0; i < 4; i++) {
          final tile = tester.getRect(
            find.byKey(ValueKey('navigation-lane-$i')),
          );
          expect(tile.left, greaterThanOrEqualTo(0));
          expect(tile.right, lessThanOrEqualTo(375));
          final semantics = tester.widget<Semantics>(
            find
                .ancestor(
                  of: find.byKey(ValueKey('navigation-lane-$i')),
                  matching: find.byType(Semantics),
                )
                .first,
          );
          expect(semantics.properties.selected, i == 0);
        }
      },
    );
  }
  testWidgets('route overview control switches to follow action', (
    tester,
  ) async {
    final engine = DriveEngine();
    addTearDown(engine.dispose);
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NavigationOverlay(
            engine: engine,
            destinationTitle: 'Destination',
            gpsAccuracy: 8,
            voiceEnabled: true,
            lanesEnabled: true,
            onEnd: () {},
            onRecenter: () => taps += 1,
            onOverview: () {},
            following: false,
            overviewMode: true,
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
          ),
        ),
      ),
    );

    expect(find.byTooltip('Re-center on my location'), findsOneWidget);
    expect(find.byKey(const Key('navigationRecenterButton')), findsOneWidget);
    expect(find.text('Re-center'), findsOneWidget);
    await tester.tap(find.text('Re-center'));
    await tester.pump();
    expect(taps, 1);
    await tester.tap(find.byTooltip('Re-center on my location'));
    await tester.pump();
    expect(taps, 2);
  });
}
