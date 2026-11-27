import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../domain/map_provider.dart';
import '../domain/navigation_camera_mode.dart';
import '../theme/waybi_theme.dart';
import '../widgets/companion_search_prompt.dart';

// Small pieces of the home page's widget tree: the browse map's side
// controls, the search header and the route preview's start button.

/// The browse map's side controls: the parked car (Plus), saved places,
/// map layers, a road report and the location / camera-mode control.
class HomeMapControls extends StatelessWidget {
  const HomeMapControls({
    super.key,
    required this.language,
    required this.following,
    required this.cameraMode,
    required this.onSaved,
    required this.onLayers,
    required this.onReport,
    required this.onLocation,
    this.parkedCarLabel,
    this.onParkedCar,
  });

  final String language;

  /// The camera follows the puck; otherwise the control returns to it.
  final bool following;
  final NavigationCameraMode cameraMode;
  final VoidCallback onSaved, onLayers, onReport, onLocation;

  /// Shown with [onParkedCar] when a car park was remembered.
  final String? parkedCarLabel;
  final VoidCallback? onParkedCar;

  String _text(String en, String zh) => language == 'zh' ? zh : en;

  /// What tapping the location control does next.
  String get locationTooltip {
    if (!following) return _text('Return to my location', '回到我的位置');
    return switch (cameraMode.next) {
      NavigationCameraMode.headingUpPerspective => _text(
        'Switch to 3D view',
        '切换到 3D 视角',
      ),
      NavigationCameraMode.northUpFlat => _text(
        'Switch to north-up',
        '切换到北向俯视',
      ),
      NavigationCameraMode.headingUpFlat => _text(
        'Switch to heading-up',
        '切换到车头朝上俯视',
      ),
    };
  }

  IconData get _locationIcon {
    if (!following) return Icons.my_location_outlined;
    return cameraMode.northUp ? Icons.north_rounded : Icons.navigation_rounded;
  }

  @override
  Widget build(BuildContext context) {
    Widget button(String tooltip, Widget icon, VoidCallback onPressed) =>
        Material(
          color: Theme.of(context).colorScheme.surface,
          elevation: 5,
          borderRadius: BorderRadius.circular(14),
          child: IconButton(tooltip: tooltip, icon: icon, onPressed: onPressed),
        );
    final parked = parkedCarLabel;
    final buttons = [
      if (parked != null && onParkedCar != null)
        button(
          parked,
          const Icon(
            Icons.directions_car_filled_rounded,
            color: WaybiColors.ocean,
          ),
          onParkedCar!,
        ),
      button(
        _text('Saved places', '收藏地点'),
        const Icon(Icons.bookmark_outline_rounded),
        onSaved,
      ),
      button(
        _text('Map layers', '地图图层'),
        const Icon(Icons.layers_rounded),
        onLayers,
      ),
      button(
        _text('Report road issue', '上报道路情况'),
        const Icon(Icons.add_alert_rounded, color: WaybiColors.ocean),
        onReport,
      ),
      button(
        locationTooltip,
        Icon(
          _locationIcon,
          color: following ? WaybiColors.ocean : WaybiColors.deepOcean,
        ),
        onLocation,
      ),
    ];
    return Column(
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          buttons[i],
        ],
      ],
    );
  }
}

/// The search field (following the browse location), the shortcut chips
/// and "Search this area" after the map moved.
class HomeSearchHeader extends StatelessWidget {
  const HomeSearchHeader({
    super.key,
    required this.language,
    required this.marker,
    required this.location,
    required this.fallbackLocation,
    required this.loadSuggestions,
    required this.cachedSuggestions,
    required this.onSuggestionSelected,
    required this.onSearch,
    required this.quickActions,
    required this.showSearchArea,
    required this.onSearchArea,
  });

  final String language;
  final LocationMarkerStyle marker;
  final ValueListenable<GeoPoint?> location;

  /// Where suggestions are ranked from without a fix (the map's centre).
  final GeoPoint fallbackLocation;
  final Future<List<PlaceCandidate>> Function(String query) loadSuggestions;
  final List<PlaceCandidate> Function(String query) cachedSuggestions;
  final ValueChanged<PlaceCandidate> onSuggestionSelected;
  final ValueChanged<String> onSearch;
  final Widget quickActions;
  final bool showSearchArea;
  final VoidCallback onSearchArea;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      ValueListenableBuilder<GeoPoint?>(
        valueListenable: location,
        builder: (context, here, _) => CompanionSearchPrompt(
          marker: marker,
          language: language,
          currentLocation: here ?? fallbackLocation,
          loadSuggestions: loadSuggestions,
          cachedSuggestions: cachedSuggestions,
          onSuggestionSelected: onSuggestionSelected,
          onSearch: onSearch,
        ),
      ),
      const SizedBox(height: 9),
      quickActions,
      if (showSearchArea)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: FilledButton.icon(
            onPressed: onSearchArea,
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: Text(language == 'zh' ? '搜索此区域' : 'Search this area'),
          ),
        ),
    ],
  );
}

/// The route preview's floating start button.
class RouteStartButton extends StatelessWidget {
  const RouteStartButton({
    super.key,
    required this.language,
    required this.busy,
    required this.planning,
    required this.hasRoute,
    required this.transit,
    required this.needsDetour,
    required this.onShowAllRoutes,
    required this.onStart,
  });

  final String language;

  /// A start or a detour search is running.
  final bool busy;

  /// [busy] with a detour search.
  final bool planning;

  /// The filter left a route to start; otherwise the button shows them all.
  final bool hasRoute;
  final bool transit;
  final bool needsDetour;
  final VoidCallback onShowAllRoutes, onStart;

  String _text(String en, String zh) => language == 'zh' ? zh : en;

  @override
  Widget build(BuildContext context) => FloatingActionButton.extended(
    key: const Key('routeStartFloatingButton'),
    heroTag: 'route-start-floating',
    elevation: 9,
    onPressed: busy
        ? null
        : hasRoute
        ? onStart
        : onShowAllRoutes,
    backgroundColor: WaybiColors.ocean,
    foregroundColor: Colors.white,
    icon: busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
        : const Icon(Icons.navigation_rounded),
    label: Text(
      busy
          ? (planning
                ? _text('Planning…', '正在规划…')
                : _text('Starting…', '正在开始…'))
          : !hasRoute
          ? _text('Show all routes', '查看全部路线')
          : transit
          ? _text('Start trip', '开始行程')
          : needsDetour
          ? _text('Find detour', '规划绕行')
          : _text('Start', '开始导航'),
      style: const TextStyle(fontWeight: FontWeight.w700),
    ),
  );
}

/// Notifies listeners, but never while widgets are building: a source that
/// changes during a build (the drive engine starting a camera reload from a
/// page's initState) is passed on after that frame instead.
class FrameSafeNotifier extends ChangeNotifier {
  bool _scheduled = false;

  void ping() {
    final binding = SchedulerBinding.instance;
    if (binding.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      notifyListeners();
      return;
    }
    if (_scheduled) return;
    _scheduled = true;
    binding.addPostFrameCallback((_) {
      _scheduled = false;
      if (hasListeners) notifyListeners();
    });
  }
}
