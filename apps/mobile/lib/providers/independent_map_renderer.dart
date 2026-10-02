import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:url_launcher/url_launcher.dart';

import '../domain/map_layer_settings.dart';
import '../domain/map_provider.dart';
import '../domain/safety_camera.dart';
import '../domain/road_event.dart';
import '../theme/kiwi_lens_theme.dart';
import '../widgets/kiwi_mascot.dart';
import 'location_marker_art.dart';
import 'independent_map_style.dart';
import 'provider_contracts.dart';

/// Flutter owns both projection and the single location marker in Practice.
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
    required this.route,
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
  final List<GeoPoint> route;
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
  final Future<Style> Function({required bool dark, required String language})
  styleLoader;
  @override
  State<IndependentMapRenderer> createState() => _IndependentMapRendererState();
}

class _IndependentMapRendererState extends State<IndependentMapRenderer>
    implements RouteMapRenderer, PlaceFocusMapRenderer {
  final _controller = MapController();
  late MapViewportState _viewport = widget.initialViewport;
  EdgeInsets? _placePadding;
  bool _ready = false;
  Future<Style>? _style;
  bool? _dark;
  void _loadStyle() {
    _dark = Theme.of(context).brightness == Brightness.dark;
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
  MapProvider get provider => MapProvider.independent;
  @override
  MapViewportState get viewport => _viewport;
  ll.LatLng _point(GeoPoint p) => ll.LatLng(p.latitude, p.longitude);
  EdgeInsets get _padding => _placePadding ?? widget.contentPadding;
  @override
  void didUpdateWidget(covariant IndependentMapRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.language != widget.language) _loadStyle();
    if (oldWidget.contentPadding != widget.contentPadding &&
        widget.following &&
        widget.location != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.following) {
          moveTo(_viewport.copyWith(center: widget.location));
        }
      });
    }
  }

  @override
  Future<void> moveTo(MapViewportState viewport) async {
    if (!_ready) return;
    _viewport = viewport;
    _controller.rotate(-viewport.bearing);
    _controller.move(
      _point(viewport.center),
      viewport.zoom,
      offset: Offset(
        (_padding.left - _padding.right) / 2,
        (_padding.top - _padding.bottom) / 2,
      ),
    );
  }

  @override
  Future<void> focusPlace(GeoPoint point, {required double bottomInset}) async {
    _placePadding = EdgeInsets.fromLTRB(18, 104, 18, bottomInset);
    setState(() {});
    await moveTo(
      _viewport.copyWith(center: point, zoom: math.max(15, _viewport.zoom)),
    );
  }

  @override
  Future<void> clearContentPadding() async {
    _placePadding = null;
    setState(() {});
  }

  @override
  Future<void> fitRoute(
    List<GeoPoint> points, {
    required double bottomInset,
  }) async {
    if (!_ready || points.length < 2) return;
    _controller.rotate(0);
    _controller.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points.map(_point).toList()),
        padding: EdgeInsets.fromLTRB(
          36,
          widget.contentPadding.top > 0 ? widget.contentPadding.top : 150,
          36,
          bottomInset,
        ),
        maxZoom: 17,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Marker _pin(GeoPoint p, Widget child) =>
      Marker(point: _point(p), width: 40, height: 40, child: child);
  Widget _button(
    IconData icon,
    VoidCallback onTap, {
    Color color = KiwiLensColors.ocean,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 6)],
      ),
      child: Icon(icon, color: color, size: 24),
    ),
  );
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      FlutterMap(
        mapController: _controller,
        options: MapOptions(
          initialCenter: _point(widget.initialViewport.center),
          initialZoom: widget.initialViewport.zoom,
          maxZoom: 19,
          initialRotation: -widget.initialViewport.bearing,
          onMapReady: () {
            _ready = true;
            widget.onReady(this);
          },
          onPositionChanged: (camera, gesture) {
            _viewport = MapViewportState(
              center: GeoPoint(camera.center.latitude, camera.center.longitude),
              zoom: camera.zoom,
              bearing: -camera.rotation,
            );
            setState(() {});
            widget.onViewportChanged(_viewport);
            if (gesture) widget.onUserPan();
          },
          onTap: (_, _) => widget.onBlankTap(),
          onLongPress: (_, point) => widget.onMapPlace(
            PlaceSummary(
              name: widget.language == 'zh' ? '选定位置' : 'Dropped pin',
              kind: PlaceKind.coordinate,
              location: GeoPoint(point.latitude, point.longitude),
            ),
          ),
        ),
        children: [
          FutureBuilder<Style>(
            future: _style,
            builder: (_, snapshot) {
              final style = snapshot.data;
              if (style != null) {
                return VectorTileLayer(
                  key: ValueKey('kiwi-map-$_dark-${widget.language}'),
                  theme: style.theme,
                  sprites: style.sprites,
                  tileProviders: style.providers,
                  layerMode: VectorTileLayerMode.vector,
                  fileCacheTtl: const Duration(days: 7),
                  fileCacheMaximumSizeInBytes: 80 * 1024 * 1024,
                  concurrency: 2,
                );
              }
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
                      : const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                ),
              );
            },
          ),
          if (widget.route.length > 1)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: widget.route.map(_point).toList(),
                  color: KiwiLensColors.ocean,
                  strokeWidth: 6,
                  borderStrokeWidth: 2,
                  borderColor: Colors.white,
                ),
              ],
            ),
          MarkerLayer(
            markers: [
              for (final c in widget.cameras.where(widget.layers.shows))
                _pin(
                  GeoPoint(c.latitude, c.longitude),
                  _button(Icons.speed_rounded, () => widget.onCamera(c)),
                ),
              for (final e in widget.roadEvents)
                _pin(
                  e.location,
                  _button(
                    Icons.warning_amber_rounded,
                    () => widget.onRoadEvent(e),
                    color: Colors.orange.shade800,
                  ),
                ),
              for (final p in widget.explorePlaces)
                _pin(
                  p.location,
                  _button(Icons.place_rounded, () => widget.onExplorePlace(p)),
                ),
              if (widget.selectedPlace != null)
                _pin(
                  widget.selectedPlace!.location,
                  const Icon(
                    Icons.location_on_rounded,
                    size: 40,
                    color: KiwiLensColors.ocean,
                  ),
                ),
              if (widget.route.isNotEmpty)
                _pin(
                  widget.route.last,
                  const Icon(
                    Icons.flag_circle_rounded,
                    size: 38,
                    color: KiwiLensColors.ocean,
                  ),
                ),
              if (widget.locationEnabled && widget.location != null)
                Marker(
                  point: _point(widget.location!),
                  width: 240,
                  height: 240,
                  child: Transform.rotate(
                    angle: (widget.heading - _viewport.bearing) * math.pi / 180,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const HeadingGlow(),
                        if (widget.locationMarker == LocationMarkerStyle.kiwi)
                          const KiwiMascot(size: 44)
                        else
                          FutureBuilder(
                            future: LocationMarkerArt.png(
                              widget.locationMarker,
                            ),
                            builder: (_, image) => image.data == null
                                ? const SizedBox(width: 44, height: 44)
                                : Image.memory(
                                    image.data!,
                                    width: 44,
                                    height: 44,
                                  ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      // Always visible above decks, rather than hidden inside an attribution popup.
      Positioned(
        right: 6,
        bottom: _padding.bottom + 24,
        child: Material(
          color: Colors.white.withValues(alpha: .92),
          borderRadius: BorderRadius.circular(6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _credit('© OpenMapTiles', 'https://openmaptiles.org/'),
              _credit(
                '© OpenStreetMap',
                'https://www.openstreetmap.org/copyright',
              ),
              if (widget.route.isNotEmpty)
                _credit('OSRM', 'https://routing.openstreetmap.de/about.html'),
            ],
          ),
        ),
      ),
      Positioned(
        left: 6,
        bottom: _padding.bottom + 24,
        child: Material(
          color: Colors.white.withValues(alpha: .92),
          child: InkWell(
            onTap: () =>
                launchUrl(Uri.parse('https://www.openstreetmap.org/fixthemap')),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Text(
                widget.language == 'zh' ? '纠正地图' : 'Fix the map',
                style: const TextStyle(fontSize: 10, color: Colors.black87),
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _credit(String text, String url) => InkWell(
    onTap: () => launchUrl(Uri.parse(url)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, color: Colors.black87),
      ),
    ),
  );
}

/// The light and puck share one map marker, so their origin cannot diverge.
class HeadingGlow extends StatefulWidget {
  const HeadingGlow({super.key});
  @override
  State<HeadingGlow> createState() => _HeadingGlowState();
}

class _HeadingGlowState extends State<HeadingGlow>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat(reverse: true);
  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _pulse,
    builder: (_, _) => CustomPaint(
      size: const Size(240, 240),
      painter: _LightPainter(.8 + .2 * _pulse.value),
    ),
  );
}

class _LightPainter extends CustomPainter {
  _LightPainter(this.strength);
  final double strength;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final path = Path()
      ..moveTo(center.dx, center.dy)
      ..cubicTo(86, 89, 42, 37, 56, 24)
      ..quadraticBezierTo(120, -5, 184, 24)
      ..cubicTo(198, 37, 154, 89, center.dx, center.dy)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: .9,
          colors: [
            KiwiLensColors.sky.withValues(alpha: .42 * strength),
            KiwiLensColors.sky.withValues(alpha: .12),
            Colors.transparent,
          ],
          stops: const [0, .5, 1],
        ).createShader(Rect.fromCircle(center: center, radius: 118))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
  }

  @override
  bool shouldRepaint(_LightPainter old) => old.strength != strength;
}
