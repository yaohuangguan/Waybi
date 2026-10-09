import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_layer_settings.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/widgets/map_layer_sheet.dart';

void main() {
  testWidgets('independent map can disable live traffic', (tester) async {
    MapLayerSettings? changed;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapLayerSheet(
            settings: const MapLayerSettings(),
            mapProvider: MapProvider.independent,
            language: 'en',
            trafficStatus: 'live',
            trafficSegmentCount: 78,
            onChanged: (value) => changed = value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Live traffic'), findsOneWidget);
    expect(find.textContaining('Traffic colors'), findsOneWidget);

    final trafficTile = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Live traffic'),
    );
    expect(trafficTile.value, isTrue);
    expect(trafficTile.onChanged, isNotNull);

    await tester.tap(find.text('Live traffic'));
    await tester.pumpAndSettle();

    expect(changed?.traffic, isFalse);
  });

  testWidgets(
    'Auckland transit-lane layer defaults on and stays independent of bus cameras',
    (tester) async {
      MapLayerSettings? changed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapLayerSheet(
              settings: const MapLayerSettings(),
              mapProvider: MapProvider.independent,
              language: 'en',
              transitLaneCount: 361,
              reviewCorridorCount: 54,
              onChanged: (value) => changed = value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final toggle = find.widgetWithText(SwitchListTile, 'Bus & transit lanes');
      await tester.ensureVisible(toggle);
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      expect(find.textContaining('54 Christchurch/Wellington'), findsOneWidget);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(changed?.transitLanes, isFalse);
      expect(changed?.busLane, isTrue);
      expect(changed?.alertBusLane, isTrue);
    },
  );
}
