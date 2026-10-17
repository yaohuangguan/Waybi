import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/widgets/place_details_content.dart';
import 'package:waybi_mobile/widgets/route_preview_sheet.dart';
import 'package:waybi_mobile/widgets/independent_navigation_overlay.dart';
import 'package:waybi_mobile/widgets/drive_hud.dart';

import 'support/app_harness.dart';

RoutePreviewSheet preview(WidgetTester t) =>
    t.widget<RoutePreviewSheet>(find.byType(RoutePreviewSheet));
PlaceDetailsContent details(WidgetTester t) =>
    t.widget<PlaceDetailsContent>(find.byType(PlaceDetailsContent));
void main() {
  for (final previousProvider in ['google', 'independent', 'invalid']) {
    testWidgets(
      'legacy provider $previousProvider migrates to the sole Waybi renderer',
      (t) async {
        final h = AppHarness(t);
        await http.runWithClient(() async {
          await h.boot(preferences: {'waybi.map.provider': previousProvider});
          expect(
            (await SharedPreferences.getInstance()).getString(
              'waybi.map.provider',
            ),
            'independent',
          );
          expect(h.map.location, const GeoPoint(-37.2, 174.9));
          await h.select();
          await h.act(details(t).onNavigate);
          expect(preview(t).plan.provider, 'independent');
          expect(h.requests.any((r) => r.url.host.contains('google')), isFalse);
          await h.dispose();
        }, () => h.client);
      },
    );
  }
  testWidgets(
    'real map selection previews alternatives, changes mode and starts and ends independent navigation',
    (t) async {
      final h = AppHarness(t);
      await http.runWithClient(() async {
        await h.boot();
        expect(h.map.location, const GeoPoint(-37.2, 174.9));
        await h.select();
        expect(details(t).selectedPlace.name, 'Test destination');
        await h.act(details(t).onNavigate);
        await h.frames();
        expect(preview(t).plan.options, hasLength(2));
        expect(preview(t).selectedRouteId, 'drive-fast');
        preview(t).onRouteSelected(preview(t).plan.options.last);
        await h.frames();
        expect(preview(t).selectedRouteId, 'drive-short');
        preview(t).onModeChanged(WaybiTravelMode.walk);
        await h.frames();
        expect(preview(t).selectedMode, WaybiTravelMode.walk);
        preview(t).onModeChanged(WaybiTravelMode.drive);
        await h.frames();
        expect(preview(t).selectedMode, WaybiTravelMode.drive);
        await h.act(preview(t).onStart);
        await h.frames(12);
        await h.until(
          () => h.map.navigating,
          reason: 'Navigation should start after native location and transit matching are ready',
        );
        expect(
          find.byType(IndependentNavigationOverlay),
          findsOneWidget,
          reason: t
              .widgetList<Text>(find.byType(Text))
              .map((w) => w.data)
              .join(' | '),
        );
        expect(h.map.navigating, isTrue);
        expect(h.map.selectedPlace, isNull);
        expect(
          h.calls.any(
            (c) =>
                c.method == 'start' &&
                (c.arguments as Map?)?['provider'] == 'independent',
          ),
          isTrue,
        );
        final overlay = t.widget<IndependentNavigationOverlay>(
          find.byType(IndependentNavigationOverlay),
        );
        overlay.onOverview();
        await h.frames();
        expect(h.map.following, isFalse);
        overlay.onRecenter();
        await h.frames();
        expect(h.map.following, isTrue);
        overlay.onVoiceToggle();
        overlay.onLanesToggle();
        await h.frames();
        overlay.onDirections();
        await h.frames();
        expect(find.text('Directions'), findsOneWidget);
        Navigator.of(t.element(find.text('Directions'))).pop();
        await h.frames();
        await h.act(
          t
              .widget<IndependentNavigationOverlay>(
                find.byType(IndependentNavigationOverlay),
              )
              .onEnd,
        );
        await h.frames();
        expect(h.map.navigating, isFalse);
        expect(h.map.driving, isFalse);
        expect(
          h.routeRequests.every(
            (r) => r.url.queryParameters['provider'] == 'independent',
          ),
          isTrue,
        );
        expect(h.requests.any((r) => r.url.host.contains('google')), isFalse);
        await h.dispose();
      }, () => h.client);
    },
  );
  testWidgets(
    'closure start failures explain recovery and a fresh clear detour can start',
    (t) async {
      final h = AppHarness(t)..blocked = true;
      await http.runWithClient(() async {
        await h.boot();
        await h.select();
        await h.act(details(t).onNavigate);
        await h.frames();
        await h.act(preview(t).onStart);
        await h.frames();
        expect(find.textContaining('No verified detour'), findsOneWidget);
        expect(h.map.navigating, isFalse);
        expect(preview(t).busy, isFalse);
        h.blocked = false;
        await h.act(preview(t).onStart);
        await h.frames();
        expect(find.textContaining('Detour ready'), findsOneWidget);
        expect(
          preview(t).plan.options.every((r) => !r.blockedForDriving),
          isTrue,
        );
        await h.act(preview(t).onStart);
        await h.frames(12);
        await h.until(
          () => h.map.navigating,
          reason: 'A verified clear detour should start navigation',
        );
        expect(h.map.navigating, isTrue);
        await h.dispose();
      }, () => h.client);
    },
  );
  testWidgets(
    'failed route planning retains the selected destination and recovers without reopening it',
    (t) async {
      final h = AppHarness(t)..routeFailure = true;
      await http.runWithClient(() async {
        await h.boot();
        await h.select();
        await h.act(details(t).onNavigate);
        await h.frames();
        expect(
          find.textContaining('Route service is temporarily unavailable'),
          findsWidgets,
        );
        expect(details(t).selectedPlace.name, 'Test destination');
        expect(h.map.navigating, isFalse);
        h.routeFailure = false;
        await h.act(details(t).onNavigate);
        await h.frames();
        expect(find.byType(RoutePreviewSheet), findsOneWidget);
        preview(t).onClose();
        await h.frames();
        expect(h.map.selectedPlace, isNull);
        expect(h.map.routePaths, isEmpty);
        await h.dispose();
      }, () => h.client);
    },
  );
  testWidgets(
    'Just Drive starts from search, follows on recenter and clears its temporary trail when ended',
    (t) async {
      final h = AppHarness(t);
      await http.runWithClient(() async {
        await h.boot();
        await h.tapText('Start');
        await h.tapText('Just Drive');
        await h.frames(12);
        expect(find.byType(DriveHud), findsOneWidget);
        expect(h.map.driving, isTrue);
        expect(h.map.navigating, isFalse);
        expect(h.map.following, isTrue);
        h.map.onUserPan();
        await h.frames();
        expect(h.map.following, isFalse);
        final hud = t.widget<DriveHud>(find.byType(DriveHud));
        await t.tap(find.byTooltip('Return to my location'));
        await h.frames();
        expect(h.map.following, isTrue);
        h.gps.current = AppGps.position(
          longitude: 174.9002,
          speed: 4,
          time: DateTime.now().add(const Duration(seconds: 4)),
        );
        h.gps.positions.add(h.gps.current);
        await h.frames();
        expect(h.map.routePaths.any((p) => p.trail), isTrue);
        await h.act(hud.onStop);
        await h.frames();
        expect(h.map.driving, isFalse);
        expect(h.map.routePaths, isEmpty);
        await h.dispose();
      }, () => h.client);
    },
  );
  testWidgets(
    'permanent location denial preserves pending destination and resumes planning after access is restored',
    (t) async {
      final h = AppHarness(t)..permission = 4;
      await http.runWithClient(() async {
        await h.boot();
        expect(h.map.location, isNull);
        expect(find.text('Open settings'), findsOneWidget);
        await h.select();
        await h.act(details(t).onNavigate);
        await h.frames();
        expect(h.routeRequests, isEmpty);
        await h.tapText('Open settings');
        expect(h.calls.any((c) => c.method == 'openAppSettings'), isTrue);
        h.permission = 1;
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await h.frames();
        h.gps.emit(longitude: 174.9, speed: 0);
        await h.frames();
        expect(find.byType(RoutePreviewSheet), findsOneWidget);
        expect(h.routeRequests.last.url.queryParameters['from'], '174.9,-37.2');
        await h.dispose();
      }, () => h.client);
    },
  );
}
