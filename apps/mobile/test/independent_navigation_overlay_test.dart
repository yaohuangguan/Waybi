import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/domain/safety_camera.dart';
import 'package:waybi_mobile/providers/independent_navigation_engine.dart';
import 'package:waybi_mobile/widgets/independent_navigation_overlay.dart';
import 'package:waybi_mobile/theme/waybi_theme.dart';

import 'independent_navigation_engine_test.dart'
    show FakeDrive, makeRoute, origin;

void main() {
  testWidgets(
    'Independent has full compact HUD, camera alert and driving controls in dark mode',
    (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final drive = FakeDrive();
      final nav = IndependentNavigationEngine(drive);
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
          theme: WaybiTheme.dark,
          home: Scaffold(
            body: IndependentNavigationOverlay(
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
      expect(find.text('Safety camera ahead'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('navigationCameraAlert')),
          matching: find.text('300 m'),
        ),
        findsOneWidget,
      );
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
    expect(independentManeuverIcon(null), Icons.straight_rounded);
    expect(
      independentManeuverIcon(
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
