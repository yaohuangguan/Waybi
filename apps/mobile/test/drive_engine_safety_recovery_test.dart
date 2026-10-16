import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_mobile/data/camera_repository.dart';
import 'package:waybi_mobile/data/speed_limit_repository.dart';
import 'package:waybi_mobile/data/traffic_flow_repository.dart';
import 'package:waybi_mobile/data/transit_lane_repository.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/drive/drive_engine.dart';
import 'package:waybi_mobile/drive/voice_engine.dart';

class SafetyGps extends GeolocatorPlatform {
  final stream = StreamController<Position>.broadcast();
  Position current = fix();
  Object? failure;
  bool enabled = true;
  @override
  Future<bool> isLocationServiceEnabled() async => enabled;
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      stream.stream;
  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    if (failure != null) throw failure!;
    return current;
  }

  void emit(double longitude) {
    current = fix(longitude: longitude, speed: 5);
    stream.add(current);
  }
}

Position fix({double longitude = 174.76, double speed = 0}) => Position(
  latitude: -36.85,
  longitude: longitude,
  timestamp: DateTime.now(),
  accuracy: 3,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 90,
  headingAccuracy: 1,
  speed: speed,
  speedAccuracy: 1,
);
RouteOption safetyRoute() => const RouteOption(
  id: 'safety',
  mode: WaybiTravelMode.drive,
  durationSeconds: 600,
  distanceMeters: 900,
  points: [
    GeoPoint(-36.85, 174.76),
    GeoPoint(-36.85, 174.765),
    GeoPoint(-36.85, 174.77),
  ],
  provider: 'independent',
  traffic: TrafficSummary(normal: 0, slow: 0, trafficJam: 0),
  trafficIntervals: [],
  steps: [
    RouteStepInfo(
      instruction: 'Continue',
      distanceMeters: 100,
      location: GeoPoint(-36.85, 174.76),
      maneuverModifier: 'straight',
    ),
    RouteStepInfo(
      instruction: 'Turn left',
      distanceMeters: 300,
      location: GeoPoint(-36.85, 174.7612),
      maneuverModifier: 'left',
    ),
    RouteStepInfo(
      instruction: 'Arrive',
      distanceMeters: 500,
      location: GeoPoint(-36.85, 174.77),
      maneuverType: 'arrive',
    ),
  ],
);
Future<void> until(bool Function() ready, String reason) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 15));
  }
  expect(ready(), isTrue, reason: reason);
}

class SafetyFixture {
  final gps = SafetyGps();
  final speech = <String>[];
  final audio = <String>[];
  final requests = <http.Request>[];
  bool withLane = true,
      failSpeech = false,
      trafficFails = false,
      speedFails = false;
  late DriveEngine drive;
  late GeolocatorPlatform originalGps;
  late final client = MockClient((r) async {
    requests.add(r);
    if (r.url.path == '/api/cameras') {
      return http.Response(
        jsonEncode({
          'syncStatus': 'live',
          'cameras': [
            {
              'id': 'camera',
              'name': 'Safety camera',
              'type': 'Fixed speed camera',
              'location': 'Safety road',
              'latitude': -36.85,
              'longitude': 174.764,
            },
          ],
        }),
        200,
      );
    }
    if (r.url.path == '/api/speed-limit') {
      return http.Response(
        speedFails
            ? '{"error":"offline"}'
            : '{"speedLimitKph":50,"zoneName":"Local road"}',
        speedFails ? 503 : 200,
      );
    }
    if (r.url.path == '/api/traffic-flow') {
      return http.Response(
        trafficFails
            ? '{"error":"offline"}'
            : jsonEncode({
                'syncStatus': 'live',
                'checkedAt': DateTime.now().toIso8601String(),
                'segments': [
                  {
                    'id': 'traffic',
                    'level': 'heavy',
                    'motorway': 'SH1',
                    'name': 'Safety road',
                    'geometryQuality': 'road-matched',
                    'geometry': {
                      'coordinates': [
                        [174.76, -36.85],
                        [174.77, -36.85],
                      ],
                    },
                    'start': {'latitude': -36.85, 'longitude': 174.76},
                    'end': {'latitude': -36.85, 'longitude': 174.77},
                  },
                ],
              }),
        trafficFails ? 503 : 200,
      );
    }
    return http.Response('{"error":"offline"}', 503);
  });
  Future<void> boot(
    TargetPlatform platform, {
    bool routed = true,
    bool voice = true,
  }) async {
    SharedPreferences.setMockInitialValues({});
    originalGps = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = gps;
    debugDefaultTargetPlatformOverride = platform;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'), (
      call,
    ) async {
      if (call.method == 'speak') {
        speech.add(
          call.arguments is Map
              ? (call.arguments as Map)['text'] as String
              : call.arguments as String,
        );
        if (failSpeech) {
          throw PlatformException(
            code: 'audio',
            message: 'Temporary speech failure',
          );
        }
      }
      return 1;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('waybi/navigation_audio'),
      (call) async {
        audio.add(call.method);
        return null;
      },
    );
    drive = DriveEngine(
      voiceEngine: VoiceEngine(),
      cameraRepository: CameraRepository(client: client),
      speedLimitRepository: SpeedLimitRepository(client: client),
      trafficFlowRepository: TrafficFlowRepository(client: client),
      transitLaneRepository: TransitLaneRepository(
        client: client,
        seedLoader: () async => jsonEncode({
          'checkedAt': DateTime.now().toUtc().toIso8601String(),
          'source': 'Controlled lane fixture',
          'lanes': [
            if (withLane)
              {
                'id': 'lane',
                'roadName': 'Safety road',
                'kind': 'Bus',
                'directionKnown': true,
                'wholeRoad': false,
                'schedule': {
                  'known': true,
                  'days': [1, 2, 3, 4, 5, 6, 7],
                  'windows': [
                    [0, 1440],
                  ],
                },
                'coordinates': [
                  [174.762, -36.85],
                  [174.764, -36.85],
                ],
              },
          ],
        }),
      ),
    )..voiceEnabled = voice;
    addTearDown(() async {
      await drive.stop();
      drive.dispose();
      await gps.stream.close();
      GeolocatorPlatform.instance = originalGps;
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(
        const MethodChannel('flutter_tts'),
        null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('waybi/navigation_audio'),
        null,
      );
    });
    if (routed) drive.setRoute(safetyRoute());
    await drive.startLocal(initialPosition: gps.current);
    gps.emit(174.7601);
    await until(
      () => drive.hasReliableLocation,
      'A fresh GPS fix should become reliable',
    );
    await until(
      () => drive.cameras.isNotEmpty,
      'The validated camera snapshot should load',
    );
    gps.emit(174.7602);
    await until(
      () => drive.latestPosition?.longitude == 174.7602,
      'The second camera observation should be accepted',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    test(
      '$platform active bus-lane advice is spoken once and camera speech keeps audio coexistence',
      () async {
        final f = SafetyFixture();
        await http.runWithClient(() async {
          await f.boot(platform);
          await until(
            () => f.drive.upcomingTransitLane != null,
            'The published lane should match the route',
          );
          await until(
            () => f.speech.any((s) => s.toLowerCase().contains('bus lane')),
            'Lane advice should reach the TTS boundary',
          );
          await until(
            () => f.speech.any((s) => s.toLowerCase().contains('camera')),
            'Camera warning should reach the TTS boundary',
          );
          // The fixture's left turn precedes the matched bus lane.
          // It must not be recycled as a maneuver instruction for that lane.
          expect(f.drive.upcomingTransitLane!.turningLeft, isFalse);
          expect(
            f.speech.any((s) => s.toLowerCase().contains('turning left')),
            isFalse,
          );
          final laneCount = f.speech
              .where((s) => s.toLowerCase().contains('bus lane'))
              .length;
          f.gps.emit(174.7603);
          await Future<void>.delayed(const Duration(milliseconds: 100));
          expect(
            f.speech.where((s) => s.toLowerCase().contains('bus lane')).length,
            laneCount,
          );
          if (platform == TargetPlatform.iOS) {
            expect(f.audio, containsAll(['prepare', 'release']));
          }
          f.drive.setRoute(null);
          expect(f.drive.upcomingTransitLane, isNull);
        }, () => f.client);
      },
    );
    for (final error in [
      const LocationServiceDisabledException(),
      const PermissionDeniedException('denied'),
      TimeoutException('signal'),
      StateError('stream unavailable'),
    ]) {
      test(
        '$platform location issue ${error.runtimeType} retains a useful cause and recovers from real GPS',
        () async {
          final f = SafetyFixture()..withLane = false;
          await http.runWithClient(() async {
            await f.boot(platform, routed: false, voice: false);
            final last = f.drive.latestPosition;
            f.gps.failure = error;
            f.gps.stream.addError(error);
            await until(
              () => f.drive.gpsIssue != null,
              'Location issue should be visible',
            );
            final expected = error is LocationServiceDisabledException
                ? NavigationGpsIssue.servicesDisabled
                : error is PermissionDeniedException
                ? NavigationGpsIssue.permissionDenied
                : error is TimeoutException
                ? NavigationGpsIssue.stale
                : NavigationGpsIssue.unavailable;
            expect(f.drive.gpsIssue, expected);
            expect(f.drive.latestPosition, last);
            f.gps.failure = null;
            f.gps.emit(174.7603);
            await until(
              () => f.drive.gpsIssue == null,
              'A genuine OS fix should clear the issue',
            );
            expect(
              f.drive.latestPosition!.longitude,
              closeTo(174.7603, .00001),
            );
          }, () => f.client);
        },
      );
    }
  }
  test('failed camera and lane audio is bounded and does not crash or duplicate warnings', () async {
    final f = SafetyFixture()..failSpeech = true;
    await http.runWithClient(() async {
      await f.boot(TargetPlatform.android);
      await until(
        () => f.speech.any((s) => s.toLowerCase().contains('bus lane')),
        'Lane audio failure should be handled',
      );
      await until(
        () => f.speech.any((s) => s.toLowerCase().contains('camera')),
        'Camera audio failure should be handled',
      );
      final attempts = f.speech.length;
      f.gps.emit(174.7603);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        f.speech.length,
        attempts,
        reason: 'Failed audio should respect the bounded retry delay',
      );
      expect(f.drive.active, isTrue);
      expect(f.drive.hasReliableLocation, isTrue);
    }, () => f.client);
  });
  test('traffic refresh keeps previously validated geometry through an offline response', () async {
    final f = SafetyFixture()..withLane = false;
    await http.runWithClient(() async {
      await f.boot(TargetPlatform.android, routed: false, voice: false);
      await f.drive.loadTrafficFlow(force: true);
      expect(f.drive.trafficFlowStatus, 'live');
      expect(f.drive.trafficFlowSegments.single.id, 'traffic');
      final revision = f.drive.trafficFlowRevision;
      await f.drive.loadTrafficFlow();
      expect(f.drive.trafficFlowRevision, revision);
      f.trafficFails = true;
      await f.drive.loadTrafficFlow(force: true);
      expect(f.drive.trafficFlowStatus, 'stale');
      expect(f.drive.trafficFlowSegments.single.id, 'traffic');
      await f.drive.startTrafficFlowRefresh(force: true);
      await f.drive.startTrafficFlowRefresh();
      f.drive.stopTrafficFlowRefresh();
    }, () => f.client);
  });
}
