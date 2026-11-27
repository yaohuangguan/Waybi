import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:google_navigation_flutter/google_navigation_flutter.dart'
    show LatLng;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_friends/waybi_friends.dart' show JourneyMemory;

import '../data/navigation_feedback_repository.dart';
import '../data/navigation_reward_repository.dart';
import '../data/parking_repository.dart';
import '../data/place_details_repository.dart';
import '../domain/geo_math.dart';
import '../domain/map_provider.dart';
import '../domain/navigation_camera_mode.dart';
import '../domain/navigation_link.dart';
import '../domain/route_option.dart';
import '../domain/transit_lane.dart';
import '../drive/drive_engine.dart';
import '../drive/journey_tracker.dart';
import '../drive/navigation_language.dart';
import '../drive/navigation_location_filter.dart' show NavigationLocationFix;
import '../drive/route_progress_tracker.dart';
import '../drive/system_navigation.dart';
import '../drive/voice_prompts.dart';
import '../providers/independent_navigation_engine.dart';
import '../services/external_navigation_inbox.dart';
import '../widgets/explore_search.dart' show DestinationSuggestion;
import '../widgets/friendly_error.dart';
import '../widgets/waybi_format.dart';
import 'journey_store.dart';
import 'offline_corridor.dart';
import 'place_selection_controller.dart';
import 'request_generation.dart';
import 'road_alerts.dart';
import 'route_preview_controller.dart';
import 'trip_state.dart';

/// What a trip asks of the home screen around it: the map camera, the
/// browse GPS feed, and the screens of a navigation-link hand-off.
abstract interface class TripHost {
  /// Forgets the camera's smoothing before a trip moves it; [drive] also
  /// re-arms Just Drive's automatic follow.
  void resetTripCamera({required bool drive});

  /// Follows the puck again and leaves the route overview; a [mode] also
  /// switches the camera mode.
  void followTrip([NavigationCameraMode? mode]);

  void setTripCameraMode(NavigationCameraMode mode);

  /// Moves the map camera soon.
  void refreshTripMap();

  /// Restarts the traffic layer's refresh, which stopping the engine ended.
  void resumeTrafficRefresh();

  /// The browse fix, if any.
  GeoPoint? get browseLocation;
  Position? get lastReliablePosition;
  Future<bool> ensureLocationPermission();

  /// Pauses the browse feed while the drive engine owns location.
  Future<void> pauseBrowseLocation();
  Future<void> startBrowseLocation();

  /// Closes the place card or preview, including its map padding.
  Future<void> clearPreview();

  /// Shows the end-of-trip summary.
  void showJourneySummary(
    JourneySummary summary,
    Future<JourneyMemory?>? reward,
  );

  /// The page is ready for a navigation link (settings restored, in the
  /// foreground).
  bool get handOffReady;
  void popToHome();

  /// Asks whether to end the current trip for a link to [destination].
  Future<bool> confirmSwitchTrip(String destination);

  /// Lets the person pick the place a link names; null when cancelled.
  Future<PlaceSummary?> searchHandOffTarget(
    String query,
    String purpose,
    bool Function() current,
  );
  void showHandOffError(String message);
  void selectHandOffPlace(PlaceSummary place);

  /// Runs [callback] after the next frame.
  void afterFrame(VoidCallback callback);
}

/// A trip from start to end: turn-by-turn guidance (arrival, the parking
/// leg, the offline corridor, the Lock Screen / notification surface and
/// the journey record), Just Drive, a public-transport trip, and navigation
/// links handed over by other apps. Every state change goes through [trip].
///
/// Starting takes a token from the preview's route generation, so closing
/// the preview, choosing another place or pressing back while it awaits
/// lane matching, permission or the engine cancels it. Ending always ends:
/// whatever fails, the page returns to browsing.
class NavigationSessionController extends ChangeNotifier {
  NavigationSessionController({
    required this.trip,
    required this.preview,
    required this.places,
    required this.drive,
    required this.guidance,
    required this.system,
    required this.host,
    required this.notice,
    required this._roadAlerts,
    required this._journeys,
    required this._rewards,
    required this._feedback,
    required this._parking,
    required this._fetchDetails,
    required this._isPlus,
    required this._hasAccount,
    required this._language,
    ExternalNavigationInbox? inbox,
    Future<void> Function()? requestNotificationPermission,
    DateTime Function()? clock,
  }) : _inbox = inbox ?? ExternalNavigationInbox.instance,
       _requestNotificationPermission =
           requestNotificationPermission ??
           (() => Permission.notification.request()),
       _clock = clock ?? DateTime.now {
    guidance.addListener(_onGuidanceChanged);
    drive.addListener(_onDriveChanged);
    _inbox.addListener(scheduleHandOff);
  }

  final TripMachine trip;
  final RoutePreviewController preview;
  final PlaceSelectionController places;
  final DriveEngine drive;
  final IndependentNavigationEngine guidance;
  final SystemNavigation system;
  final TripHost host;

  /// The page's status banner.
  final ValueNotifier<String?> notice;

  final RoadAlerts _roadAlerts;
  final JourneyStore _journeys;
  final NavigationRewardRepository _rewards;
  final NavigationFeedbackRepository _feedback;
  final ParkingLookup _parking;
  final Future<PlaceDetails> Function(PlaceSummary place) _fetchDetails;
  final bool Function() _isPlus;
  final bool Function() _hasAccount;
  final String Function() _language;
  final ExternalNavigationInbox _inbox;
  final Future<void> Function() _requestNotificationPermission;
  final DateTime Function() _clock;
  bool _disposed = false;

  String _text(String en, String zh) => _language() == 'zh' ? zh : en;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  TripState get _state => trip.value;

  // ---------------------------------------------------------------------
  // State

  RouteOption? _activeRoute;

  /// The route guidance follows (updated by reroutes without a rebuild).
  RouteOption? get activeRoute => _activeRoute;

  RouteOption? _transitRoute;

  /// The itinerary of a public-transport trip.
  RouteOption? get transitRoute => _transitRoute;
  List<MapRoutePath>? _transitPaths;

  /// The transit trip's path for the map (the same list for the trip).
  List<MapRoutePath> get transitPaths {
    final route = _transitRoute;
    if (route == null) return const [];
    return _transitPaths ??= List.unmodifiable([
      MapRoutePath(id: route.id, points: route.points, active: true),
    ]);
  }

  String? _destinationTitle;
  String get destinationTitle =>
      _destinationTitle ?? _text('Destination', '目的地');

  PlaceSummary? _destination;

  /// The place guidance leads to.
  PlaceSummary? get destination => _destination;

  PlaceDetails? _arrivalDetails;
  PlaceDetails? get arrivalDetails => _arrivalDetails;
  List<ParkingPlace> _arrivalParking = const [];

  /// Car parks near the destination, offered on arrival (Plus).
  List<ParkingPlace> get arrivalParking => _arrivalParking;
  bool _arrivalPrefetching = false;
  bool get arrivalPrefetching => _arrivalPrefetching;
  bool _arrivalPrefetched = false;
  final _arrivalRequests = RequestGeneration();

  DateTime? _corridorCachedAt;

  /// When the offline corridor was last saved.
  DateTime? get corridorCachedAt => _corridorCachedAt;
  bool _offlineReady = false;

  /// The next stretch of the route is saved for a dead zone (Plus).
  bool get offlineReady => _offlineReady;

  JourneyTracker? _journey;
  Future<String?>? _journeyCountry;

  bool _keepScreenAwake = true;
  bool get keepScreenAwake => _keepScreenAwake;

  void _resetArrival() {
    _arrivalPrefetching = false;
    _arrivalPrefetched = false;
    _arrivalParking = const [];
    _arrivalDetails = null;
  }

  /// Metres left on the guided route.
  double? get remainingMeters {
    if (guidance.active) return guidance.remainingDistanceMeters;
    final route = _activeRoute;
    final progress = drive.routeProgress;
    if (route == null || progress == null || route.points.length < 2) {
      return null;
    }
    final geometry = RouteProgressTracker.geometryLength(route.points);
    if (geometry <= 0) return route.distanceMeters.toDouble();
    final fraction = (progress.alongMeters / geometry).clamp(0.0, 1.0);
    return route.distanceMeters * (1 - fraction);
  }

  // ---------------------------------------------------------------------
  // Engines

  void _onGuidanceChanged() {
    if (_disposed) return;
    final route = guidance.route;
    if (route != null) _activeRoute = route;
    // The HUD, the arrival panel and the map listen to the engine themselves.
    if (_state.guidanceRunning) unawaited(system.update(systemState()));
    _updateArrival();
    unawaited(_cacheCorridor());
  }

  void _onDriveChanged() {
    if (_disposed) return;
    if (_state == const TripJustDrive() && !drive.active) {
      // The engine stopped on its own (for example location was revoked).
      trip.dispatch(const DriveEnded());
    }
    if (_state.guidanceRunning) unawaited(system.update(systemState()));
    _journey?.cameraPassed(drive.passedCamera?.id);
    unawaited(_roadAlerts.check(drive));
    _updateArrival();
    unawaited(_cacheCorridor());
  }

  /// Back in the foreground: the Lock Screen surface catches up at once.
  void onResumed() {
    if (_state.guidanceRunning) {
      unawaited(system.update(systemState(), force: true));
    }
  }

  /// An accepted fix while navigating: ends the trip on arrival.
  void onLocationFix(NavigationLocationFix accepted, Position position) {
    if (_state is! TripNavigating ||
        _clock().difference(position.timestamp).abs() >
            const Duration(seconds: 10)) {
      return;
    }
    final arrived =
        _journey?.update(
          accepted.point,
          accuracyMeters: accepted.accuracyMeters,
          time: accepted.timestamp,
        ) ??
        false;
    if (arrived) unawaited(stop(arrived: true));
  }

  // ---------------------------------------------------------------------
  // Guidance

  /// Starts the preview's selected route: guidance, or a public-transport
  /// trip. A blocked route searches for a detour instead.
  Future<void> start() async {
    final selected = places.selected?.place;
    final route = preview.selectedRoute;
    if (selected == null || route == null || _state.busy) return;
    if (preview.needsRecovery(route)) {
      await preview.recoverBlockedRoute();
      return;
    }
    // Starting also supersedes a preview reload still in flight.
    final token = preview.requests.next();
    bool cancelled() => _disposed || token.isStale;
    trip.dispatch(const StartRequested());
    notice.value = null;
    // Navigation always starts in a flat heading-up view. Users can switch
    // to perspective or north-up after the trip begins.
    host.setTripCameraMode(NavigationCameraMode.headingUpFlat);
    try {
      if (preview.mode == WaybiTravelMode.transit) {
        await _startTransit(selected, route);
        return;
      }
      final lanes = await drive.transitMatchesForRoute(route);
      if (cancelled()) return;
      final restricted = transitRoadBlocks(route, lanes, _clock());
      if (restricted.isNotEmpty) {
        notice.value = _text(
          'Bus-only access on ${restricted.first.lane.roadName}. Choose another route.',
          '${restricted.first.lane.roadName} 当前禁止普通汽车通行，请选择其他路线。',
        );
        return;
      }
      await _roadAlerts.prepare();
      if (cancelled()) return;
      if (!await host.ensureLocationPermission() || cancelled()) return;
      await host.pauseBrowseLocation();
      if (cancelled()) return;
      host.resetTripCamera(drive: false);
      await guidance.start(route, initialPosition: host.lastReliablePosition);
      if (cancelled()) {
        // The engine installed the route after the user backed out.
        await guidance.stop();
        return;
      }
      trip.dispatch(const NavigationStarted());
      preview.handOffToGuidance();
      places.clear();
      _destinationTitle = selected.name;
      _activeRoute = route;
      _destination = selected;
      _resetArrival();
      _offlineReady = false;
      _changed();
      host.followTrip(NavigationCameraMode.headingUpFlat);
      _beginJourney(selected);
      _updateArrival();
      await _startSystemNavigation();
      unawaited(_cacheCorridor(force: true));
      host.refreshTripMap();
    } catch (error) {
      if (_disposed) return;
      if (!_state.guidanceRunning && guidance.route != null) {
        // A half-started engine must not keep the drive route or GPS feed.
        try {
          await guidance.stop();
        } catch (_) {
          // The page is leaving navigation regardless.
        }
      }
      if (cancelled()) return;
      notice.value = _text(
        'Could not start navigation. ${friendlyErrorMessage(error, _language())}',
        '无法开始导航。${friendlyErrorMessage(error, _language())}',
      );
    } finally {
      // A start that did not reach guidance (failed, bus-only road, no
      // permission) returns to its preview; a cancelled one already left it.
      if (!_disposed) {
        trip.dispatch(const StartAborted());
        if (!drive.active) unawaited(host.startBrowseLocation());
      }
    }
  }

  void _beginJourney(PlaceSummary place) {
    _journeyCountry = _rewards.countryAt(place.location);
    unawaited(_feedback.flush());
    _journey = JourneyTracker(target: place.location, destination: place.name);
  }

  Future<void> _startSystemNavigation() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await _requestNotificationPermission();
    }
    await system.start(systemState());
  }

  /// What the Lock Screen / notification shows for the current step.
  Map<String, Object?> systemState() {
    final language = _language();
    final independent = guidance.active;
    final step = independent ? guidance.nextStep : null;
    final instruction = routeStepInstruction(step, language);
    final type = '${step?.maneuverType} ${step?.maneuverModifier}';
    final offRoute = independent && (guidance.offRoute || guidance.rerouting);
    final distance = independent ? guidance.distanceToStepMeters : null;
    final remaining = remainingMeters;
    final gpsReliable = !independent || drive.hasReliableLocation;
    final seconds = independent
        ? guidance.remainingSeconds
        : _activeRoute?.durationSeconds ?? 0;
    return {
      'destination': destinationTitle,
      'language': language,
      'provider': 'independent',
      'gpsReliable': gpsReliable,
      'instruction': !gpsReliable
          ? _text('Waiting for accurate GPS', '正在等待准确定位')
          : offRoute
          ? _text('Updating route...', '正在重新规划路线…')
          : instruction,
      'distance': !gpsReliable
          ? '—'
          : offRoute
          ? ''
          : distance == null
          ? '—'
          : navigationMetres(distance, language),
      'remaining': remaining == null
          ? '—'
          : navigationMetres(remaining, language),
      'seconds': seconds,
      'offRoute': offRoute,
      'maneuver': offRoute
          ? 'arrow.triangle.swap'
          : type.contains('arrive')
          ? 'flag.fill'
          : type.contains('uturn')
          ? 'arrow.uturn.left'
          : type.contains('roundabout')
          ? 'arrow.triangle.2.circlepath'
          : type.contains('right')
          ? 'arrow.turn.up.right'
          : type.contains('left')
          ? 'arrow.turn.up.left'
          : 'arrow.up',
    };
  }

  /// Ends guidance. [arrived]: the journey reached its destination (a
  /// reward, the arrival prompt, and the parking leg at a chosen car park).
  Future<void> stop({bool arrived = false, bool showSummary = true}) async {
    if (_state is! TripNavigating) return;
    trip.dispatch(const EndRequested());
    final parkingTarget = preview.selectedParking;
    final parkingFix = host.browseLocation;
    final reachedParking =
        parkingTarget != null &&
        (arrived ||
            (drive.hasReliableLocation &&
                parkingFix != null &&
                distanceMeters(
                      parkingFix.latitude,
                      parkingFix.longitude,
                      parkingTarget.location.latitude,
                      parkingTarget.location.longitude,
                    ) <=
                    75));
    final route = _activeRoute;
    final summary = _journey?.finish(arrived: arrived);
    final reward = summary?.arrived == true
        ? _rewards
              .complete(summary!, country: _journeyCountry)
              .catchError((Object _) => null)
        : null;
    _journeyCountry = null;
    _journey = null;
    // Ending always ends: whatever fails below, the page leaves guidance and
    // returns to browsing instead of a "zombie" trip that cannot be stopped.
    try {
      try {
        await system.stop();
      } catch (_) {
        // The Live Activity / notification expires on its own.
      }
      try {
        if (guidance.route != null) {
          await guidance.stop();
        } else {
          await drive.stop();
        }
      } catch (_) {
        try {
          if (drive.active) await drive.stop();
        } catch (_) {
          // The engine is disposed with the page; nothing else can be done.
        }
      }
      // Only count GPS-tracked travel, never the entire planned route.
      if (summary != null &&
          summary.distanceMeters.isFinite &&
          summary.distanceMeters > 0) {
        try {
          if (_hasAccount() && route != null && route.points.isNotEmpty) {
            final end = route.points.last;
            await _journeys.queueAccountJourney(
              destinationName: destinationTitle,
              latitude: end.latitude,
              longitude: end.longitude,
              mode: preview.mode.apiValue,
              distanceMeters: summary.distanceMeters.round(),
              durationSeconds: summary.elapsed.inSeconds.clamp(0, 2000000),
            );
          } else {
            await _journeys.recordGuestJourney(summary);
          }
        } catch (_) {
          // Navigation still ends if local persistence is unavailable.
        }
      }
    } finally {
      final parkingLeg =
          reachedParking &&
          preview.parkingOriginalPlace != null &&
          preview.mode == WaybiTravelMode.drive;
      _arrivalRequests.invalidate();
      _roadAlerts.newTrip();
      if (!_disposed) {
        trip.dispatch(NavigationEnded(parkingLeg: parkingLeg));
        _activeRoute = null;
        _destination = null;
        _corridorCachedAt = null;
        _destinationTitle = null;
        _resetArrival();
        _offlineReady = false;
        _changed();
        host.followTrip(NavigationCameraMode.northUpFlat);
        // DriveEngine.stop() also stopped the traffic refresh.
        host.resumeTrafficRefresh();
        if (!drive.active) unawaited(host.startBrowseLocation());
      }
    }
    if (_disposed) return;
    final parked = _state is TripParkingLeg ? preview.selectedParking : null;
    if (parked != null) unawaited(rememberParkedCar(parked));
    if (arrived) {
      unawaited(
        drive.speakUtterance(VoicePrompts.arrival(drive.navigationLanguage)),
      );
    }
    if (summary != null && showSummary) {
      host.showJourneySummary(summary, reward);
    }
  }

  // ---------------------------------------------------------------------
  // Arrival and parking

  void _updateArrival() {
    final remaining = remainingMeters;
    final eligible =
        _isPlus() &&
        _state.guidanceRunning &&
        preview.mode == WaybiTravelMode.drive &&
        remaining != null;
    if (!eligible) {
      trip.dispatch(const ArrivalChanged(false));
      return;
    }
    if (remaining <= 800 && !_arrivalPrefetching && !_arrivalPrefetched) {
      unawaited(_prefetchArrival());
    }
    trip.dispatch(ArrivalChanged(remaining <= 300));
  }

  Future<void> _prefetchArrival() async {
    if (!_isPlus()) return;
    final destination = _destination;
    if (destination == null || _arrivalPrefetching) return;
    final token = _arrivalRequests.next();
    _arrivalPrefetching = true;
    _changed();
    var parking = _arrivalParking;
    var details = _arrivalDetails;
    if (preview.selectedParking == null) {
      try {
        parking = await _parking(destination.location);
      } catch (_) {
        // Arrival guidance works without parking suggestions.
      }
    }
    try {
      details = await _fetchDetails(destination);
    } catch (_) {
      // Arrival guidance and parking remain usable without place details.
    }
    if (_disposed || token.isStale) return;
    _arrivalParking = parking;
    _arrivalDetails = details;
    _arrivalPrefetching = false;
    _arrivalPrefetched = true;
    _changed();
  }

  /// Ends guidance for a car park near the destination and starts guidance
  /// to it; the destination stays for the walk after parking.
  Future<void> routeToArrivalParking(ParkingPlace parking) async {
    final destination = _destination;
    if (destination == null || _state is TripEnding) return;
    await stop(showSummary: false);
    if (_disposed) return;
    preview.targetParking(destination, parking);
    await preview.load();
    if (!_disposed && preview.selectedRoute != null) await start();
  }

  /// The parking-continuation card was dismissed.
  void dismissParkingLeg() {
    trip.dispatch(const ParkingLegDismissed());
    preview.forgetParkingTarget();
  }

  static const parkedCarKey = 'waybi.plus.parked_car.v1';

  PlaceSummary? _parkedCar;

  /// Where the car was parked in the last 72 hours (Plus).
  PlaceSummary? get parkedCar => _parkedCar;
  DateTime? _parkedCarAt;

  Future<void> rememberParkedCar(ParkingPlace parking) async {
    if (!_isPlus()) return;
    final parkedAt = _clock();
    final place = parking.toPlaceSummary();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      parkedCarKey,
      jsonEncode({
        'name': place.name,
        'address': place.address,
        'latitude': place.location.latitude,
        'longitude': place.location.longitude,
        'parkedAt': parkedAt.toIso8601String(),
      }),
    );
    if (_disposed) return;
    _parkedCar = place;
    _parkedCarAt = parkedAt;
    _changed();
  }

  String parkedCarLabel() {
    final parkedAt = _parkedCarAt;
    if (parkedAt == null) return _text('Parked car', '停车位置');
    final age = _clock().difference(parkedAt);
    if (age.inMinutes < 2) return _text('Parked just now', '刚刚停车');
    if (age.inHours < 1) {
      return _text('Parked ${age.inMinutes} min ago', '停车 ${age.inMinutes} 分钟');
    }
    if (age.inHours < 24) {
      return _text('Parked ${age.inHours} h ago', '停车 ${age.inHours} 小时');
    }
    return _text('Parked ${age.inDays} d ago', '停车 ${age.inDays} 天');
  }

  /// Restores the parked car (dropping a stale or damaged record) and the
  /// keep-screen-awake setting.
  Future<void> restoreSettings(SharedPreferences prefs) async {
    final record = prefs.getString(parkedCarKey);
    if (record != null) {
      try {
        final item = jsonDecode(record) as Map<String, dynamic>;
        final parkedAt = DateTime.tryParse(item['parkedAt']?.toString() ?? '');
        final latitude = item['latitude'];
        final longitude = item['longitude'];
        if (parkedAt != null &&
            latitude is num &&
            longitude is num &&
            _clock().difference(parkedAt) < const Duration(hours: 72)) {
          _parkedCarAt = parkedAt;
          _parkedCar = PlaceSummary(
            name: item['name']?.toString() ?? _text('Parked car', '停车位置'),
            address: item['address']?.toString() ?? '',
            location: GeoPoint(latitude.toDouble(), longitude.toDouble()),
          );
        } else {
          await prefs.remove(parkedCarKey);
        }
      } catch (_) {
        await prefs.remove(parkedCarKey);
      }
    }
    _keepScreenAwake = prefs.getBool('waybi.nav.keep_screen_awake') ?? true;
    await drive.setKeepScreenAwake(_keepScreenAwake);
  }

  /// Keeps the screen on while the drive engine runs (the engine holds the
  /// wakelock only while active).
  Future<void> setKeepScreenAwake(bool value) async {
    _keepScreenAwake = value;
    _changed();
    await drive.setKeepScreenAwake(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('waybi.nav.keep_screen_awake', value);
  }

  // ---------------------------------------------------------------------
  // Offline corridor

  Future<void> _cacheCorridor({bool force = false}) async {
    if (!_isPlus()) {
      if (_offlineReady) {
        _offlineReady = false;
        _changed();
      }
      return;
    }
    final route = _activeRoute;
    if (!_state.guidanceRunning || route == null || route.points.length < 2) {
      return;
    }
    final now = _clock();
    final last = _corridorCachedAt;
    if (!force &&
        last != null &&
        now.difference(last) < const Duration(seconds: 30)) {
      return;
    }
    try {
      await saveOfflineCorridor(
        route: route,
        drive: drive,
        destination: destinationTitle,
        language: _language(),
        now: now,
      );
      _corridorCachedAt = now;
      if (!_offlineReady) {
        _offlineReady = true;
        _changed();
      }
    } catch (_) {
      // Navigation remains usable from its in-memory route if persistence fails.
    }
  }

  /// An ETA snapshot to share (not live location sharing).
  String tripSnapshot() {
    final active = guidance.active;
    final remaining = active ? guidance.remainingDistanceMeters : null;
    final arrival = active ? guidance.remainingSeconds : null;
    final unknown = _text('unknown', '未知');
    final distance = remaining == null
        ? unknown
        : formatDistance(remaining, _language());
    final eta = arrival == null
        ? unknown
        : _clock()
              .add(Duration(seconds: arrival))
              .toLocal()
              .toString()
              .substring(0, 16);
    return _text(
      'Waybi trip to $destinationTitle. Remaining: $distance. ETA: $eta. '
          'This is an ETA snapshot, not live location sharing.',
      'Waybi 行程：前往 $destinationTitle。剩余：$distance。预计到达：$eta。'
          '这是一次到达时间快照，不是实时位置共享。',
    );
  }

  // ---------------------------------------------------------------------
  // Just Drive

  /// Drive Mode without a route: cameras, speed and road events.
  Future<void> startDrive() async {
    if (_state.busy || _state.guidanceRunning || _state is TripTransit) return;
    notice.value = null;
    try {
      await _roadAlerts.prepare();
      if (host.browseLocation == null) await host.startBrowseLocation();
      if (_disposed) return;
      if (host.browseLocation == null) {
        notice.value = _text(
          'Waiting for your current GPS position before opening Drive Mode.',
          '正在等待当前定位，定位成功后即可打开驾驶模式。',
        );
        return;
      }
      trip.dispatch(const DriveRequested());
      // A preview or place focus must not retain camera ownership in Drive.
      await host.clearPreview();
      host.resetTripCamera(drive: true);
      await host.pauseBrowseLocation();
      await drive.startLocal(initialPosition: host.lastReliablePosition);
      if (_disposed) return;
      trip.dispatch(drive.active ? const DriveStarted() : const DriveEnded());
      host.followTrip(NavigationCameraMode.headingUpFlat);
      host.refreshTripMap();
    } catch (error) {
      if (_disposed) return;
      trip.dispatch(const DriveEnded());
      notice.value = _text(
        'Could not start Drive Mode. ${friendlyErrorMessage(error, _language())}',
        '无法打开驾驶模式。${friendlyErrorMessage(error, _language())}',
      );
    } finally {
      // The browse feed was paused for Drive; a failed start must not leave
      // the map without location.
      if (!_disposed && !drive.active) unawaited(host.startBrowseLocation());
    }
  }

  /// Ends Drive Mode (and guidance with it).
  Future<void> stopDrive() async {
    if (_state.guidanceRunning) await stop();
    await drive.stop();
    if (_disposed) return;
    trip.dispatch(const DriveEnded());
    host.setTripCameraMode(NavigationCameraMode.northUpFlat);
    host.resumeTrafficRefresh();
    unawaited(host.startBrowseLocation());
    _changed();
  }

  // ---------------------------------------------------------------------
  // Public transport

  Future<void> _startTransit(PlaceSummary place, RouteOption route) async {
    // The trip shows only its itinerary: drop the preview, its alternatives
    // and the drive route so none of them stay on the map during or after it.
    preview.handOffToTransit();
    trip.dispatch(const TransitTripStarted());
    _transitRoute = route;
    _transitPaths = null;
    _destinationTitle = place.name;
    places.clear();
    _changed();
    host.followTrip();
    host.refreshTripMap();
    await drive.speakUtterance(
      VoicePrompts.transitTripStarted(drive.navigationLanguage),
    );
  }

  Future<void> stopTransit() async {
    if (_state is! TripTransit) return;
    trip.dispatch(const TransitTripEnded());
    _transitRoute = null;
    _transitPaths = null;
    _destinationTitle = null;
    _changed();
    host.followTrip();
    host.refreshTripMap();
  }

  // ---------------------------------------------------------------------
  // Navigation links from other apps

  final _handOffs = RequestGeneration();
  Timer? _handOffRetry;

  /// Handles a waiting link once the page is ready and no trip is starting
  /// or ending; the latest link wins.
  void scheduleHandOff() {
    if (_disposed || !host.handOffReady || !_inbox.hasPending) return;
    if (_state.busy || _state is TripEnding) {
      _handOffRetry ??= Timer(const Duration(milliseconds: 200), () {
        _handOffRetry = null;
        scheduleHandOff();
      });
      return;
    }
    final value = _inbox.takePending();
    if (value == null) return;
    final token = _handOffs.next();
    preview.cancelPending();
    host.afterFrame(() {
      if (_disposed || token.isStale) return;
      unawaited(
        _handOff(value, token).catchError((Object _) {
          if (!_disposed && token.isCurrent) {
            host.showHandOffError(
              _text(
                'Could not open this destination. Try searching for it.',
                '无法打开这个目的地，请尝试搜索。',
              ),
            );
          }
        }),
      );
    });
  }

  static DestinationSuggestion _suggestion(PlaceSummary place) =>
      DestinationSuggestion(
        label: place.name,
        name: place.name,
        address: place.address,
        location: LatLng(
          latitude: place.location.latitude,
          longitude: place.location.longitude,
        ),
      );

  Future<void> _handOff(String value, RequestToken token) async {
    bool current() => !_disposed && token.isCurrent;
    NavigationLink? link;
    try {
      link = NavigationLink.parse(value);
    } on FormatException {
      host.showHandOffError(
        _text(
          'This navigation link has an invalid destination.',
          '这个导航链接的目的地无效。',
        ),
      );
      return;
    }
    if (link == null || !current()) return;
    host.popToHome();
    if (_state.guidanceRunning || drive.active || _state is TripTransit) {
      final replace = await host.confirmSwitchTrip(link.destination.label);
      if (!replace || !current()) return;
      if (_state.guidanceRunning) await stop(showSummary: false);
      if (!current()) return;
      if (_state is TripTransit) await stopTransit();
      if (!current()) return;
      if (drive.active) await stopDrive();
      if (!current()) return;
    }
    // Resolve every text location through the map provider. Never silently
    // use the first result or discard an explicit source or waypoint.
    Future<PlaceSummary?> resolve(
      NavigationTarget target,
      String purpose,
    ) async {
      if (!current()) return null;
      final point = target.coordinate;
      if (point != null) {
        return PlaceSummary(
          name: target.label,
          address: '',
          location: point,
          kind: PlaceKind.coordinate,
        );
      }
      return host.searchHandOffTarget(target.label, purpose, current);
    }

    final destination = await resolve(
      link.destination,
      _text('Choose destination', '选择目的地'),
    );
    if (destination == null || !current()) return;
    PlaceSummary? source;
    if (link.source != null) {
      source = await resolve(
        link.source!,
        _text('Choose starting point', '选择起点'),
      );
      if (source == null || !current()) return;
    }
    final stops = <DestinationSuggestion>[];
    for (final target in link.waypoints) {
      final place = await resolve(
        target,
        _text('Choose stop ${stops.length + 1}', '选择途经点 ${stops.length + 1}'),
      );
      if (place == null || !current()) return;
      stops.add(_suggestion(place));
    }
    if (!current()) return;
    preview.applyLink(
      origin: source == null ? null : _suggestion(source),
      stops: stops,
      mode: link.mode,
    );
    host.selectHandOffPlace(destination);
    final selected = places.selected;
    if (link.showPlaceOnly || selected == null) return;
    if (preview.origin == null) {
      preview.deferUntilLocated(selected, link.mode);
      notice.value = _text(
        'Waiting for your location to preview the route…',
        '正在等待定位以预览路线…',
      );
    } else {
      await preview.load(mode: link.mode);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _handOffs.invalidate();
    _arrivalRequests.invalidate();
    _handOffRetry?.cancel();
    guidance.removeListener(_onGuidanceChanged);
    drive.removeListener(_onDriveChanged);
    _inbox.removeListener(scheduleHandOff);
    super.dispose();
  }
}
