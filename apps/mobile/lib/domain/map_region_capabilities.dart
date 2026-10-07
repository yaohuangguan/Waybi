import 'package:waybi_map/waybi_map.dart' show GeoPoint;

/// Runtime map region selection.
///
/// New Zealand is Waybi's first owned map region. Everywhere else deliberately
/// stays on the existing global fallback stack so worldwide usability never
/// regresses while regional ownership expands.
enum WaybiMapRegion { newZealand, global }

class MapRegionCapabilities {
  const MapRegionCapabilities._({
    required this.region,
    required this.vectorSource,
    required this.usesWaybiHostedBasemap,
    required this.prefersRegionalSearch,
    required this.prefersRegionalRouting,
  });

  static const globalVectorSource = 'https://tiles.openfreemap.org/planet';
  static const nzVectorSource =
      'pmtiles://https://maps.waybi.co/regions/nz.pmtiles';

  final WaybiMapRegion region;
  final String vectorSource;
  final bool usesWaybiHostedBasemap;

  /// NZ search is enriched/ranked by Waybi first, but retains the global
  /// fallback while the owned index is being completed.
  final bool prefersRegionalSearch;

  /// Reserved for the regional routing rollout. This remains false until the
  /// NZ routing graph is hosted by Waybi.
  final bool prefersRegionalRouting;

  static const newZealand = MapRegionCapabilities._(
    region: WaybiMapRegion.newZealand,
    vectorSource: nzVectorSource,
    usesWaybiHostedBasemap: true,
    prefersRegionalSearch: true,
    prefersRegionalRouting: false,
  );

  static const global = MapRegionCapabilities._(
    region: WaybiMapRegion.global,
    vectorSource: globalVectorSource,
    usesWaybiHostedBasemap: false,
    prefersRegionalSearch: false,
    prefersRegionalRouting: false,
  );

  static MapRegionCapabilities forPoint(GeoPoint point) =>
      isNewZealand(point) ? newZealand : global;

  /// Keep this aligned with the server-side NZ data boundary. It intentionally
  /// covers the main islands first; outlying islands continue using the global
  /// fallback until Waybi has matching regional archives for them.
  static bool isNewZealand(GeoPoint point) =>
      point.longitude > 166 &&
      point.longitude < 179 &&
      point.latitude > -48 &&
      point.latitude < -34;
}
