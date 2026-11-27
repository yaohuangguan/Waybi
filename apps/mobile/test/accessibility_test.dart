import 'dart:ui' show Tristate;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_layer_settings.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/drive/drive_engine.dart';
import 'package:waybi_mobile/theme/waybi_theme.dart';
import 'package:waybi_mobile/widgets/map_layer_sheet.dart';
import 'package:waybi_mobile/widgets/navigation_overlay.dart';
import 'package:waybi_mobile/widgets/route_preview_sheet.dart';
import 'package:waybi_mobile/widgets/splash_gate.dart';
import 'package:waybi_mobile/widgets/status_banner.dart';
import 'package:waybi_mobile/widgets/trips_page.dart';
import 'package:waybi_mobile/widgets/waybi_bird.dart';

import 'layout_matrix_test.dart' show drive;

Widget host(Widget child, {bool reduceMotion = false, bool a11y = false}) =>
    MaterialApp(
      theme: WaybiTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: reduceMotion, accessibleNavigation: a11y),
        child: child!,
      ),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('route preview controls are 48 dp, labelled and expose '
      'selection', (t) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(
      host(
        Align(
          alignment: Alignment.bottomCenter,
          child: RoutePreviewSheet(
            destinationTitle: 'Auckland Museum',
            originTitle: 'Current location',
            plan: RoutePlan(
              options: [drive('a'), drive('b', time: 3300)],
              trafficAvailable: true,
              provider: 'independent',
              stopsApplied: 0,
            ),
            selectedMode: WaybiTravelMode.drive,
            selectedRouteId: 'a',
            busy: false,
            stopCount: 0,
            cameraCount: 0,
            customOrigin: false,
            onModeChanged: (_) {},
            onRouteSelected: (_) {},
            onStart: () {},
            onAddStop: () {},
            onSave: () {},
            isFavorite: false,
            onFavorite: () {},
            onReview: () {},
            onClose: () {},
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    for (final tooltip in ['Save favorite', 'My review', 'Close']) {
      final button = find.byTooltip(tooltip);
      expect(button, findsOneWidget, reason: tooltip);
      final size = t.getSize(button);
      expect(size.width, greaterThanOrEqualTo(48), reason: tooltip);
      expect(size.height, greaterThanOrEqualTo(48), reason: tooltip);
    }
    final driveTab = t.getSemantics(find.text('Drive'));
    expect(driveTab.flagsCollection.isSelected, Tristate.isTrue);
    final walkTab = t.getSemantics(find.text('Walk'));
    expect(walkTab.flagsCollection.isSelected, isNot(Tristate.isTrue));
    expect(
      find.bySemanticsLabel(RegExp('45 min')),
      findsWidgets,
      reason: 'route options are announced',
    );
    final selectedRoutes = find.semantics.byPredicate(
      (node) =>
          node.flagsCollection.isSelected == Tristate.isTrue &&
          node.flagsCollection.isButton,
    );
    expect(selectedRoutes, findsWidgets);
    handle.dispose();
  });

  testWidgets('camera alert bells are 48 dp toggles', (t) async {
    final handle = t.ensureSemantics();
    var settings = const MapLayerSettings();
    await t.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => MapLayerSheet(
            settings: settings,
            onChanged: (next) => setState(() => settings = next),
            mapProvider: MapProvider.independent,
            language: 'en',
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Spot speed'), 200);
    final bell = find.bySemanticsLabel('Alert while driving · Spot speed');
    expect(bell, findsOneWidget);
    expect(t.getSize(bell).height, greaterThanOrEqualTo(48));
    final before = t.getSemantics(bell).flagsCollection.isToggled;
    await t.tap(bell);
    await t.pumpAndSettle();
    expect(t.getSemantics(bell).flagsCollection.isToggled, isNot(before));
    handle.dispose();
  });

  testWidgets('commute traffic is an icon and a word, not a dot', (t) async {
    await t.pumpWidget(
      host(
        TripsPage(
          language: 'en',
          loader: () async => TripsSnapshot(
            quickPlaces: const {
              'Home': TripDestination(
                name: 'Home',
                location: GeoPoint(-36.8, 174.7),
              ),
            },
            quickRoutes: {'Home': drive('h', jam: 1)},
            recent: const [],
            history: const [],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final badge = find.byKey(const ValueKey('commuteTrafficBadge'));
    expect(badge, findsOneWidget);
    expect(
      find.descendant(of: badge, matching: find.text('Heavy')),
      findsOneWidget,
    );
  });

  testWidgets('the mascot is decorative unless labelled', (t) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(
      host(
        const Column(
          children: [
            WaybiBird(size: 40),
            WaybiBird(size: 40, semanticLabel: 'Kiwi 鸟 Waybi'),
          ],
        ),
      ),
    );
    expect(find.bySemanticsLabel('Waybi kiwi bird'), findsNothing);
    expect(find.bySemanticsLabel('Kiwi 鸟 Waybi'), findsOneWidget);
    handle.dispose();
  });

  group('status banner', () {
    test('reading time grows with the message', () {
      expect(statusBannerDuration('Saved'), const Duration(seconds: 4));
      expect(
        statusBannerDuration('x' * 120),
        greaterThan(const Duration(seconds: 8)),
      );
      expect(statusBannerDuration('x' * 900), const Duration(seconds: 12));
    });

    testWidgets('touching pauses the countdown', (t) async {
      var dismissed = 0;
      await t.pumpWidget(
        host(
          WaybiStatusBanner(
            message: 'Route saved',
            onDismiss: () => dismissed++,
          ),
        ),
      );
      await t.pump(const Duration(seconds: 3));
      final press = await t.startGesture(t.getCenter(find.text('Route saved')));
      await t.pump(const Duration(seconds: 6));
      expect(dismissed, 0);
      await press.up();
      await t.pump(const Duration(milliseconds: 3900));
      expect(dismissed, 0, reason: 'release restarts the full reading time');
      await t.pump(const Duration(milliseconds: 200));
      expect(dismissed, 1);
    });

    testWidgets('iOS announces the notice and a cancelled touch resumes', (
      t,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final announced = <Object?>[];
      t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
        SystemChannels.accessibility,
        (message) async {
          announced.add(message);
          return null;
        },
      );
      addTearDown(() {
        t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
          SystemChannels.accessibility,
          null,
        );
      });
      var dismissed = 0;
      await t.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(supportsAnnounce: true),
            child: child!,
          ),
          home: Scaffold(
            body: WaybiStatusBanner(
              message: 'Route saved',
              onDismiss: () => dismissed++,
            ),
          ),
        ),
      );
      await t.pump();
      expect(
        announced.whereType<Map>().where(
          (m) =>
              m['type'] == 'announce' && m['data']['message'] == 'Route saved',
        ),
        isNotEmpty,
      );
      final press = await t.startGesture(t.getCenter(find.text('Route saved')));
      await t.pump(const Duration(seconds: 5));
      await press.cancel();
      await t.pump(const Duration(seconds: 4));
      expect(dismissed, 1);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('screen-reader users dismiss notices themselves', (t) async {
      var dismissed = 0;
      await t.pumpWidget(
        host(
          WaybiStatusBanner(
            message: 'Route saved',
            onDismiss: () => dismissed++,
          ),
          a11y: true,
        ),
      );
      await t.pump(const Duration(seconds: 20));
      expect(dismissed, 0);
    });
  });

  for (final dark in [false, true]) {
    testWidgets('splash is localized in ${dark ? 'dark' : 'light'} mode', (
      t,
    ) async {
      await t.pumpWidget(
        MaterialApp(
          theme: WaybiTheme.light,
          darkTheme: WaybiTheme.dark,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          locale: dark ? const Locale('zh') : const Locale('en'),
          supportedLocales: const [Locale('en'), Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const SplashGate(child: Text('Map ready')),
        ),
      );
      final scaffold = t.widget<Scaffold>(find.byType(Scaffold));
      // One splash colour matching the native launch screens.
      expect(scaffold.backgroundColor, WaybiColors.lightBackground);
      expect(
        find.text(dark ? '遇见 Waybi，找到你的路。' : 'Meet Waybi. Find your way.'),
        findsOneWidget,
      );
      await t.pump(const Duration(milliseconds: 1100));
      await t.pumpAndSettle();
      expect(find.text('Map ready'), findsOneWidget);
    });
  }

  testWidgets('reduced motion swaps the splash without a fade', (t) async {
    await t.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const SplashGate(child: Text('Map ready')),
      ),
    );
    await t.pump(const Duration(milliseconds: 1051));
    await t.pump();
    expect(find.text('Map ready'), findsOneWidget);
    expect(find.text('Waybi'), findsNothing);
  });

  testWidgets('reduced motion opens the trip deck without animating', (
    t,
  ) async {
    final engine = DriveEngine();
    addTearDown(engine.dispose);
    await t.pumpWidget(
      host(
        NavigationOverlay(
          engine: engine,
          destinationTitle: 'Museum',
          gpsAccuracy: 5,
          voiceEnabled: true,
          lanesEnabled: true,
          onEnd: () {},
          onRecenter: () {},
          onOverview: () {},
          northUp: false,
          onCompassToggle: () {},
          onReport: () {},
          onSearchAlongRoute: () {},
          onDirections: () {},
          onShare: () {},
          onSettings: () {},
          onLayers: () {},
          onVoiceToggle: () {},
          onLanesToggle: () {},
        ),
        reduceMotion: true,
      ),
    );
    await t.pumpAndSettle();
    expect(find.byType(AnimatedSize), findsNothing);
    await t.tap(find.byKey(const Key('navigationSheetHandle')));
    await t.pump();
    await t.pump();
    expect(find.text('Trip tools'), findsOneWidget);
  });
}
