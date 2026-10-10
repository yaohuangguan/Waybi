import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/map_layer_settings.dart';
import 'package:waybi_mobile/domain/road_event.dart';
import 'package:waybi_mobile/domain/safety_camera.dart';
import 'package:waybi_mobile/drive/drive_engine.dart';
import 'package:waybi_mobile/widgets/navigation_camera_alert.dart';

void main() {
  testWidgets('confirmed camera type is visible in English and Chinese', (
    tester,
  ) async {
    for (final language in ['en', 'zh']) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NavigationCameraAlert(
              notice: const NavigationCameraNotice(
                'Green Lane East',
                476,
                kind: CameraKind.dualRedLightSpeed,
              ),
              language: language,
            ),
          ),
        ),
      );
      expect(
        find.text(
          language == 'zh' ? '前方红灯及测速摄像头' : 'Red-light + speed camera ahead',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });
  for (final kind in CameraKind.values) {
    testWidgets('Chinese ${kind.name} reminder names a camera', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NavigationCameraAlert(
              notice: NavigationCameraNotice('Symonds Street', 120, kind: kind),
              language: 'zh',
            ),
          ),
        ),
      );
      expect(find.text('前方${kind.cameraLabel('zh')}'), findsOneWidget);
      expect(kind.cameraLabel('zh'), contains('摄像头'));
      expect(kind.cameraLabel('zh'), isNot(contains('闯红灯')));
    });
  }
  RoadEvent camera(
    String id,
    double? distance, {
    double confidence = 1,
    DateTime? expiry,
  }) => RoadEvent(
    id: id,
    type: RoadEventType.safetyCamera,
    location: const GeoPoint(-36.8, 174.7),
    source: RoadEventSource(provider: 'nzta', country: 'NZ', sourceId: id),
    roadName: 'Queen Street',
    distanceAlongRoute: distance,
    confidence: confidence,
    validUntil: expiry,
  );
  test('a camera in the deck waits for the confirmed reminder lifecycle', () {
    final engine = DriveEngine();
    addTearDown(engine.dispose);
    engine.upcomingRoadEvents = [camera('far', 900), camera('close', 300)];
    expect(upcomingNavigationCamera(engine), isNull);
    engine.upcomingCamera = const SafetyCamera(
      id: 'close',
      name: 'Camera',
      region: 'Auckland',
      suburb: 'CBD',
      location: 'Queen Street',
      type: 'fixed',
      latitude: -36.8,
      longitude: 174.7,
    );
    engine.upcomingCameraDistanceMeters = 300;
    final notice = upcomingNavigationCamera(engine);
    expect(notice?.metres, 300);
    expect(notice?.road, 'Queen Street');
    engine.locationIssue = 'GPS signal lost';
    expect(upcomingNavigationCamera(engine), isNull);
  });
  test('nearby cameras without route distance, behind, uncertain or expired do not produce a reminder', () {
    final engine = DriveEngine();
    addTearDown(engine.dispose);
    engine.upcomingRoadEvents = [
      camera('nearby', null),
      camera('behind', -15),
      camera('later', 1500),
      camera('uncertain', 100, confidence: .2),
      camera('old', 300, expiry: DateTime(2020)),
    ];
    expect(upcomingNavigationCamera(engine), isNull);
  });
  for (final width in [320.0, 390.0]) {
    testWidgets(
      'camera distance is readable at $width with larger system text',
      (tester) async {
        tester.view.physicalSize = Size(width, 200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 200),
                textScaler: const TextScaler.linear(1.3),
              ),
              child: const Scaffold(
                body: Padding(
                  padding: EdgeInsets.all(14),
                  child: NavigationCameraAlert(
                    notice: NavigationCameraNotice('Queen Street', 300),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(find.text('Safety camera ahead'), findsOneWidget);
        expect(find.text('300 m'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
