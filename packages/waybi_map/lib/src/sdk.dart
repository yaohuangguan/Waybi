import 'layers.dart';
import 'road_intelligence.dart';
import 'safety_cameras.dart';
import 'traffic.dart';

/// Composition root for an embeddable Waybi Map.
///
/// Camera locations are part of the default product surface. Traffic and Road
/// Intelligence remain replaceable layers so consumer and B2B integrations can
/// use the same map abstraction without inheriting Waybi app state.
class WaybiMapStack {
  WaybiMapStack({
    SafetyCameraLayerSource? safetyCameras,
    this.traffic,
    this.roadIntelligence,
    this.layers = const [
      MapLayerDescriptor(id: 'safety-cameras', label: 'Safety cameras'),
      MapLayerDescriptor(
        id: 'traffic',
        label: 'Traffic',
        enabledByDefault: false,
      ),
      MapLayerDescriptor(
        id: 'road-intelligence',
        label: 'Road Intelligence',
        b2bEntitlement: 'road-intelligence',
      ),
    ],
  }) : safetyCameras = safetyCameras ?? WaybiSafetyCameraSource();

  final SafetyCameraLayerSource safetyCameras;
  final TrafficFlowLayerSource? traffic;
  final RoadIntelligenceLayerSource? roadIntelligence;
  final List<MapLayerDescriptor> layers;
}
