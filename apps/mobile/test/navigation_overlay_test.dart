import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_lens_mobile/drive/drive_engine.dart';
import 'package:kiwi_lens_mobile/widgets/navigation_overlay.dart';

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
    expect(recenterCount, 1);

    await tester.tap(find.byKey(const Key('navigationSheetHandle')));
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

    expect(find.byTooltip('Follow my location'), findsOneWidget);
    await tester.tap(find.byTooltip('Follow my location'));
    await tester.pump();
    expect(taps, 1);
  });
}
