import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waybi_mobile/data/account_repository.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/road_event.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/drive/system_navigation.dart';
import 'package:waybi_mobile/providers/provider_contracts.dart';
import 'package:waybi_mobile/widgets/splash_gate.dart';
import 'package:waybi_mobile/widgets/transit_trip_overlay.dart';
import 'package:waybi_mobile/widgets/road_event_details_sheet.dart';
import 'package:waybi_mobile/widgets/profile_sheet.dart';
import 'package:waybi_mobile/widgets/explore_sheet.dart';
import 'package:waybi_mobile/widgets/system_navigation_status.dart';

class ExploreFixture implements ExploreProvider {
  Future<List<PlaceSummary>> Function(String) load = (_) async => const [];
  @override
  Future<List<PlaceSummary>> nearby(
    String category, {
    required GeoPoint center,
    required String language,
  }) => load(category);
}

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'splash reveals the app and disposal cancels the pending transition',
    (t) async {
      await t.pumpWidget(host(const SplashGate(child: Text('Map ready'))));
      expect(find.text('Waybi'), findsOneWidget);
      expect(find.text('Map ready'), findsNothing);
      await t.pump(const Duration(milliseconds: 1051));
      await t.pumpAndSettle();
      expect(find.text('Map ready'), findsOneWidget);
      await t.pumpWidget(
        host(
          const SplashGate(key: ValueKey('new'), child: Text('Never mounted')),
        ),
      );
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'transit trip exposes recenter/end and leg information without GPS',
    (t) async {
      var end = 0, recenter = 0;
      final route = RouteOption.fromJson({
        'id': 'bus',
        'mode': 'transit',
        'durationSeconds': 3660,
        'distanceMeters': 12000,
        'transit': [
          {
            'lineName': '70',
            'headsign': 'Britomart',
            'departureStop': 'Airport',
            'arrivalStop': 'CBD',
          },
        ],
      });
      await t.pumpWidget(
        host(
          TransitTripOverlay(
            destinationTitle: 'Britomart',
            route: route,
            gpsAccuracy: null,
            onEnd: () => end++,
            onRecenter: () => recenter++,
          ),
        ),
      );
      expect(find.text('1 hr 1 min'), findsOneWidget);
      expect(find.textContaining('GPS —'), findsOneWidget);
      expect(find.text('70 → Britomart'), findsOneWidget);
      await t.tap(find.byTooltip('Recenter'));
      await t.tap(find.text('End trip'));
      expect([end, recenter], [1, 1]);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'closure details distinguish official diversions and community reports',
    (t) async {
      final event = RoadEvent(
        id: 'closure',
        type: RoadEventType.roadClosure,
        location: const GeoPoint(-37, 174),
        roadName: 'SH20',
        source: RoadEventSource(
          provider: 'NZTA',
          country: 'NZ',
          sourceId: 'c',
          updatedAt: DateTime(2026, 10, 15, 12),
        ),
        validUntil: DateTime(2026, 10, 16, 12),
        metadata: const {
          'description': 'Ramp closed',
          'comments': 'Ramp closed',
          'alternativeRoute': 'Use next exit',
        },
      );
      await t.pumpWidget(
        host(
          RoadEventDetailsSheet(
            event: event,
            title: 'Road closed',
            language: 'en',
          ),
        ),
      );
      expect(find.text('Ramp closed'), findsOneWidget);
      expect(find.text('Use next exit'), findsOneWidget);
      expect(find.text('Published by NZTA'), findsOneWidget);
      expect(find.textContaining('Until '), findsOneWidget);
      await t.pumpWidget(
        host(
          const RoadEventDetailsSheet(
            event: RoadEvent(
              id: 'report',
              type: RoadEventType.roadworks,
              location: GeoPoint(-37, 174),
              source: RoadEventSource(
                provider: 'Waybi',
                country: 'NZ',
                sourceId: 'r',
              ),
              metadata: {
                'userReported': true,
                'reporterName': 'Sam',
                'description': 'Works',
                'comments': 'Slow down',
              },
            ),
            title: '施工',
            language: 'zh',
          ),
        ),
      );
      expect(find.text('Sam报告'), findsOneWidget);
      expect(find.text('Slow down'), findsOneWidget);
    },
  );
  testWidgets(
    'legacy profile validates credentials, reports errors and changes registration mode',
    (t) async {
      final account = AccountRepository(
        client: MockClient(
          (_) async => http.Response('{"error":"Try later"}', 503),
        ),
      );
      addTearDown(account.dispose);
      await t.pumpWidget(host(ProfileSheet(account: account)));
      await t.enterText(find.byType(TextField).first, 'driver@example.test');
      await t.enterText(find.byType(TextField).last, 'test-only-long-password');
      await t.tap(find.text('Sign in'));
      await t.pumpAndSettle();
      expect(find.text('Try later'), findsOneWidget);
      await t.tap(find.text('New here? Create an account'));
      await t.pumpAndSettle();
      expect(find.text('Password (12+ characters)'), findsOneWidget);
      expect(find.text('Create account'), findsOneWidget);
    },
  );
  testWidgets(
    'explore category changes ignore older replies and keep marker selection coherent',
    (t) async {
      final provider = ExploreFixture();
      final old = Completer<List<PlaceSummary>>();
      const cafe = PlaceSummary(
        name: 'Cafe',
        location: GeoPoint(-37, 174),
        address: 'CBD',
      );
      provider.load = (q) =>
          q == 'restaurant' ? old.future : Future.value([cafe]);
      final focus = ValueNotifier<PlaceSummary?>(null);
      addTearDown(focus.dispose);
      PlaceSummary? selected;
      final results = <List<PlaceSummary>>[];
      await t.pumpWidget(
        host(
          ExploreSheet(
            provider: provider,
            center: const GeoPoint(-37, 174),
            language: 'en',
            route: const [GeoPoint(-37, 174)],
            saved: const [],
            markerFocus: focus,
            onResultsChanged: results.add,
            onFocused: (p) => focus.value = p,
            onSelected: (p) => selected = p,
          ),
        ),
      );
      await t.tap(find.text('Coffee'));
      await t.pumpAndSettle();
      old.complete(const [
        PlaceSummary(name: 'Old restaurant', location: GeoPoint(-38, 175)),
      ]);
      await t.pumpAndSettle();
      expect(find.text('Old restaurant'), findsNothing);
      expect(results.last.single.name, 'Cafe');
      await t.tap(find.text('Cafe').first);
      expect(selected, cafe);
      expect(await const NoDetourEstimate().estimate(cafe, []), isNull);
    },
  );
  testWidgets(
    'explore errors clear unavailable data instead of inventing stops',
    (t) async {
      final provider = ExploreFixture()
        ..load = (_) async => throw StateError('offline');
      final focus = ValueNotifier<PlaceSummary?>(null);
      addTearDown(focus.dispose);
      await t.pumpWidget(
        host(
          ExploreSheet(
            provider: provider,
            center: const GeoPoint(-37, 174),
            language: 'zh',
            route: const [],
            saved: const [],
            markerFocus: focus,
            onResultsChanged: (p) => expect(p, isEmpty),
            onFocused: (_) {},
            onSelected: (_) {},
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('附近地点暂不可用。'), findsOneWidget);
    },
  );
  testWidgets(
    'system navigation status exposes settings, retry and active state',
    (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel('test/component-system');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <String>[];
      var enabled = false, active = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return {
          'supported': true,
          'enabled': enabled,
          'active': active,
          'errorCode': null,
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final nav = SystemNavigation(channel: channel);
      addTearDown(nav.dispose);
      await nav.start({'instruction': 'Continue'});
      await t.pumpWidget(
        host(SystemNavigationStatus(navigation: nav, language: 'zh')),
      );
      await t.tap(find.text('设置'));
      await t.pump();
      expect(calls.last, 'openSettings');
      enabled = true;
      await nav.start({'instruction': 'Continue'});
      await t.pump();
      expect(find.text('重试'), findsOneWidget);
      active = true;
      await t.tap(find.text('重试'));
      await t.pumpAndSettle();
      expect(find.text('灵动岛导航已开启'), findsOneWidget);
      await nav.stop();
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
