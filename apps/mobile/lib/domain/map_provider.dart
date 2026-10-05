import 'package:waybi_map/waybi_map.dart';

export 'package:waybi_map/waybi_map.dart'
    show
        GeoPoint,
        LocationMarkerStyle,
        MapAppearance,
        MapRoutePath,
        MapViewportState,
        PlaceCandidate,
        PlaceKind,
        PlaceSummary,
        ProviderReference,
        placeSecondaryAddress;

enum MapProvider { google, independent }

enum SelectionSource {
  search,
  map,
  explore,
  saved,
  recent,
  home,
  work,
  frequent,
  longPress,
}

class SelectedPlace {
  const SelectedPlace(this.place, this.source, {required this.originMap});

  final PlaceSummary place;
  final SelectionSource source;
  final MapProvider originMap;
}

enum JourneyPhase { idle, searching, placeSelected, routePreview, navigating }

/// Provider choices are explicit. Google Places/Routes content is never
/// displayed on Independent merely because the renderer changed.
class ProviderPolicy {
  const ProviderPolicy(this.map);

  final MapProvider map;

  ProviderCapabilities get capabilities => switch (map) {
    MapProvider.google => const ProviderCapabilities(
      trafficAwareRouting: true,
      transitRouting: true,
      nativeTurnGuidance: true,
      persistProviderPlaces: true,
    ),
    MapProvider.independent => const ProviderCapabilities(
      trafficAwareRouting: false,
      transitRouting: true,
      nativeTurnGuidance: false,
      persistProviderPlaces: true,
    ),
  };

  String get searchProvider => switch (map) {
    MapProvider.google => 'geoapify',
    MapProvider.independent => 'osm',
  };
  String get placeProvider => switch (map) {
    MapProvider.google => 'google',
    MapProvider.independent => 'osm',
  };
  String get routingProvider => switch (map) {
    MapProvider.google => 'google',
    MapProvider.independent => 'independent',
  };
  String get navigationEngine => switch (map) {
    MapProvider.google => 'google',
    MapProvider.independent => 'independent',
  };

  bool canDisplay(ProviderReference? reference) =>
      reference == null ||
      reference.provider == placeProvider ||
      reference.provider == 'geoapify' ||
      reference.provider == 'here' ||
      reference.provider == 'osm' ||
      reference.provider == 'at' ||
      reference.provider.startsWith('regional:');
}

class ProviderCapabilities {
  const ProviderCapabilities({
    required this.trafficAwareRouting,
    required this.transitRouting,
    required this.nativeTurnGuidance,
    required this.persistProviderPlaces,
  });

  final bool trafficAwareRouting;
  final bool transitRouting;
  final bool nativeTurnGuidance;
  final bool persistProviderPlaces;
}
