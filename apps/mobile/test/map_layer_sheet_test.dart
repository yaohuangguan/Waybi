import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_layer_settings.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/widgets/map_layer_sheet.dart';

void main() {
  testWidgets('independent map can enable opt-in live traffic', (tester) async {
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
    expect(find.textContaining('Off by default'), findsOneWidget);

    final trafficTile = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Live traffic'),
    );
    expect(trafficTile.value, isFalse);
    expect(trafficTile.onChanged, isNotNull);

    await tester.tap(find.text('Live traffic'));
    await tester.pumpAndSettle();

    expect(changed?.traffic, isTrue);
  });
}
