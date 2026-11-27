import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart'
    show LatLng;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/parking_repository.dart';
import '../domain/geo_math.dart';
import '../domain/map_layer_settings.dart' show CameraKindLabel;
import '../domain/map_provider.dart';
import '../domain/road_event.dart';
import '../domain/route_option.dart';
import '../domain/route_preference.dart';
import '../domain/route_reachability.dart';
import '../domain/route_road_events.dart' as road_routes;
import '../domain/safety_camera.dart';
import '../drive/route_camera_matcher.dart';
import '../widgets/explore_search.dart' show DestinationSuggestion;
import '../widgets/friendly_error.dart';
import '../widgets/route_preview_sheet.dart' show RouteCameraSummary;
import 'place_selection_controller.dart';
import 'request_generation.dart';
import 'trip_state.dart';

/// Routes in one travel mode, for a preview or a detour.
typedef RoutePlanner = Future<RoutePlan> Function({
  required GeoPoint origin,
  required GeoPoint destination,
  required List<GeoPoint> stops,
  required WaybiTravelMode mode,
  required double? headingDegrees,
  required List<RouteExclusion> avoid,
});

/// Public-transport itineraries between two points.
typedef TransitPlanner = Future<RoutePlan> Function({
  required GeoPoint origin,
  required GeoPoint destination,
});

/// Car parks near a destination.
typedef ParkingLookup = Future<List<ParkingPlace>> Function(
  GeoPoint destination,
);

/// The route preview of the selected place: its plan, the chosen mode,
/// route, filter and stops, the car parks near the destination, the
/// public-transport merge and the detour search around closures.
///
/// [requests] is the trip's route generation. Choosing another place,
/// closing the preview or starting a trip makes every answer in flight
/// stale, so a late plan never comes back without its sheet. A reload (a
/// new stop, mode or language) keeps the plan on screen until its
/// replacement arrives, and a failed reload leaves it usable.
class RoutePreviewController extends ChangeNotifier {
  RoutePreviewController({
    required this.trip,
    required this.places,
    required this._planner,
    required this._transit,
    required this._parking,
    required this._routeLocation,
    required this._gpsLocation,
    required this._heading,
    required this._cameras,
    required this._roadEvents,
    required this._cameraDataReady,
    required this._setDriveRoute,
    required this._navigationOwnsRoute,
    required this._driveActive,
    required this.notice,
    required this._language,
    required this._showRoute,
    this._beforeLoad,
    this._onLoadStarted,
    this._recoverLocation,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final TripMachine trip;
  final PlaceSelectionController places;

  /// The page's status banner.
  final ValueNotifier<String?> notice;

  final RoutePlanner _planner;
  final TransitPlanner _transit;
  final ParkingLookup _parking;
  final GeoPoint? Function() _routeLocation;
  final GeoPoint? Function() _gpsLocation;
  final double? Function() _heading;
  final List<SafetyCamera> Function() _cameras;
  final List<RoadEvent> Function() _roadEvents;
  final bool Function() _cameraDataReady;
  final void Function(RouteOption? route) _setDriveRoute;
  final bool Function() _navigationOwnsRoute;
  final bool Function() _driveActive;
  final String Function() _language;
  final Future<void> Function() _showRoute;
  final VoidCallback? _beforeLoad;
  final void Function(WaybiTravelMode mode)? _onLoadStarted;
  final VoidCallback? _recoverLocation;
  final DateTime Function() _clock;
  bool _disposed = false;

  /// The trip's route requests: a preview, a detour or a start takes a
  /// token; another place, closing the preview or a trip invalidates them.
  final requests = RequestGeneration();
  final _parkingRequests = RequestGeneration();
  final _modeRequests = RequestGeneration();

  String _text(String en, String zh) => _language() == 'zh' ? zh : en;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  static GeoPoint _point(LatLng value) =>
      GeoPoint(value.latitude, value.longitude);

  // ---------------------------------------------------------------------
  // State

  RoutePlan? _plan;
  RoutePlan? get plan => _plan;

  WaybiTravelMode _mode = WaybiTravelMode.drive;

  /// The chosen travel mode; it stays with a trip started from the preview.
  WaybiTravelMode get mode => _mode;

  String? _selectedRouteId;
  String? get selectedRouteId => _selectedRouteId;

  RouteFilter _filter = RouteFilter.recommended;
  RouteFilter get filter => _filter;

  /// The detour search's progress or outcome, shown on the sheet.
  String? _recoveryMessage;
  String? get recoveryMessage => _recoveryMessage;

  Map<String, RouteCameraSummary> _cameraSummaries = const {};
  Map<String, RouteCameraSummary> get cameraSummaries => _cameraSummaries;
  Map<String, RoutePreferenceSummary> _preferenceSummaries = const {};
  Map<String, RoutePreferenceSummary> get preferenceSummaries =>
      _preferenceSummaries;

  final List<DestinationSuggestion> _stops = [];
  late final stops = UnmodifiableListView(_stops);

  DestinationSuggestion? _manualOrigin;

  /// A starting point other than here (from a navigation link).
  DestinationSuggestion? get manualOrigin => _manualOrigin;

  /// Where routes start: the link's origin, else the GPS route origin.
  GeoPoint? get origin {
    final manual = _manualOrigin;
    return manual == null ? _routeLocation() : _point(manual.location);
  }

  /// A custom origin has no travel direction to route from.
  double? get headingDegrees => _manualOrigin == null ? _heading() : null;

  List<ParkingPlace> _parkingPlaces = const [];
  List<ParkingPlace> get parkingPlaces => _parkingPlaces;
  ParkingPlace? _selectedParking;

  /// The car park the trip leads to, instead of the destination itself.
  ParkingPlace? get selectedParking => _selectedParking;
  PlaceSummary? _parkingOriginalPlace;

  /// The destination behind [selectedParking].
  PlaceSummary? get parkingOriginalPlace => _parkingOriginalPlace;
  bool _parkingLoading = false;
  bool get parkingLoading => _parkingLoading;

  /// A preview waiting for the first location fix.
  ({SelectedPlace selected, WaybiTravelMode mode})? _pending;
  bool get hasPending => _pending != null;
  void cancelPending() => _pending = null;

  /// Shows the preview for [selected] once a location fix arrives.
  void deferUntilLocated(SelectedPlace selected, WaybiTravelMode mode) =>
      _pending = (selected: selected, mode: mode);

  // ---------------------------------------------------------------------
  // Routes and closures

  final _closureCache =
      <
        String,
        ({
          RouteOption route,
          List<RoadEvent> events,
          DateTime checkedAt,
          List<RoadEvent> matches,
        })
      >{};

  /// Current closures on [route], cached for 30 s per route and events list.
  List<RoadEvent> closuresOn(RouteOption route) {
    final events = _roadEvents();
    final cached = _closureCache[route.id];
    final now = _clock();
    if (cached != null &&
        identical(cached.route, route) &&
        identical(cached.events, events) &&
        now.difference(cached.checkedAt).inSeconds < 30) {
      return cached.matches;
    }
    final matches = road_routes.routeClosures(route, events, now: now);
    if (_closureCache.length >= 12) {
      _closureCache.remove(_closureCache.keys.first);
    }
    _closureCache[route.id] = (
      route: route,
      events: events,
      checkedAt: now,
      matches: matches,
    );
    return matches;
  }

  /// The preview's routes in the chosen mode, through the filter; a route
  /// with an official closure counts as blocked.
  List<RouteOption> get filteredRoutes {
    final routes = _plan?.forMode(_mode).toList() ?? <RouteOption>[];
    if (_mode != WaybiTravelMode.drive) return routes;
    return filterRoutes(
      routes,
      _filter,
      _cameraDataReady() ? _preferenceSummaries : const {},
      blockedIds: {
        for (final route in routes)
          if (closuresOn(route)
              .any((e) => e.observation == RoadEventObservation.official))
            route.id,
      },
    );
  }

  RouteOption? get selectedRoute {
    final routes = filteredRoutes;
    return routes.where((route) => route.id == _selectedRouteId).firstOrNull ??
        routes.firstOrNull;
  }

  /// Starting [route] would need a detour first.
  bool needsRecovery(RouteOption route) =>
      route.blockedForDriving ||
      closuresOn(route)
          .any((e) => e.observation == RoadEventObservation.official);

  /// Closures by route id, for the sheet.
  Map<String, List<RoadEvent>> get closuresByRoute => {
    for (final route in _plan?.forMode(_mode) ?? const <RouteOption>[])
      route.id: closuresOn(route),
  };

  ({
    (RoutePlan, WaybiTravelMode, String?, RouteFilter, bool, List<RoadEvent>)
    key,
    List<MapRoutePath> value,
  })?
  _pathsMemo;

  /// The preview's paths for the map. The same list is returned until the
  /// plan, mode, selection, filter or closures change.
  List<MapRoutePath> get paths {
    final plan = _plan;
    if (plan == null) return const [];
    final key = (
      plan,
      _mode,
      _selectedRouteId,
      _filter,
      _cameraDataReady(),
      _roadEvents(),
    );
    final memo = _pathsMemo;
    if (memo != null &&
        identical(memo.key.$1, key.$1) &&
        memo.key.$2 == key.$2 &&
        memo.key.$3 == key.$3 &&
        memo.key.$4 == key.$4 &&
        memo.key.$5 == key.$5 &&
        identical(memo.key.$6, key.$6)) {
      return memo.value;
    }
    final value = filteredRoutes
        .map(
          (route) => MapRoutePath(
            id: route.id,
            points: route.points,
            active: route.id == _selectedRouteId,
          ),
        )
        .toList(growable: false);
    _pathsMemo = (key: key, value: value);
    return value;
  }

  Map<String, RouteCameraSummary> _summarizeCameras(RoutePlan plan) {
    const matcher = RouteCameraMatcher();
    final cameras = _cameras();
    final summaries = <String, RouteCameraSummary>{};
    for (final route in plan.options) {
      if (route.mode != WaybiTravelMode.drive) {
        summaries[route.id] = const RouteCameraSummary();
        continue;
      }
      final matches = matcher.match(route, cameras);
      final types = <String>{
        for (final match in matches)
          CameraKindLabel.fromCamera(match.camera).label,
      };
      summaries[route.id] = RouteCameraSummary(
        count: matches.length,
        types: types.toList(growable: false),
      );
    }
    return summaries;
  }

  static Map<String, RoutePreferenceSummary> _summarizePreferences(
    RoutePlan plan,
    Map<String, RouteCameraSummary> cameraSummaries,
  ) => {
    for (final route in plan.options)
      if (route.mode == WaybiTravelMode.drive)
        route.id: RoutePreferenceSummary(
          cameraCount: cameraSummaries[route.id]?.count ?? 0,
          congestionScore:
              (route.trafficDelaySeconds ?? 0) +
              route.traffic.trafficJam * 300 +
              route.traffic.slow * 90,
        ),
  };

  /// The engine's cameras changed: recount them on the plan. The page
  /// redraws for the engine on its own.
  void refreshSummaries() {
    final plan = _plan;
    if (plan == null) return;
    _cameraSummaries = _summarizeCameras(plan);
    _preferenceSummaries = _summarizePreferences(plan, _cameraSummaries);
  }

  // ---------------------------------------------------------------------
  // Lifecycle of a preview

  /// Drops the drive route unless guidance owns it: a navigation that is
  /// starting notices its cancelled request and stops the engine itself.
  void releaseDriveRoute() {
    if (!_navigationOwnsRoute()) _setDriveRoute(null);
  }

  void _resetPlan() {
    _plan = null;
    _selectedRouteId = null;
    _mode = WaybiTravelMode.drive;
    _recoveryMessage = null;
    _filter = RouteFilter.recommended;
    _stops.clear();
  }

  void _resetParking() {
    _parkingRequests.invalidate();
    _parkingPlaces = const [];
    _parkingOriginalPlace = null;
    _selectedParking = null;
    _parkingLoading = false;
  }

  /// A new place supersedes the last place's preview, ETA, parking and
  /// start. Its mode, filter and stops stay.
  void beginPlace() {
    requests.invalidate();
    trip.dispatch(const PlaceChosen());
    _recoveryMessage = null;
    _resetParking();
    _plan = null;
    _selectedRouteId = null;
    _changed();
  }

  /// Back to the browse map: the preview, its place, stops and parking go.
  void clear() {
    requests.invalidate();
    _parkingRequests.invalidate();
    releaseDriveRoute();
    trip.dispatch(const PlaceCleared());
    _resetPlan();
    places.clear();
    _resetParking();
    _changed();
  }

  /// Back from the preview to its place card, which stays selected.
  void closeToPlace() {
    requests.invalidate();
    _parkingRequests.invalidate();
    releaseDriveRoute();
    trip.dispatch(const PreviewClosed());
    _resetPlan();
    _parkingPlaces = const [];
    _parkingLoading = false;
    _changed();
  }

  /// A navigation link chose the origin, stops and mode; it supersedes any
  /// preview in flight.
  void applyLink({
    required DestinationSuggestion? origin,
    required List<DestinationSuggestion> stops,
    required WaybiTravelMode mode,
  }) {
    requests.invalidate();
    _manualOrigin = origin;
    _stops
      ..clear()
      ..addAll(stops);
    _mode = mode;
    _changed();
  }

  /// Guidance took over: the preview closes; its mode and car park stay
  /// with the trip.
  void handOffToGuidance() {
    _plan = null;
    _selectedRouteId = null;
    _stops.clear();
    _changed();
  }

  /// A public-transport trip took over: nothing of the preview (its
  /// alternatives, parking or drive route) stays on the map.
  void handOffToTransit() {
    requests.invalidate();
    _parkingRequests.invalidate();
    _setDriveRoute(null);
    _plan = null;
    _selectedRouteId = null;
    _stops.clear();
    _recoveryMessage = null;
    _resetParking();
    _changed();
  }

  static bool _samePlaceLocation(PlaceSummary a, PlaceSummary? b) =>
      b != null &&
      a.location.latitude == b.location.latitude &&
      a.location.longitude == b.location.longitude;

  /// A location fix arrived: shows the preview that waited for one, if its
  /// place is still selected. Reverse geocoding replaces the selection with
  /// an enriched copy of the same place, so it matches by location.
  void retryPending() {
    final pending = _pending;
    if (pending == null) return;
    if (!_samePlaceLocation(pending.selected.place, places.selected?.place) ||
        _driveActive() ||
        trip.value is TripTransit) {
      _pending = null;
      return;
    }
    if (_routeLocation() == null ||
        places.selected == null ||
        trip.value.busy) {
      return;
    }
    _pending = null;
    unawaited(load(mode: pending.mode));
  }

  /// Plans routes to the selected place in [mode]. Without a location the
  /// preview waits for the first fix instead.
  Future<void> load({WaybiTravelMode mode = WaybiTravelMode.drive}) async {
    _beforeLoad?.call();
    _pending = null;
    final selected = places.selected;
    if (selected == null) return;
    final destination = selected.place.location;
    final origin = this.origin;
    if (origin == null) {
      _pending = (selected: selected, mode: mode);
      notice.value = _text(
        'Getting your location. The route will appear automatically.',
        '正在获取位置，定位成功后会自动显示路线。',
      );
      _recoverLocation?.call();
      return;
    }
    final stops = [for (final stop in _stops) _point(stop.location)];
    if (isCrossTasmanSurfaceRoute([origin, ...stops, destination])) {
      trip.dispatch(PreviewSettled(hasPlan: _plan != null));
      notice.value = const NoSurfaceRouteException().localized(_language());
      return;
    }
    final token = requests.next();
    // A reload keeps the loaded plan and mode on screen until the
    // replacement arrives; a failure leaves them usable.
    trip.dispatch(const PreviewRequested());
    _recoveryMessage = null;
    notice.value = null;
    _changed();
    if (mode == WaybiTravelMode.drive && _selectedParking == null) {
      unawaited(_loadParking(selected.place));
    }
    _onLoadStarted?.call(mode);
    try {
      final plan = await _planner(
        origin: origin,
        destination: destination,
        stops: stops,
        mode: mode,
        headingDegrees: mode == WaybiTravelMode.drive ? headingDegrees : null,
        avoid: const [],
      );
      final cameraSummaries = _summarizeCameras(plan);
      final preferenceSummaries = _summarizePreferences(plan, cameraSummaries);
      final preferred = plan.forMode(mode).take(3).toList(growable: false);
      final open = preferred
          .where((route) => closuresOn(route).isEmpty)
          .toList(growable: false);
      final route = mode == WaybiTravelMode.drive
          ? recommendedRoute(
              open.isEmpty ? preferred : open,
              preferenceSummaries,
            )
          : preferred.firstOrNull;
      if (_disposed || token.isStale) return;
      _plan = plan;
      _cameraSummaries = cameraSummaries;
      _preferenceSummaries = preferenceSummaries;
      _filter = RouteFilter.recommended;
      _mode = mode;
      _selectedRouteId = route?.id;
      _changed();
      _setDriveRoute(mode == WaybiTravelMode.drive ? route : null);
      await _showRoute();
    } catch (error) {
      if (!_disposed && token.isCurrent) {
        notice.value = routeFailureMessage(error, _language());
      }
    } finally {
      if (!_disposed && token.isCurrent) {
        trip.dispatch(PreviewSettled(hasPlan: _plan != null));
      }
    }
  }

  /// Adds a stop before the destination and plans again.
  Future<void> addStop(DestinationSuggestion stop) async {
    _stops.add(stop);
    _changed();
    await load(mode: _mode);
  }

  void selectRoute(RouteOption route) {
    _selectedRouteId = route.id;
    _changed();
    _setDriveRoute(route.mode == WaybiTravelMode.drive ? route : null);
    unawaited(_showRoute());
  }

  void selectFilter(RouteFilter filter) {
    _filter = filter;
    _selectedRouteId = filteredRoutes.firstOrNull?.id;
    _recoveryMessage = null;
    _changed();
    _setDriveRoute(selectedRoute);
    unawaited(_showRoute());
  }

  /// Switches the travel mode: uses the plan's routes, loads transit, or
  /// plans again. The last tapped mode wins: a slow transit answer must not
  /// flip a later Drive choice back to Transit.
  Future<void> selectMode(WaybiTravelMode mode) async {
    final plan = _plan;
    if (plan == null) return;
    final selection = _modeRequests.next();
    final token = requests.current;
    var routes = plan.forMode(mode).take(3).toList(growable: false);
    if (routes.isEmpty && mode == WaybiTravelMode.transit) {
      routes = await loadTransit();
      if (_disposed || selection.isStale || token.isStale) return;
    }
    if (routes.isEmpty) {
      if (places.selected != null && mode != WaybiTravelMode.transit) {
        await load(mode: mode);
      }
      return;
    }
    final selected = mode == WaybiTravelMode.drive
        ? recommendedRoute(routes, _preferenceSummaries) ?? routes.first
        : routes.first;
    _mode = mode;
    _selectedRouteId = selected.id;
    _changed();
    _setDriveRoute(mode == WaybiTravelMode.drive ? selected : null);
    await _showRoute();
  }

  /// The transit provider's answer for "the network has no itinerary".
  static bool isNoTransitRoute(Object error) =>
      error is StateError &&
      error.message.startsWith('No public-transport route');

  /// Adds public-transport itineraries to the plan. Closing the preview or
  /// picking another place invalidates the request: a late answer must not
  /// revive a plan with no sheet (a ghost route).
  Future<List<RouteOption>> loadTransit() async {
    final selected = places.selected;
    final manual = _manualOrigin;
    final origin = manual == null ? _gpsLocation() : _point(manual.location);
    if (selected == null || origin == null || _plan == null) return const [];
    final token = requests.current;
    bool current() => !_disposed && token.isCurrent;
    final calculating = _text('Calculating public transport…', '正在计算公交路线…');
    String noTransit() => _text(
      'No public transport routes were found for this trip.',
      '这段行程暂时没有可用的公共交通路线。',
    );
    trip.dispatch(const TransitLoadStarted());
    notice.value = calculating;
    try {
      final transitPlan = await _transit(
        origin: origin,
        destination: selected.place.location,
      );
      final transit = transitPlan
          .forMode(WaybiTravelMode.transit)
          .take(3)
          .toList(growable: false);
      final latest = _plan;
      if (!current() || latest == null) return const [];
      if (transit.isEmpty) {
        notice.value = noTransit();
        return transit;
      }
      _plan = RoutePlan(
        options: [
          ...latest.options.where(
            (route) => route.mode != WaybiTravelMode.transit,
          ),
          ...transit,
        ],
        trafficAvailable: latest.trafficAvailable,
        provider: latest.provider,
        stopsApplied: latest.stopsApplied,
      );
      notice.value = null;
      _changed();
      return transit;
    } catch (error) {
      if (current()) {
        notice.value = isNoTransitRoute(error)
            ? noTransit()
            : _text(
                'Could not calculate public transport. ${friendlyErrorMessage(error, _language())}',
                '公交路线计算失败。${friendlyErrorMessage(error, _language())}',
              );
      }
      return const [];
    } finally {
      if (current()) {
        trip.dispatch(PreviewSettled(hasPlan: _plan != null));
      } else if (!_disposed && notice.value == calculating) {
        notice.value = null;
      }
    }
  }

  /// Plans around the selected route's closures: switches to a clear
  /// alternative when there is one, else asks for a detour that avoids
  /// them, keeping the plan's other modes.
  Future<void> recoverBlockedRoute() async {
    final previous = selectedRoute;
    final selected = places.selected;
    final plan = _plan;
    if (trip.value.busy ||
        previous == null ||
        selected == null ||
        plan == null) {
      return;
    }
    final existing = filteredRoutes
        .where((route) => !needsRecovery(route))
        .firstOrNull;
    if (existing != null) {
      selectRoute(existing);
      _recoveryMessage = _text(
        'A clear alternative is selected. Start when ready.',
        '已切换到可通行的备选路线，可开始导航。',
      );
      _changed();
      return;
    }
    final origin = this.origin;
    if (origin == null) {
      _recoveryMessage = _text(
        'Waiting for your location. Try again when GPS is ready.',
        '正在获取位置，请定位成功后重试绕行。',
      );
      _changed();
      _recoverLocation?.call();
      return;
    }
    final token = requests.next();
    trip.dispatch(const DetourStarted());
    _recoveryMessage = _text(
      'Finding a route around closed roads…',
      '正在避开封闭路段规划路线…',
    );
    _changed();
    try {
      final result = await _planner(
        origin: origin,
        destination: selected.place.location,
        stops: [for (final stop in _stops) _point(stop.location)],
        mode: WaybiTravelMode.drive,
        headingDegrees: headingDegrees,
        avoid: road_routes.closureExclusions(previous, closuresOn(previous)),
      );
      if (_disposed || token.isStale) return;
      final clear = result.options
          .where((route) => !needsRecovery(route))
          .toList();
      if (clear.isEmpty) throw StateError('No verified detour');
      final updated = RoutePlan(
        options: [
          ...clear,
          ...plan.options.where((route) => route.mode != WaybiTravelMode.drive),
        ],
        trafficAvailable: result.trafficAvailable,
        provider: result.provider,
        stopsApplied: result.stopsApplied,
      );
      _plan = updated;
      _cameraSummaries = _summarizeCameras(updated);
      _preferenceSummaries = _summarizePreferences(updated, _cameraSummaries);
      _selectedRouteId = filteredRoutes.firstOrNull?.id;
      _recoveryMessage = _selectedRouteId == null
          ? _text(
              'A detour is available. Change your filter to view it.',
              '已找到绕行路线，请切换筛选条件查看。',
            )
          : _text(
              'Detour ready. Review the route and start navigation.',
              '已规划绕行路线，确认后可开始导航。',
            );
      _changed();
      _setDriveRoute(selectedRoute);
      await _showRoute();
    } catch (_) {
      if (!_disposed && token.isCurrent) {
        _recoveryMessage = _text(
          'No verified detour is available right now. Retry or add a stop to try a different road.',
          '暂未找到可通行的绕行路线，请重试或添加途经点换一条路。',
        );
        _changed();
      }
    } finally {
      if (!_disposed && token.isCurrent) {
        trip.dispatch(PreviewSettled(hasPlan: _plan != null));
      }
    }
  }

  // ---------------------------------------------------------------------
  // Parking

  Future<void> _loadParking(PlaceSummary destination) async {
    final token = _parkingRequests.next();
    _parkingPlaces = const [];
    _parkingLoading = true;
    _changed();
    try {
      final found = await _parking(destination.location);
      if (_disposed || token.isStale) return;
      _parkingPlaces = found;
    } catch (_) {
      if (_disposed || token.isStale) return;
      _parkingPlaces = const [];
    }
    _parkingLoading = false;
    _changed();
  }

  void _show(PlaceSummary place) => places.replace(
    SelectedPlace(
      place,
      SelectionSource.map,
      originMap: MapProvider.independent,
    ),
  );

  /// Leads the preview to [parking]; the destination stays as the final
  /// stop on foot.
  Future<void> selectParking(ParkingPlace parking) async {
    final original = _parkingOriginalPlace ?? places.selected?.place;
    if (original == null) return;
    _parkingRequests.invalidate();
    _parkingOriginalPlace = original;
    _selectedParking = parking;
    _parkingLoading = false;
    _show(parking.toPlaceSummary());
    _stops.clear();
    _changed();
    await load();
  }

  /// Back from a car park to the destination itself.
  Future<void> restoreDirectDestination() async {
    final original = _parkingOriginalPlace;
    if (original == null) return;
    _parkingOriginalPlace = null;
    _selectedParking = null;
    _show(original);
    _changed();
    await load();
  }

  /// Guidance to [destination] ended for one of its car parks: the next
  /// preview leads to [parking].
  void targetParking(PlaceSummary destination, ParkingPlace parking) {
    trip.dispatch(const PlaceChosen());
    _parkingOriginalPlace = destination;
    _selectedParking = parking;
    _show(parking.toPlaceSummary());
    _stops.clear();
    _changed();
  }

  /// Parked: walks from here to the destination behind the car park.
  Future<void> continueOnFoot() async {
    final original = _parkingOriginalPlace;
    if (original == null) return;
    trip.dispatch(const PlaceChosen());
    _parkingOriginalPlace = null;
    _selectedParking = null;
    _parkingPlaces = const [];
    _manualOrigin = null;
    _stops.clear();
    _show(original);
    _changed();
    await load(mode: WaybiTravelMode.walk);
  }

  /// The parking leg was dismissed.
  void forgetParkingTarget() {
    _parkingOriginalPlace = null;
    _selectedParking = null;
    _changed();
  }

  // ---------------------------------------------------------------------
  // Saved routes

  /// Coordinates picked in Google's place UI this session; a saved route
  /// keeps Waybi's own road geometry instead of them.
  final Set<(double, double)> _sessionCoordinates = {};

  void rememberSessionCoordinate(GeoPoint point) =>
      _sessionCoordinates.add((point.latitude, point.longitude));

  /// Saves the selected route on this device (the last 20, one per
  /// destination). False when nothing is selected.
  Future<bool> saveCurrentRoute() async {
    final place = places.selected?.place;
    final selected = selectedRoute;
    if (place == null || selected == null) return false;
    GeoPoint savedPoint(GeoPoint point) {
      if (!_sessionCoordinates.contains((point.latitude, point.longitude)) ||
          selected.points.isEmpty) {
        return point;
      }
      // Persist Valhalla's independent road geometry rather than Google's.
      double away(GeoPoint p) => distanceMeters(
        p.latitude,
        p.longitude,
        point.latitude,
        point.longitude,
      );
      return selected.points.reduce((a, b) => away(a) < away(b) ? a : b);
    }

    final destination = savedPoint(place.location);
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('waybi.saved.routes') ?? <String>[];
    final record = jsonEncode({
      'savedAt': _clock().toIso8601String(),
      'destination': {
        'name': place.name,
        'latitude': destination.latitude,
        'longitude': destination.longitude,
      },
      'mode': selected.mode.apiValue,
      'provider': selected.provider,
      'durationSeconds': selected.durationSeconds,
      'distanceMeters': selected.distanceMeters,
      'stops': [
        for (final stop in _stops)
          if (savedPoint(_point(stop.location)) case final point)
            {
              'label': stop.label,
              'latitude': point.latitude,
              'longitude': point.longitude,
            },
      ],
    });
    saved.removeWhere((item) {
      try {
        final existing = jsonDecode(item) as Map<String, dynamic>;
        final destination = existing['destination'] as Map<String, dynamic>?;
        return destination?['name'] == place.name;
      } catch (_) {
        return false;
      }
    });
    saved.insert(0, record);
    if (saved.length > 20) saved.removeRange(20, saved.length);
    await prefs.setStringList('waybi.saved.routes', saved);
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    requests.invalidate();
    _parkingRequests.invalidate();
    _modeRequests.invalidate();
    super.dispose();
  }
}
