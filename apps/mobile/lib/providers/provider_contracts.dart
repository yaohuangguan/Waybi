import '../domain/map_provider.dart';

abstract interface class MapRenderer {
  MapProvider get provider;
  MapViewportState get viewport;
  Future<void> moveTo(MapViewportState viewport);
}

abstract interface class RouteMapRenderer implements MapRenderer {
  Future<void> fitRoute(List<GeoPoint> points, {required double bottomInset});
}

abstract interface class PlaceFocusMapRenderer implements MapRenderer {
  Future<void> focusPlace(GeoPoint point, {required double bottomInset});

  Future<void> clearContentPadding();
}

abstract interface class SearchProvider {
  Future<List<PlaceCandidate>> search(
    String query, {
    GeoPoint? proximity,
    required String language,
  });
}

/// Immediate local suggestions while a newer prefix is refreshed online.
abstract interface class CachedSearchProvider implements SearchProvider {
  List<PlaceCandidate> cachedSuggestions(
    String query, {
    GeoPoint? proximity,
    required String language,
  });
}

/// A deliberate wider search, separate from everyday nearby suggestions.
abstract interface class ExpandedSearchProvider implements SearchProvider {
  Future<List<PlaceCandidate>> searchFurther(
    String query, {
    GeoPoint? proximity,
    required String language,
  });
}

abstract interface class PlaceProvider {
  Future<PlaceSummary> resolve(
    ProviderReference reference, {
    required String language,
  });
}

abstract interface class ExploreProvider {
  Future<List<PlaceSummary>> nearby(
    String category, {
    required GeoPoint center,
    required String language,
  });
}

abstract interface class RoutingProvider<TPlan> {
  Future<TPlan> route({
    required GeoPoint origin,
    required GeoPoint destination,
    List<GeoPoint> stops,
    required String language,
  });
}

abstract interface class NavigationEngine<TPlan> {
  Future<void> start(TPlan plan);
  Future<void> stop();
}
