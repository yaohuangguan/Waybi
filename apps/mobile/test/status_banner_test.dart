import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/widgets/status_banner.dart';

Widget page(Widget banner) => MaterialApp(home: Scaffold(body: banner));

void main() {
  testWidgets('location recovery remains available until the user acts', (
    tester,
  ) async {
    var dismissed = 0, retries = 0;
    await tester.pumpWidget(
      page(
        WaybiStatusBanner(
          message: 'Waiting for location',
          actionLabel: 'Retry location',
          onAction: () => retries++,
          onDismiss: () => dismissed++,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 10));
    expect(dismissed, 0);
    await tester.tap(find.text('Retry location'));
    expect(retries, 1);
    await tester.tap(find.byTooltip('Dismiss'));
    expect(dismissed, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ordinary notices still dismiss after four seconds', (
    tester,
  ) async {
    var dismissed = 0;
    await tester.pumpWidget(
      page(
        WaybiStatusBanner(message: 'Route saved', onDismiss: () => dismissed++),
      ),
    );
    await tester.pump(const Duration(seconds: 4));
    expect(dismissed, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('adding a recovery action cancels an existing dismiss timer', (
    tester,
  ) async {
    var dismissed = 0;
    await tester.pumpWidget(
      page(WaybiStatusBanner(message: 'Waiting', onDismiss: () => dismissed++)),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(
      page(
        WaybiStatusBanner(
          message: 'Waiting',
          onAction: () {},
          onDismiss: () => dismissed++,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 6));
    expect(dismissed, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Chinese recovery fits a compact phone with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.7)),
          child: child!,
        ),
        home: Scaffold(
          body: WaybiStatusBanner(
            message: 'Waybi 的定位权限已关闭，请在系统设置中开启。',
            actionLabel: '打开设置',
            dismissLabel: '关闭',
            onAction: () {},
            onDismiss: () {},
          ),
        ),
      ),
    );
    expect(find.text('打开设置').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
