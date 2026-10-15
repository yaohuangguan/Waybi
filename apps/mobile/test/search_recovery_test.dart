import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_mobile/providers/provider_contracts.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/widgets/full_screen_search.dart';

PlaceCandidate candidate(String name) => PlaceCandidate(
  name: name,
  kind: PlaceKind.address,
  location: const GeoPoint(-36.85, 174.76),
  reference: ProviderReference('test', name),
);

class SearchStub
    implements SearchProvider, CachedSearchProvider, ExpandedSearchProvider {
  Future<List<PlaceCandidate>> Function(String, bool) handler = (
    query,
    all,
  ) async => [candidate(query)];
  List<PlaceCandidate> Function(String) cached = (_) => [];
  final calls = <String>[];

  @override
  List<PlaceCandidate> cachedSuggestions(
    String query, {
    GeoPoint? proximity,
    required String language,
  }) => cached(query);

  @override
  Future<List<PlaceCandidate>> search(
    String query, {
    GeoPoint? proximity,
    required String language,
  }) {
    calls.add('near:$query');
    return handler(query, false);
  }

  @override
  Future<List<PlaceCandidate>> searchFurther(
    String query, {
    GeoPoint? proximity,
    required String language,
  }) {
    calls.add('all:$query');
    return handler(query, true);
  }
}

Future<void> openSearch(
  WidgetTester tester,
  SearchStub provider, {
  Future<PlaceSummary> Function(PlaceCandidate)? resolve,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FullScreenSearch(
                    provider: provider,
                    resolve:
                        resolve ?? (item) async => item.toPlace(item.location!),
                    language: 'en',
                    currentLocation: const GeoPoint(-36.85, 174.76),
                    recent: const [],
                  ),
                ),
              ),
              child: const Text('Open search'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open search'));
  await tester.pumpAndSettle();
}

Future<void> typeQuery(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump(const Duration(milliseconds: 170));
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a failed refresh retains matching cached results and retries', (
    tester,
  ) async {
    final provider = SearchStub();
    provider.cached = (_) => [candidate('Saved airport')];
    provider.handler = (_, _) async => throw StateError('offline');
    await openSearch(tester, provider);
    await typeQuery(tester, 'airport');
    expect(find.text('Saved airport'), findsOneWidget);
    expect(
      find.text('Could not refresh. Showing previous results.'),
      findsOneWidget,
    );

    provider.handler = (_, _) async => [candidate('Updated airport')];
    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Updated airport'), findsOneWidget);
    expect(find.text('Saved airport'), findsNothing);
    expect(provider.calls, ['near:airport', 'near:airport']);
  });

  testWidgets('failed new query never presents an earlier query as a match', (
    tester,
  ) async {
    final provider = SearchStub();
    await openSearch(tester, provider);
    await typeQuery(tester, 'Airport');
    expect(find.text('Airport'), findsWidgets);
    provider.handler = (_, _) async => throw StateError('offline');
    await typeQuery(tester, 'Home');
    expect(find.text('Airport'), findsNothing);
    expect(find.text('Search is temporarily unavailable'), findsOneWidget);
  });

  testWidgets(
    'retrying a place failure resolves that place instead of searching again',
    (tester) async {
      final provider = SearchStub();
      var resolves = 0;
      await openSearch(
        tester,
        provider,
        resolve: (item) async {
          if (++resolves == 1) throw StateError('Temporary details failure');
          return item.toPlace(item.location!);
        },
      );
      await typeQuery(tester, 'Airport');
      await tester.tap(find.widgetWithText(ListTile, 'Airport'));
      await tester.pump();
      expect(find.text('Could not open this place'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(resolves, 2);
      expect(provider.calls, ['near:Airport']);
      expect(find.text('Open search'), findsOneWidget);
    },
  );

  testWidgets(
    'changing search cancels a pending selection before it can navigate',
    (tester) async {
      final selected = Completer<PlaceSummary>();
      final provider = SearchStub();
      await openSearch(tester, provider, resolve: (_) => selected.future);
      await typeQuery(tester, 'Airport');
      await tester.tap(find.widgetWithText(ListTile, 'Airport'));
      await tester.pump();
      await typeQuery(tester, 'Home');
      selected.complete(
        candidate('Airport').toPlace(const GeoPoint(-36.85, 174.76)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FullScreenSearch), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Home'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('expanded-area retry stays in the chosen search scope', (
    tester,
  ) async {
    final provider = SearchStub()
      ..handler = (query, all) async {
        if (all) throw StateError('offline');
        return [candidate('Nearby airport')];
      };
    await openSearch(tester, provider);
    await typeQuery(tester, 'airport');
    await tester.tap(find.text('Search further'));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    provider.handler = (_, all) async => [
      candidate(all ? 'Further airport' : 'Wrong scope'),
    ];
    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(provider.calls, ['near:airport', 'all:airport', 'all:airport']);
    expect(find.text('Further airport'), findsOneWidget);
  });

  testWidgets(
    'results from an earlier query cannot be selected while the new query loads',
    (tester) async {
      final pending = Completer<List<PlaceCandidate>>();
      final provider = SearchStub();
      var resolves = 0;
      await openSearch(
        tester,
        provider,
        resolve: (item) async {
          resolves++;
          return item.toPlace(item.location!);
        },
      );
      await typeQuery(tester, 'Airport');
      provider.handler = (_, _) => pending.future;
      await typeQuery(tester, 'Home');
      final old = find.widgetWithText(ListTile, 'Airport');
      expect(tester.widget<ListTile>(old).onTap, isNull);
      await tester.tap(old);
      expect(resolves, 0);
      pending.complete([candidate('Home')]);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Home'));
      await tester.pumpAndSettle();
      expect(resolves, 1);
      expect(find.text('Open search'), findsOneWidget);
    },
  );

  testWidgets(
    'history and places remain reachable above a keyboard with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'waybi.search.recent_queries.v1': List.generate(
          6,
          (i) => 'Recent query $i',
        ),
      });
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              viewInsets: const EdgeInsets.only(bottom: 280),
              textScaler: TextScaler.linear(1.5),
            ),
            child: child!,
          ),
          home: FullScreenSearch(
            provider: SearchStub(),
            resolve: (item) async => item.toPlace(item.location!),
            language: 'en',
            onDriveMode: () {},
            recent: List.generate(
              6,
              (i) =>
                  candidate('Recent place $i')
                      .toPlace(const GeoPoint(-36.85, 174.76)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Recent place 5'),
        120,
        scrollable: find.descendant(
          of: find.byKey(const Key('fullScreenSearchScroll')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('Recent place 5').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
