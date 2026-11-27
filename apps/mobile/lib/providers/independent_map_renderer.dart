import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:url_launcher/url_launcher.dart';

import '../domain/map_layer_settings.dart';
import '../domain/map_region_capabilities.dart';
import '../domain/map_provider.dart';
import '../domain/safety_camera.dart';
import '../domain/traffic_flow.dart';
import '../domain/road_event.dart';
import '../domain/transit_lane.dart';
import '../domain/transit_lane_map.dart';
import '../domain/transit_review_corridor.dart';
import '../domain/route_geometry.dart';
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
    this.transitLanes = const [],
    this.onTransitLane,
    this.transitReviewCorridors = const [],
    this.onTransitReviewCorridor,
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
    this.driving = false,
    this.onGestureChanged,
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
  final List<TransitLane> transitLanes;
  final ValueChanged<TransitLane>? onTransitLane;
  final List<TransitReviewCorridor> transitReviewCorridors;
  final ValueChanged<TransitReviewCorridor>? onTransitReviewCorridor;
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
  final bool driving;
  final ValueChanged<bool>? onGestureChanged;
  final TrafficTileOverlay? trafficTileOverlay;
  final bool trafficFresh;
  final Future<String> Function({
    required bool dark,
    required String language,
    required GeoPoint center,
  })
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
  late WaybiMapRegion _region;
  bool _ready = false, _syncing = false, _dirty = false;
  bool _sceneDirty = true;
  int _cameraRevision = 0;
  int _trafficMinute = 0;
  Timer? _creditTimer;
  bool _creditsVisible = false;
  bool _styleEventReceived = false;
  bool _initializingStyle = false;
  int _generation = 0;
  String? _trafficTileSignature;
  final _signatures = <String, int>{};

  /// Route progress changed without the rest of the scene.
  bool _progressDirty = false;

  /// Chunk index whose filters are applied to the route layers.
  int? _appliedHeadChunk;
  _RouteChunks? _chunks;
  _TrafficSpans? _trafficSpans;
  final _pointHashes = <String, (List<GeoPoint>, int)>{};
  final _pointers = <int, Offset>{};
  bool _gestureReported = false;
  EdgeInsets get _padding => _placePadding ?? widget.contentPadding;
  @override
  MapProvider get provider => MapProvider.independent;
  @override
  MapViewportState get viewport => _viewport;
  ml.LatLng _point(GeoPoint p) => ml.LatLng(p.latitude, p.longitude);

  @override
  void initState() {
    super.initState();
    _region = MapRegionCapabilities.forPoint(widget.initialViewport.center)
        .region;
  }

  @override
  void dispose() {
    _creditTimer?.cancel();
    super.dispose();
  }

  void _loadStyle() {
    _dark = Theme.of(context).brightness == Brightness.dark;
    _ready = false;
    _styleEventReceived = false;
    _generation++;
    _trafficTileSignature = null;
    _signatures.clear();
    _sceneDirty = true;
    _appliedHeadChunk = null;
    _appliedPadding = null;
    _style = widget.styleLoader(
      dark: _dark!,
      language: widget.language,
      center: _viewport.center,
    );
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
    if ((widget.navigating && !oldWidget.navigating) ||
        (widget.driving && !oldWidget.driving)) {
      _placePadding = null;
    }
    // Position/compass updates are frequent. Do not reproject traffic or hash
    // every route point unless the scene inputs actually changed.
    _sceneDirty |=
        oldWidget.layers.markerSignature != widget.layers.markerSignature ||
        oldWidget.layers.traffic != widget.layers.traffic ||
        oldWidget.layers.roadEvents != widget.layers.roadEvents ||
        oldWidget.layers.transitLanes != widget.layers.transitLanes ||
        !listEquals(oldWidget.transitLanes, widget.transitLanes) ||
        !listEquals(
          oldWidget.transitReviewCorridors,
          widget.transitReviewCorridors,
        ) ||
        oldWidget.trafficFresh != widget.trafficFresh ||
        oldWidget.navigating != widget.navigating ||
        !listEquals(oldWidget.cameras, widget.cameras) ||
        !listEquals(oldWidget.roadEvents, widget.roadEvents) ||
        !listEquals(oldWidget.trafficSegments, widget.trafficSegments) ||
        !listEquals(oldWidget.explorePlaces, widget.explorePlaces) ||
        oldWidget.selectedPlace != widget.selectedPlace ||
        _routeChange(oldWidget.routePaths, widget.routePaths) ==
            _RouteChange.scene ||
        oldWidget.trafficTileOverlay != widget.trafficTileOverlay ||
        _trafficMinute != DateTime.now().millisecondsSinceEpoch ~/ 60000;
    _progressDirty |=
        _routeChange(oldWidget.routePaths, widget.routePaths) !=
        _RouteChange.none;
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
    _cameraRevision++;
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
    _cameraRevision++;
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

  Future<void> _cameraIdle() async {
    final controller = _controller;
    if (controller == null || !_ready) return;
    final generation = _generation;
    final revision = _cameraRevision;
    // Native gestures stay entirely on the native thread. Read the exact final
    // camera once on idle instead of sending a platform message on every frame.
    ml.CameraPosition? camera;
    try {
      camera = await controller.queryCameraPosition();
    } catch (error) {
      if (mounted) debugPrint('Waybi final camera unavailable: $error');
      return;
    }
    if (!mounted || generation != _generation || revision != _cameraRevision) {
      return;
    }
    if (camera != null) _cameraMoved(camera);

    // MapLibre can report a transient/default camera while a new style is
    // still being attached. Never let that tear down the first overlay setup:
    // Waybi driver, POIs, routes and traffic are all installed in
    // _styleLoaded(). Region switching is only safe after that setup is ready.
    if (!_ready) return;

    final next = MapRegionCapabilities.forPoint(_viewport.center).region;
    if (next == _region) return;
    setState(() {
      _region = next;
      _loadStyle();
    });
  }

  void _pan() {
    if (_gestureReported) return;
    _gestureReported = true;
    _cameraRevision++;
    if (_creditsVisible) setState(() => _creditsVisible = false);
    widget.onUserPan();
  }

  void _mapCreated(ml.MapLibreMapController controller) {
    _controller = controller;
    if (_styleEventReceived) unawaited(_styleLoaded());
  }

  void _styleDidLoad() {
    _styleEventReceived = true;
    if (_controller != null) unawaited(_styleLoaded());
  }

  Future<void> _styleLoaded() async {
    if (_initializingStyle || !_styleEventReceived) return;
    final c = _controller;
    if (c == null) return;

    _initializingStyle = true;
    final generation = _generation;
    try {
      final imageScale = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
          ? View.of(context).devicePixelRatio
          : 1.0;
      Set<String> existingLayerIds = const {};
      try {
        existingLayerIds = (await c.getLayerIds())
            .map((id) => id.toString())
            .toSet();
      } catch (e) {
        debugPrint(
          'Waybi map layer discovery unavailable; using safe overlay fallback: $e',
        );
      }
      final overlayAnchor = existingLayerIds.contains('waybi-poi-dot')
          ? 'waybi-poi-dot'
          : existingLayerIds.contains('waterway_line_label')
          ? 'waterway_line_label'
          : null;
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
        'waybi-transit-lanes',
        'waybi-route-traffic',
        'waybi-route',
        'waybi-route-head',
        'waybi-route-traffic-head',
        'waybi-road-events',
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
          filter: active ? _activeFilter(-1) : _alternativeFilter,
          belowLayerId: overlayAnchor,
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
          filter: active ? _activeFilter(-1) : _alternativeFilter,
          belowLayerId: overlayAnchor,
          enableInteraction: false,
        );
      }
      // Opaque, pre-blended greys: the driven part is drawn in pieces (route
      // chunks plus the piece at the car), and translucent overlaps would
      // show as dots at every joint.
      for (final casing in [true, false]) {
        await c.addLineLayer(
          'waybi-route',
          casing ? 'waybi-traversed-edge' : 'waybi-traversed-line',
          ml.LineLayerProperties(
            lineColor: casing ? '#8A9198' : '#BBC1C7',
            lineWidth: casing ? 8 : 5.5,
            lineCap: 'round',
            lineJoin: 'round',
          ),
          filter: _traversedFilter(-1),
          belowLayerId: 'waybi-route-edge',
          enableInteraction: false,
        );
      }
      // The route piece at the car (and a Just Drive trail's live end): a
      // few points re-sent per update instead of the whole route.
      for (final (id, below, color, width, filter) in [
        (
          'waybi-head-traversed-edge',
          'waybi-traversed-line',
          '#8A9198',
          8.0,
          _headTraversedFilter,
        ),
        (
          'waybi-head-traversed-line',
          'waybi-route-edge',
          '#BBC1C7',
          5.5,
          _headTraversedFilter,
        ),
        ('waybi-head-edge', 'waybi-route-line', '#486B29', 10.0, _headFilter),
        ('waybi-head-line', overlayAnchor, '#A8D86A', 7.0, _headFilter),
      ]) {
        await c.addLineLayer(
          'waybi-route-head',
          id,
          ml.LineLayerProperties(
            lineColor: color,
            lineWidth: width,
            lineCap: 'round',
            lineJoin: 'round',
          ),
          filter: filter,
          belowLayerId: below,
          enableInteraction: false,
        );
      }
      // A thin dashed official lane trace: never paint the whole road as
      // restricted. Draw beneath live traffic and navigation routes.
      await c.addLineLayer(
        'waybi-transit-lanes',
        'waybi-transit-casing',
        const ml.LineLayerProperties(
          lineColor: '#ffffff',
          lineWidth: 6,
          lineOpacity: .7,
          lineCap: 'round',
          lineJoin: 'round',
        ),
        belowLayerId: 'waybi-alternative-edge',
        enableInteraction: false,
      );
      await c.addLineLayer(
        'waybi-transit-lanes',
        'waybi-transit-lines',
        ml.LineLayerProperties(
          lineColor: [
            'match',
            ['get', 'laneStatus'],
            'active',
            '#2674B5',
            'unknown',
            '#D59126',
            'candidate',
            '#BD8131',
            '#A4AFBD',
          ],
          lineWidth: 3.6,
          lineOpacity: .86,
          lineDasharray: [2, 1.5],
          lineCap: 'round',
          lineJoin: 'round',
        ),
        belowLayerId: 'waybi-alternative-edge',
        enableInteraction: false,
      );
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
      for (final (source, id) in [
        ('waybi-route-traffic', 'waybi-route-traffic-flow'),
        // Traffic in the route piece at the car, clipped there each update.
        ('waybi-route-traffic-head', 'waybi-route-traffic-head-flow'),
      ]) {
        await c.addLineLayer(
          source,
          id,
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
          belowLayerId: overlayAnchor,
          enableInteraction: false,
        );
      }
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
      await c.addLineLayer(
        'waybi-road-events',
        'waybi-road-events-casing',
        const ml.LineLayerProperties(lineColor: '#ffffff', lineWidth: 11),
        belowLayerId: 'waybi-pins-dot',
        enableInteraction: false,
      );
      await c.addLineLayer(
        'waybi-road-events',
        'waybi-road-events-line',
        const ml.LineLayerProperties(
          lineColor: [
            'match',
            ['get', 'type'],
            'roadClosure',
            '#d63b3b',
            '#d88d22',
          ],
          lineWidth: 7,
          lineDasharray: [2, 1.5],
        ),
        belowLayerId: 'waybi-pins-dot',
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
      _styleEventReceived = false;
      _ready = true;
      if (_creditTimer == null) {
        setState(() => _creditsVisible = true);
        _creditTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) setState(() => _creditsVisible = false);
        });
      }
      _signatures.clear();
      await _updatePadding();
      _queueSync();
      debugPrint('Waybi native map layers ready');
      widget.onReady(this);
    } catch (e, stack) {
      if (mounted) {
        debugPrint('Practice map initialization failed: $e');
        debugPrintStack(stackTrace: stack);
      }
    } finally {
      _initializingStyle = false;
      if (mounted &&
          !_ready &&
          _styleEventReceived &&
          _controller != null &&
          generation == _generation) {
        scheduleMicrotask(_styleLoaded);
      }
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

  static const _chunkSentinel = 1000000000;

  static const _alternativeFilter = [
    'all',
    [
      '==',
      ['get', 'active'],
      false,
    ],
    [
      '!=',
      ['get', 'traversed'],
      true,
    ],
  ];

  /// Active features, minus route chunks up to and including [head].
  static List<Object> _activeFilter(int head) => [
    'all',
    [
      '==',
      ['get', 'active'],
      true,
    ],
    [
      '!=',
      ['get', 'traversed'],
      true,
    ],
    [
      '>',
      [
        'coalesce',
        ['get', 'chunk'],
        _chunkSentinel,
      ],
      head,
    ],
  ];

  /// Traversed features, plus route chunks before [head].
  static List<Object> _traversedFilter(int head) => [
    'any',
    [
      '==',
      ['get', 'traversed'],
      true,
    ],
    [
      '<',
      [
        'coalesce',
        ['get', 'chunk'],
        _chunkSentinel,
      ],
      head,
    ],
  ];

  static const _headTraversedFilter = [
    '==',
    ['get', 'traversed'],
    true,
  ];
  static const _headFilter = [
    'all',
    [
      '==',
      ['get', 'active'],
      true,
    ],
    [
      '!=',
      ['get', 'traversed'],
      true,
    ],
  ];

  MapRoutePath? get _activeRoute => widget.routePaths
      .where((route) => route.active && !route.trail)
      .firstOrNull;

  /// What changed between two route lists, without comparing points.
  _RouteChange _routeChange(List<MapRoutePath> a, List<MapRoutePath> b) {
    if (a.length != b.length) return _RouteChange.scene;
    var change = _RouteChange.none;
    for (var i = 0; i < a.length; i++) {
      final x = a[i], y = b[i];
      if (x.id != y.id ||
          x.active != y.active ||
          x.traversed != y.traversed ||
          x.trail != y.trail ||
          x.live != y.live ||
          (x.progressMeters == null) != (y.progressMeters == null)) {
        return _RouteChange.scene;
      }
      if (!x.sameGeometry(y)) {
        if (!x.live) return _RouteChange.scene;
        change = _RouteChange.progress;
      }
      if (x.progressMeters != y.progressMeters) change = _RouteChange.progress;
    }
    return change;
  }

  /// O(1) identity for a path's geometry; hashes points only for a new list.
  int _routeKey(MapRoutePath route) {
    final cached = _pointHashes[route.id];
    final geometry =
        route.revision ??
        (cached != null && identical(cached.$1, route.points)
            ? cached.$2
            : (_pointHashes[route.id] = (
                route.points,
                Object.hashAll(route.points),
              )).$2);
    return Object.hash(
      route.id,
      route.active,
      route.traversed,
      route.trail,
      route.progressMeters != null,
      geometry,
    );
  }

  Map<String, dynamic> _lineFeature(
    String id,
    List<GeoPoint> points,
    Map<String, dynamic> properties,
  ) => {
    'type': 'Feature',
    'id': id,
    'geometry': {
      'type': 'LineString',
      'coordinates': [
        for (final p in points) [p.longitude, p.latitude],
      ],
    },
    'properties': properties,
  };

  _RouteChunks _chunksFor(MapRoutePath route) {
    final key = _routeKey(route);
    final cached = _chunks;
    if (cached != null && cached.key == key) return cached;
    return _chunks = _RouteChunks(key, RouteGeometry.of(route.points));
  }

  /// The route as fixed-length pieces, sent once per route. Progress only
  /// changes which pieces the traversed and active filters select.
  List<Map<String, dynamic>> _chunkFeatures(MapRoutePath route) {
    final chunks = _chunksFor(route);
    return [
      for (var i = 0; i < chunks.count; i++)
        if (chunks.slice(i) case final points when points.length > 1)
          _lineFeature('${route.id}:chunk:$i', points, {
            'active': true,
            'traversed': false,
            'chunk': i,
          }),
    ];
  }

  Future<void> _syncRouteProgress() async {
    final c = _controller!;
    final route = _activeRoute;
    final progress = route?.progressMeters;
    final chunks = route != null && progress != null ? _chunksFor(route) : null;
    final head = chunks == null ? -1 : chunks.indexAt(progress!);
    if (_appliedHeadChunk != head) {
      for (final id in ['waybi-route-edge', 'waybi-route-line']) {
        await c.setFilter(id, _activeFilter(head));
      }
      for (final id in ['waybi-traversed-edge', 'waybi-traversed-line']) {
        await c.setFilter(id, _traversedFilter(head));
      }
      _appliedHeadChunk = head;
    }
    final live = widget.routePaths
        .where((path) => path.live)
        .toList(growable: false);
    await _setSource(
      'waybi-route-head',
      Object.hash(
        route == null || chunks == null ? null : _routeKey(route),
        progress,
        Object.hashAll(
          live.map(
            (path) => Object.hash(
              path.id,
              path.revision,
              identityHashCode(path.points),
            ),
          ),
        ),
      ),
      () => _collection([
        if (route != null && chunks != null) ...[
          if (chunks.geometry.slice(chunks.start(head), progress!)
              case final driven when driven.length > 1)
            _lineFeature('${route.id}:head:driven', driven, {
              'active': true,
              'traversed': true,
            }),
          if (chunks.geometry.slice(progress, chunks.end(head)) case final ahead
              when ahead.length > 1)
            _lineFeature('${route.id}:head', ahead, {
              'active': true,
              'traversed': false,
            }),
        ],
        for (final path in live)
          if (path.points.length > 1)
            _lineFeature(path.id, path.points, {
              'active': path.active,
              'traversed': path.traversed,
            }),
      ]),
    );
    await _syncRouteTraffic(
      route,
      progress ?? 0,
      chunks == null ? 0 : chunks.end(head),
      head,
    );
  }

  /// Traffic is matched to a route once per (route, traffic snapshot); each
  /// update only clips the already-matched spans at the car.
  Future<void> _syncRouteTraffic(
    MapRoutePath? route,
    double progress,
    double headEnd,
    int head,
  ) async {
    final segments = widget.navigating && widget.layers.traffic && route != null
        ? widget.trafficSegments
        : const <TrafficFlowSegment>[];
    final routeKey = route == null ? 0 : _routeKey(route);
    var spans = _trafficSpans;
    if (spans == null ||
        spans.routeKey != routeKey ||
        !identical(spans.segments, segments)) {
      spans = _trafficSpans = _TrafficSpans(
        routeKey,
        segments,
        route == null ? const [] : routeTrafficSpans(segments, route.points),
      );
    }
    final geometry = route == null ? null : RouteGeometry.of(route.points);
    final level = widget.trafficFresh;
    Map<String, dynamic> feature(
      RouteTrafficSpan span,
      double from,
      double to,
    ) => _lineFeature('route-${span.segment.id}', geometry!.slice(from, to), {
      'level': level ? span.segment.level.name : 'unknown',
    });
    // Ahead of the piece at the car: re-sent only when that piece changes.
    final ahead = spans.spans
        .where((span) => span.endMeters > headEnd)
        .toList(growable: false);
    await _setSource(
      'waybi-route-traffic',
      Object.hash(identityHashCode(spans), level, headEnd),
      () => _collection([
        for (final span in ahead)
          if (math.max(span.startMeters, headEnd) < span.endMeters)
            feature(span, math.max(span.startMeters, headEnd), span.endMeters),
      ]),
    );
    final near = spans.spans
        .where(
          (span) => span.startMeters < headEnd && span.endMeters > progress,
        )
        .toList(growable: false);
    await _setSource(
      'waybi-route-traffic-head',
      Object.hash(
        identityHashCode(spans),
        level,
        head,
        near.isEmpty ? null : progress,
      ),
      () => _collection([
        for (final span in near)
          if (math.max(span.startMeters, progress) <
              math.min(span.endMeters, headEnd))
            feature(
              span,
              math.max(span.startMeters, progress),
              math.min(span.endMeters, headEnd),
            ),
      ]),
    );
  }

  Future<void> _sync() async {
    _syncing = true;
    final generation = _generation;
    try {
      while (mounted && _ready && _dirty && generation == _generation) {
        _dirty = false;
        final scene = _sceneDirty;
        if (_sceneDirty) {
          _sceneDirty = false;
          _trafficMinute = DateTime.now().millisecondsSinceEpoch ~/ 60000;
          await _syncTrafficTiles();
          final transit = widget.layers.transitLanes
              ? widget.transitLanes
              : const <TransitLane>[];
          final reviewCorridors = widget.layers.transitLanes
              ? widget.transitReviewCorridors
              : const <TransitReviewCorridor>[];
          final laneTime = DateTime.now();
          await _setSource(
            'waybi-transit-lanes',
            Object.hash(
              widget.layers.transitLanes,
              Object.hashAll(transit),
              Object.hashAll(reviewCorridors),
              // Lane colours follow their schedules; only a status change
              // needs the 5k-point source again.
              Object.hashAll(
                transit.map((lane) => lane.schedule.activeAt(laneTime)),
              ),
            ),
            () => transitLaneFeatureCollection(
              transit,
              laneTime,
              reviewCorridors,
            ),
          );
          final activeRoute = _activeRoute;
          final destinationRoute =
              activeRoute ??
              widget.routePaths.where((route) => route.traversed).lastOrNull;
          final traffic = widget.layers.traffic && !widget.navigating
              ? widget.trafficSegments
                    .where((segment) => segment.hasRoadGeometry)
                    .toList(growable: false)
              : const <TrafficFlowSegment>[];
          final trafficHash = Object.hash(
            widget.layers.traffic,
            widget.trafficFresh,
            widget.navigating,
            Object.hashAll(traffic),
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
                      for (final p in segment.geometry)
                        [p.longitude, p.latitude],
                    ],
                  },
                  'properties': {
                    'level': widget.trafficFresh
                        ? segment.level.name
                        : 'unknown',
                    'name': segment.name,
                    'direction': segment.direction,
                    'congestion': segment.congestion,
                  },
                },
            ]),
          );
          final staticRoutes = widget.routePaths
              .where((route) => !route.live)
              .toList(growable: false);
          await _setSource(
            'waybi-route',
            Object.hashAll(staticRoutes.map(_routeKey)),
            () => _collection([
              for (final route in staticRoutes)
                if (route.progressMeters != null && route.active)
                  ..._chunkFeatures(route)
                else if (route.points.length > 1)
                  _lineFeature(route.id, route.points, {
                    'active': route.active,
                    'traversed': route.traversed,
                  }),
            ]),
          );
          final cameras = widget.cameras
              .where(widget.layers.shows)
              .toList(growable: false);
          await _setSource(
            'waybi-road-events',
            Object.hashAll(widget.roadEvents),
            () => _collection([
              for (final event in widget.roadEvents)
                if (event.geometry.length >= 2 &&
                    event.metadata['geometryType'] == 'LINESTRING')
                  {
                    'type': 'Feature',
                    'id': 'event:${event.id}',
                    'geometry': {
                      'type': 'LineString',
                      'coordinates': [
                        for (final p in event.geometry)
                          [p.longitude, p.latitude],
                      ],
                    },
                    'properties': {'type': event.type.name},
                  },
            ]),
          );
          final pinsHash = Object.hash(
            Object.hashAll(cameras),
            Object.hashAll(widget.roadEvents),
            Object.hashAll(widget.explorePlaces),
            widget.selectedPlace,
            destinationRoute?.points.lastOrNull,
          );
          await _setSource(
            'waybi-pins',
            pinsHash,
            () => _collection([
              for (final c in cameras) _cameraPin(c),
              for (final e in widget.roadEvents)
                {
                  ..._pin(
                    'event:${e.id}',
                    e.location,
                    'event',
                    e.roadName ?? '',
                  ),
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
              if (destinationRoute != null &&
                  destinationRoute.points.isNotEmpty)
                _pin(
                  'destination',
                  destinationRoute.points.last,
                  'destination',
                  '',
                ),
            ]),
          );
        }
        if (scene || _progressDirty) {
          _progressDirty = false;
          await _syncRouteProgress();
        }
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
          'waybi-road-events-line',
          'waybi-transit-lines',
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
        if (id.startsWith('transit:') && widget.layers.transitLanes) {
          final lane = widget.transitLanes
              .where((lane) => 'transit:${lane.id}' == id)
              .firstOrNull;
          if (lane != null) {
            widget.onTransitLane?.call(lane);
            return;
          }
        }
        if (id.startsWith('review:') && widget.layers.transitLanes) {
          final corridor = widget.transitReviewCorridors
              .where((entry) => 'review:${entry.id}' == id)
              .firstOrNull;
          if (corridor != null) {
            widget.onTransitReviewCorridor?.call(corridor);
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
                widget.onGestureChanged?.call(true);
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
                if (_pointers.isEmpty) {
                  _gestureReported = false;
                  widget.onGestureChanged?.call(false);
                }
              },
              onPointerCancel: (event) {
                _pointers.remove(event.pointer);
                if (_pointers.isEmpty) {
                  _gestureReported = false;
                  widget.onGestureChanged?.call(false);
                }
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
                trackCameraPosition: false,
                compassEnabled: false,
                attributionButtonEnabled: kIsWeb,
                tiltGesturesEnabled: false,
                dragEnabled: false,
                annotationOrder: const [],
                onMapCreated: _mapCreated,
                onStyleLoadedCallback: _styleDidLoad,
                onCameraIdle: _cameraIdle,
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
      if (_creditsVisible && !kIsWeb)
        Positioned(
          right: 8,
          bottom: _padding.bottom + 8,
          child: Material(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: .9),
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              onTap: () => launchUrl(
                Uri.parse('https://www.openstreetmap.org/copyright'),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                child: Text(
                  '© OpenStreetMap contributors · © OpenMapTiles',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

enum _RouteChange { none, progress, scene }

/// A route cut into fixed-length pieces (at most ~400).
class _RouteChunks {
  _RouteChunks(this.key, this.geometry)
    : meters = math.max(200.0, geometry.totalMeters / 400) {
    count = math.max(1, (geometry.totalMeters / meters).ceil());
  }
  final int key;
  final RouteGeometry geometry;
  final double meters;
  late final int count;
  final _slices = <int, List<GeoPoint>>{};

  int indexAt(double along) =>
      (along / meters).floor().clamp(0, count - 1).toInt();
  double start(int index) => index * meters;
  double end(int index) =>
      index >= count - 1 ? geometry.totalMeters : (index + 1) * meters;
  List<GeoPoint> slice(int index) =>
      _slices[index] ??= geometry.slice(start(index), end(index));
}

class _TrafficSpans {
  _TrafficSpans(this.routeKey, this.segments, this.spans);
  final int routeKey;
  final List<TrafficFlowSegment> segments;
  final List<RouteTrafficSpan> spans;
}
