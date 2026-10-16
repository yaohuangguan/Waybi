import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_mobile/main.dart';
import 'package:waybi_mobile/drive/drive_engine.dart';
import 'package:waybi_mobile/data/transit_lane_repository.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/providers/independent_map_renderer.dart';

import 'recording_map_platform.dart';

class AppGps extends GeolocatorPlatform {
  final positions = StreamController<Position>.broadcast();
  bool enabled = true;
  Object? error;
  Position current = position();
  final settings = <LocationSettings?>[];
  static Position position({
    double latitude = -37.2,
    double longitude = 174.9,
    double accuracy = 3,
    double speed = 0,
    DateTime? time,
  }) => Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: time ?? DateTime.now(),
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 90,
    headingAccuracy: 1,
    speed: speed,
    speedAccuracy: 1,
  );
  @override
  Future<bool> isLocationServiceEnabled() async => enabled;
  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    if (!enabled) throw const LocationServiceDisabledException();
    if (error != null) throw error!;
    return current;
  }

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async => current;
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    settings.add(locationSettings);
    return positions.stream;
  }

  @override
  Future<bool> openLocationSettings() async => true;
  void emit({
    double longitude = 174.9001,
    double accuracy = 3,
    double speed = 4,
  }) {
    current = position(longitude: longitude, accuracy: accuracy, speed: speed);
    positions.add(current);
  }
}

class AppHarness {
  AppHarness(this.tester);
  final WidgetTester tester;
  final gps = AppGps();
  late final DriveEngine drive;
  final requests = <http.Request>[];
  final calls = <MethodCall>[];
  final mapPlatform = RecordingMapPlatform();
  int permission = 1;
  bool routeFailure = false;
  bool blocked = false;
  int reportStatus = 201;
  bool signedIn = false;
  bool plus = false;
  final endpointFailures = <String, int>{};
  final savedPlaces = <Map<String, dynamic>>[];
  final reviews = <Map<String, dynamic>>[];
  final recentDestinations = <Map<String, dynamic>>[];
  final quickLocations = <Map<String, dynamic>>[];
  Map<String, Object> get accountProfile => {
    'user': {
      'id': 'driver',
      'email': 'driver@example.test',
      'displayName': 'Driver',
      'providers': ['password'],
    },
    'subscription': {'plan': plus ? 'plus' : 'free'},
    'savedPlaces': savedPlaces,
    'reviews': reviews,
    'recentDestinations': recentDestinations,
    'quickLocations': quickLocations,
    'routeHistory': <Object>[],
    'companionTotals': {
      'distanceMeters': 0,
      'tripCount': 0,
      'durationSeconds': 0,
    },
  };
  Completer<http.Response>? delayedRoute;
  late final client = MockClient((request) async {
    requests.add(request);
    final path = request.url.path;
    Object body = {};
    int status = 200;
    if (endpointFailures.containsKey(path)) {
      return http.Response(
        jsonEncode({'error': 'Temporarily unavailable'}),
        endpointFailures[path]!,
      );
    }
    if (path == '/api/auth/me') {
      body = accountProfile;
    } else if (path == '/api/profile/places' ||
        path == '/api/profile/reviews' ||
        path == '/api/profile/destinations' ||
        path == '/api/profile/quick-locations') {
      final item = jsonDecode(request.body) as Map<String, dynamic>;
      final rows = switch (path) {
        '/api/profile/places' => savedPlaces,
        '/api/profile/reviews' => reviews,
        '/api/profile/destinations' => recentDestinations,
        _ => quickLocations,
      };
      final key =
          path.endsWith('destinations') || path.endsWith('quick-locations')
          ? 'label'
          : 'placeId';
      rows.removeWhere((row) => row[key] == item[key]);
      rows.insert(0, {
        ...item,
        if (path.endsWith('places')) 'isFavorite': item['isFavorite'],
      });
      body = accountProfile;
    } else if (path == '/api/profile/routes' ||
        path == '/api/profile/companion/import') {
      body = accountProfile;
    } else if (path == '/api/billing/apple/config') {
      body = {'ready': false, 'productId': 'co.waybi.plus.monthly'};
    } else if (path == '/api/route-watches') {
      body = {'watches': []};
    } else if (path == '/api/route-watch-alerts') {
      body = {'alerts': []};
    } else if (path == '/api/route-options') {
      if (delayedRoute != null) return delayedRoute!.future;
      if (routeFailure) return http.Response('{"error":"offline"}', 503);
      final q = request.url.queryParameters;
      final from = q['from']!.split(',').map(double.parse).toList();
      final to = q['to']!.split(',').map(double.parse).toList();
      final mode = q['mode'] ?? 'drive';
      body = {
        'provider': 'independent',
        'trafficAvailable': false,
        'stopsApplied': 0,
        'options': [
          for (final short in [false, true])
            {
              'id': '$mode-${short ? 'short' : 'fast'}',
              'mode': mode,
              'durationSeconds': short ? 800 : 600,
              'distanceMeters': short ? 900 : 1100,
              'description': short ? 'Shorter road' : 'Faster road',
              'provider': 'independent',
              'coordinates': [
                from,
                [(from[0] + to[0]) / 2, (from[1] + to[1]) / 2],
                to,
              ],
              'closureIds': blocked ? ['closed'] : [],
              'steps': [
                {
                  'instruction': 'Head east',
                  'distance': 500,
                  'duration': 300,
                  'location': from,
                  'maneuver': 'depart',
                  'modifier': 'straight',
                  'name': 'Test road',
                },
                {
                  'instruction': 'Turn right',
                  'distance': 600,
                  'duration': 300,
                  'location': [(from[0] + to[0]) / 2, (from[1] + to[1]) / 2],
                  'maneuver': 'turn',
                  'modifier': 'right',
                  'name': 'Destination road',
                  'lanes': [
                    {
                      'indications': ['straight'],
                      'valid': false,
                    },
                    {
                      'indications': ['right'],
                      'valid': true,
                    },
                  ],
                },
                {
                  'instruction': 'Arrive',
                  'distance': 0,
                  'location': to,
                  'maneuver': 'arrive',
                },
              ],
            },
        ],
      };
    } else if (path == '/api/cameras') {
      body = {
        'syncStatus': 'live',
        'checkedAt': DateTime.now().toUtc().toIso8601String(),
        'sourceUpdatedAt': '2026-10-16',
        'cameras': [
          {
            'id': 'test-camera',
            'name': 'Test road camera',
            'latitude': -37.2,
            'longitude': 174.905,
            'type': 'Fixed speed camera',
          },
        ],
      };
    } else if (path == '/api/speed-limit') {
      body = {'speedLimitKph': 80};
    } else if (path == '/api/road-reports' && request.method == 'POST') {
      status = reportStatus;
      body = status == 201
          ? {'id': 'new-report'}
          : {'error': 'Temporarily unavailable'};
    } else if (path.endsWith('/query')) {
      body = {'features': []};
    } else if (path.contains('road-intelligence') ||
        path.contains('road-events')) {
      body = {
        'events': [],
        'sources': [],
        'generatedAt': DateTime.now().toIso8601String(),
      };
    } else if (path.contains('search') ||
        path.contains('suggest') ||
        path.contains('autocomplete')) {
      body = {'results': [], 'suggestions': [], 'features': []};
    } else {
      status = 503;
      body = {'error': 'Fixture unavailable'};
    }
    return http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );
  });
  IndependentMapRenderer get map => tester.widget<IndependentMapRenderer>(
    find.byType(IndependentMapRenderer),
  );
  List<http.Request> get routeRequests =>
      requests.where((r) => r.url.path == '/api/route-options').toList();
  Future<void> frames([int count = 6]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
    expect(
      tester.takeException(),
      isNull,
      reason: 'Application frame must lay out without errors',
    );
  }

  Future<void> boot({
    Map<String, Object> preferences = const {},
    bool signedIn = false,
    bool plus = false,
  }) async {
    this.signedIn = signedIn;
    this.plus = plus;
    SharedPreferences.setMockInitialValues({
      'waybi.onboarding.core.v1': true,
      'waybi.app.language': 'en',
      'waybi.voice.enabled': false,
      'waybi.layers.traffic': false,
      'waybi.layers.transit_lanes': false,
      ...preferences,
    });
    FlutterSecureStorage.setMockInitialValues({
      if (signedIn) 'waybi_session': 'f' * 64,
    });
    drive = DriveEngine(
      transitLaneRepository: TransitLaneRepository(
        client: client,
        seedLoader: () async => jsonEncode({
          'lanes': [],
          'checkedAt': DateTime.now().toUtc().toIso8601String(),
          'source': 'Controlled app-flow fixture',
          'syncStatus': 'live',
        }),
      ),
    );
    final originalGps = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = gps;
    final originalMap = ml.MapLibrePlatform.createInstance;
    ml.MapLibrePlatform.createInstance = () => mapPlatform;
    final originalPlatform = debugDefaultTargetPlatformOverride;
    // Keep the widget test platform; native iOS/Android location settings have their own regressions.
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final channels = <MethodChannel>[
      for (final name in [
        'flutter.baseflow.com/permissions/methods',
        'dexterous.com/flutter/local_notifications',
        'flutter_tts',
        'waybi/device_heading',
        'waybi/external_navigation',
        'waybi/map_language',
        'waybi/system_navigation',
        'waybi/navigation_audio',
        'plugins.flutter.io/url_launcher',
      ])
        MethodChannel(name),
    ];
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'checkPermissionStatus') return permission;
        if (call.method == 'requestPermissions') {
          return <int, int>{3: permission, 5: permission};
        }
        if (call.method == 'takePending') return null;
        if (call.method == 'areNotificationsEnabled' ||
            call.method == 'requestNotificationsPermission') {
          return true;
        }
        if (channel.name == 'waybi/system_navigation') {
          return {
            'supported': true,
            'enabled': true,
            'active': call.method != 'stop',
          };
        }
        if (call.method == 'initialize' ||
            call.method == 'setLanguage' ||
            call.method == 'openAppSettings') {
          return true;
        }
        return 1;
      });
    }
    const wake =
        'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
    messenger.setMockMessageHandler(
      wake,
      (_) async => const StandardMessageCodec().encodeMessage([null]),
    );
    final storeChannels = [
      for (final method in [
        'startListeningToTransactions',
        'stopListeningToTransactions',
      ])
        'dev.flutter.pigeon.in_app_purchase_storekit.InAppPurchase2API.$method',
    ];
    for (final name in storeChannels) {
      messenger.setMockMessageHandler(
        name,
        (_) async => const StandardMessageCodec().encodeMessage([null]),
      );
    }
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await gps.positions.close();
      GeolocatorPlatform.instance = originalGps;
      ml.MapLibrePlatform.createInstance = originalMap;
      debugDefaultTargetPlatformOverride = originalPlatform;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      for (final channel in channels) {
        messenger.setMockMethodCallHandler(channel, null);
      }
      messenger.setMockMessageHandler(wake, null);
      for (final name in storeChannels) {
        messenger.setMockMessageHandler(name, null);
      }
    });
    await tester.pumpWidget(MaterialApp(home: MapHomePage(driveEngine: drive)));
    await frames();
    gps.emit(longitude: 174.9, speed: 0);
    await frames(2);
  }

  Future<void> select({
    String name = 'Test destination',
    GeoPoint point = const GeoPoint(-37.2, 174.91),
    PlaceKind kind = PlaceKind.coordinate,
  }) async {
    map.onMapPlace(
      PlaceSummary(
        name: name,
        address: 'Destination road',
        location: point,
        kind: kind,
      ),
    );
    await frames();
  }

  Future<void> tapText(String text) async {
    final finder = find.text(text).hitTestable();
    expect(finder, findsWidgets);
    await tester.tap(finder.first);
    await frames();
  }

  Future<void> until(bool Function() ready, {required String reason}) async {
    for (var attempt = 0; attempt < 80 && !ready(); attempt++) {
      // Transit matching uses a real isolate; simulated frame time does not advance it.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(
      ready(),
      isTrue,
      reason:
          '$reason; driveActive=${drive.active}; gpsIssue=${drive.gpsIssue}; transitLanes=${drive.transitSnapshot?.lanes.length}; lastNativeCalls=${calls.reversed.take(12).map((c) => c.method).toList()}',
    );
  }

  Future<void> act(VoidCallback action) async {
    await tester.runAsync(() async {
      action();
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await frames();
  }

  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await frames(4);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(tester.takeException(), isNull);
  }
}
