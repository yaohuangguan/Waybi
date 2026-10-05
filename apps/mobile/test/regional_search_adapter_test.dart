import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/providers/regional_place_sources.dart';
import 'package:waybi_mobile/providers/regional_query_aliases.dart';

void main() {
  test(
    'regional query aliases enrich one market without changing global queries',
    () {
      expect(
        resolveRegionalQueryAlias('福地', const GeoPoint(-36.85, 174.76)),
        'Foodie Asian Supermarket',
      );
      expect(
        resolveRegionalQueryAlias('福地', const GeoPoint(35.681, 139.767)),
        '福地',
      );
    },
  );

  test('regional provider policy is namespaced instead of city-hardcoded', () {
    const independent = ProviderPolicy(MapProvider.independent);
    expect(
      independent.canDisplay(
        const ProviderReference('regional:sample-official', 'address:1'),
      ),
      isTrue,
    );
  });

  test('regional source credit registry is provider-driven', () {
    final credits = regionalCreditsForProviders([
      'regional:auckland-council',
      'regional:future-city-provider',
    ]);
    expect(credits, hasLength(1));
    expect(credits.single.provider, 'regional:auckland-council');
  });
}
