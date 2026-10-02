import 'geometry.dart';
import 'layers.dart';

class MapRendererCapabilities {
  const MapRendererCapabilities({
    this.pitch = false,
    this.bearing = false,
    this.liveTraffic = false,
    this.customLayers = false,
    this.featurePicking = false,
  });

  final bool pitch;
  final bool bearing;
  final bool liveTraffic;
  final bool customLayers;
  final bool featurePicking;
}

/// Renderer-neutral controller contract.
///
/// Kiwi Lens currently adapts MapLibre to this interface. A future consumer can
/// provide another renderer without changing search, routing or Road
/// Intelligence layer models.
abstract interface class MapRendererController {
  MapViewportState get viewport;
  MapRendererCapabilities get capabilities;

  Future<void> moveTo(
    MapViewportState viewport, {
    Duration duration = Duration.zero,
  });

  Future<void> fitBounds(
    MapBounds bounds, {
    double padding = 0,
    Duration duration = Duration.zero,
  });
}
