import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:kiwi_lens_mobile/domain/map_provider.dart';
import 'package:kiwi_lens_mobile/domain/map_layer_settings.dart';
import 'package:kiwi_lens_mobile/drive/drive_engine.dart';
import 'package:kiwi_lens_mobile/providers/independent_map_renderer.dart';
import 'package:kiwi_lens_mobile/providers/provider_contracts.dart';
import 'package:kiwi_lens_mobile/providers/place_search_providers.dart';
import 'package:kiwi_lens_mobile/widgets/full_screen_search.dart';
import 'package:kiwi_lens_mobile/theme/kiwi_lens_theme.dart';
import 'package:kiwi_lens_mobile/widgets/navigation_overlay.dart';
import 'package:kiwi_lens_mobile/widgets/arrival_experience_panel.dart';

final _night = ValueNotifier(false);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  runApp(
    ValueListenableBuilder<bool>(
      valueListenable: _night,
      builder: (_, dark, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: KiwiLensTheme.lightFor('zh'),
        darkTheme: KiwiLensTheme.darkFor('zh'),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: const _Preview(),
      ),
    ),
  );
}

class _Preview extends StatefulWidget {
  const _Preview();
  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  final _drive = DriveEngine();
  final _search = IndependentSearchProvider();
  bool _browse = false;
  PlaceSummary? _selected;
  MapRenderer? _map;
  Timer? _gpsTick;
  @override
  void initState() {
    super.initState();
    _gpsTick = Timer.periodic(const Duration(seconds: 2), (_) => _follow());
  }

  bool _following = true;
  double _top = 130, _bottom = 215;
  static const _location = GeoPoint(-36.8485, 174.7633);
  void _follow() {
    if (!_following || _map == null) return;
    _map!.moveTo(_map!.viewport.copyWith(center: _location));
  }

  @override
  void dispose() {
    _gpsTick?.cancel();
    _drive.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.all(6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '样例行程 · ${_following ? "跟车" : "自由浏览"} · 缩放 ${_map?.viewport.zoom.toStringAsFixed(1) ?? "17"}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                IconButton(
                  tooltip: '地点搜索',
                  icon: const Icon(Icons.search),
                  iconSize: 18,
                  onPressed: () async {
                    final place = await Navigator.of(context)
                        .push<PlaceSummary>(
                          MaterialPageRoute(
                            builder: (_) => FullScreenSearch(
                              provider: _search,
                              resolve: (candidate) async =>
                                  candidate.toPlace(candidate.location!),
                              language: 'zh',
                              recent: const [],
                              currentLocation: _location,
                            ),
                          ),
                        );
                    if (!mounted || place == null) return;
                    setState(() {
                      _selected = place;
                      _browse = true;
                      _following = false;
                    });
                    (_map as PlaceFocusMapRenderer?)?.focusPlace(
                      place.location,
                      bottomInset: 90,
                    );
                  },
                ),
                IconButton(
                  tooltip: '切换浏览与导航预览',
                  icon: const Icon(Icons.map_outlined),
                  iconSize: 18,
                  onPressed: () => setState(() => _browse = !_browse),
                ),
                IconButton(
                  tooltip: '切换日夜预览',
                  onPressed: () => _night.value = !_night.value,
                  icon: const Icon(Icons.brightness_6_outlined),
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: IndependentMapRenderer(
                  initialViewport: const MapViewportState(
                    center: _location,
                    zoom: 17,
                  ),
                  layers: const MapLayerSettings(),
                  locationMarker: LocationMarkerStyle.kiwi,
                  locationEnabled: true,
                  following: _following,
                  moving: true,
                  language: 'zh',
                  cameras: const [],
                  onCamera: (_) {},
                  roadEvents: const [],
                  onRoadEvent: (_) {},
                  trafficSegments: const [],
                  route: _browse
                      ? const []
                      : const [
                          GeoPoint(-36.8470, 174.7641),
                          _location,
                          GeoPoint(-36.8500, 174.7625),
                        ],
                  selectedPlace: _selected,
                  explorePlaces: const [],
                  onExplorePlace: (_) {},
                  location: _location,
                  heading: 205,
                  contentPadding: _browse
                      ? const EdgeInsets.only(bottom: 55)
                      : EdgeInsets.fromLTRB(16, _top, 16, _bottom),
                  onReady: (renderer) {
                    _map = renderer;
                    _follow();
                  },
                  onViewportChanged: (_) {},
                  onMapPlace: (place) {
                    setState(() => _selected = place);
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(place.name)));
                  },
                  onBlankTap: () {},
                  onUserPan: () {
                    if (_following) setState(() => _following = false);
                  },
                ),
              ),
              if (!_browse)
                Positioned.fill(
                  child: NavigationOverlay(
                    engine: _drive,
                    language: 'zh',
                    guidance: const NavigationGuidance(
                      instruction: '右转进入 Queen Street',
                      maneuverIcon: Icons.turn_right_rounded,
                      stepMeters: 90,
                      remainingMeters: 180,
                      remainingSeconds: 45,
                      lanes: [
                        NavigationLane('↑', false),
                        NavigationLane('→', true),
                      ],
                    ),
                    destinationTitle: 'Aotea Square',
                    gpsAccuracy: 8,
                    voiceEnabled: true,
                    lanesEnabled: true,
                    northUp: false,
                    perspectiveAvailable: false,
                    following: _following,
                    onTopInsetChanged: (inset) {
                      setState(() => _top = inset);
                      _follow();
                    },
                    onBottomInsetChanged: (inset) {
                      setState(() => _bottom = inset);
                      _follow();
                    },
                    onEnd: () {},
                    onRecenter: () {
                      setState(() => _following = true);
                      _follow();
                    },
                    onOverview: () {
                      setState(() => _following = false);
                      (_map as RouteMapRenderer?)?.fitRoute(const [
                        GeoPoint(-36.8470, 174.7641),
                        GeoPoint(-36.8500, 174.7625),
                      ], bottomInset: _bottom);
                    },
                    onCompassToggle: () {},
                    onReport: () {},
                    onSearchAlongRoute: () {},
                    onDirections: () {},
                    onShare: () {},
                    onSettings: () {},
                    onLayers: () {},
                    onVoiceToggle: () {},
                    onLanesToggle: () {},
                    arrivalPanel: ArrivalExperiencePanel(
                      language: 'zh',
                      destinationTitle: 'Aotea Square',
                      remainingMeters: 180,
                      photoUrl: null,
                      parkingPlaces: const [],
                      parkingLoading: false,
                      onParkingSelected: (_) {},
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
