import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart'
    show LatLng;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waybi_mobile/data/explore_repository.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/theme/waybi_theme.dart';
import 'package:waybi_mobile/widgets/explore_page.dart';
import 'package:waybi_mobile/widgets/load_error.dart';
import 'package:waybi_mobile/widgets/trips_page.dart';

const plusSnapshot = TripsSnapshot(
  signedIn: true,
  isPlus: true,
  quickPlaces: {
    'Home': TripDestination(name: 'Home', location: GeoPoint(-36.8, 174.7)),
  },
  quickRoutes: {},
  recent: [],
  history: [],
);

void main() {
  for (final zh in [false, true]) {
    testWidgets('trips shows a full error state when the first load fails '
        '(${zh ? 'zh' : 'en'})', (t) async {
      var fail = true;
      await t.pumpWidget(
        MaterialApp(
          theme: WaybiTheme.light,
          home: TripsPage(
            language: zh ? 'zh' : 'en',
            loader: () async {
              if (fail) throw StateError('offline');
              return plusSnapshot;
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('trips-load-error')), findsOneWidget);
      expect(
        find.text(zh ? '行程暂时无法加载' : 'Trips couldn’t load'),
        findsOneWidget,
      );
      // Nothing that would misdescribe a saved Home or a Plus account.
      for (final misleading
          in zh
              ? ['设置地点', 'Plus 专属', '你导航过的地点会自动出现在这里。']
              : [
                  'Set location',
                  'Plus locked',
                  'Places you navigate to will appear here.',
                ]) {
        expect(find.text(misleading), findsNothing);
      }
      expect(find.textContaining('Plus unlocks'), findsNothing);

      fail = false;
      await t.tap(find.text(zh ? '重试' : 'Try again'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('trips-load-error')), findsNothing);
      expect(find.text(zh ? '家' : 'Home'), findsWidgets);
      expect(find.text(zh ? '设置地点' : 'Set location'), findsOneWidget);
    });
  }

  testWidgets('a failed refresh keeps loaded trips and offers retry', (
    t,
  ) async {
    var calls = 0;
    await t.pumpWidget(
      MaterialApp(
        home: TripsPage(
          language: 'en',
          loader: () async {
            calls++;
            if (calls > 1) throw StateError('offline');
            return plusSnapshot;
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Refresh'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('trips-refresh-error')), findsOneWidget);
    expect(find.byType(WaybiLoadError), findsNothing);
    expect(find.text('Smart Commute'), findsOneWidget);
    expect(
      find.text('Couldn’t refresh — showing your last loaded trips.'),
      findsOneWidget,
    );
    await t.tap(
      find.descendant(
        of: find.byType(WaybiInlineError),
        matching: find.text('Retry'),
      ),
    );
    await t.pumpAndSettle();
    expect(calls, 3);
  });

  testWidgets('explore clears or marks stale places when loading fails', (
    t,
  ) async {
    final failing = <String>{};
    final repository = ExploreRepository(
      client: MockClient((request) async {
        final category = request.url.queryParameters['category']!;
        if (failing.contains(category)) return http.Response('busy', 503);
        return http.Response.bytes(
          utf8.encode(
            jsonEncode([
              {
                'placeId': 'osm:$category',
                'provider': 'osm',
                'name': 'Place for $category',
                'primaryType': category,
                'latitude': -36.85,
                'longitude': 174.76,
              },
            ]),
          ),
          200,
        );
      }),
    );
    await t.pumpWidget(
      MaterialApp(
        home: ExplorePage(
          currentLocation: const LatLng(latitude: -36.85, longitude: 174.76),
          language: 'en',
          repository: repository,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Place for for-you'), findsOneWidget);

    // Switching category fails: the previous category's places must go.
    failing.add('food');
    await t.tap(find.text('Food'));
    await t.pumpAndSettle();
    expect(find.text('Place for for-you'), findsNothing);
    expect(find.byKey(const ValueKey('explore-load-error')), findsOneWidget);

    // Retry after recovery loads the selected category.
    failing.clear();
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(find.text('Place for food'), findsOneWidget);

    // Refreshing the same list fails: keep it, clearly marked stale.
    failing.add('food');
    await t.fling(find.text('Place for food'), const Offset(0, 400), 1000);
    await t.pumpAndSettle();
    expect(find.text('Place for food'), findsOneWidget);
    expect(find.byKey(const ValueKey('explore-stale')), findsOneWidget);
    expect(
      find.text('Couldn’t refresh — these places may be out of date.'),
      findsOneWidget,
    );
  });

  testWidgets('explore waits for location without an error colour', (t) async {
    final repository = ExploreRepository(
      client: MockClient((_) async => http.Response('[]', 200)),
    );
    await t.pumpWidget(
      MaterialApp(
        home: ExplorePage(
          currentLocation: null,
          language: 'zh',
          repository: repository,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('正在获取你的位置…'), findsOneWidget);
    expect(find.byType(WaybiLoadError), findsNothing);
  });
}
