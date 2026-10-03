import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart'
    as google;
import 'package:waybi_mobile/domain/map_layer_settings.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/providers/independent_map_renderer.dart';
import 'package:waybi_mobile/theme/waybi_theme.dart';
import 'package:waybi_mobile/widgets/explore_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: WaybiTheme.lightFor('zh'),
      home: const _Preview(),
    ),
  );
}

class _Preview extends StatefulWidget {
  const _Preview();
  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  int _page = 0;
  LocationMarkerStyle _marker = LocationMarkerStyle.cat;
  static const _location = GeoPoint(-36.8506, 174.7677);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Waybi Map')),
    body: _page == 1
        ? const ExplorePage(
            currentLocation: google.LatLng(latitude: -36.8485, longitude: 174.7633),
            language: 'zh',
            mapCompatible: true,
          )
        : Column(
            children: [
              Expanded(
                child: IndependentMapRenderer(
                  initialViewport: const MapViewportState(
                    center: _location,
                    zoom: 16,
                  ),
                  layers: const MapLayerSettings(),
                  locationMarker: _marker,
                  locationEnabled: true,
                  moving: false,
                  language: 'zh',
                  cameras: const [],
                  onCamera: (_) {},
                  roadEvents: const [],
                  onRoadEvent: (_) {},
                  trafficSegments: const [],
                  routePaths: const [],
                  selectedPlace: null,
                  explorePlaces: const [],
                  onExplorePlace: (_) {},
                  location: _location,
                  onReady: (_) {},
                  onViewportChanged: (_) {},
                  onMapPlace: (_) {},
                  onUserPan: () {},
                  onBlankTap: () {},
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SegmentedButton<LocationMarkerStyle>(
                  segments: [
                    const ButtonSegment(
                      value: LocationMarkerStyle.kiwi,
                      label: Text('Waybi'),
                    ),
                    ButtonSegment(
                      value: LocationMarkerStyle.cat,
                      label: const Text('Caity'),
                      icon: Image.asset(
                        'assets/markers/caity.png',
                        width: 40,
                        height: 40,
                      ),
                    ),
                    ButtonSegment(
                      value: LocationMarkerStyle.dog,
                      label: const Text('Sett'),
                      icon: Image.asset(
                        'assets/markers/sett.png',
                        width: 40,
                        height: 40,
                      ),
                    ),
                  ],
                  selected: {_marker},
                  onSelectionChanged: (value) =>
                      setState(() => _marker = value.single),
                ),
              ),
            ],
          ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _page,
      onDestinationSelected: (value) => setState(() => _page = value),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.map_rounded),
          label: 'Waybi Map',
        ),
        NavigationDestination(
          icon: Icon(Icons.explore_rounded),
          label: 'Explore',
        ),
      ],
    ),
  );
}
