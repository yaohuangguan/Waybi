import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/widgets/trips_page.dart';

void main() {
  testWidgets('commute setup opens missing Home on a small screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    TripsResult? result;
    const snapshot = TripsSnapshot(
      quickPlaces: {
        'Work': TripDestination(
          name: 'Work',
          location: GeoPoint(-36.87, 174.77),
        ),
      },
      quickRoutes: {},
      recent: [],
      history: [],
      signedIn: true,
      isPlus: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<TripsResult>(
                  MaterialPageRoute(
                    builder: (_) => MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: const TextScaler.linear(1.3)),
                      child: TripsPage(
                        language: 'zh',
                        loader: () async => snapshot,
                      ),
                    ),
                  ),
                );
              },
              child: const Text('Open trips'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open trips'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('commute-setup-Home')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('设置你的通勤 · 1/2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('commute-setup-Home')));
    await tester.pumpAndSettle();
    expect(result?.configureLabel, 'Home');
  });

  testWidgets('trip search includes older records and combines mode filters', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final snapshot = TripsSnapshot(
      quickPlaces: const {},
      quickRoutes: const {},
      recent: const [],
      history: List.generate(
        12,
        (i) => TripHistoryItem(
          destination: TripDestination(
            name: i == 11 ? 'Old Library' : 'Destination $i',
            address: i == 11 ? 'Queen Street' : '',
            location: const GeoPoint(-36.85, 174.76),
          ),
          mode: i == 11 ? 'walking' : 'drive',
          distanceMeters: 1000,
          durationSeconds: 600,
          createdAt: DateTime.now().subtract(Duration(days: i)),
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TripsPage(language: 'zh', loader: () async => snapshot),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('trip-history-search')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const ValueKey('trip-history-search')),
      'Queen',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Old Library'));
    expect(find.text('1 段行程'), findsOneWidget);
    expect(find.text('Old Library'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('trip-mode-drive')));
    await tester.tap(find.byKey(const ValueKey('trip-mode-drive')));
    await tester.pumpAndSettle();
    expect(find.text('0 段行程'), findsOneWidget);
    expect(find.text('没有找到匹配的行程，试试其他目的地或出行方式。'), findsOneWidget);
    await tester.tap(find.byTooltip('清空搜索'));
    await tester.pumpAndSettle();
    expect(find.text('11 段行程'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
