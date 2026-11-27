import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/app/home_overlays.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/navigation_camera_mode.dart';
import 'package:waybi_mobile/widgets/companion_search_prompt.dart';

Widget host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('RouteStartButton', () {
    Future<String> label(
      WidgetTester t, {
      String language = 'en',
      bool busy = false,
      bool planning = false,
      bool hasRoute = true,
      bool transit = false,
      bool needsDetour = false,
      VoidCallback? onStart,
      VoidCallback? onShowAll,
    }) async {
      await t.pumpWidget(
        host(
          RouteStartButton(
            language: language,
            busy: busy,
            planning: planning,
            hasRoute: hasRoute,
            transit: transit,
            needsDetour: needsDetour,
            onShowAllRoutes: onShowAll ?? () {},
            onStart: onStart ?? () {},
          ),
        ),
      );
      final button = t.widget<FloatingActionButton>(
        find.byKey(const Key('routeStartFloatingButton')),
      );
      expect(button.onPressed == null, busy);
      return t
          .widget<Text>(
            find.descendant(
              of: find.byType(FloatingActionButton),
              matching: find.byType(Text),
            ),
          )
          .data!;
    }

    testWidgets('names what pressing it does', (t) async {
      expect(await label(t), 'Start');
      expect(await label(t, transit: true), 'Start trip');
      expect(await label(t, needsDetour: true), 'Find detour');
      expect(await label(t, hasRoute: false), 'Show all routes');
      expect(await label(t, busy: true), 'Starting…');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(await label(t, busy: true, planning: true), 'Planning…');
      expect(await label(t, language: 'zh'), '开始导航');
    });

    testWidgets('starts, or shows every route when the filter left none', (
      t,
    ) async {
      var starts = 0, shown = 0;
      await label(t, onStart: () => starts++, onShowAll: () => shown++);
      await t.tap(find.byType(FloatingActionButton));
      await label(
        t,
        hasRoute: false,
        onStart: () => starts++,
        onShowAll: () => shown++,
      );
      await t.tap(find.byType(FloatingActionButton));
      expect((starts, shown), (1, 1));
    });
  });

  group('HomeMapControls', () {
    Widget controls({
      bool following = true,
      NavigationCameraMode mode = NavigationCameraMode.northUpFlat,
      String language = 'en',
      String? parked,
      List<String>? taps,
    }) => host(
      HomeMapControls(
        language: language,
        following: following,
        cameraMode: mode,
        parkedCarLabel: parked,
        onParkedCar: () => taps?.add('parked'),
        onSaved: () => taps?.add('saved'),
        onLayers: () => taps?.add('layers'),
        onReport: () => taps?.add('report'),
        onLocation: () => taps?.add('location'),
      ),
    );

    testWidgets('every control has a named action', (t) async {
      final taps = <String>[];
      await t.pumpWidget(controls(parked: 'Parked just now', taps: taps));
      for (final tooltip in [
        'Parked just now',
        'Saved places',
        'Map layers',
        'Report road issue',
        'Switch to heading-up',
      ]) {
        await t.tap(find.byTooltip(tooltip));
      }
      expect(taps, ['parked', 'saved', 'layers', 'report', 'location']);
    });

    testWidgets('the location control says what it does next', (t) async {
      await t.pumpWidget(controls(following: false));
      expect(find.byTooltip('Return to my location'), findsOneWidget);
      expect(find.byIcon(Icons.my_location_outlined), findsOneWidget);
      expect(find.byTooltip('Parked just now'), findsNothing);
      await t.pumpWidget(controls(mode: NavigationCameraMode.headingUpFlat));
      expect(find.byTooltip('Switch to north-up'), findsOneWidget);
      expect(find.byIcon(Icons.navigation_rounded), findsOneWidget);
      await t.pumpWidget(
        controls(mode: NavigationCameraMode.headingUpFlat, language: 'zh'),
      );
      expect(find.byTooltip('切换到北向俯视'), findsOneWidget);
      expect(find.byTooltip('收藏地点'), findsOneWidget);
    });
  });

  testWidgets('the search header offers to search a moved map', (t) async {
    final location = ValueNotifier<GeoPoint?>(null);
    addTearDown(location.dispose);
    var searched = 0;
    Widget header(bool searchArea) => host(
      SizedBox(
        width: 380,
        child: HomeSearchHeader(
          language: 'en',
          marker: LocationMarkerStyle.kiwi,
          location: location,
          fallbackLocation: const GeoPoint(-36.85, 174.76),
          loadSuggestions: (_) async => const [],
          cachedSuggestions: (_) => const [],
          onSuggestionSelected: (_) {},
          onSearch: (_) {},
          quickActions: const Text('Shortcuts'),
          showSearchArea: searchArea,
          onSearchArea: () => searched++,
        ),
      ),
    );
    await t.pumpWidget(header(false));
    expect(find.text('Shortcuts'), findsOneWidget);
    expect(find.text('Search this area'), findsNothing);
    expect(
      t
          .widget<CompanionSearchPrompt>(find.byType(CompanionSearchPrompt))
          .currentLocation,
      const GeoPoint(-36.85, 174.76),
    );
    location.value = const GeoPoint(-37.2, 174.9);
    await t.pumpWidget(header(true));
    expect(
      t
          .widget<CompanionSearchPrompt>(find.byType(CompanionSearchPrompt))
          .currentLocation,
      const GeoPoint(-37.2, 174.9),
    );
    await t.tap(find.text('Search this area'));
    expect(searched, 1);
  });

  testWidgets('FrameSafeNotifier defers a ping made during a build', (t) async {
    final notifier = FrameSafeNotifier();
    addTearDown(notifier.dispose);
    var heard = 0;
    notifier.addListener(() => heard++);
    notifier.ping();
    expect(heard, 1);
    int? duringBuild;
    await t.pumpWidget(
      Builder(
        builder: (context) {
          notifier
            ..ping()
            ..ping();
          duringBuild = heard;
          return const SizedBox();
        },
      ),
    );
    // Not during the build; once, after that frame.
    expect(duringBuild, 1);
    expect(heard, 2);
    expect(t.takeException(), isNull);
  });
}
