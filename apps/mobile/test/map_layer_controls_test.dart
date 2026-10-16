import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_layer_settings.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/widgets/map_layer_sheet.dart';

Future<void> reveal(WidgetTester t, Finder f) async {
  await t.scrollUntilVisible(
    f,
    200,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 40,
  );
  await t.ensureVisible(f);
  await t.pumpAndSettle();
}

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'camera visibility and each driving reminder remain independent in ${dark ? 'dark' : 'light'} mode',
      (t) async {
        t.view.physicalSize = const Size(390, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(() {
          t.view.resetPhysicalSize();
          t.view.resetDevicePixelRatio();
        });
        final changes = <MapLayerSettings>[];
        await t.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            home: Scaffold(
              body: MapLayerSheet(
                settings: const MapLayerSettings(),
                mapProvider: MapProvider.independent,
                language: 'en',
                onChanged: changes.add,
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        for (final title in [
          'Spot speed',
          'Average speed',
          'Red light',
          'Red light + speed',
          'Bus / transit lane',
          'Other enforcement cameras',
        ]) {
          final label = find.text(title);
          await reveal(t, label);
          final row = find
              .ancestor(of: label, matching: find.byType(AnimatedContainer))
              .first;
          final visible = find.descendant(
            of: row,
            matching: find.byType(Switch),
          );
          final before = t.widget<Switch>(visible).value;
          await t.tap(visible);
          await t.pumpAndSettle();
          expect(t.widget<Switch>(visible).value, !before);
          final alert = find.descendant(
            of: row,
            matching: find.byTooltip('Alert while driving'),
          );
          await t.tap(alert);
          await t.pumpAndSettle();
        }
        final settings = changes.last;
        expect([
          settings.spotSpeed,
          settings.averageSpeed,
          settings.redLight,
          settings.dualRedLightSpeed,
          settings.busLane,
          settings.other,
        ], everyElement(false));
        expect([
          settings.alertSpotSpeed,
          settings.alertAverageSpeed,
          settings.alertRedLight,
          settings.alertDualRedLightSpeed,
          settings.alertBusLane,
        ], everyElement(false));
        expect(settings.alertOther, true);
        expect(changes, hasLength(12));
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final status in ['stale', 'unavailable', 'not_loaded']) {
    testWidgets(
      'traffic status $status describes the available data truthfully',
      (t) async {
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MapLayerSheet(
                settings: const MapLayerSettings(),
                mapProvider: MapProvider.independent,
                language: 'zh',
                trafficStatus: status,
                trafficSegmentCount: status == 'stale' ? 12 : 0,
                onChanged: (_) {},
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        final expected = status == 'stale'
            ? '12 条缓存路况 · 数据源过期'
            : status == 'unavailable'
            ? '实时交通暂时不可用'
            : '正在加载实时交通…';
        expect(find.text(expected), findsOneWidget);
        await t.tap(find.text('实时交通'));
        await t.pumpAndSettle();
        expect(find.text('开启后显示交通颜色'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }
}
