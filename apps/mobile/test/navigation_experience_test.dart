import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/navigation_preview.dart';

void main() {
  testWidgets('Chinese lanes and journey summary fit a compact phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const NavigationPreview());
    await tester.pumpAndSettle();
    expect(find.text('推荐车道'), findsOneWidget);
    expect(find.text('摄像头 · 300 米'), findsOneWidget);
    final header = tester.getRect(
      find.byKey(const Key('navigationGuidanceHeader')),
    );
    final camera = tester.getRect(
      find.byKey(const Key('navigationCameraAlert')),
    );
    final deck = tester.getRect(
      find.byKey(const Key('navigationSheetSurface')),
    );
    expect(camera.top, greaterThan(header.bottom));
    expect(camera.bottom, lessThan(667 / 2));
    expect(camera.bottom, lessThan(deck.top));
    // Expanding the trip deck must leave the upcoming camera above it.
    await tester.tap(find.byKey(const Key('navigationSheetHandle')));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const Key('navigationCameraAlert'))).bottom,
      lessThan(
        tester.getRect(find.byKey(const Key('navigationSheetSurface'))).top,
      ),
    );
    await tester.tap(find.byKey(const Key('navigationSheetHandle')));
    await tester.pumpAndSettle();
    expect(find.text('180 米'), findsOneWidget);
    expect(find.text('2.4 公里'), findsNWidgets(2));
    expect(find.byTooltip('路线全览'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('结束'));
    await tester.pumpAndSettle();
    expect(find.text('到啦！'), findsOneWidget);
    expect(find.text('8.2 公里'), findsOneWidget);
    expect(find.text('经过摄像头'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('继续探索'));
    await tester.tap(find.text('继续探索'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('EN'));
    await tester.pumpAndSettle();
    expect(find.text('USE LANE'), findsOneWidget);
    expect(find.text('Camera · 300 m'), findsOneWidget);
    await tester.tap(find.byTooltip('Camera alert'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('navigationCameraAlert')), findsNothing);
    expect(tester.takeException(), isNull);
    expect(find.text('Turn left onto Queen Street'), findsOneWidget);
    expect(find.byTooltip('Route overview'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Chinese camera and lanes remain readable at larger text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await tester.pumpWidget(const NavigationPreview());
    await tester.pumpAndSettle();
    expect(find.text('摄像头 · 300 米'), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const Key('navigationCameraAlert'))).bottom,
      lessThan(
        tester.getRect(find.byKey(const Key('navigationSheetSurface'))).top,
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
