import 'layers.dart';
import 'road_intelligence.dart';
import 'traffic.dart';

/// Composition root for an embeddable Kiwi map.
///
/// The base map does not require Kiwi Lens services. Customers may attach
/// their own traffic source, the Kiwi Lens Road Intelligence API, both, or
/// neither.
class KiwiMapStack {
  const KiwiMapStack({
    this.traffic,
    this.roadIntelligence,
    this.layers = const [
      MapLayerDescriptor(id: 'traffic', label: 'Traffic'),
      MapLayerDescriptor(
        id: 'road-intelligence',
        label: 'Road Intelligence',
        b2bEntitlement: 'road-intelligence',
      ),
    ],
  });

  final TrafficFlowLayerSource? traffic;
  final RoadIntelligenceLayerSource? roadIntelligence;
  final List<MapLayerDescriptor> layers;
}
