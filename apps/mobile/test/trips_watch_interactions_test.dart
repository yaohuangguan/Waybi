import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/widgets/trips_page.dart';

const home = TripDestination(name: 'Home', location: GeoPoint(-36.85, 174.76));
const work = TripDestination(name: 'Work', location: GeoPoint(-36.86, 174.77));
RouteOption route(int seconds) => RouteOption(
  id: 'commute',
  mode: WaybiTravelMode.drive,
  durationSeconds: seconds,
  distanceMeters: 5000,
  points: const [],
  provider: 'independent',
  traffic: const TrafficSummary(normal: 0, slow: 0, trafficJam: 0),
  trafficIntervals: const [],
);
TripsSnapshot snapshot(
  Map<String, RouteWatchItem> watches, {
  Map<String, RouteOption> routes = const {},
  List<TripHistoryItem> history = const [],
}) => TripsSnapshot(
  quickPlaces: const {'Home': home, 'Work': work},
  quickRoutes: const {},
  recent: const [],
  history: history,
  routeWatches: watches,
  smartCommuteRoutes: routes,
  signedIn: true,
  isPlus: true,
);
Future<void> reveal(WidgetTester t, Finder f, {double delta = 200}) async {
  await t.scrollUntilVisible(
    f,
    delta,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 50,
  );
  await t.ensureVisible(f);
  await t.pumpAndSettle();
}

void main() {
  for (final zh in [false, true]) {
    testWidgets(
      'route watch $zh details show disruption evidence and toggles recover from failure',
      (t) async {
        final watch = RouteWatchItem.fromJson({
          'id': 'watch',
          'label': 'home-work',
          'status': 'advisory',
          'routeProvider': 'independent',
          'lastCheckedAt': DateTime.now()
              .subtract(const Duration(minutes: 5))
              .toIso8601String(),
          'events': [
            {
              'type': 'roadworks',
              'severity': 'warning',
              'roadName': 'SH20',
              'description': 'Ramp maintenance',
              'impact': 'Lane closed',
            },
            {'description': 'Second road event'},
          ],
        });
        var fail = true;
        final calls = <bool>[];
        await t.pumpWidget(
          MaterialApp(
            home: TripsPage(
              language: zh ? 'zh' : 'en',
              loader: () async => snapshot({'home-work': watch}),
              onRouteWatchChanged: (label, current, enabled) async {
                calls.add(enabled);
                if (fail) throw StateError('Watch unavailable');
              },
            ),
          ),
        );
        await t.pumpAndSettle();
        final info = find.byTooltip(zh ? '路线监控详情' : 'Route Watch details');
        await reveal(t, info);
        await t.tap(info);
        await t.pumpAndSettle();
        expect(find.text('SH20'), findsOneWidget);
        expect(find.text('Lane closed'), findsOneWidget);
        expect(find.text('Ramp maintenance'), findsOneWidget);
        expect(find.textContaining(zh ? '5 分钟前' : '5m ago'), findsWidgets);
        Navigator.of(t.element(find.text('Ramp maintenance'))).pop();
        await t.pumpAndSettle();
        final toggle = find.byType(Switch).first;
        await t.tap(toggle);
        await t.pumpAndSettle();
        expect(calls, [false]);
        await reveal(t, find.text('Watch unavailable'), delta: -200);
        expect(find.text('Watch unavailable'), findsOneWidget);
        await reveal(t, info);
        fail = false;
        await t.tap(toggle);
        await t.pumpAndSettle();
        expect(calls, [false, false]);
        expect(find.text('Watch unavailable'), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      'unknown route watch $zh refresh disables duplicate requests until completion',
      (t) async {
        final wait = Completer<void>();
        var calls = 0;
        final watch = RouteWatchItem.fromJson({
          'id': 'unknown',
          'label': 'home-work',
          'status': 'unknown',
        });
        await t.pumpWidget(
          MaterialApp(
            home: TripsPage(
              language: zh ? 'zh' : 'en',
              loader: () async => snapshot({'home-work': watch}),
              onRouteWatchChanged: (label, current, enabled) async {
                calls++;
                expect(enabled, true);
                await wait.future;
              },
            ),
          ),
        );
        await t.pumpAndSettle();
        final refresh = find.byTooltip(zh ? '刷新已保存路线' : 'Refresh saved route');
        await reveal(t, refresh);
        await t.tap(refresh);
        await t.pump();
        expect(calls, 1);
        expect(
          t
              .widget<IconButton>(
                find
                    .ancestor(of: refresh, matching: find.byType(IconButton))
                    .first,
              )
              .onPressed,
          isNull,
        );
        expect(
          t.widgetList<Switch>(find.byType(Switch)).first.onChanged,
          isNull,
        );
        wait.complete();
        await t.pumpAndSettle();
        expect(
          t
              .widget<IconButton>(
                find
                    .ancestor(of: refresh, matching: find.byType(IconButton))
                    .first,
              )
              .onPressed,
          isNotNull,
        );
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      'commute $zh distinguishes faster, normal and stale baseline summaries',
      (t) async {
        final watches = {
          'home-work': RouteWatchItem.fromJson({
            'id': 'a',
            'label': 'home-work',
            'status': 'healthy',
            'baselineDurationSeconds': 900,
            'lastCheckedAt': DateTime.now()
                .subtract(const Duration(minutes: 15))
                .toIso8601String(),
          }),
          'work-home': RouteWatchItem.fromJson({
            'id': 'b',
            'label': 'work-home',
            'status': 'healthy',
            'baselineDurationSeconds': 600,
            'events': [],
          }),
        };
        await t.pumpWidget(
          MaterialApp(
            home: TripsPage(
              language: zh ? 'zh' : 'en',
              loader: () async => snapshot(
                watches,
                routes: {'home-work': route(600), 'work-home': route(660)},
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await reveal(t, find.text(zh ? '智能通勤' : 'Smart Commute'));
        expect(
          find.textContaining(zh ? '比平时快 5 分钟' : '5 min faster than usual'),
          findsOneWidget,
        );
        expect(
          find.textContaining(zh ? '接近平时通勤时间' : 'close to your usual commute'),
          findsOneWidget,
        );
        expect(find.text(zh ? '正常' : 'Clear'), findsWidgets);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Trips refresh failures retain a usable retry button and recover',
    (t) async {
      var fail = true;
      await t.pumpWidget(
        MaterialApp(
          home: TripsPage(
            language: 'en',
            loader: () async {
              if (fail) throw StateError('offline');
              return snapshot({});
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Could not refresh trips right now.'), findsOneWidget);
      fail = false;
      await t.tap(find.byTooltip('Refresh'));
      await t.pumpAndSettle();
      expect(find.text('Could not refresh trips right now.'), findsNothing);
      expect(find.text('Smart Commute'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'trip insights handle morning, afternoon and long-duration journeys',
    (t) async {
      final history = [
        TripHistoryItem(
          destination: home,
          mode: 'drive',
          distanceMeters: 180000,
          durationSeconds: 7200,
          createdAt: DateTime.now().copyWith(hour: 8, minute: 0),
        ),
        TripHistoryItem(
          destination: work,
          mode: 'drive',
          distanceMeters: 90000,
          durationSeconds: 3660,
          createdAt: DateTime.now().copyWith(hour: 14, minute: 0),
        ),
        TripHistoryItem(
          destination: work,
          mode: 'walk',
          distanceMeters: 500,
          durationSeconds: 600,
          createdAt: DateTime.now().copyWith(hour: 22, minute: 0),
        ),
      ];
      await t.pumpWidget(
        MaterialApp(
          home: TripsPage(
            language: 'en',
            loader: () async => snapshot({}, history: history),
          ),
        ),
      );
      await t.pumpAndSettle();
      await reveal(t, find.text('Trip Intelligence'));
      expect(find.textContaining('2h'), findsWidgets);
      expect(find.textContaining('Mixed times'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
