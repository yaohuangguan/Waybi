import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/theme/waybi_theme.dart';
import 'package:waybi_mobile/widgets/full_screen_search.dart';
import 'package:waybi_mobile/widgets/independent_navigation_overlay.dart';
import 'package:waybi_mobile/widgets/place_details_content.dart';
import 'package:waybi_mobile/widgets/route_preview_sheet.dart';

import 'support/app_harness.dart';
import 'support/contrast.dart';

/// Home-screen copy follows the app language: chips, dialogs, banners,
/// spoken lines and failure messages never fall back to raw English keys or
/// exception text.
void flow(String name, Future<void> Function(WidgetTester, AppHarness) body) {
  testWidgets(name, (t) async {
    final h = AppHarness(t);
    await http.runWithClient(() async {
      await body(t, h);
      await h.dispose();
    }, () => h.client);
  });
}

PlaceDetailsContent details(WidgetTester t) =>
    t.widget(find.byType(PlaceDetailsContent));
RoutePreviewSheet preview(WidgetTester t) =>
    t.widget(find.byType(RoutePreviewSheet));

String encodePolyline(List<GeoPoint> points) {
  final out = StringBuffer();
  var lastLat = 0, lastLon = 0;
  void value(int delta) {
    var n = delta < 0 ? ~(delta << 1) : delta << 1;
    while (n >= 32) {
      out.writeCharCode((32 | (n & 31)) + 63);
      n >>= 5;
    }
    out.writeCharCode(n + 63);
  }

  for (final p in points) {
    final lat = (p.latitude * 1e6).round(), lon = (p.longitude * 1e6).round();
    value(lat - lastLat);
    value(lon - lastLon);
    lastLat = lat;
    lastLon = lon;
  }
  return out.toString();
}

void main() {
  for (final (language, petrol, query, home) in [
    ('en', 'Petrol', 'petrol station', 'Home'),
    ('zh', '加油站', '加油站', '家'),
  ]) {
    flow('$language shortcut chips are localized and search locally', (
      t,
      h,
    ) async {
      await h.boot(preferences: {'waybi.app.language': language});
      expect(find.widgetWithText(ActionChip, home), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'Gas'), findsNothing);
      // The last chip sits beyond the screen edge of the scrolling row.
      await t.dragUntilVisible(
        find.text(petrol),
        find.byWidgetPredicate(
          (w) => w is ListView && w.scrollDirection == Axis.horizontal,
        ),
        const Offset(-120, 0),
      );
      await h.act(
        t
            .widget<ActionChip>(find.widgetWithText(ActionChip, petrol))
            .onPressed!,
      );
      expect(
        t.widget<FullScreenSearch>(find.byType(FullScreenSearch)).initialQuery,
        query,
      );
      Navigator.of(t.element(find.byType(FullScreenSearch))).pop();
      await h.frames();
    });
  }

  flow('the Chinese review dialog is translated and readable in dark mode', (
    t,
    h,
  ) async {
    await h.boot(
      signedIn: true,
      preferences: {'waybi.app.language': 'zh'},
      theme: WaybiTheme.darkFor('zh'),
    );
    await h.select();
    await h.act(details(t).onReview);
    expect(find.text('我的评价 · Test destination'), findsOneWidget);
    expect(find.text('评分'), findsOneWidget);
    expect(find.text('私人备注'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    final hint = t.widget<Text>(find.text('仅保存在 Waybi，不会发布到 Google。'));
    final dialog = t.widget<AlertDialog>(find.byType(AlertDialog));
    final surface =
        dialog.backgroundColor ??
        Theme.of(t.element(find.byType(AlertDialog)))
            .dialogTheme
            .backgroundColor ??
        Theme.of(t.element(find.byType(AlertDialog)))
            .colorScheme
            .surfaceContainerHigh;
    expect(contrastRatio(hint.style!.color!, surface), greaterThan(4.5));
    h.endpointFailures['/api/profile/reviews'] = 503;
    await h.tapText('保存');
    expect(find.textContaining('无法保存评价'), findsOneWidget);
    expect(find.textContaining('Temporarily unavailable'), findsNothing);
  });

  flow('Chinese road-report failures never show the raw exception', (
    t,
    h,
  ) async {
    h.reportStatus = 503;
    await h.boot(preferences: {'waybi.app.language': 'zh'});
    await t.tap(find.byTooltip('上报道路情况'));
    await h.frames();
    await h.tapText('道路封闭');
    expect(find.textContaining('道路上报失败'), findsOneWidget);
    expect(find.textContaining('Bad state'), findsNothing);
    expect(find.textContaining('Temporarily unavailable'), findsNothing);
  });

  flow('the Chinese shared ETA snapshot is written in Chinese', (t, h) async {
    String copied = '';
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await h.boot(preferences: {'waybi.app.language': 'zh'});
    await h.select(name: '港口目的地');
    await h.act(details(t).onNavigate);
    await h.act(preview(t).onStart);
    await h.until(() => h.map.navigating, reason: '导航应开始');
    final nav = t.widget<IndependentNavigationOverlay>(
      find.byType(IndependentNavigationOverlay),
    );
    await h.act(nav.onShare);
    expect(copied, contains('前往 港口目的地'));
    expect(copied, contains('剩余：1.1 公里'));
    expect(copied, isNot(contains('Remaining')));
    expect(find.text('到达时间快照已复制'), findsOneWidget);
  });

  flow('the transit trip announcement follows the voice language', (
    t,
    h,
  ) async {
    h.transitResponse = {
      'itineraries': [
        {
          'duration': 900,
          'transfers': 0,
          'legs': [
            {
              'mode': 'BUS',
              'routeShortName': '70',
              'headsign': 'City',
              'from': {'name': 'A'},
              'to': {'name': 'B'},
              'legGeometry': {
                'precision': 6,
                'points': encodePolyline(const [
                  GeoPoint(-37.2, 174.9),
                  GeoPoint(-37.2, 174.91),
                ]),
              },
            },
          ],
        },
      ],
    };
    await h.boot(
      preferences: {'waybi.app.language': 'zh', 'waybi.voice.enabled': true},
    );
    await h.select();
    await h.act(details(t).onNavigate);
    await h.act(() => preview(t).onModeChanged(WaybiTravelMode.transit));
    await h.until(
      () => preview(t).selectedMode == WaybiTravelMode.transit,
      reason: 'transit becomes selected',
    );
    await h.act(preview(t).onStart);
    final spoken = h.calls
        .where((c) => c.method == 'speak')
        .map((c) => c.arguments.toString())
        .join(' | ');
    expect(spoken, contains('公交行程已开始'));
    expect(spoken, isNot(contains('Transit trip started')));
  });
}
