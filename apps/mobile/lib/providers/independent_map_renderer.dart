import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import '../domain/map_layer_settings.dart';
import '../domain/map_provider.dart';
import '../domain/safety_camera.dart';
import '../domain/traffic_flow.dart';
import '../domain/road_event.dart';
import '../domain/route_traffic_match.dart';
import 'location_marker_art.dart';
import 'road_event_marker_art.dart';
import 'independent_map_style.dart';
import 'provider_contracts.dart';

/// Native GPU projection for tiles, POIs, route, puck and its light together.
class IndependentMapRenderer extends StatefulWidget {
  const IndependentMapRenderer({
    super.key,
    required this.initialViewport,
    required this.layers,
    required this.locationMarker,
    required this.locationEnabled,
    required this.moving,
    required this.language,
    required this.cameras,
    required this.onCamera,
    required this.roadEvents,
    required this.onRoadEvent,
    required this.trafficSegments,
    required this.routePaths,
    required this.selectedPlace,
    required this.explorePlaces,
    required this.onExplorePlace,
    required this.onReady,
    required this.onViewportChanged,
    required this.onMapPlace,
    required this.onUserPan,
    required this.onBlankTap,
    this.location,
    this.heading = 0,
    this.contentPadding = EdgeInsets.zero,
    this.following = false,
    this.navigating = false,
    this.trafficTileOverlay,
    this.trafficFresh = true,
    this.styleLoader = IndependentMapStyle.load,
  });
  final MapViewportState initialViewport;
  final MapLayerSettings layers;
  final LocationMarkerStyle locationMarker;
  final bool locationEnabled, moving;
  final String language;
  final List<SafetyCamera> cameras;
  final ValueChanged<SafetyCamera> onCamera;
  final List<RoadEvent> roadEvents;
  final ValueChanged<RoadEvent> onRoadEvent;
  final List<TrafficFlowSegment> trafficSegments;
  final List<MapRoutePath> routePaths;
  final PlaceSummary? selectedPlace;
  final List<PlaceSummary> explorePlaces;
  final ValueChanged<PlaceSummary> onExplorePlace;
  final ValueChanged<MapRenderer> onReady;
  final ValueChanged<MapViewportState> onViewportChanged;
  final ValueChanged<PlaceSummary> onMapPlace;
  final VoidCallback onUserPan, onBlankTap;
  final GeoPoint? location;
  final double heading;
  final EdgeInsets contentPadding;
  final bool following;
  final bool navigating;
  final TrafficTileOverlay? trafficTileOverlay;
  final bool trafficFresh;
  final Future<String> Function({required bool dark, required String language})
  styleLoader;
  @override
  State<IndependentMapRenderer> createState() => _IndependentMapRendererState();
}

class _IndependentMapRendererState extends State<IndependentMapRenderer>
    implements RouteMapRenderer, PlaceFocusMapRenderer {
  ml.MapLibreMapController? _controller;
  late MapViewportState _viewport = widget.initialViewport;
  EdgeInsets? _placePadding;
  EdgeInsets? _appliedPadding;
  Future<String>? _style;
  bool? _dark;
  bool _ready = false, _syncing = false, _dirty = false;
  int _generation = 0;
  String? _trafficTileSignature;
  final _signatures = <String, int>{};
  final _pointers = <int, Offset>{};
  bool _gestureReported = false;
  EdgeInsets get _padding => _placePadding ?? widget.contentPadding;
  @override
  MapProvider get provider => MapProvider.independent;
  @override
  MapViewportState get viewport => _viewport;
  ml.LatLng _point(GeoPoint p) => ml.LatLng(p.latitude, p.longitude);

  @override
  void dispose() {
    super.dispose();
  }

  void _loadStyle() {
    _dark = Theme.of(context).brightness == Brightness.dark;
    _ready = false;
    _generation++;
    _trafficTileSignature = null;
    _signatures.clear();
    _appliedPadding = null;
    _style = widget.styleLoader(dark: _dark!, language: widget.language);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_style == null ||
        _dark != (Theme.of(context).brightness == Brightness.dark)) {
      _loadStyle();
    }
  }

  @override
  void didUpdateWidget(covariant IndependentMapRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.language != widget.language) _loadStyle();
    if (widget.navigating && !oldWidget.navigating) _placePadding = null;
    _queueSync();
    if (oldWidget.contentPadding != widget.contentPadding) {
      unawaited(_updatePadding());
    }
  }

  Future<void> _updatePadding() async {
    if (!_ready) return;
    await _applyPadding();
    if (mounted && widget.following && widget.location != null) {
      await moveTo(_viewport.copyWith(center: widget.location));
    }
  }

  Future<void> _applyPadding() async {
    if (_appliedPadding == _padding) return;
    await _controller!.updateContentInsets(_padding);
    _appliedPadding = _padding;
  }

  @override
  Future<void> moveTo(MapViewportState viewport) async {
    if (!_ready) return;
    _viewport = viewport;
    await _applyPadding();
    await _controller!.easeCamera(
      ml.CameraUpdate.newCameraPosition(
        ml.CameraPosition(
          target: _point(viewport.center),
          zoom: viewport.zoom,
          bearing: viewport.bearing,
          tilt: viewport.pitch,
        ),
      ),
      duration: Duration(milliseconds: widget.navigating ? 850 : 650),
      interpolation: ml.CameraAnimationInterpolation.linear,
    );
  }

  @override
  Future<void> focusPlace(GeoPoint point, {required double bottomInset}) async {
    _placePadding = EdgeInsets.fromLTRB(18, 104, 18, bottomInset);
    setState(() {});
    await _updatePadding();
    await moveTo(
      _viewport.copyWith(center: point, zoom: math.max(15, _viewport.zoom)),
    );
  }

  @override
  Future<void> clearContentPadding() async {
    _placePadding = null;
    setState(() {});
    await _updatePadding();
  }

  @override
  Future<void> fitRoute(
    List<GeoPoint> points, {
    required double bottomInset,
  }) async {
    if (!_ready || points.length < 2) return;
    final south = points.map((p) => p.latitude).reduce(math.min);
    final north = points.map((p) => p.latitude).reduce(math.max);
    final west = points.map((p) => p.longitude).reduce(math.min);
    final east = points.map((p) => p.longitude).reduce(math.max);
    // Bounds padding is explicit, so avoid counting the deck twice.
    await _controller!.updateContentInsets(EdgeInsets.zero);
    _appliedPadding = EdgeInsets.zero;
    await _controller!.easeCamera(
      ml.CameraUpdate.newLatLngBounds(
        ml.LatLngBounds(
          southwest: ml.LatLng(south, west),
          northeast: ml.LatLng(north, east),
        ),
        left: 36,
        top: math.max(150, widget.contentPadding.top),
        right: 36,
        bottom: bottomInset,
      ),
      duration: const Duration(milliseconds: 700),
      interpolation: ml.CameraAnimationInterpolation.linear,
    );
  }

  void _cameraMoved(ml.CameraPosition camera) {
    _viewport = MapViewportState(
      center: GeoPoint(camera.target.latitude, camera.target.longitude),
      zoom: camera.zoom,
      bearing: camera.bearing,
      pitch: camera.tilt,
    );
    // No setState here: native map movement must not rebuild the Flutter HUD.
    widget.onViewportChanged(_viewport);
  }

  void _pan() {
    if (_gestureReported) return;
    _gestureReported = true;
    widget.onUserPan();
  }

  Future<void> _styleLoaded() async {
    final generation = _generation;
    final c = _controller!;
    final imageScale = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
        ? View.of(context).devicePixelRatio
        : 1.0;
    try {
      for (final style in LocationMarkerStyle.values) {
        await c.addImage(
          'waybi-puck-${style.name}',
          await LocationMarkerArt.practicePng(style),
        );
      }
      await c.addImage('waybi-light', await LocationMarkerArt.glowPng());
      for (final type in RoadEventType.values) {
        await c.addImage(
          'waybi-event-${type.name}',
          await RoadEventMarkerArt.png(type),
        );
      }
      for (final kind in CameraKind.values) {
        await c.addImage(
          'waybi-camera-${kind.name}',
          await LocationMarkerArt.cameraPng(kind),
        );
      }
      await c.addImage(
        'waybi-finish-flag',
        await LocationMarkerArt.finishFlagPng(),
      );
      for (final source in [
        'waybi-traffic',
        'waybi-route-traffic',
        'waybi-route',
        'waybi-pins',
        'waybi-driver',
      ]) {
        await c.addGeoJsonSource(source, _collection(const []));
      }
      for (final active in [false, true]) {
        final prefix = active ? 'waybi-route' : 'waybi-alternative';
        await c.addLineLayer(
          'waybi-route',
          '$prefix-edge',
          ml.LineLayerProperties(
            lineColor: active ? '#486B29' : '#ffffff',
            lineWidth: active ? 10 : 7,
            lineOpacity: active ? 1 : .8,
            lineCap: 'round',
            lineJoin: 'round',
          ),
          filter: [
            '==',
            ['get', 'active'],
            active,
          ],
          belowLayerId: 'waybi-poi-dot',
          enableInteraction: false,
        );
        await c.addLineLayer(
          'waybi-route',
          '$prefix-line',
          ml.LineLayerProperties(
            lineColor: active ? '#A8D86A' : '#8c959d',
            lineWidth: active ? 7 : 4,
            lineOpacity: active ? 1 : .75,
            lineCap: 'round',
            lineJoin: 'round',
          ),
          filter: [
            '==',
            ['get', 'active'],
            active,
          ],
          belowLayerId: 'waybi-poi-dot',
          enableInteraction: false,
        );
      }
      await c.addLineLayer(
        'waybi-traffic',
        'waybi-traffic-casing',
        const ml.LineLayerProperties(
          lineColor: '#ffffff',
          lineWidth: 4.2,
          lineOpacity: .56,
          lineCap: 'round',
          lineJoin: 'round',
        ),
        belowLayerId: 'waybi-alternative-edge',
        enableInteraction: false,
      );
      await c.addLineLayer(
        'waybi-traffic',
        'waybi-traffic-flow',
        ml.LineLayerProperties(
          lineColor: [
            'match',
            ['get', 'level'],
            'free',
            '#2EA44F',
            'moderate',
            '#F2A900',
            'heavy',
            '#D93025',
            '#8A8F98',
          ],
          lineWidth: 2.6,
          lineOpacity: .9,
          lineCap: 'round',
          lineJoin: 'round',
        ),
        belowLayerId: 'waybi-alternative-edge',
        enableInteraction: false,
      );
      // During active navigation traffic belongs to the route itself. Only
      // official traffic sections that actually align with this route are drawn,
      // at exactly the route width, so there is one visual path rather than a
      // competing traffic ribbon beside it.
      await c.addLineLayer(
        'waybi-route-traffic',
        'waybi-route-traffic-flow',
        ml.LineLayerProperties(
          lineColor: [
            'match',
            ['get', 'level'],
            'free',
            '#36B85A',
            'moderate',
            '#F2A900',
            'heavy',
            '#D93025',
            '#A8D86A',
          ],
          lineWidth: 7,
          lineOpacity: .98,
          lineCap: 'round',
          lineJoin: 'round',
        ),
        belowLayerId: 'waybi-poi-dot',
        enableInteraction: false,
      );
      await c.addCircleLayer(
        'waybi-pins',
        'waybi-pins-dot',
        ml.CircleLayerProperties(
          circleRadius: [
            'match',
            ['get', 'kind'],
            ['selected', 'destination'],
            9,
            6,
          ],
          circleColor: [
            'match',
            ['get', 'kind'],
            'event',
            '#d88b38',
            '#608b32',
          ],
          circleStrokeColor: '#ffffff',
          circleStrokeWidth: 2,
        ),
        filter: [
          'all',
          [
            '!=',
            ['get', 'kind'],
            'camera',
          ],
          [
            '!=',
            ['get', 'kind'],
            'destination',
          ],
        ],
        enableInteraction: false,
      );
      await c.addSymbolLayer(
        'waybi-pins',
        'waybi-camera-icon',
        ml.SymbolLayerProperties(
          iconImage: ['get', 'icon'],
          iconSize: 30 / 96 * imageScale,
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
          iconAnchor: 'center',
        ),
        filter: [
          '==',
          ['get', 'kind'],
          'camera',
        ],
        enableInteraction: false,
      );
      await c.addSymbolLayer(
        'waybi-pins',
        'waybi-event-icon',
        ml.SymbolLayerProperties(
          iconImage: ['get', 'icon'],
          iconSize: 38 / 96 * imageScale,
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
          iconAnchor: 'center',
        ),
        filter: [
          '==',
          ['get', 'kind'],
          'event',
        ],
        enableInteraction: false,
      );
      await c.addSymbolLayer(
        'waybi-pins',
        'waybi-destination-flag',
        ml.SymbolLayerProperties(
          iconImage: 'waybi-finish-flag',
          iconSize: 42 / 96 * imageScale,
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
          iconAnchor: 'bottom-left',
        ),
        filter: [
          '==',
          ['get', 'kind'],
          'destination',
        ],
        enableInteraction: false,
      );
      await c.addSymbolLayer(
        'waybi-pins',
        'waybi-pins-label',
        const ml.SymbolLayerProperties(
          textField: ['get', 'name'],
          textFont: ['Noto Sans Regular'],
          textSize: 12,
          textAnchor: 'top',
          textOffset: [0, .9],
          textHaloColor: '#ffffff',
          textHaloWidth: 1.5,
          textColor: '#3f612c',
        ),
        filter: [
          'all',
          [
            '!=',
            ['get', 'kind'],
            'camera',
          ],
          [
            '!=',
            ['get', 'kind'],
            'destination',
          ],
        ],
        enableInteraction: false,
      );
      await c.addSymbolLayer(
        'waybi-driver',
        'waybi-driver-light',
        ml.SymbolLayerProperties(
          iconImage: 'waybi-light',
          iconSize: .5 * imageScale,
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
          iconRotationAlignment: 'map',
          iconRotate: ['get', 'heading'],
        ),
        enableInteraction: false,
      );
      await c.addSymbolLayer(
        'waybi-driver',
        'waybi-driver-puck',
        ml.SymbolLayerProperties(
          iconImage: ['get', 'icon'],
          iconSize: 44 / 96 * imageScale,
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
          iconRotationAlignment: 'map',
          iconRotate: ['get', 'heading'],
        ),
        enableInteraction: false,
      );
      if (!mounted || generation != _generation) return;
      _ready = true;
      _signatures.clear();
      await _updatePadding();
      _queueSync();
      debugPrint('Waybi native map layers ready');
      widget.onReady(this);
    } catch (e) {
      if (mounted) debugPrint('Practice map initialization failed: $e');
    }
  }

  Future<void> _syncTrafficTiles() async {
    final overlay = widget.layers.traffic ? widget.trafficTileOverlay : null;
    final signature = overlay == null
        ? null
        : '${overlay.tileTemplate}:${DateTime.now().millisecondsSinceEpoch ~/ 60000}';
    if (signature == _trafficTileSignature) return;
    final c = _controller!;
    if (_trafficTileSignature != null) {
      await c.removeLayer('waybi-city-traffic');
      await c.removeSource('waybi-city-traffic');
      _trafficTileSignature = null;
    }
    if (overlay == null) return;
    await c.addSource(
      'waybi-city-traffic',
      ml.RasterSourceProperties(
        tiles: [
          '${overlay.tileTemplate}?refresh=${DateTime.now().millisecondsSinceEpoch ~/ 60000}',
        ],
        tileSize: 256,
        minzoom: 6,
        maxzoom: 19,
        attribution: overlay.attribution,
      ),
    );
    await c.addRasterLayer(
      'waybi-city-traffic',
      'waybi-city-traffic',
      const ml.RasterLayerProperties(rasterOpacity: .85, rasterFadeDuration: 0),
      belowLayerId: 'waybi-alternative-edge',
    );
    _trafficTileSignature = signature;
  }

  Map<String, dynamic> _collection(List<Map<String, dynamic>> features) => {
    'type': 'FeatureCollection',
    'features': features,
  };
  Map<String, dynamic> _pin(String id, GeoPoint p, String kind, String name) =>
      {
        'type': 'Feature',
        'id': id,
        'geometry': {
          'type': 'Point',
          'coordinates': [p.longitude, p.latitude],
        },
        'properties': {'kind': kind, 'name': name},
      };

  Map<String, dynamic> _cameraPin(SafetyCamera camera) {
    final kind = CameraKindLabel.fromCamera(camera);
    return {
      'type': 'Feature',
      'id': 'camera:${camera.id}',
      'geometry': {
        'type': 'Point',
        'coordinates': [camera.longitude, camera.latitude],
      },
      'properties': {
        'kind': 'camera',
        'name': camera.name,
        'cameraKind': kind.name,
        'icon': 'waybi-camera-${kind.name}',
      },
    };
  }

  void _queueSync() {
    _dirty = true;
    if (_ready && !_syncing) unawaited(_sync());
  }

  Future<void> _sync() async {
    _syncing = true;
    final generation = _generation;
    try {
      while (mounted && _ready && _dirty && generation == _generation) {
        _dirty = false;
        await _syncTrafficTiles();
        final activeRoute = widget.routePaths
            .where((route) => route.active)
            .firstOrNull;
        final allTraffic = widget.layers.traffic
            ? widget.trafficSegments
                  .where((segment) => segment.hasRoadGeometry)
                  .toList(growable: false)
            : const <TrafficFlowSegment>[];
        final traffic = widget.navigating
            ? const <TrafficFlowSegment>[]
            : allTraffic;
        final routeTraffic = widget.navigating && activeRoute != null
            ? allTraffic
                  .where(
                    (segment) =>
                        trafficSegmentMatchesRoute(segment, activeRoute),
                  )
                  .toList(growable: false)
            : const <TrafficFlowSegment>[];
        final trafficHash = Object.hash(
          widget.layers.traffic,
          widget.trafficFresh,
          widget.navigating,
          Object.hashAll(
            traffic.map(
              (segment) => Object.hash(
                segment.id,
                segment.level,
                segment.start,
                segment.end,
                Object.hashAll(segment.geometry),
              ),
            ),
          ),
        );
        await _setSource(
          'waybi-traffic',
          trafficHash,
          () => _collection([
            for (final segment in traffic)
              {
                'type': 'Feature',
                'id': segment.id,
                'geometry': {
                  'type': 'LineString',
                  'coordinates': [
                    for (final p in segment.geometry) [p.longitude, p.latitude],
                  ],
                },
                'properties': {
                  'level': widget.trafficFresh ? segment.level.name : 'unknown',
                  'name': segment.name,
                  'direction': segment.direction,
                  'congestion': segment.congestion,
                },
              },
          ]),
        );
        final routeTrafficHash = Object.hash(
          widget.trafficFresh,
          Object.hashAll(
            routeTraffic.map(
              (segment) => Object.hash(
                segment.id,
                segment.level,
                Object.hashAll(segment.geometry),
              ),
            ),
          ),
        );
        await _setSource(
          'waybi-route-traffic',
          routeTrafficHash,
          () => _collection([
            for (final segment in routeTraffic)
              if (trafficGeometryOnRoute(segment, activeRoute!).length >= 2)
                {
                  'type': 'Feature',
                  'id': 'route-${segment.id}',
                  'geometry': {
                    'type': 'LineString',
                    'coordinates': [
                      for (final p in trafficGeometryOnRoute(
                        segment,
                        activeRoute,
                      ))
                        [p.longitude, p.latitude],
                    ],
                  },
                  'properties': {
                    'level': widget.trafficFresh
                        ? segment.level.name
                        : 'unknown',
                  },
                },
          ]),
        );
        final routeHash = Object.hashAll(
          widget.routePaths.map(
            (route) => Object.hash(
              route.id,
              route.active,
              Object.hashAll(route.points),
            ),
          ),
        );
        await _setSource(
          'waybi-route',
          routeHash,
          () => _collection([
            for (final route in widget.routePaths)
              if (route.points.length > 1)
                {
                  'type': 'Feature',
                  'id': route.id,
                  'geometry': {
                    'type': 'LineString',
                    'coordinates': [
                      for (final p in route.points) [p.longitude, p.latitude],
                    ],
                  },
                  'properties': <String, dynamic>{'active': route.active},
                },
          ]),
        );
        final cameras = widget.cameras
            .where(widget.layers.shows)
            .toList(growable: false);
        final pinsHash = Object.hash(
          Object.hashAll(cameras),
          Object.hashAll(widget.roadEvents),
          Object.hashAll(widget.explorePlaces),
          widget.selectedPlace,
          activeRoute?.points.lastOrNull,
        );
        await _setSource(
          'waybi-pins',
          pinsHash,
          () => _collection([
            for (final c in cameras) _cameraPin(c),
            for (final e in widget.roadEvents)
              {
                ..._pin('event:${e.id}', e.location, 'event', e.roadName ?? ''),
                'properties': {
                  'kind': 'event',
                  'name': e.roadName ?? '',
                  'icon': 'waybi-event-${e.type.name}',
                },
              },
            for (var i = 0; i < widget.explorePlaces.length; i++)
              _pin(
                'explore:$i',
                widget.explorePlaces[i].location,
                'explore',
                widget.explorePlaces[i].name,
              ),
            if (widget.selectedPlace case final p?)
              _pin('selected', p.location, 'selected', p.name),
            if (activeRoute != null && activeRoute.points.isNotEmpty)
              _pin('destination', activeRoute.points.last, 'destination', ''),
          ]),
        );
        final driverHash = Object.hash(
          widget.locationEnabled,
          widget.location,
          widget.heading,
          widget.locationMarker,
        );
        await _setSource(
          'waybi-driver',
          driverHash,
          () => _collection([
            if (widget.locationEnabled && widget.location != null)
              {
                'type': 'Feature',
                'geometry': {
                  'type': 'Point',
                  'coordinates': [
                    widget.location!.longitude,
                    widget.location!.latitude,
                  ],
                },
                'properties': {
                  'heading': widget.heading,
                  'icon': 'waybi-puck-${widget.locationMarker.name}',
                },
              },
          ]),
        );
      }
    } catch (e) {
      if (mounted) debugPrint('Practice map update failed: $e');
    } finally {
      _syncing = false;
      if (mounted && _ready && _dirty) _queueSync();
    }
  }

  Future<void> _setSource(
    String id,
    int signature,
    Map<String, dynamic> Function() data,
  ) async {
    if (_signatures[id] == signature || !_ready) return;
    await _controller!.setGeoJsonSource(id, data());
    _signatures[id] = signature;
  }

  Future<void> _tap(math.Point<double> screen, ml.LatLng coordinate) async {
    if (!_ready) return;
    try {
      final features = await _controller!.queryRenderedFeaturesInRect(
        Rect.fromCenter(
          center: Offset(screen.x, screen.y),
          width: 24,
          height: 24,
        ),
        [
          'waybi-camera-icon',
          'waybi-event-icon',
          'waybi-pins-dot',
          'waybi-pins-label',
          'waybi-poi-dot',
          'waybi-poi-label',
        ],
        null,
      );
      if (!mounted) return;
      for (final raw in features) {
        final feature = raw is String ? jsonDecode(raw) as Map : raw as Map;
        final id = feature['id']?.toString() ?? '';
        if (id.startsWith('camera:')) {
          final c = widget.cameras
              .where((c) => 'camera:${c.id}' == id)
              .firstOrNull;
          if (c != null) {
            widget.onCamera(c);
            return;
          }
        }
        if (id.startsWith('event:')) {
          final e = widget.roadEvents
              .where((e) => 'event:${e.id}' == id)
              .firstOrNull;
          if (e != null) {
            widget.onRoadEvent(e);
            return;
          }
        }
        if (id.startsWith('explore:')) {
          final index = int.tryParse(id.substring(8));
          if (index != null && index < widget.explorePlaces.length) {
            widget.onExplorePlace(widget.explorePlaces[index]);
            return;
          }
        }
        final props = (feature['properties'] as Map?) ?? const {};
        if (props['kind'] != null) continue;
        final geometry = feature['geometry'] as Map?;
        final coords = geometry?['coordinates'];
        final name =
            (widget.language == 'zh' ? props['name:zh'] : null) ??
            props['name'] ??
            props['name:en'];
        if (name != null &&
            coords is List &&
            coords.length >= 2 &&
            coords[0] is num &&
            coords[1] is num) {
          widget.onMapPlace(
            PlaceSummary(
              name: name.toString(),
              category: (props['subclass'] ?? props['class'] ?? '').toString(),
              location: GeoPoint(
                (coords[1] as num).toDouble(),
                (coords[0] as num).toDouble(),
              ),
              reference: ProviderReference('osm', 'tile:$id'),
            ),
          );
          return;
        }
      }
    } catch (e) {
      debugPrint('Practice place selection failed: $e');
    }
    if (mounted) widget.onBlankTap();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: FutureBuilder<String>(
          future: _style,
          builder: (_, snapshot) {
            if (!snapshot.hasData) {
              return ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: Center(
                  child: snapshot.hasError
                      ? TextButton.icon(
                          onPressed: () => setState(_loadStyle),
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(
                            widget.language == 'zh' ? '重新加载地图' : 'Reload map',
                          ),
                        )
                      : const CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            return Listener(
              onPointerDown: (event) {
                _pointers[event.pointer] = event.position;
                if (_pointers.length > 1) _pan();
              },
              onPointerMove: (event) {
                final start = _pointers[event.pointer];
                if (start != null && (event.position - start).distance > 6) {
                  _pan();
                }
              },
              onPointerUp: (event) {
                _pointers.remove(event.pointer);
                if (_pointers.isEmpty) _gestureReported = false;
              },
              onPointerCancel: (event) {
                _pointers.remove(event.pointer);
                if (_pointers.isEmpty) _gestureReported = false;
              },
              onPointerSignal: (_) {
                widget.onUserPan();
              },
              child: ml.MapLibreMap(
                styleString: snapshot.data!,
                initialCameraPosition: ml.CameraPosition(
                  target: _point(widget.initialViewport.center),
                  zoom: widget.initialViewport.zoom,
                  bearing: widget.initialViewport.bearing,
                ),
                minMaxZoomPreference: const ml.MinMaxZoomPreference(3, 20),
                trackCameraPosition: true,
                compassEnabled: false,
                tiltGesturesEnabled: false,
                dragEnabled: false,
                annotationOrder: const [],
                onMapCreated: (c) => _controller = c,
                onStyleLoadedCallback: () => unawaited(_styleLoaded()),
                onCameraMove: _cameraMoved,
                onCameraIdle: () {
                  // Native iOS reports the settled position separately from
                  // movement frames. Keep follow calculations on that final
                  // bearing and zoom, rather than the last animation frame.
                  final camera = _controller?.cameraPosition;
                  if (camera != null) _cameraMoved(camera);
                },
                onMapClick: (p, ll) => unawaited(_tap(p, ll)),
                onMapLongClick: (_, p) => widget.onMapPlace(
                  PlaceSummary(
                    name: widget.language == 'zh' ? '选定位置' : 'Dropped pin',
                    kind: PlaceKind.coordinate,
                    location: GeoPoint(p.latitude, p.longitude),
                  ),
                ),
                attributionButtonPosition:
                    ml.AttributionButtonPosition.bottomRight,
                attributionButtonMargins: const math.Point(8, 8),
              ),
            );
          },
        ),
      ),
    ],
  );
}
