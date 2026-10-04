// Read-only native preview. Run as a separate debug entrypoint; never submits reports.
import 'package:flutter/material.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/map_layer_settings.dart';
import 'package:waybi_mobile/domain/road_event.dart';
import 'package:waybi_mobile/providers/independent_map_renderer.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            IndependentMapRenderer(
              initialViewport: const MapViewportState(
                center: GeoPoint(-36.8485, 174.7633),
                zoom: 16,
              ),
              layers: const MapLayerSettings(),
              locationMarker: LocationMarkerStyle.kiwi,
              locationEnabled: false,
              moving: false,
              language: 'en',
              cameras: const [],
              onCamera: (_) {},
              roadEvents: [
                for (var i = 0; i < 6; i++)
                  RoadEvent(
                    id: 'preview-$i',
                    type: const [
                      RoadEventType.incident,
                      RoadEventType.roadworks,
                      RoadEventType.roadClosure,
                      RoadEventType.congestion,
                      RoadEventType.flooding,
                      RoadEventType.slip,
                    ][i],
                    location: GeoPoint(
                      -36.8474 + (i ~/ 2) * -.0011,
                      174.7624 + (i % 2) * .0018,
                    ),
                    source: const RoadEventSource(
                      provider: 'Test fixture',
                      country: 'GLOBAL',
                      sourceId: 'preview',
                    ),
                  ),
              ],
              onRoadEvent: (_) {},
              trafficSegments: const [],
              routePaths: const [],
              selectedPlace: null,
              explorePlaces: const [],
              onExplorePlace: (_) {},
              onReady: (_) {},
              onViewportChanged: (_) {},
              onMapPlace: (_) {},
              onUserPan: () {},
              onBlankTap: () {},
            ),
            const SafeArea(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Text(
                      'Waybi · Report symbols\nCrash · Roadworks · Closure · Traffic · Flood · Debris',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
