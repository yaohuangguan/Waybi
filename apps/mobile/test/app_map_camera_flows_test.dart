import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/providers/independent_map_style.dart';
import 'package:waybi_mobile/widgets/drive_hud.dart';
import 'package:waybi_mobile/widgets/explore_page.dart';
import 'package:waybi_mobile/widgets/place_details_content.dart';
import 'package:waybi_mobile/widgets/route_preview_sheet.dart';
import 'package:waybi_mobile/widgets/independent_navigation_overlay.dart';

import 'support/app_harness.dart';

void flow(String name, Future<void> Function(WidgetTester, AppHarness) body) {
  testWidgets(name, (t) async {
    final h = AppHarness(t);
    await http.runWithClient(() async {
      await body(t, h);
      await h.dispose();
    }, () => h.client);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await IndependentMapStyle.load(
      dark: false,
      language: 'en',
      center: const GeoPoint(-37.2, 174.9),
    );
  });
  flow(
    'browse camera follows a fresh fix, pauses on pan and searches the actual viewport',
    (t, h) async {
      await h.boot();
      await h.readyMap();
      final before = h.mapPlatform.moves.length;
      h.gps.emit(longitude: 174.9002);
      await h.frames();
      expect(h.mapPlatform.moves.length, greaterThan(before));
      await h.act(
        () => h.map.onViewportChanged(
          const MapViewportState(center: GeoPoint(-37.2, 174.99), zoom: 15),
        ),
      );
      await h.act(h.map.onUserPan);
      expect(h.map.following, isFalse);
      await h.tapText('Search this area');
      final page = t.widget<ExplorePage>(find.byType(ExplorePage));
      expect(page.currentLocation!.longitude, 174.99);
      expect(page.mapCompatible, isTrue);
      Navigator.of(t.element(find.byType(ExplorePage))).pop();
      await h.frames();
      await t.tap(find.byTooltip('Return to my location'));
      await h.frames();
      expect(h.map.following, isTrue);
    },
  );
  flow(
    'Just Drive sends camera updates as the car moves and recenter resumes follow after panning',
    (t, h) async {
      await h.boot();
      await h.readyMap();
      await h.tapText('Start');
      await h.tapText('Just Drive');
      await h.until(
        () => h.map.driving,
        reason: 'Just Drive should become active',
      );
      final before = h.mapPlatform.moves.length;
      for (final lon in [174.9001, 174.9002, 174.9003]) {
        h.gps.emit(longitude: lon, speed: 5);
        await h.frames(2);
      }
      expect(h.mapPlatform.moves.length, greaterThan(before));
      await h.act(h.map.onUserPan);
      expect(h.map.following, isFalse);
      final hud = t.widget<DriveHud>(find.byType(DriveHud));
      await h.act(hud.onRecenter!);
      expect(h.map.following, isTrue);
      final resumed = h.mapPlatform.moves.length;
      h.gps.emit(longitude: 174.9004, speed: 5);
      await h.frames();
      await h.until(
        () => h.mapPlatform.moves.length > resumed,
        reason: 'Recenter should resume native camera updates',
      );
      expect(h.mapPlatform.moves.length, greaterThan(resumed));
      await h.act(hud.onStop);
      await h.until(
        () => !h.map.driving,
        reason: 'Just Drive should stop cleanly',
      );
    },
  );
  flow(
    'guidance fits the full route and returns to the car with correct map content padding',
    (t, h) async {
      await h.boot();
      await h.readyMap();
      await h.select();
      var details = t.widget<PlaceDetailsContent>(
        find.byType(PlaceDetailsContent),
      );
      expect(h.mapPlatform.padding.bottom, greaterThan(0));
      await h.act(details.onNavigate);
      final preview = t.widget<RoutePreviewSheet>(
        find.byType(RoutePreviewSheet),
      );
      await h.act(preview.onStart);
      await h.until(() => h.map.navigating, reason: 'Guidance should start');
      final nav = t.widget<IndependentNavigationOverlay>(
        find.byType(IndependentNavigationOverlay),
      );
      final before = h.mapPlatform.moves.length;
      await h.act(nav.onOverview);
      expect(h.map.following, isFalse);
      expect(h.mapPlatform.moves.length, greaterThan(before));
      await h.act(nav.onRecenter);
      expect(h.map.following, isTrue);
      await h.until(
        () => h.mapPlatform.padding.bottom > 0,
        reason: 'Returning from overview should restore guidance insets',
      );
      expect(h.mapPlatform.padding.bottom, greaterThan(0));
      await h.act(nav.onEnd);
      await h.until(() => !h.map.navigating, reason: 'Guidance should end');
      expect(h.mapPlatform.padding.bottom, 96);
    },
  );
}
