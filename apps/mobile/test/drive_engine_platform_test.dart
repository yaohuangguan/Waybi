import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_mobile/data/camera_repository.dart';
import 'package:waybi_mobile/data/speed_limit_repository.dart';
import 'package:waybi_mobile/data/traffic_flow_repository.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/drive/drive_engine.dart';
import 'package:waybi_mobile/drive/voice_engine.dart';

class QuietVoice extends VoiceEngine {
  Completer<void>? startup;
  int stops = 0;
  @override
  Future<void> initialize() => startup?.future ?? Future.value();
  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() => stop();
}

class PlatformGps extends GeolocatorPlatform {
  final positions = StreamController<Position>.broadcast();
  final settings = <LocationSettings?>[];
  bool enabled = true;
  Position current = fix();
  @override
  Future<bool> isLocationServiceEnabled() async => enabled;
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    settings.add(locationSettings);
    return positions.stream;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async => current;
}

Position fix({
  double latitude = -36.85,
  double longitude = 174.76,
  double accuracy = 3,
  double speed = 0,
}) => Position(
  latitude: latitude,
  longitude: longitude,
  timestamp: DateTime.now(),
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 90,
  headingAccuracy: 1,
  speed: speed,
  speedAccuracy: 1,
);
Future<void> flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

RouteOption route() => const RouteOption(
  id: 'east',
  mode: WaybiTravelMode.drive,
  durationSeconds: 600,
  distanceMeters: 1000,
  points: [GeoPoint(-36.85, 174.76), GeoPoint(-36.85, 174.77)],
  provider: 'waybi',
  traffic: TrafficSummary(normal: 0, slow: 0, trafficJam: 0),
  trafficIntervals: [],
);
DriveEngine engine(QuietVoice voice) => DriveEngine(
  voiceEngine: voice,
  cameraRepository: CameraRepository(
    client: MockClient(
      (_) async => http.Response(
        jsonEncode({
          'syncStatus': 'live',
          'cameras': [
            {
              'id': 'cam',
              'name': 'SH1',
              'type': 'Fixed speed camera',
              'latitude': -36.85,
              'longitude': 174.765,
            },
          ],
        }),
        200,
      ),
    ),
  ),
  speedLimitRepository: SpeedLimitRepository(
    client: MockClient((_) async => http.Response('{"speedLimitKph":50}', 200)),
  ),
  trafficFlowRepository: TrafficFlowRepository(
    client: MockClient((_) async => http.Response('{}', 503)),
  ),
)..voiceEnabled = false;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final routed in [false, true]) {
      test(
        '$platform ${routed ? 'navigation' : 'Just Drive'} owns a recoverable native feed and stops cleanly',
        () async {
          SharedPreferences.setMockInitialValues({});
          debugDefaultTargetPlatformOverride = platform;
          final original = GeolocatorPlatform.instance;
          final gps = PlatformGps();
          GeolocatorPlatform.instance = gps;
          final voice = QuietVoice();
          final drive = engine(voice);
          addTearDown(() async {
            await drive.stop();
            drive.dispose();
            await gps.positions.close();
            GeolocatorPlatform.instance = original;
            debugDefaultTargetPlatformOverride = null;
          });
          if (routed) drive.setRoute(route());
          await drive.startLocal(initialPosition: gps.current);
          await flush();
          expect(drive.active, isTrue);
          expect(drive.guidanceRunning, routed);
          expect(gps.settings, hasLength(1));
          if (platform == TargetPlatform.iOS) {
            final settings = gps.settings.single as AppleSettings;
            expect(settings.allowBackgroundLocationUpdates, isTrue);
            expect(settings.pauseLocationUpdatesAutomatically, isFalse);
            expect(settings.activityType, ActivityType.automotiveNavigation);
          } else {
            final settings = gps.settings.single as AndroidSettings;
            expect(settings.distanceFilter, 0);
            expect(settings.foregroundNotificationConfig == null, routed);
          }
          gps.current = fix(longitude: 174.7601, speed: 5);
          gps.positions.add(gps.current);
          await flush();
          final reliable = drive.latestPosition;
          expect(reliable, isNotNull);
          gps.positions.add(fix(longitude: 175.2, accuracy: 200, speed: 5));
          await flush();
          expect(
            drive.latestPosition?.longitude,
            reliable!.longitude,
            reason: 'A GPS jump must not advance the trip',
          );
          await drive.stop();
          expect(drive.active, isFalse);
          expect(drive.guidanceRunning, isFalse);
          expect(drive.trailPaths, isEmpty);
          expect(drive.routeProgress, isNull);
          gps.positions.add(fix(longitude: 174.761));
          await flush();
          expect(
            drive.latestPosition,
            isNull,
            reason: 'Stopped trips ignore late GPS events',
          );
        },
      );
    }
    test(
      '$platform disabled location services cannot create an active trip',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        final original = GeolocatorPlatform.instance;
        final gps = PlatformGps()..enabled = false;
        GeolocatorPlatform.instance = gps;
        final drive = engine(QuietVoice());
        addTearDown(() async {
          await drive.stop();
          drive.dispose();
          await gps.positions.close();
          GeolocatorPlatform.instance = original;
          debugDefaultTargetPlatformOverride = null;
        });
        await expectLater(drive.startLocal(), throwsStateError);
        expect(drive.active, isFalse);
        expect(gps.settings, isEmpty);
      },
    );
  }
  test(
    'stopping while voice initializes prevents a late navigation start',
    () async {
      final original = GeolocatorPlatform.instance;
      final gps = PlatformGps();
      GeolocatorPlatform.instance = gps;
      final voice = QuietVoice()..startup = Completer<void>();
      final drive = engine(voice);
      addTearDown(() async {
        await drive.stop();
        drive.dispose();
        await gps.positions.close();
        GeolocatorPlatform.instance = original;
      });
      final started = drive.startLocal();
      await flush();
      await drive.stop();
      voice.startup!.complete();
      await started;
      expect(drive.active, isFalse);
      expect(gps.settings, isEmpty);
    },
  );
}
