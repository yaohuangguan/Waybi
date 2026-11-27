import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';

import '../data/camera_repository.dart';
import '../data/transit_lane_repository.dart';
import '../domain/transit_lane.dart';
import '../domain/transit_review_corridor.dart';
import '../data/nzta_road_event_provider.dart';
import '../data/nzta_traffic_road_event_provider.dart';
import '../data/speed_limit_repository.dart';
import '../data/traffic_flow_repository.dart';
import '../domain/country_profile.dart';
import '../domain/geo_math.dart';
import '../domain/map_provider.dart';
import '../domain/road_event.dart';
import '../domain/road_intelligence.dart';
import '../domain/route_option.dart';
import '../domain/safety_camera.dart';
import '../domain/traffic_flow.dart';
import 'camera_alert_lifecycle.dart';
import 'camera_matcher.dart';
import 'route_camera_matcher.dart';
import 'route_progress_tracker.dart';
import 'custom_voice.dart';
import 'voice_engine.dart';
import 'voice_prompts.dart';
import 'navigation_location_filter.dart';
import 'reliable_location_feed.dart';
import 'speed_limit_pacer.dart';
import '../data/http_guard.dart';
import 'navigation_motion.dart';
import 'drive_trail.dart';

enum NavigationGpsIssue {
  acquiring,
  stale,
  unstable,
  unavailable,
  servicesDisabled,
  permissionDenied,
}

List<RouteCameraMatch> _matchCamerasInBackground(
  (RouteOption, List<SafetyCamera>) input,
) => const RouteCameraMatcher().match(input.$1, input.$2);

List<TransitLaneMatch> _matchTransitInBackground(
  (RouteOption, List<TransitLane>) input,
) => matchTransitLanes(input.$1, input.$2);

class DriveEngine extends ChangeNotifier {
  DriveEngine({
    CameraRepository? cameraRepository,
    CameraMatcher? cameraMatcher,
    VoiceEngine? voiceEngine,
    SpeedLimitRepository? speedLimitRepository,
    TrafficFlowRepository? trafficFlowRepository,
    RoadIntelligenceEngine? roadIntelligence,
    CameraAlertLifecycle? cameraLifecycle,
    TransitLaneRepository? transitLaneRepository,
  }) : _cameraMatcher = cameraMatcher ?? const CameraMatcher(),
       _voiceEngine = voiceEngine ?? VoiceEngine(),
       _speedLimitRepository = speedLimitRepository ?? SpeedLimitRepository(),
       _trafficFlowRepository =
           trafficFlowRepository ?? TrafficFlowRepository(),
       _roadIntelligence = roadIntelligence ?? RoadIntelligenceEngine(),
       _cameraLifecycle = cameraLifecycle ?? CameraAlertLifecycle(),
       _transitRepository = transitLaneRepository ?? TransitLaneRepository() {
    _nztaProvider = NztaRoadEventProvider(
      cameraRepository ?? CameraRepository(),
    );
    _trafficProvider = NztaTrafficRoadEventProvider();
    _providerRegistry = RoadEventProviderRegistry([
      _nztaProvider,
      _trafficProvider,
    ]);
  }

  final CameraMatcher _cameraMatcher;
  final VoiceEngine _voiceEngine;

  /// Waybi Plus recorded voice; null or inactive means the standard voice.
  set customVoice(CustomVoiceClips? clips) => _voiceEngine.customVoice = clips;
  final SpeedLimitRepository _speedLimitRepository;
  final TrafficFlowRepository _trafficFlowRepository;
  final RoadIntelligenceEngine _roadIntelligence;
  final CameraAlertLifecycle _cameraLifecycle;
  final TransitLaneRepository _transitRepository;
  TransitLaneSnapshot? transitSnapshot;
  List<TransitReviewCorridor> transitReviewCorridors = const [];
  Future<void>? _transitReviewLoad;

  Future<void> loadTransitReviewCorridors() =>
      _transitReviewLoad ??= _loadTransitReviewCorridors();

  Future<void> _loadTransitReviewCorridors() async {
    try {
      transitReviewCorridors = await loadBundledTransitReviewCorridors();
      if (!_disposed) notifyListeners();
    } catch (error) {
      debugPrint('Review-only bus corridor data unavailable: $error');
    }
  }

  List<TransitLaneMatch> transitLaneMatches = const [];
  TransitLaneNotice? upcomingTransitLane;
  RouteOption? _transitMatchedRoute;
  TransitLaneSnapshot? _transitMatchedSnapshot;
  Future<List<TransitLaneMatch>>? _transitMatchJob;
  final Map<String, DateTime> _spokenTransitAlerts = {};
  final Map<String, Object> _pendingTransitAlerts = {};
  final Map<String, DateTime> _transitRetryAfter = {};

  Future<List<TransitLaneMatch>> transitMatchesForRoute(
    RouteOption route,
  ) async {
    final snapshot = transitSnapshot ??= await _transitRepository.loadLocal();
    if (identical(route, _transitMatchedRoute) &&
        identical(snapshot, _transitMatchedSnapshot) &&
        _transitMatchJob != null) {
      return _transitMatchJob!;
    }
    _transitMatchedRoute = route;
    _transitMatchedSnapshot = snapshot;
    return _transitMatchJob = compute(_matchTransitInBackground, (
      route,
      snapshot.lanes,
    ));
  }

  Future<void> loadTransitLanes({bool refresh = false}) async {
    try {
      transitSnapshot = refresh
          ? await _transitRepository.refresh()
          : await _transitRepository.loadLocal();
      await _recomputeTransitLanes();
      if (!_disposed && _route == null) notifyListeners();
    } catch (_) {
      /* Navigation remains usable outside the supported dataset. */
    }
  }

  Future<void> _recomputeTransitLanes() async {
    final route = _route;
    if (route == null) {
      transitLaneMatches = const [];
      upcomingTransitLane = null;
      return;
    }
    try {
      final matches = await transitMatchesForRoute(route);
      if (_disposed || !identical(route, _route)) return;
      transitLaneMatches = matches;
      _updateTransitLane(DateTime.now());
      notifyListeners();
    } catch (_) {
      /* The bundled lane snapshot is an additional reminder. */
    }
  }

  void _updateTransitLane(DateTime now) {
    final progress = routeProgress, route = _route;
    if (!active ||
        route == null ||
        route.mode != WaybiTravelMode.drive ||
        progress == null ||
        progress.offsetMeters > 35) {
      upcomingTransitLane = null;
      return;
    }
    final match = transitLaneMatches
        .where(
          (m) =>
              m.endMeters > progress.alongMeters &&
              m.startMeters - progress.alongMeters <= 350 &&
              m.lane.schedule.activeAt(now) != false,
        )
        .firstOrNull;
    if (match == null) {
      upcomingTransitLane = null;
      return;
    }
    final turningLeft = hasImmediateTransitLaneLeftTurn(
      route,
      match,
      progress.alongMeters,
    );
    upcomingTransitLane = TransitLaneNotice(
      match: match,
      distanceMeters: (match.startMeters - progress.alongMeters).clamp(
        0,
        double.infinity,
      ),
      turningLeft: turningLeft,
    );
    unawaited(_maybeAlertTransit(upcomingTransitLane!, now));
  }

  Future<void> _maybeAlertTransit(
    TransitLaneNotice notice,
    DateTime now,
  ) async {
    if (!voiceEnabled) return;
    final key = notice.alertKey;
    if (_pendingTransitAlerts.containsKey(key) ||
        (_transitRetryAfter[key]?.isAfter(now) ?? false) ||
        (_spokenTransitAlerts[key] != null &&
            now.difference(_spokenTransitAlerts[key]!) <
                const Duration(minutes: 10))) {
      return;
    }
    final token = Object(),
        session = _locationSession,
        revision = _turnRevision;
    _pendingTransitAlerts[key] = token;
    try {
      final spoken = await _voiceEngine.roadAlertUtterance(
        () {
          final lane = upcomingTransitLane;
          return lane == null
              ? VoiceUtterance.freeform('', navigationLanguage)
              : VoicePrompts.transitLane(lane, navigationLanguage);
        },
        stillRelevant: () =>
            active &&
            voiceEnabled &&
            session == _locationSession &&
            revision == _turnRevision &&
            upcomingTransitLane?.alertKey == key &&
            notice.lane.schedule.activeAt(DateTime.now()) != false,
      );
      if (spoken && session == _locationSession) {
        _spokenTransitAlerts[key] = DateTime.now();
      }
    } catch (_) {
      if (identical(_pendingTransitAlerts[key], token)) {
        _transitRetryAfter[key] = DateTime.now().add(
          const Duration(seconds: 5),
        );
      }
    } finally {
      if (identical(_pendingTransitAlerts[key], token)) {
        _pendingTransitAlerts.remove(key);
      }
    }
  }

  late final NztaRoadEventProvider _nztaProvider;
  late final NztaTrafficRoadEventProvider _trafficProvider;
  late final RoadEventProviderRegistry _providerRegistry;

  bool _disposed = false;
  int _locationSession = 0;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Timer? _roadIntelligenceRefreshTimer;
  Timer? _trafficFlowRefreshTimer;
  Duration? _trafficFlowRefreshInterval;

  /// Spoken camera reminders by `alertKey:threshold`. They expire with the
  /// lifecycle cooldown and when the camera is passed, so a driver who passes
  /// the same camera again later (Just Drive all day, or after a reroute)
  /// hears it again instead of only seeing the card.
  late final SpokenCameraAlerts _spokenAlerts = SpokenCameraAlerts(
    lifetime: _cameraLifecycle.cooldown,
  );
  final SpeedLimitPacer _speedLimitPacer = SpeedLimitPacer();
  final Map<String, Object> _pendingCameraAlerts = {};
  final Map<String, DateTime> _cameraRetryAfter = {};
  final RouteCameraMatcher _routeMatcher = const RouteCameraMatcher();
  final NavigationLocationFilter _localLocationFilter =
      NavigationLocationFilter();
  final _localMotion = NavigationMotionEstimator();
  final _driveTrail = DriveTrail();
  List<MapRoutePath> get trailPaths =>
      active && _route == null ? _driveTrail.paths : const [];

  List<SafetyCamera> _cameras = const [];
  RouteOption? _route;
  RouteProgressTracker? _progressTracker;
  RouteProjection? routeProgress;
  double locationAccuracyMeters = 10;
  int locationRevision = 0;
  Position? latestPosition;
  Set<String> _highConfidenceCameraIds = const {};
  List<RouteCameraMatch> routeCameras = const [];
  List<SafetyCamera> get cameras => _cameras;
  CameraSnapshot? get cameraSnapshot => _nztaProvider.lastSnapshot;
  List<RoadEvent> roadEvents = const [];
  String get roadEventSyncStatus => _trafficProvider.lastSyncStatus;
  DateTime? get roadEventCheckedAt => _trafficProvider.lastCheckedAt;
  List<String> get roadEventOfficialCoverage =>
      _trafficProvider.officialCoverage;
  List<RoadEvent> _routeRoadEvents = const [];
  List<RoadEvent> upcomingRoadEvents = const [];
  List<TrafficFlowSegment> trafficFlowSegments = const [];
  DateTime? trafficFlowUpdatedAt;
  TrafficTileOverlay? trafficTileOverlay;
  String trafficFlowStatus = 'not_loaded';
  int trafficFlowRevision = 0;
  String roadIntelligenceStatus = 'not_loaded';
  bool get roadIntelligenceStale => roadIntelligenceStatus == 'stale';
  int get routeCameraCount => routeCameras.length;
  LatLng? get snappedLocation => _lastSnappedLocation;
  LatLng? get rawLocation => _lastRawLocation;
  double? get rawHeadingDegrees => _rawHeadingDegrees;
  LatLng? _lastRawLocation;
  double? _rawHeadingDegrees;
  bool _localNavigation = false;
  String? locationIssue;
  NavigationGpsIssue? gpsIssue;
  ReliableLocationFeed? _localLocationFeed;
  bool get hasReliableLocation => !_localNavigation
      ? _lastSnappedLocation != null
      : latestPosition != null &&
            locationIssue == null &&
            DateTime.now().difference(latestPosition!.timestamp).inSeconds <=
                10;
  double? get snappedHeadingDegrees => _headingDegrees;
  LatLng? _lastSnappedLocation;
  DateTime? _lastRoadEventEvaluationAt;
  LatLng? _lastRoadEventEvaluationLocation;
  double? _headingDegrees;

  bool active = false;
  bool guidanceRunning = false;
  bool loadingCameras = false;
  Future<void>? _cameraLoad;
  String? _roadEventRegion;
  double speedKph = 0;
  int? speedLimitKph;
  bool _voiceEnabled = true;
  bool _keepScreenAwake = true;
  String navigationLanguage = 'en';
  int _turnRevision = 0;
  Future<void> setKeepScreenAwake(bool value) async {
    _keepScreenAwake = value;
    await _updateWakeLock();
  }

  Future<void> _updateWakeLock() async {
    try {
      await WakelockPlus.toggle(enable: active && _keepScreenAwake);
    } catch (_) {
      /* Unsupported test/desktop platform. */
    }
  }

  bool get voiceEnabled => _voiceEnabled;
  set voiceEnabled(bool enabled) {
    _voiceEnabled = enabled;
    if (!enabled) unawaited(_voiceEngine.stop());
  }

  bool Function(SafetyCamera) _cameraAlertFilter = (_) => true;

  void setCameraAlertFilter(bool Function(SafetyCamera) filter) {
    _cameraAlertFilter = filter;
    _recomputeRouteCameras();
    notifyListeners();
  }

  Future<void> setVoiceLanguage(String language) =>
      _voiceEngine.setLanguage(language);
  String? speedLimitZoneName;
  SpeedAlertSeverity speedSeverity = SpeedAlertSeverity.notSpeeding;
  double? percentageAboveLimit;
  SafetyCamera? upcomingCamera;
  double? upcomingCameraDistanceMeters;
  SafetyCamera? passedCamera;
  CameraAlertState cameraAlertState = const CameraAlertState.idle();
  bool get routed => _route != null;

  /// Turn-by-turn data from the Google Navigation SDK session, which Waybi
  /// no longer starts: always null. Kept for the HUD widgets that still read
  /// it; the independent engine provides guidance instead.
  NavInfo? get navInfo => null;
  String? error;

  /// Local location feed for a non-Google map renderer. Camera alerts keep
  /// using the same matching and voice logic, without starting Google SDK.
  Future<void> startLocal({Position? initialPosition}) async {
    if (active || _disposed) return;
    final session = ++_locationSession;
    _localNavigation = true;
    _localMotion.reset();
    _driveTrail.clear();
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Turn on location services to start driving');
    }
    error = null;
    await _voiceEngine.initialize();
    if (_disposed || session != _locationSession) return;

    final routeStart = _route != null && _route!.points.isNotEmpty
        ? _route!.points.first
        : null;
    _localLocationFilter.reset(
      anchor: routeStart,
      trustedFix: initialPosition == null
          ? null
          : NavigationLocationFix(
              point: GeoPoint(
                initialPosition.latitude,
                initialPosition.longitude,
              ),
              accuracyMeters: initialPosition.accuracy,
              speedMetresPerSecond: initialPosition.speed.isFinite
                  ? initialPosition.speed.clamp(0.0, 70.0)
                  : 0,
              timestamp: initialPosition.timestamp,
            ),
    );
    active = true;
    guidanceRunning = _route != null;

    // Keep the puck on the freshly-calculated route origin until iOS provides
    // a trustworthy fix. This prevents an indoor 50–100 m GPS jump from
    // instantly moving the Waybi onto a nearby motorway.
    if (routeStart != null) {
      // This is only a visual anchor, never a GPS observation. Synthetic fixes
      // must not advance turns, ETA, camera alerts or arrival confirmation.
      _lastSnappedLocation = LatLng(
        latitude: routeStart.latitude,
        longitude: routeStart.longitude,
      );
      _lastRawLocation = null;
      latestPosition = null;
      routeProgress = null;
      locationAccuracyMeters = double.infinity;
      error = 'Waiting for an accurate GPS fix';
      locationIssue = error;
      gpsIssue = NavigationGpsIssue.acquiring;
    }

    final settings = switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: _route != null
            ? null
            : const ForegroundNotificationConfig(
                notificationTitle: 'Waybi Drive',
                notificationText:
                    'Navigation and safety-camera alerts are active',
                notificationChannelName: 'Waybi navigation',
                enableWakeLock: true,
                setOngoing: true,
              ),
      ),
      TargetPlatform.iOS => AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        activityType:
            _route?.mode == WaybiTravelMode.walk ||
                _route?.mode == WaybiTravelMode.bicycle
            ? ActivityType.fitness
            : ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      ),
      _ => const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      ),
    };
    _localLocationFeed =
        ReliableLocationFeed(
          settings: settings,
          onPosition: _consumeLocalPosition,
          onIssue: (issue) {
            if (!active || _disposed) return;
            if (issue == null) {
              locationIssue = null;
              gpsIssue = null;
              error = null;
            } else if (issue is LocationServiceDisabledException) {
              gpsIssue = NavigationGpsIssue.servicesDisabled;
              locationIssue =
                  'Location services are off. Enable them in Settings.';
            } else if (issue is PermissionDeniedException) {
              gpsIssue = NavigationGpsIssue.permissionDenied;
              locationIssue =
                  'Location permission is disabled. Enable it in Settings.';
            } else {
              gpsIssue = issue is TimeoutException
                  ? NavigationGpsIssue.stale
                  : NavigationGpsIssue.unavailable;
              locationIssue = 'Waiting for a fresh GPS fix';
            }
            error = locationIssue;
            notifyListeners();
          },
        )..start(
          initialPosition: _localLocationFilter.accepted == null
              ? null
              : initialPosition,
        );
    await _updateWakeLock();
    _startRoadIntelligenceRefreshTimer();
    notifyListeners();
    // Provider refreshes must not delay entering Drive.
    unawaited(loadCameras(force: true));
    unawaited(startTrafficFlowRefresh(force: true));
  }

  Future<void> recoverLocalLocation() async {
    if (active && _localNavigation) {
      await _localLocationFeed?.recover(force: true);
    }
  }

  bool _consumeLocalPosition(Position position) {
    if (!active || _disposed) return false;
    final observation = NavigationLocationFix(
      point: GeoPoint(position.latitude, position.longitude),
      accuracyMeters: position.accuracy,
      speedMetresPerSecond: position.speed.isFinite && position.speed > 0
          ? position.speed
          : 0,
      timestamp: position.timestamp,
    );
    final motion = _localMotion.update(
      observation,
      heading: position.heading,
      headingAccuracy: position.headingAccuracy,
    );
    final speed = motion.speedMetresPerSecond;
    final accepted = _localLocationFilter.accept(
      NavigationLocationFix(
        point: GeoPoint(position.latitude, position.longitude),
        accuracyMeters: position.accuracy,
        speedMetresPerSecond: speed,
        timestamp: position.timestamp,
      ),
    );
    final previous = _localLocationFilter.accepted;
    assert(() {
      if (const bool.fromEnvironment('WAYBI_NAVIGATION_DIAGNOSTICS')) {
        debugPrint(
          'WAYBI_NAV_FIX accuracy=${position.accuracy} '
          'sensorSpeed=${position.speed} motionSpeed=$speed '
          'course=${motion.heading} accepted=${accepted != null}',
        );
      }
      return true;
    }());
    final duplicate =
        previous?.timestamp == position.timestamp &&
        DateTime.now().difference(position.timestamp) <=
            const Duration(seconds: 10);
    if (accepted == null && !duplicate) {
      // A rejected jump must not conceal a still-fresh reliable observation.
      if (latestPosition == null ||
          DateTime.now().difference(latestPosition!.timestamp) >
              const Duration(seconds: 10)) {
        locationIssue = !position.accuracy.isFinite || position.accuracy > 35
            ? 'Waiting for an accurate GPS fix'
            : 'GPS unstable — holding the last reliable position';
        gpsIssue = !position.accuracy.isFinite || position.accuracy > 35
            ? NavigationGpsIssue.acquiring
            : NavigationGpsIssue.unstable;
        error = locationIssue;
        notifyListeners();
      }
      return false;
    }
    if (latestPosition?.timestamp == position.timestamp) return true;
    final fix = accepted ?? previous!;
    if (_route == null) _driveTrail.add(fix);
    error = null;
    locationIssue = null;
    gpsIssue = null;
    latestPosition = position;
    locationAccuracyMeters = fix.accuracyMeters;
    speedKph = speed * 3.6;
    if (speedKph >= 2 && motion.heading != null) {
      _rawHeadingDegrees = motion.heading;
      _headingDegrees = motion.heading;
    } else {
      _rawHeadingDegrees = null;
    }
    _onLocation(
      LatLng(latitude: fix.point.latitude, longitude: fix.point.longitude),
    );
    speedSeverity = speedLimitKph != null && speedKph > speedLimitKph!
        ? SpeedAlertSeverity.minor
        : SpeedAlertSeverity.notSpeeding;
    return true;
  }

  Future<void> loadTrafficFlow({bool force = false}) async {
    if (!force &&
        trafficFlowUpdatedAt != null &&
        DateTime.now().difference(trafficFlowUpdatedAt!) <
            const Duration(seconds: 45)) {
      return;
    }
    try {
      final snapshot = await _trafficFlowRepository.load();
      trafficFlowSegments = snapshot.segments;
      trafficTileOverlay = snapshot.tileOverlay;
      trafficFlowUpdatedAt =
          snapshot.sourceUpdatedAt ?? snapshot.checkedAt ?? DateTime.now();
      trafficFlowStatus = snapshot.syncStatus;
      trafficFlowRevision++;
      notifyListeners();
    } catch (_) {
      if (trafficFlowSegments.isEmpty) {
        trafficFlowStatus = 'unavailable';
        notifyListeners();
      } else {
        trafficFlowStatus = 'stale';
        notifyListeners();
      }
    }
  }

  Future<void> startTrafficFlowRefresh({bool force = false}) async {
    await loadTrafficFlow(force: force);
    // The shared upstream traffic snapshot refreshes every five minutes.
    // Polling every 30 seconds while navigating exhausts Workers Free with
    // 1,000 active drivers but cannot provide fresher traffic information.
    const interval = Duration(minutes: 5);
    if (_trafficFlowRefreshTimer != null &&
        _trafficFlowRefreshInterval == interval) {
      return;
    }
    _trafficFlowRefreshTimer?.cancel();
    _trafficFlowRefreshInterval = interval;
    _trafficFlowRefreshTimer = Timer.periodic(
      interval,
      (_) => unawaited(loadTrafficFlow(force: true)),
    );
  }

  void stopTrafficFlowRefresh() {
    _trafficFlowRefreshTimer?.cancel();
    _trafficFlowRefreshTimer = null;
    _trafficFlowRefreshInterval = null;
  }

  Future<CameraSnapshot?> syncCameraData({required String sessionToken}) async {
    final snapshot = await _nztaProvider.repository.syncNow(
      sessionToken: sessionToken,
    );
    _nztaProvider.lastSnapshot = snapshot;
    await loadCameras(force: true);
    return _nztaProvider.lastSnapshot ?? snapshot;
  }

  Future<void> loadCameras({bool force = false, GeoPoint? center}) async {
    final location =
        center ??
        (latestPosition == null
            ? null
            : GeoPoint(latestPosition!.latitude, latestPosition!.longitude));
    final country = location == null
        ? CountryProfiles.nz
        : CountryProfiles.at(location) ?? CountryProfiles.global;
    final isNsw =
        location != null &&
        location.longitude >= 140.9 &&
        location.longitude <= 153.7 &&
        location.latitude >= -37.6 &&
        location.latitude <= -28.1;
    final region = country.code == 'AU'
        ? (isNsw ? 'AU-NSW' : 'AU-global')
        : country.code;
    final pending = _cameraLoad;
    if (pending != null) {
      await pending;
      if (_roadEventRegion == region) return;
    }
    if (!force && _roadEventRegion == region) return;
    final job = _loadRegionalRoadIntelligence(location, country);
    _cameraLoad = job;
    try {
      await job;
      _roadEventRegion = region;
    } finally {
      if (identical(_cameraLoad, job)) _cameraLoad = null;
    }
  }

  Future<void> _loadRegionalRoadIntelligence(
    GeoPoint? location,
    CountryProfile country,
  ) async {
    loadingCameras = true;
    notifyListeners();
    try {
      _trafficProvider.regionCenter = location;
      final inAuckland =
          location != null &&
          location.longitude >= 174.3 &&
          location.longitude <= 175.6 &&
          location.latitude >= -37.5 &&
          location.latitude <= -36.3;
      unawaited(loadTransitLanes(refresh: inAuckland));
      unawaited(loadTransitReviewCorridors());
      roadEvents = await _providerRegistry.load(country);
      final snapshot = _nztaProvider.lastSnapshot;
      _cameras = country.code == 'NZ'
          ? snapshot?.cameras ?? const []
          : const [];
      final cameraStatus = country.code == 'NZ'
          ? snapshot?.syncStatus ?? 'unavailable'
          : 'not_applicable';
      final trafficStatus = _trafficProvider.lastSyncStatus;
      final providerErrors = _providerRegistry.lastErrors;
      roadIntelligenceStatus =
          cameraStatus == 'stale' || trafficStatus == 'stale'
          ? 'stale'
          : (providerErrors.isNotEmpty ||
                    cameraStatus == 'unavailable' ||
                    trafficStatus == 'unavailable' ||
                    trafficStatus == 'not_loaded'
                ? 'partial'
                : 'live');
      _recomputeRouteCameras();
      error = null;
    } catch (exception) {
      roadIntelligenceStatus = 'unavailable';
      error = 'Could not load safety cameras: $exception';
    } finally {
      loadingCameras = false;
      notifyListeners();
    }
  }

  void _startRoadIntelligenceRefreshTimer() {
    _roadIntelligenceRefreshTimer?.cancel();
    _roadIntelligenceRefreshTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(loadCameras(force: true)),
    );
  }

  void setRoute(RouteOption? route, {bool preserveAlerts = false}) {
    ++_turnRevision;
    unawaited(_voiceEngine.stop());
    _route = route;
    _driveTrail.clear();
    transitLaneMatches = const [];
    upcomingTransitLane = null;
    _pendingTransitAlerts.clear();
    unawaited(_recomputeTransitLanes());
    _routeRoadEvents = RoadIntelligenceEngine.routeEvents(route);
    _progressTracker = route != null && route.points.length >= 2
        ? RouteProgressTracker(route.points)
        : null;
    routeProgress = null;
    if (!preserveAlerts) _spokenAlerts.clear();
    _pendingCameraAlerts.clear();
    _cameraRetryAfter.clear();
    _lastRoadEventEvaluationAt = null;
    _recomputeRouteCameras();
    _cameraLifecycle.reset();
    cameraAlertState = const CameraAlertState.idle();
    upcomingCamera = null;
    upcomingCameraDistanceMeters = null;
    notifyListeners();
  }

  int _cameraMatchJob = 0;

  /// Small routes match synchronously; a long route (Auckland–Wellington is
  /// ~4k points against ~130 cameras) is matched on a background isolate so
  /// a reroute or camera refresh does not stall the UI thread.
  void _recomputeRouteCameras() {
    final job = ++_cameraMatchJob;
    final route = _route;
    final cameras = route == null
        ? const <SafetyCamera>[]
        : _cameras.where(_cameraAlertFilter).toList(growable: false);
    if (route == null || route.points.length * cameras.length <= 100000) {
      _applyRouteCameras(
        route == null ? const [] : _routeMatcher.match(route, cameras),
      );
      return;
    }
    unawaited(
      compute(_matchCamerasInBackground, (route, cameras)).then(
        (matches) {
          if (_disposed ||
              job != _cameraMatchJob ||
              !identical(route, _route)) {
            return;
          }
          _applyRouteCameras(matches);
          notifyListeners();
        },
        onError: (Object error) {
          debugPrint('Route camera matching failed: $error');
        },
      ),
    );
  }

  void _applyRouteCameras(List<RouteCameraMatch> matches) {
    routeCameras = matches;
    _highConfidenceCameraIds = routeCameras
        .where((match) => match.highConfidence)
        .map((match) => match.camera.id)
        .toSet();
  }

  void _onLocation(LatLng current) {
    if (!active || _disposed) return;
    final previous = _lastRawLocation;
    _lastRawLocation = current;

    if (previous != null) {
      final travelled = distanceMeters(
        previous.latitude,
        previous.longitude,
        current.latitude,
        current.longitude,
      );
      if (_rawHeadingDegrees == null &&
          speedKph > 5 &&
          travelled >= math.max(8, locationAccuracyMeters)) {
        _headingDegrees = bearingDegrees(
          previous.latitude,
          previous.longitude,
          current.latitude,
          current.longitude,
        );
      }
    }

    // Keep raw GPS for deviation detection and rerouting. Only the display
    // puck is snapped: otherwise a genuine missed turn would be concealed.
    final routeForFix = _route;
    routeProgress = routeForFix == null
        ? null
        : _progressTracker?.update(
            GeoPoint(current.latitude, current.longitude),
            time: _localNavigation
                ? latestPosition?.timestamp ?? DateTime.now()
                : DateTime.now(),
            accuracyMeters: locationAccuracyMeters,
            speedKph: speedKph,
            headingDegrees: _rawHeadingDegrees,
          );
    final projection = routeProgress;
    final aligned =
        _rawHeadingDegrees == null ||
        speedKph < 15 ||
        projection == null ||
        angleDifference(_rawHeadingDegrees!, projection.bearingDegrees) < 80;
    final snapped = projection?.point;
    final canSnap =
        _localNavigation &&
        aligned &&
        snapped != null &&
        projection!.offsetMeters <=
            (locationAccuracyMeters * 1.4).clamp(12, 30);
    _lastSnappedLocation = canSnap
        ? LatLng(latitude: snapped.latitude, longitude: snapped.longitude)
        : current;
    if (canSnap && speedKph >= 2) _headingDegrees = projection.bearingDegrees;
    locationRevision++;
    final country = CountryProfiles.at(
      GeoPoint(current.latitude, current.longitude),
    );
    if (country?.code != 'NZ') {
      _cameraLifecycle.reset();
      upcomingCamera = null;
      upcomingCameraDistanceMeters = null;
      passedCamera = null;
      cameraAlertState = const CameraAlertState.idle();
    }
    unawaited(_refreshSpeedLimit(current));

    CameraMatch? match;
    final route = _route;
    if (route != null) {
      final point = GeoPoint(current.latitude, current.longitude);
      final progress =
          routeProgress ??
          (_progressTracker == null
              ? _routeMatcher.project(point, route.points)
              : null);
      routeProgress = progress;
      final upcoming =
          progress == null ||
              progress.offsetMeters >
                  (locationAccuracyMeters * 1.5).clamp(35, 100)
          ? null
          : routeCameras
                .where(
                  (match) =>
                      match.highConfidence &&
                      match.alongMeters - progress.alongMeters >= -15 &&
                      match.alongMeters - progress.alongMeters <= 1200,
                )
                .firstOrNull;
      if (upcoming != null && progress != null) {
        match = CameraMatch(
          camera: upcoming.camera,
          distanceMeters: (upcoming.alongMeters - progress.alongMeters).clamp(
            0,
            1200,
          ),
          passKey: upcoming.pass == 0 ? null : upcoming.alertKey,
        );
      }
    } else {
      match = _cameraMatcher.findUpcoming(
        latitude: current.latitude,
        longitude: current.longitude,
        cameras: _cameras.where(_cameraAlertFilter).toList(growable: false),
        headingDegrees: _headingDegrees,
      );
    }

    final now = DateTime.now();
    final lastEventLocation = _lastRoadEventEvaluationLocation;
    _updateTransitLane(now);
    final eventMove = lastEventLocation == null
        ? double.infinity
        : distanceMeters(
            lastEventLocation.latitude,
            lastEventLocation.longitude,
            current.latitude,
            current.longitude,
          );
    if (_lastRoadEventEvaluationAt == null ||
        now.difference(_lastRoadEventEvaluationAt!).inSeconds >= 5 ||
        eventMove >= 35) {
      upcomingRoadEvents = _roadIntelligence.relevant(
        driver: GeoPoint(current.latitude, current.longitude),
        events: route == null
            ? roadEvents
            : roadEvents
                  .where(
                    (event) =>
                        event.type != RoadEventType.safetyCamera ||
                        _highConfidenceCameraIds.contains(
                          event.source.sourceId,
                        ),
                  )
                  .followedBy(_routeRoadEvents)
                  .toList(growable: false),
        headingDegrees: _headingDegrees,
        route: route,
        progress: routeProgress,
        now: now,
      );
      _lastRoadEventEvaluationAt = now;
      _lastRoadEventEvaluationLocation = current;
    }

    cameraAlertState = _cameraLifecycle.update(match, now);
    _spokenAlerts.expire(now);
    if (cameraAlertState.phase == CameraAlertPhase.passed) {
      _spokenAlerts.passed(cameraAlertState.alertKey);
    }
    if (cameraAlertState.phase == CameraAlertPhase.approaching) {
      upcomingCamera = match?.camera;
      upcomingCameraDistanceMeters = match?.distanceMeters;
      passedCamera = null;
      if (match != null) unawaited(_maybeAlert(match));
    } else if (cameraAlertState.phase == CameraAlertPhase.passed) {
      upcomingCamera = null;
      upcomingCameraDistanceMeters = null;
      passedCamera = _cameras
          .where((camera) => camera.id == cameraAlertState.cameraId)
          .firstOrNull;
    } else {
      upcomingCamera = null;
      upcomingCameraDistanceMeters = null;
      passedCamera = null;
    }

    notifyListeners();
  }

  /// A free-form message. Prefer [speakUtterance] with a [VoicePrompts]
  /// builder, so a custom voice can play every fixed word.
  Future<void> speakMessage(String message) async {
    if (!voiceEnabled) return;
    try {
      await _voiceEngine.guidance(
        message,
        language: navigationLanguage == 'zh' ? 'zh-CN' : 'en-NZ',
      );
    } catch (_) {
      debugPrint('Navigation audio unavailable');
    }
  }

  /// A prompt built from parts (for example [VoicePrompts.arrival]), spoken
  /// in its own language.
  Future<void> speakUtterance(VoiceUtterance prompt) async {
    if (!voiceEnabled) return;
    try {
      await _voiceEngine.say(prompt);
    } catch (_) {
      debugPrint('Navigation audio unavailable');
    }
  }

  /// A maneuver prompt: plays before queued camera, road and transit alerts
  /// (an [urgent] one interrupts an alert already speaking). [message] is
  /// built when spoken, so its distance is current; [stillRelevant] drops it
  /// once the maneuver is passed or superseded.
  Future<void> speakTurn(
    String Function() message, {
    bool Function()? stillRelevant,
    bool urgent = false,
  }) async {
    if (!voiceEnabled) return;
    final session = _locationSession;
    try {
      await _voiceEngine.turnPrompt(
        message,
        language: navigationLanguage == 'zh' ? 'zh-CN' : 'en-NZ',
        urgent: urgent,
        stillRelevant: () =>
            active &&
            voiceEnabled &&
            session == _locationSession &&
            (stillRelevant?.call() ?? true),
      );
    } catch (_) {
      debugPrint('Navigation audio unavailable');
    }
  }

  /// [speakTurn] for a prompt built from parts ([VoicePrompts.turn]).
  Future<void> speakTurnUtterance(
    VoiceUtterance Function() prompt, {
    bool Function()? stillRelevant,
    bool urgent = false,
  }) async {
    if (!voiceEnabled) return;
    final session = _locationSession;
    try {
      await _voiceEngine.turnUtterance(
        prompt,
        urgent: urgent,
        stillRelevant: () =>
            active &&
            voiceEnabled &&
            session == _locationSession &&
            (stillRelevant?.call() ?? true),
      );
    } catch (_) {
      debugPrint('Navigation audio unavailable');
    }
  }

  Future<void> _refreshSpeedLimit(LatLng current) async {
    final now = DateTime.now();
    final at = GeoPoint(current.latitude, current.longitude);
    if (speedLimitKph != null && _speedLimitPacer.isStale(now, at)) {
      // Lookups have failed or been rate limited for a long way: an old limit
      // may belong to a different road.
      speedLimitKph = null;
      speedLimitZoneName = null;
    }
    if (!_speedLimitPacer.shouldLookUp(now, at, speedKph)) return;
    final session = _locationSession;
    _speedLimitPacer.started(now, at);
    try {
      final info = await _speedLimitRepository.fetch(
        latitude: current.latitude,
        longitude: current.longitude,
      );
      if (!active || _disposed || session != _locationSession) return;
      _speedLimitPacer.finished(DateTime.now(), success: true);
      final latest = _lastSnappedLocation;
      if (latest != null &&
          SpeedLimitPacer.stillApplies(
            at,
            GeoPoint(latest.latitude, latest.longitude),
            speedKph,
          )) {
        speedLimitKph = info.speedLimitKph;
        speedLimitZoneName = info.zoneName;
        notifyListeners();
      }
    } on RateLimitedException catch (error) {
      if (session != _locationSession) return;
      // Keep a fresh limit; staleness clears it if the back-off lasts.
      _speedLimitPacer.finished(DateTime.now(), retryAfter: error.retryAfter);
    } catch (_) {
      if (!active || _disposed || session != _locationSession) return;
      _speedLimitPacer.finished(DateTime.now());
      // An old limit may belong to a different road or region.
      speedLimitKph = null;
      speedLimitZoneName = null;
      notifyListeners();
    }
  }

  Future<void> _maybeAlert(CameraMatch match) async {
    if (!voiceEnabled) return;
    final distance = match.distanceMeters;
    if (distance <= 0) return;
    final threshold = distance <= 300
        ? 300
        : distance <= 800
        ? 800
        : null;
    if (threshold == null) return;
    final key = '${match.alertKey}:$threshold';
    if (_spokenAlerts.contains(match.alertKey, threshold) ||
        _pendingCameraAlerts.containsKey(key) ||
        (_cameraRetryAfter[key]?.isAfter(DateTime.now()) ?? false)) {
      return;
    }
    final token = Object();
    _pendingCameraAlerts[key] = token;
    final session = _locationSession;
    final revision = _turnRevision;
    try {
      final spoken = await _voiceEngine.cameraAlert(
        distanceMeters: threshold,
        cameraType: match.camera.type,
        roadName: match.camera.location,
        speedLimit: speedLimitKph?.toString(),
        currentDistanceMeters: () =>
            (upcomingCameraDistanceMeters ?? distance).round(),
        stillRelevant: () =>
            active &&
            session == _locationSession &&
            revision == _turnRevision &&
            voiceEnabled &&
            upcomingCamera?.id == match.camera.id &&
            (upcomingCameraDistanceMeters ?? 0) > 0 &&
            (threshold != 800 || (upcomingCameraDistanceMeters ?? 0) > 300),
      );
      if (spoken && session == _locationSession && revision == _turnRevision) {
        _spokenAlerts.record(match.alertKey, threshold, DateTime.now());
      }
    } catch (_) {
      // Audio errors must not become unhandled navigation errors or consume
      // this camera's reminder. Retry while it is still ahead.
      if (identical(_pendingCameraAlerts[key], token)) {
        _cameraRetryAfter[key] = DateTime.now().add(const Duration(seconds: 5));
      }
    } finally {
      if (identical(_pendingCameraAlerts[key], token)) {
        _pendingCameraAlerts.remove(key);
      }
    }
  }

  Future<void> stop() async {
    // Capture the session and reset state before the first await: a new
    // Drive session started while the old feed or voice is stopping must not
    // be switched off by this call afterwards.
    final session = ++_locationSession;
    final localFeed = _localLocationFeed;
    _localLocationFeed = null;
    _driveTrail.clear();
    locationIssue = null;
    gpsIssue = null;
    active = false;
    guidanceRunning = false;
    _progressTracker = null;
    routeProgress = null;
    _roadIntelligenceRefreshTimer?.cancel();
    _roadIntelligenceRefreshTimer = null;
    stopTrafficFlowRefresh();
    _localLocationFilter.reset();
    _spokenAlerts.clear();
    _pendingCameraAlerts.clear();
    _pendingTransitAlerts.clear();
    _spokenTransitAlerts.clear();
    _transitRetryAfter.clear();
    upcomingTransitLane = null;
    transitLaneMatches = const [];
    _cameraRetryAfter.clear();
    _cameraLifecycle.reset();
    _route = null;
    _routeRoadEvents = const [];
    routeCameras = const [];
    upcomingRoadEvents = const [];
    upcomingCamera = null;
    upcomingCameraDistanceMeters = null;
    passedCamera = null;
    cameraAlertState = const CameraAlertState.idle();
    speedKph = 0;
    speedLimitKph = null;
    speedLimitZoneName = null;
    _speedLimitPacer.reset();
    _lastSnappedLocation = null;
    _lastRawLocation = null;
    latestPosition = null;
    _rawHeadingDegrees = null;
    _localNavigation = false;
    _lastRoadEventEvaluationAt = null;
    _lastRoadEventEvaluationLocation = null;
    await localFeed?.stop();
    if (session != _locationSession || _disposed) return;
    await _voiceEngine.stop();
    if (session != _locationSession || _disposed) return;
    unawaited(WakelockPlus.disable().catchError((Object _) {}));
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_localLocationFeed?.stop());
    active = false;
    ++_locationSession;
    unawaited(WakelockPlus.disable().catchError((Object _) {}));
    _roadIntelligenceRefreshTimer?.cancel();
    _trafficFlowRefreshTimer?.cancel();
    _trafficFlowRepository.dispose();
    unawaited(_voiceEngine.dispose());
    super.dispose();
  }
}
