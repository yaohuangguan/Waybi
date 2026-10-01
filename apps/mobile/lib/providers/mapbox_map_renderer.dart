import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import '../domain/map_layer_settings.dart';
import '../domain/map_provider.dart';
import '../domain/safety_camera.dart';
import '../domain/road_event.dart';
import 'location_marker_art.dart';
import 'provider_contracts.dart';

void initializeMapboxMaps(String accessToken) {
  if (accessToken.isNotEmpty) {
    mb.MapboxOptions.setAccessToken(accessToken);
  }
}

class MapboxMapRenderer extends StatefulWidget {
  const MapboxMapRenderer({
    super.key,
    required this.initialViewport,
    required this.layers,
    required this.locationMarker,
    required this.locationEnabled,
    required this.moving,
    required this.language,
    required this.cameras,
    required this.roadEvents,
    required this.onRoadEvent,
    required this.route,
    required this.selectedPlace,
    required this.explorePlaces,
    required this.onExplorePlace,
    required this.onReady,
    required this.onViewportChanged,
    required this.onMapPlace,
    required this.onUserPan,
    required this.onBlankTap,
  });

  final MapViewportState initialViewport;
  final MapLayerSettings layers;
  final LocationMarkerStyle locationMarker;
  final bool locationEnabled;
  final bool moving;
  final String language;
  final List<SafetyCamera> cameras;
  final List<RoadEvent> roadEvents;
  final ValueChanged<RoadEvent> onRoadEvent;
  final List<GeoPoint> route;
  final PlaceSummary? selectedPlace;
  final List<PlaceSummary> explorePlaces;
  final ValueChanged<PlaceSummary> onExplorePlace;
  final ValueChanged<MapRenderer> onReady;
  final ValueChanged<MapViewportState> onViewportChanged;
  final ValueChanged<PlaceSummary> onMapPlace;
  final VoidCallback onUserPan;
  final VoidCallback onBlankTap;

  @override
  State<MapboxMapRenderer> createState() => _MapboxMapRendererState();
}

class _MapboxMapRendererState extends State<MapboxMapRenderer>
    implements RouteMapRenderer, PlaceFocusMapRenderer {
  mb.MapboxMap? _map;
  mb.CircleAnnotationManager? _cameraManager;
  mb.CircleAnnotationManager? _selectedManager;
  mb.CircleAnnotationManager? _exploreManager;
  mb.CircleAnnotationManager? _roadEventManager;
  final Map<String, RoadEvent> _roadEventAnnotations = {};
  final Map<String, PlaceSummary> _exploreAnnotations = {};
  mb.PolylineAnnotationManager? _routeManager;
  int _syncVersion = 0;
  Future<void> _overlayQueue = Future<void>.value();
  List<SafetyCamera>? _renderedCameras;
  List<RoadEvent>? _renderedEvents;
  List<PlaceSummary>? _renderedExplore;
  List<GeoPoint>? _renderedRoute;
  PlaceSummary? _renderedPlace;
  String? _renderedCameraLayers;
  int _tapVersion = 0;
  late MapViewportState _viewport = widget.initialViewport;

  @override
  MapProvider get provider => MapProvider.mapbox;

  @override
  MapViewportState get viewport => _viewport;

  mb.Point _point(GeoPoint point) =>
      mb.Point(coordinates: mb.Position(point.longitude, point.latitude));

  GeoPoint _geo(mb.Point point) => GeoPoint(
    point.coordinates.lat.toDouble(),
    point.coordinates.lng.toDouble(),
  );

  String get _styleUri => switch (widget.layers.style) {
    BaseMapStyle.standard => mb.MapboxStyles.STANDARD,
    BaseMapStyle.satellite => mb.MapboxStyles.STANDARD_SATELLITE,
    BaseMapStyle.terrain => mb.MapboxStyles.OUTDOORS,
    BaseMapStyle.hybrid => mb.MapboxStyles.SATELLITE_STREETS,
  };

  @override
  void didUpdateWidget(covariant MapboxMapRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layers.style != widget.layers.style) {
      final map = _map;
      if (map != null) unawaited(map.loadStyleURI(_styleUri));
    }
    if (oldWidget.locationMarker != widget.locationMarker ||
        oldWidget.locationEnabled != widget.locationEnabled ||
        oldWidget.moving != widget.moving) {
      unawaited(_setLocationPuck());
    }
    if (!listEquals(oldWidget.cameras, widget.cameras) ||
        !listEquals(oldWidget.roadEvents, widget.roadEvents) ||
        !listEquals(oldWidget.route, widget.route) ||
        oldWidget.selectedPlace != widget.selectedPlace ||
        !listEquals(oldWidget.explorePlaces, widget.explorePlaces) ||
        oldWidget.layers != widget.layers) {
      unawaited(_syncOverlays());
    }
  }

  @override
  Future<void> moveTo(MapViewportState viewport) async {
    _viewport = viewport;
    await _map?.easeTo(
      mb.CameraOptions(
        center: _point(viewport.center),
        zoom: viewport.zoom,
        bearing: viewport.bearing,
        pitch: viewport.pitch,
      ),
      mb.MapAnimationOptions(duration: 400),
    );
  }

  @override
  Future<void> focusPlace(GeoPoint point, {required double bottomInset}) async {
    final map = _map;
    if (map == null) return;
    final focus = MapViewportState(
      center: point,
      zoom: _viewport.zoom < 15 ? 15 : _viewport.zoom,
      bearing: _viewport.bearing,
      pitch: _viewport.pitch,
    );
    _viewport = focus;
    await map.easeTo(
      mb.CameraOptions(
        center: _point(point),
        zoom: focus.zoom,
        bearing: focus.bearing,
        pitch: focus.pitch,
        padding: mb.MbxEdgeInsets(
          top: 104,
          left: 18,
          bottom: bottomInset,
          right: 18,
        ),
      ),
      mb.MapAnimationOptions(duration: 360),
    );
  }

  @override
  Future<void> clearContentPadding() async {
    final map = _map;
    if (map == null) return;
    await map.easeTo(
      mb.CameraOptions(
        padding: mb.MbxEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
      ),
      mb.MapAnimationOptions(duration: 220),
    );
  }

  @override
  Future<void> fitRoute(
    List<GeoPoint> points, {
    required double bottomInset,
  }) async {
    final map = _map;
    if (map == null || points.length < 2) return;
    final camera = await map.cameraForCoordinatesPadding(
      points.map(_point).toList(growable: false),
      mb.CameraOptions(bearing: 0, pitch: 0),
      mb.MbxEdgeInsets(top: 150, left: 36, bottom: bottomInset, right: 36),
      17,
      null,
    );
    if (!mounted || !identical(_map, map)) return;
    await map.easeTo(camera, mb.MapAnimationOptions(duration: 420));
  }

  Future<void> _onCreated(mb.MapboxMap map) async {
    _map = map;
    map.addInteraction(
      mb.TapInteraction.onMap((gesture) => unawaited(_onTap(gesture))),
    );
    map.addInteraction(mb.LongTapInteraction.onMap(_onLongTap));
    _cameraManager = await map.annotations.createCircleAnnotationManager();
    _routeManager = await map.annotations.createPolylineAnnotationManager();
    _selectedManager = await map.annotations.createCircleAnnotationManager();
    _exploreManager = await map.annotations.createCircleAnnotationManager();
    _roadEventManager = await map.annotations.createCircleAnnotationManager();
    _roadEventManager!.tapEvents(
      onTap: (annotation) {
        final event = _roadEventAnnotations[annotation.id];
        if (event != null) widget.onRoadEvent(event);
      },
    );
    _exploreManager!.tapEvents(
      onTap: (annotation) {
        final place = _exploreAnnotations[annotation.id];
        if (place != null) widget.onExplorePlace(place);
      },
    );
    await _setLocationPuck();
    if (!mounted || !identical(_map, map)) return;
    widget.onReady(this);
    await _syncOverlays();
  }

  Future<void> _setLocationPuck() async {
    final map = _map;
    if (map == null) return;
    final style = widget.locationMarker;
    final image = style == LocationMarkerStyle.classic
        ? null
        : await LocationMarkerArt.png(style);
    if (!mounted || !identical(_map, map)) return;
    await map.location.updateSettings(
      mb.LocationComponentSettings(
        enabled: widget.locationEnabled,
        showAccuracyRing: true,
        accuracyRingColor: const Color(0x443B9DFF).toARGB32(),
        puckBearingEnabled: style != LocationMarkerStyle.classic,
        puckBearing: widget.moving
            ? mb.PuckBearing.COURSE
            : mb.PuckBearing.HEADING,
        locationPuck: image == null
            ? null
            : mb.LocationPuck(
                locationPuck2D: mb.LocationPuck2D(bearingImage: image),
              ),
      ),
    );
  }

  Future<void> _syncOverlays() {
    final version = ++_syncVersion;
    _overlayQueue = _overlayQueue
        .then((_) async {
          if (!mounted || version != _syncVersion) return;
          await _renderOverlays(version);
        })
        .catchError((Object _) {
          // The native map can disappear during a rapid provider switch.
        });
    return _overlayQueue;
  }

  Future<void> _renderOverlays(int version) async {
    final cameras = _cameraManager;
    final selected = _selectedManager;
    final routes = _routeManager;
    final explore = _exploreManager;
    final roadEvents = _roadEventManager;
    if (cameras == null ||
        selected == null ||
        routes == null ||
        explore == null ||
        roadEvents == null) {
      return;
    }
    final cameraItems = widget.cameras;
    final eventItems = widget.roadEvents;
    final exploreItems = widget.explorePlaces;
    final routeItems = widget.route;
    final selectedPlace = widget.selectedPlace;
    final layers = widget.layers;
    if (!listEquals(_renderedCameras, cameraItems) ||
        _renderedCameraLayers != layers.markerSignature) {
      await cameras.deleteAll();
      final visibleCameras = cameraItems
          .where(layers.shows)
          .map(
            (camera) => mb.CircleAnnotationOptions(
              geometry: _point(GeoPoint(camera.latitude, camera.longitude)),
              circleRadius: 7,
              circleColor: switch (CameraKindLabel.fromCamera(camera)) {
                CameraKind.spotSpeed => const Color(0xFF1670B9).toARGB32(),
                CameraKind.averageSpeed => const Color(0xFF0891B2).toARGB32(),
                CameraKind.redLight => const Color(0xFFD95640).toARGB32(),
                CameraKind.dualRedLightSpeed => const Color(
                  0xFFD97706,
                ).toARGB32(),
                CameraKind.busLane => const Color(0xFF496B32).toARGB32(),
                CameraKind.other => const Color(0xFF325A77).toARGB32(),
              },
              circleStrokeColor: Colors.white.toARGB32(),
              circleStrokeWidth: 2,
            ),
          )
          .toList(growable: false);
      if (visibleCameras.isNotEmpty) await cameras.createMulti(visibleCameras);
      _renderedCameras = List.of(cameraItems);
      _renderedCameraLayers = layers.markerSignature;
    }
    if (!mounted || version != _syncVersion) return;
    if (!listEquals(_renderedEvents, eventItems)) {
      await roadEvents.deleteAll();
      _roadEventAnnotations.clear();
      for (final event in eventItems) {
        final annotation = await roadEvents.create(
          mb.CircleAnnotationOptions(
            geometry: _point(event.location),
            circleRadius: 9,
            circleColor: const Color(0xFF486B29).toARGB32(),
            circleStrokeColor: Colors.white.toARGB32(),
            circleStrokeWidth: 3,
          ),
        );
        _roadEventAnnotations[annotation.id] = event;
      }
      _renderedEvents = List.of(eventItems);
    }
    if (!mounted || version != _syncVersion) return;
    if (!listEquals(_renderedExplore, exploreItems)) {
      await explore.deleteAll();
      _exploreAnnotations.clear();
      for (final place in exploreItems) {
        if (version != _syncVersion) {
          return;
        }
        final annotation = await explore.create(
          mb.CircleAnnotationOptions(
            geometry: _point(place.location),
            circleRadius: 9,
            circleColor: const Color(0xFFFFFFFF).toARGB32(),
            circleStrokeColor: const Color(0xFF1479FF).toARGB32(),
            circleStrokeWidth: 3,
          ),
        );
        _exploreAnnotations[annotation.id] = place;
      }
      _renderedExplore = List.of(exploreItems);
    }
    if (!mounted || version != _syncVersion) return;

    if (!listEquals(_renderedRoute, routeItems)) {
      await routes.deleteAll();
      if (routeItems.length >= 2) {
        await routes.create(
          mb.PolylineAnnotationOptions(
            geometry: mb.LineString(
              coordinates: routeItems
                  .map((point) => mb.Position(point.longitude, point.latitude))
                  .toList(growable: false),
            ),
            lineColor: const Color(0xFF1479FF).toARGB32(),
            lineWidth: 7,
            lineOpacity: 0.9,
          ),
        );
      }
      if (!mounted || version != _syncVersion) return;
      _renderedRoute = List.of(routeItems);
    }
    if (_renderedPlace != selectedPlace) {
      await selected.deleteAll();
      final place = selectedPlace;
      if (place != null) {
        await selected.create(
          mb.CircleAnnotationOptions(
            geometry: _point(place.location),
            circleRadius: 12,
            circleColor: const Color(0xFF1479FF).toARGB32(),
            circleStrokeColor: Colors.white.toARGB32(),
            circleStrokeWidth: 4,
          ),
        );
      }
      _renderedPlace = selectedPlace;
    }
  }

  void _cameraChanged(mb.CameraChangedEventData event) {
    final state = event.cameraState;
    _viewport = MapViewportState(
      center: _geo(state.center),
      zoom: state.zoom,
      bearing: state.bearing,
      pitch: state.pitch,
    );
    widget.onViewportChanged(_viewport);
  }

  Future<void> _onTap(mb.MapContentGestureContext gesture) async {
    final map = _map;
    final tapVersion = ++_tapVersion;
    if (map == null) return;
    try {
      final features = await map.queryRenderedFeatures(
        mb.RenderedQueryGeometry.fromScreenCoordinate(gesture.touchPosition),
        mb.RenderedQueryOptions(),
      );
      if (!mounted || tapVersion != _tapVersion || !identical(_map, map)) {
        return;
      }
      for (final result in features) {
        final feature = result?.queriedFeature.feature;
        final geometry = feature?['geometry'];
        if (geometry is! Map || geometry['type'] != 'Point') continue;
        final coordinates = geometry['coordinates'];
        if (coordinates is! List ||
            coordinates.length < 2 ||
            coordinates[0] is! num ||
            coordinates[1] is! num) {
          continue;
        }
        final properties = result?.queriedFeature.feature['properties'];
        if (properties is! Map) continue;
        final name =
            (widget.language == 'zh'
                ? properties['name_zh']?.toString()
                : properties['name_en']?.toString()) ??
            properties['name']?.toString();
        if (name == null || name.trim().isEmpty) continue;
        final category = properties['class']?.toString() ?? '';
        if (category == 'road' || category == 'landuse') continue;
        widget.onMapPlace(
          PlaceSummary(
            name: name,
            location: GeoPoint(
              (coordinates[1] as num).toDouble(),
              (coordinates[0] as num).toDouble(),
            ),
            category: category,
          ),
        );
        return;
      }
      widget.onBlankTap();
    } catch (_) {
      if (mounted && tapVersion == _tapVersion) widget.onBlankTap();
    }
  }

  void _onLongTap(mb.MapContentGestureContext gesture) {
    ++_tapVersion;
    widget.onMapPlace(
      PlaceSummary(
        name:
            '${gesture.point.coordinates.lat.toStringAsFixed(5)}, '
            '${gesture.point.coordinates.lng.toStringAsFixed(5)}',
        location: _geo(gesture.point),
        kind: PlaceKind.coordinate,
      ),
    );
  }

  @override
  void dispose() {
    ++_syncVersion;
    ++_tapVersion;
    _map = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => mb.MapWidget(
    key: const ValueKey('mapbox-browse-map'),
    styleUri: _styleUri,
    viewport: mb.CameraViewportState(
      center: _point(widget.initialViewport.center),
      zoom: widget.initialViewport.zoom,
      bearing: widget.initialViewport.bearing,
      pitch: widget.initialViewport.pitch,
    ),
    onMapCreated: _onCreated,
    onStyleLoadedListener: (_) {
      _renderedCameras = null;
      _renderedEvents = null;
      _renderedExplore = null;
      _renderedRoute = null;
      _renderedPlace = null;
      unawaited(_setLocationPuck());
      unawaited(_syncOverlays());
    },
    onCameraChangeListener: _cameraChanged,
    onScrollListener: (_) => widget.onUserPan(),
  );
}
