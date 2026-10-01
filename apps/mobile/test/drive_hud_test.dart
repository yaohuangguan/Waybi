import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiwi_lens_mobile/domain/safety_camera.dart';
import 'package:kiwi_lens_mobile/drive/drive_engine.dart';
import 'package:kiwi_lens_mobile/theme/kiwi_lens_theme.dart';
import 'package:kiwi_lens_mobile/widgets/drive_hud.dart';

void main() {
  testWidgets(
    'Just Drive keeps the camera above the map in Chinese dark mode',
    (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final engine = DriveEngine()
        ..upcomingCamera = const SafetyCamera(
          id: 'camera',
          name: 'Queen St',
          region: 'Auckland',
          suburb: 'CBD',
          location: 'Queen Street',
          type: 'Spot speed',
          latitude: -36.845,
          longitude: 174.76,
        )
        ..upcomingCameraDistanceMeters = 300;
      addTearDown(engine.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: KiwiLensTheme.darkFor('zh'),
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: DriveHud(engine: engine, onStop: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('摄像头 · 300 米'), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const Key('driveCameraAlert'))).bottom,
        lessThan(667 / 2),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
