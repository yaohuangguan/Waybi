import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart'
    show LatLng;
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/drive/drive_engine.dart';
import 'package:waybi_mobile/theme/waybi_theme.dart';
import 'package:waybi_mobile/widgets/explore_search.dart';
import 'package:waybi_mobile/widgets/navigation_overlay.dart';
import 'package:waybi_mobile/widgets/transit_trip_overlay.dart';

import 'support/contrast.dart';
import 'support/surface_contrast.dart';

RouteOption transitRoute() => RouteOption.fromJson({
  'id': 'bus',
  'mode': 'transit',
  'durationSeconds': 1500,
  'distanceMeters': 8200,
  'transit': [
    {
      'lineName': 'NX1',
      'headsign': 'Britomart',
      'departureStop': 'Albany',
      'arrivalStop': 'Britomart',
    },
  ],
});

Widget themed(bool dark, Widget child) => MaterialApp(
  theme: WaybiTheme.light,
  darkTheme: WaybiTheme.dark,
  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
  home: Scaffold(body: child),
);

void main() {
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets('transit trip panel is readable in $mode mode', (t) async {
      await t.pumpWidget(
        themed(
          dark,
          TransitTripOverlay(
            destinationTitle: 'Britomart',
            route: transitRoute(),
            gpsAccuracy: 9,
            onEnd: () {},
            onRecenter: () {},
          ),
        ),
      );
      await t.pumpAndSettle();
      expectReadable(t, find.text('25 min'), reason: mode);
      expectReadable(t, find.text('NX1 → Britomart'), reason: mode);
      expectReadable(t, find.text('Albany → Britomart'), reason: mode);
      expectReadable(t, find.text('Britomart'), reason: mode);
    });

    testWidgets('add-stop search results are readable in $mode mode', (
      t,
    ) async {
      await t.pumpWidget(
        themed(
          dark,
          ExploreSearch(
            currentLocation: null,
            destinationOnly: true,
            onSelected: (_) {},
            recent: const [
              DestinationSuggestion(
                label: 'Sky Tower, Auckland',
                name: 'Sky Tower',
                address: 'Victoria Street West, Auckland',
                location: LatLng(latitude: -36.8485, longitude: 174.7622),
              ),
            ],
          ),
        ),
      );
      await t.pumpAndSettle();
      expectReadable(t, find.text('Sky Tower'), reason: mode);
      final card = t.widget<Material>(
        find
            .ancestor(
              of: find.text('Sky Tower'),
              matching: find.byType(Material),
            )
            .first,
      );
      final scheme = (dark ? WaybiTheme.dark : WaybiTheme.light).colorScheme;
      expect(card.color, scheme.surface);
      final field = t.widget<TextField>(find.byType(TextField));
      expect(field.decoration!.filled, isFalse);
    });

    testWidgets('navigation control rail follows the $mode theme', (t) async {
      final engine = DriveEngine();
      addTearDown(engine.dispose);
      await t.pumpWidget(
        themed(
          dark,
          NavigationOverlay(
            engine: engine,
            destinationTitle: 'Auckland Museum',
            gpsAccuracy: 8,
            voiceEnabled: true,
            lanesEnabled: true,
            onEnd: () {},
            onRecenter: () {},
            onOverview: () {},
            northUp: false,
            onCompassToggle: () {},
            onReport: () {},
            onSearchAlongRoute: () {},
            onDirections: () {},
            onShare: () {},
            onSettings: () {},
            onLayers: () {},
            onVoiceToggle: () {},
            onLanesToggle: () {},
          ),
        ),
      );
      await t.pumpAndSettle();
      final layers = find.byIcon(Icons.layers_rounded);
      final icon = t.widget<Icon>(layers);
      final rail = surfaceBehind(t, layers);
      expect(contrastRatio(icon.color!, rail), greaterThanOrEqualTo(4.5));
      if (dark) {
        expect(rail.computeLuminance(), lessThan(.1));
      } else {
        expect(rail.computeLuminance(), greaterThan(.8));
      }
      final report = find.byIcon(Icons.add_alert_rounded);
      expect(
        contrastRatio(t.widget<Icon>(report).color!, surfaceBehind(t, report)),
        greaterThanOrEqualTo(4.5),
      );
    });
  }
}
