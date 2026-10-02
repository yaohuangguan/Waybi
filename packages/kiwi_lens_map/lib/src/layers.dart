import 'geometry.dart';

/// Geographical viewport used by optional overlay providers.
///
/// The map package deliberately owns this primitive so traffic, road
/// intelligence and future B2B layers do not depend on Flutter, MapLibre or a
/// particular HTTP client.
class MapBounds {
  const MapBounds({required this.southWest, required this.northEast});

  final GeoPoint southWest;
  final GeoPoint northEast;

  bool get isValid =>
      southWest.isValid &&
      northEast.isValid &&
      southWest.latitude <= northEast.latitude;

  bool contains(GeoPoint point) =>
      point.latitude >= southWest.latitude &&
      point.latitude <= northEast.latitude &&
      point.longitude >= southWest.longitude &&
      point.longitude <= northEast.longitude;
}

/// Provider-neutral async layer contract.
///
/// Authentication, billing, caching and transport stay in the implementing
/// adapter. The renderer only consumes the returned snapshot.
abstract interface class MapLayerSource<TSnapshot> {
  Future<TSnapshot> load(MapBounds bounds);
}

class MapLayerStatus {
  const MapLayerStatus({this.state = 'unknown', this.updatedAt, this.source});

  final String state;
  final DateTime? updatedAt;
  final String? source;

  bool get isLive => state == 'live';
  bool get isStale => state == 'stale';
}

/// Stable identity for a renderer-consumable layer.
///
/// Consumers can toggle a layer without knowing which provider supplies it.
class MapLayerDescriptor {
  const MapLayerDescriptor({
    required this.id,
    required this.label,
    this.enabledByDefault = true,
    this.b2bEntitlement,
  });

  final String id;
  final String label;
  final bool enabledByDefault;

  /// Optional entitlement/SKU name. Null means the layer is not gated by the
  /// map core itself.
  final String? b2bEntitlement;
}
