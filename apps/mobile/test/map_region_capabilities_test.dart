import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_region_capabilities.dart';
import 'package:waybi_mobile/providers/independent_map_style.dart';
import 'package:waybi_map/waybi_map.dart';

void main() {
  test('New Zealand uses Waybi-hosted basemap', () {
    const auckland = GeoPoint(-36.8485, 174.7633);
    final capabilities = MapRegionCapabilities.forPoint(auckland);

    expect(capabilities.region, WaybiMapRegion.newZealand);
    expect(capabilities.usesWaybiHostedBasemap, isTrue);
    expect(capabilities.vectorSource, MapRegionCapabilities.nzVectorSource);
    expect(capabilities.prefersRegionalSearch, isTrue);
    expect(
      WaybiMapSourceConfig.vectorSourceFor(auckland),
      MapRegionCapabilities.nzVectorSource,
    );
  });

  test('global locations preserve the existing fallback stack', () {
    const sydney = GeoPoint(-33.8688, 151.2093);
    const london = GeoPoint(51.5074, -0.1278);

    for (final point in [sydney, london]) {
      final capabilities = MapRegionCapabilities.forPoint(point);
      expect(capabilities.region, WaybiMapRegion.global);
      expect(capabilities.usesWaybiHostedBasemap, isFalse);
      expect(
        capabilities.vectorSource,
        MapRegionCapabilities.globalVectorSource,
      );
      expect(capabilities.prefersRegionalSearch, isFalse);
      expect(
        WaybiMapSourceConfig.vectorSourceFor(point),
        MapRegionCapabilities.globalVectorSource,
      );
    }
  });
}
