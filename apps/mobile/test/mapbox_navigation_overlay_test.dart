import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_lens_mobile/domain/route_option.dart';
import 'package:kiwi_lens_mobile/domain/safety_camera.dart';
import 'package:kiwi_lens_mobile/providers/mapbox_navigation_engine.dart';
import 'package:kiwi_lens_mobile/widgets/mapbox_navigation_overlay.dart';
import 'package:kiwi_lens_mobile/theme/kiwi_lens_theme.dart';

import 'mapbox_navigation_engine_test.dart' show FakeDrive, makeRoute, origin;

void main() {
  testWidgets(
    'Mapbox has full compact HUD, camera alert and driving controls in dark mode',
    (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final drive = FakeDrive();
      final nav = MapboxNavigationEngine(drive);
      addTearDown(() {
        nav.dispose();
        drive.dispose();
      });
      await nav.start(makeRoute());
      drive.emit(origin, DateTime(2026));
      drive.speedKph = 54;
      drive.speedLimitKph = 50;
      drive.upcomingCamera = const SafetyCamera(
        id: 'test-camera',
        name: 'Queen St camera',
        region: 'Auckland',
        suburb: 'City',
        location: 'Queen Street',
        type: 'Spot speed',
        latitude: -36.845,
        longitude: 174.76,
      );
      drive.upcomingCameraDistanceMeters = 300;
      await tester.pumpWidget(
        MaterialApp(
          theme: KiwiLensTheme.dark,
          home: Scaffold(
            body: MapboxNavigationOverlay(
              engine: nav,
              drive: drive,
              destination: 'Auckland',
              language: 'en',
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
              voiceEnabled: true,
              lanesEnabled: true,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('54'), findsOneWidget);
      expect(find.text('LIMIT 50'), findsOneWidget);
      expect(find.text('Camera · 300 m'), findsOneWidget);
      final camera = tester.getRect(
        find.byKey(const Key('navigationCameraAlert')),
      );
      expect(
        camera.top,
        greaterThan(
          tester
              .getRect(find.byKey(const Key('navigationGuidanceHeader')))
              .bottom,
        ),
      );
      expect(camera.bottom, lessThan(667 / 2));
      expect(find.text('Queen Street'), findsOneWidget);
      expect(find.byTooltip('Route overview'), findsOneWidget);
      expect(find.text('End'), findsOneWidget);
      await tester.tap(find.byKey(const Key('navigationSheetHandle')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Add a report'), findsOneWidget);
      expect(find.text('Directions'), findsOneWidget);
      expect(find.text('Cameras on route'), findsOneWidget);
    },
  );
  test('maneuver icon follows real maneuver metadata', () {
    expect(mapboxManeuverIcon(null), Icons.straight_rounded);
    expect(
      mapboxManeuverIcon(
        RouteStepInfo(
          instruction: '',
          distanceMeters: 0,
          location: origin,
          maneuverType: 'turn',
          maneuverModifier: 'right',
        ),
      ),
      Icons.turn_right_rounded,
    );
  });
}
