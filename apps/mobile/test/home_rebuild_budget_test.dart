import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/main.dart';
import 'package:waybi_mobile/providers/independent_map_renderer.dart';
import 'package:waybi_mobile/widgets/place_details_content.dart';
import 'package:waybi_mobile/widgets/route_preview_sheet.dart';

import 'support/app_harness.dart';

/// GPS fixes, the compass and engine ticks reach the map and the HUDs
/// through listenables; the home page itself must not rebuild once per fix.
///
/// Before the scoped rebuilds the page rebuilt 20 times for 20 browse fixes
/// and 40 times for 20 navigation fixes (20 once the marker signature was
/// stored); now it rebuilds at most a couple of times while the map still
/// follows every fix.
void main() {
  Future<({int page, int map})> buildsDuring(
    Future<void> Function() body,
  ) async {
    var page = 0, map = 0;
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      if (element.widget is MapHomePage) page++;
      if (element.widget is IndependentMapRenderer) map++;
      previous?.call(element, builtOnce);
    };
    try {
      await body();
    } finally {
      debugOnRebuildDirtyWidget = previous;
    }
    return (page: page, map: map);
  }

  Future<void> stream(AppHarness h, {required double speed}) async {
    for (var i = 1; i <= 20; i++) {
      h.gps.current = AppGps.position(
        longitude: 174.9 + i * .00004,
        speed: speed,
        time: DateTime.now(),
      );
      h.gps.positions.add(h.gps.current);
      await h.tester.pump(const Duration(milliseconds: 500));
      await h.tester.pump(const Duration(milliseconds: 500));
    }
    await h.frames(2);
  }

  testWidgets('browsing: 20 GPS fixes move the map without rebuilding the '
      'home page per fix', (t) async {
    final h = AppHarness(t);
    await http.runWithClient(() async {
      await h.boot();
      final builds = await buildsDuring(() => stream(h, speed: 0));
      expect(builds.page, lessThanOrEqualTo(2), reason: '$builds');
      expect(builds.map, greaterThanOrEqualTo(10), reason: 'the map follows');
      expect(h.map.location, const GeoPoint(-37.2, 174.9 + 20 * .00004));
      await h.dispose();
    }, () => h.client);
  });

  testWidgets('navigating: 20 GPS fixes move the map and HUD without '
      'rebuilding the home page per fix', (t) async {
    final h = AppHarness(t);
    await http.runWithClient(() async {
      await h.boot();
      await h.select();
      await h.act(
        t
            .widget<PlaceDetailsContent>(find.byType(PlaceDetailsContent))
            .onNavigate,
      );
      await h.act(
        t.widget<RoutePreviewSheet>(find.byType(RoutePreviewSheet)).onStart,
      );
      await h.until(() => h.map.navigating, reason: 'navigation starts');
      await h.frames();
      final before = h.map.location;
      final builds = await buildsDuring(() => stream(h, speed: 8));
      expect(builds.page, lessThanOrEqualTo(2), reason: '$builds');
      expect(builds.map, greaterThanOrEqualTo(10), reason: 'the map follows');
      expect(h.map.navigating, isTrue);
      expect(h.map.location, isNot(before));
      await h.dispose();
    }, () => h.client);
  });
}
