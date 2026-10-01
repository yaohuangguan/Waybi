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
    expect(find.text('180 米'), findsOneWidget);
    expect(find.text('2.4 公里'), findsNWidgets(2));
    expect(find.byTooltip('回到当前位置'), findsOneWidget);
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
    expect(find.text('Turn left onto Queen Street'), findsOneWidget);
    expect(find.byTooltip('Recenter'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
