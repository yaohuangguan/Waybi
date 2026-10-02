import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';

import '../data/camera_repository.dart';
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
import 'voice_engine.dart';
import 'navigation_language.dart';
import 'navigation_location_filter.dart';

class DriveEngine extends ChangeNotifier {
  DriveEngine({
    CameraRepository? cameraRepository,
    CameraMatcher? cameraMatcher,
    VoiceEngine? voiceEngine,
    SpeedLimitRepository? speedLimitRepository,
    TrafficFlowRepository? trafficFlowRepository,
    RoadIntelligenceEngine? roadIntelligence,
    CameraAlertLifecycle? cameraLifecycle,
  }) : _cameraMatcher = cameraMatcher ?? const CameraMatcher(),
       _voiceEngine = voiceEngine ?? VoiceEngine(),
       _speedLimitRepository = speedLimitRepository ?? SpeedLimitRepository(),
       _trafficFlowRepository =
           trafficFlowRepository ?? TrafficFlowRepository(),
       _roadIntelligence = roadIntelligence ?? RoadIntelligenceEngine(),
       _cameraLifecycle = cameraLifecycle ?? CameraAlertLifecycle() {
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
  final SpeedLimitRepository _speedLimitRepository;
  final TrafficFlowRepository _trafficFlowRepository;
  final RoadIntelligenceEngine _roadIntelligence;
  final CameraAlertLifecycle _cameraLifecycle;
  late final NztaRoadEventProvider _nztaProvider;
  late final NztaTrafficRoadEventProvider _trafficProvider;
  late final RoadEventProviderRegistry _providerRegistry;

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _disposed = false;
  int _locationSession = 0;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Timer? _roadIntelligenceRefreshTimer;
  Timer? _trafficFlowRefreshTimer;
  final Set<String> _spokenAlerts = <String>{};
  final RouteCameraMatcher _routeMatcher = const RouteCameraMatcher();
  final NavigationLocationFilter _localLocationFilter =
      NavigationLocationFilter();

  List<SafetyCamera> _cameras = const [];
  RouteOption? _route;
  RouteProgressTracker? _progressTracker;
  RouteProjection? routeProgress;
  double locationAccuracyMeters = 10;
  int locationRevision = 0;
  Set<String> _highConfidenceCameraIds = const {};
  List<RouteCameraMatch> routeCameras = const [];
  List<SafetyCamera> get cameras => _cameras;
  CameraSnapshot? get cameraSnapshot => _nztaProvider.lastSnapshot;
  List<RoadEvent> roadEvents = const [];
  List<RoadEvent> upcomingRoadEvents = const [];
  List<TrafficFlowSegment> trafficFlowSegments = const [];
  DateTime? trafficFlowUpdatedAt;
  String trafficFlowStatus = 'not_loaded';
  int trafficFlowRevision = 0;
  String roadIntelligenceStatus = 'not_loaded';
  bool get roadIntelligenceStale => roadIntelligenceStatus == 'stale';
  int get routeCameraCount => routeCameras.length;
  LatLng? get snappedLocation => _lastSnappedLocation;
  double? get snappedHeadingDegrees => _headingDegrees;
  LatLng? _lastSnappedLocation;
  LatLng? _lastSpeedLimitLocation;
  DateTime? _lastSpeedLimitLookup;
  DateTime? _lastRoadEventEvaluationAt;
  LatLng? _lastRoadEventEvaluationLocation;
  bool _speedLimitLookupPending = false;
  double? _headingDegrees;
  Completer<void>? _roadSnappedFixCompleter;

  bool active = false;
  bool guidanceRunning = false;
  bool loadingCameras = false;
  double speedKph = 0;
  int? speedLimitKph;
  bool _voiceEnabled = true;
  bool _keepScreenAwake = true;
  String navigationLanguage = 'en';
  String? _spokenTurn;
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
  NavInfo? navInfo;
  DateTime? navInfoUpdatedAt;
  bool get nativeGuidanceStale =>
      guidanceRunning &&
      (navInfoUpdatedAt == null ||
          DateTime.now().difference(navInfoUpdatedAt!).inSeconds >= 8);
  String? error;

  Future<void> start() async {
    if (active || _disposed) return;
    ++_locationSession;
    _roadSnappedFixCompleter = Completer<void>();
    error = null;

    await _voiceEngine.initialize();
    await loadCameras(force: true);

    final snapped =
        await GoogleMapsNavigator.setRoadSnappedLocationUpdatedListener(
          _onRoadSnappedLocation,
        );
    _subscriptions.add(snapped);

    _subscriptions.add(
      GoogleMapsNavigator.setSpeedingUpdatedListener((event) {
        speedSeverity = event.severity;
        percentageAboveLimit = event.percentageAboveLimit;
        notifyListeners();
      }),
    );

    _subscriptions.add(
      GoogleMapsNavigator.setNavInfoListener(
        (event) {
          navInfo = event.navInfo;
          navInfoUpdatedAt = DateTime.now();
          guidanceRunning =
              event.navInfo.navState == NavState.enroute ||
              event.navInfo.navState == NavState.rerouting;
          _speakNativeTurn(event.navInfo);
          notifyListeners();
        },
        numNextStepsToPreview: 3,
        stepImageGenerationOptions: const StepImageGenerationOptions(
          generateLaneImages: true,
        ),
      ),
    );

    _subscriptions.add(
      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
        ),
      ).listen((position) {
        final metresPerSecond = position.speed.isFinite && position.speed > 0
            ? position.speed
            : 0;
        speedKph = metresPerSecond * 3.6;
        if (_lastSnappedLocation == null) {
          _onLocation(
            LatLng(latitude: position.latitude, longitude: position.longitude),
          );
        } else {
          notifyListeners();
        }
      }),
    );
    active = true;
    await _updateWakeLock();
    _startRoadIntelligenceRefreshTimer();
    notifyListeners();
  }

  /// Local location feed for a non-Google map renderer. Camera alerts keep
  /// using the same matching and voice logic, without starting Google SDK.
  Future<void> startLocal() async {
    if (active || _disposed) return;
    ++_locationSession;
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Turn on location services to start driving');
    }
    _roadSnappedFixCompleter = Completer<void>();
    error = null;
    await _voiceEngine.initialize();

    final routeStart = _route != null && _route!.points.isNotEmpty
        ? _route!.points.first
        : null;
    _localLocationFilter.reset(anchor: routeStart);
    active = true;
    guidanceRunning = _route != null;

    // Keep the puck on the freshly-calculated route origin until iOS provides
    // a trustworthy fix. This prevents an indoor 50–100 m GPS jump from
    // instantly moving the Kiwi onto a nearby motorway.
    if (routeStart != null) {
      locationAccuracyMeters = 20;
      _onLocation(
        LatLng(latitude: routeStart.latitude, longitude: routeStart.longitude),
      );
    }

    final settings = switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Kiwi Lens Drive',
          notificationText: 'Navigation and safety-camera alerts are active',
          notificationChannelName: 'Kiwi Lens navigation',
          enableWakeLock: true,
          setOngoing: true,
        ),
      ),
      TargetPlatform.iOS => AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      ),
      _ => const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      ),
    };
    _subscriptions.add(
      Geolocator.getPositionStream(locationSettings: settings).listen(
        (position) {
          if (!active || _disposed) return;
          final metresPerSecond = position.speed.isFinite && position.speed > 0
              ? position.speed
              : 0.0;
          final accepted = _localLocationFilter.accept(
            NavigationLocationFix(
              point: GeoPoint(position.latitude, position.longitude),
              accuracyMeters: position.accuracy,
              speedMetresPerSecond: metresPerSecond,
              timestamp: position.timestamp,
            ),
          );
          if (accepted == null) {
            error = !position.accuracy.isFinite || position.accuracy > 35
                ? 'Waiting for an accurate GPS fix'
                : 'GPS unstable — holding the last reliable position';
            notifyListeners();
            return;
          }

          error = null;
          locationAccuracyMeters = accepted.accuracyMeters;
          speedKph = metresPerSecond * 3.6;
          if (speedKph > 5 &&
              position.heading.isFinite &&
              position.heading >= 0) {
            _headingDegrees = position.heading;
          }
          _onLocation(
            LatLng(
              latitude: accepted.point.latitude,
              longitude: accepted.point.longitude,
            ),
          );
          speedSeverity = speedLimitKph != null && speedKph > speedLimitKph!
              ? SpeedAlertSeverity.minor
              : SpeedAlertSeverity.notSpeeding;
        },
        onError: (Object _) {
          if (!active || _disposed) return;
          error = 'Location unavailable. Check GPS and location permission.';
          notifyListeners();
        },
      ),
    );
    await _updateWakeLock();
    _startRoadIntelligenceRefreshTimer();
    notifyListeners();
    // Provider refreshes must not delay entering Drive.
    unawaited(loadCameras(force: true));
    unawaited(loadTrafficFlow(force: true));
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
      }
    }
    _trafficFlowRefreshTimer ??= Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(loadTrafficFlow(force: true)),
    );
  }

  Future<CameraSnapshot?> syncCameraData({required String sessionToken}) async {
    final snapshot = await _nztaProvider.repository.syncNow(
      sessionToken: sessionToken,
    );
    _nztaProvider.lastSnapshot = snapshot;
    await loadCameras(force: true);
    return _nztaProvider.lastSnapshot ?? snapshot;
  }

  Future<void> loadCameras({bool force = false}) async {
    if (loadingCameras || (!force && _cameras.isNotEmpty)) return;
    loadingCameras = true;
    notifyListeners();
    try {
      roadEvents = await _providerRegistry.load(CountryProfiles.nz);
      final snapshot = _nztaProvider.lastSnapshot;
      _cameras = snapshot?.cameras ?? const [];
      final cameraStatus = snapshot?.syncStatus ?? 'unavailable';
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
    _spokenTurn = null;
    ++_turnRevision;
    unawaited(_voiceEngine.stop());
    _route = route;
    navInfoUpdatedAt = null;
    _progressTracker = route != null && route.points.length >= 2
        ? RouteProgressTracker(route.points)
        : null;
    routeProgress = null;
    if (!preserveAlerts) _spokenAlerts.clear();
    _lastRoadEventEvaluationAt = null;
    _recomputeRouteCameras();
    _cameraLifecycle.reset();
    cameraAlertState = const CameraAlertState.idle();
    upcomingCamera = null;
    upcomingCameraDistanceMeters = null;
    notifyListeners();
  }

  void _recomputeRouteCameras() {
    routeCameras = _route == null
        ? const []
        : _routeMatcher.match(
            _route!,
            _cameras.where(_cameraAlertFilter).toList(growable: false),
          );
    _highConfidenceCameraIds = routeCameras
        .where((match) => match.highConfidence)
        .map((match) => match.camera.id)
        .toSet();
  }

  void _onRoadSnappedLocation(RoadSnappedLocationUpdatedEvent event) {
    _onLocation(event.location);
  }

  void _onLocation(LatLng current) {
    if (!active || _disposed) return;
    final fix = _roadSnappedFixCompleter;
    if (fix != null && !fix.isCompleted) fix.complete();
    final previous = _lastSnappedLocation;

    if (previous != null) {
      final travelled = distanceMeters(
        previous.latitude,
        previous.longitude,
        current.latitude,
        current.longitude,
      );
      if (travelled >= 8) {
        _headingDegrees = bearingDegrees(
          previous.latitude,
          previous.longitude,
          current.latitude,
          current.longitude,
        );
      }
    }

    _lastSnappedLocation = current;
    locationRevision++;
    final country = CountryProfiles.at(
      GeoPoint(current.latitude, current.longitude),
    );
    if (country?.code != 'NZ') {
      roadIntelligenceStatus = 'unsupported';
      _cameraLifecycle.reset();
      upcomingRoadEvents = const [];
      upcomingCamera = null;
      upcomingCameraDistanceMeters = null;
      passedCamera = null;
      cameraAlertState = const CameraAlertState.idle();
      speedLimitKph = null;
      speedLimitZoneName = null;
      notifyListeners();
      return;
    }
    unawaited(_refreshSpeedLimit(current));

    CameraMatch? match;
    final route = _route;
    if (route != null) {
      final point = GeoPoint(current.latitude, current.longitude);
      final progress =
          _progressTracker?.update(
            point,
            time: DateTime.now(),
            accuracyMeters: locationAccuracyMeters,
            speedKph: speedKph,
          ) ??
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
                  .toList(growable: false),
        headingDegrees: _headingDegrees,
        route: route,
        now: now,
      );
      _lastRoadEventEvaluationAt = now;
      _lastRoadEventEvaluationLocation = current;
    }

    cameraAlertState = _cameraLifecycle.update(match, DateTime.now());
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

  Future<bool> waitForRoadSnappedLocation({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (_lastSnappedLocation != null) return true;
    final fix = _roadSnappedFixCompleter ??= Completer<void>();
    try {
      await fix.future.timeout(timeout);
      return _lastSnappedLocation != null;
    } on TimeoutException {
      return false;
    }
  }

  Future<void> speakMessage(String message) async {
    if (!voiceEnabled) return;
    await _voiceEngine.guidance(
      message,
      language: navigationLanguage == 'zh' ? 'zh-CN' : 'en-NZ',
    );
  }

  void _speakNativeTurn(NavInfo info) {
    if (!_voiceEnabled || _route == null || info.navState != NavState.enroute) {
      return;
    }
    final step = info.currentStep;
    final distance = info.distanceToCurrentStepMeters;
    if (step == null || distance == null || distance > 800) return;
    if (info.routeChanged) {
      _spokenTurn = null;
      ++_turnRevision;
    }
    final bucket = distance <= 60
        ? 0
        : distance <= 300
        ? 300
        : 800;
    final identity =
        '${step.stepNumber}:${step.maneuver.name}:${step.fullRoadName}';
    final key = '$identity:$bucket:$navigationLanguage';
    if (_spokenTurn == key) return;
    _spokenTurn = key;
    final revision = _turnRevision;
    final instruction = navigationInstruction(step, navigationLanguage);
    final message = bucket == 0
        ? instruction
        : navigationLanguage == 'zh'
        ? '${navigationMetres(distance, navigationLanguage)}后，$instruction'
        : 'In ${navigationMetres(distance, navigationLanguage)}, $instruction';
    unawaited(
      _voiceEngine
          .guidance(
            message,
            language: navigationLanguage == 'zh' ? 'zh-CN' : 'en-NZ',
            stillRelevant: () =>
                active &&
                _voiceEnabled &&
                _route != null &&
                revision == _turnRevision &&
                _spokenTurn == key,
          )
          .catchError((Object _) {}),
    );
  }

  Future<void> _refreshSpeedLimit(LatLng current) async {
    if (_speedLimitLookupPending) return;
    final now = DateTime.now();
    final last = _lastSpeedLimitLocation;
    final moved = last == null
        ? double.infinity
        : distanceMeters(
            last.latitude,
            last.longitude,
            current.latitude,
            current.longitude,
          );
    final recent =
        _lastSpeedLimitLookup != null &&
        now.difference(_lastSpeedLimitLookup!).inSeconds < 15;
    if (recent && moved < 75) return;

    final session = _locationSession;
    _speedLimitLookupPending = true;
    _lastSpeedLimitLookup = now;
    _lastSpeedLimitLocation = current;
    try {
      final info = await _speedLimitRepository.fetch(
        latitude: current.latitude,
        longitude: current.longitude,
      );
      if (!active || _disposed || session != _locationSession) return;
      final latest = _lastSnappedLocation;
      if (latest != null &&
          distanceMeters(
                current.latitude,
                current.longitude,
                latest.latitude,
                latest.longitude,
              ) <
              100 &&
          CountryProfiles.at(GeoPoint(latest.latitude, latest.longitude))
                  ?.code ==
              'NZ') {
        speedLimitKph = info.speedLimitKph;
        speedLimitZoneName = info.zoneName;
        notifyListeners();
      }
    } catch (_) {
      if (!active || _disposed || session != _locationSession) return;
      // An old limit may belong to a different road or region.
      speedLimitKph = null;
      speedLimitZoneName = null;
      notifyListeners();
    } finally {
      _speedLimitLookupPending = false;
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
    if (threshold == 300) {
      _spokenAlerts.add('${match.camera.id}:800');
    }
    final key = '${match.camera.id}:$threshold';
    if (!_spokenAlerts.add(key)) return;
    await _voiceEngine.cameraAlert(
      distanceMeters: threshold,
      cameraType: match.camera.type,
      roadName: match.camera.location,
      speedLimit: speedLimitKph?.toString(),
      stillRelevant: () =>
          active &&
          voiceEnabled &&
          upcomingCamera?.id == match.camera.id &&
          (upcomingCameraDistanceMeters ?? 0) > 0 &&
          (threshold != 800 || (upcomingCameraDistanceMeters ?? 0) > 300),
    );
  }

  Future<void> stop() async {
    ++_locationSession;
    active = false;
    guidanceRunning = false;
    await _voiceEngine.stop();
    unawaited(WakelockPlus.disable().catchError((Object _) {}));
    _progressTracker = null;
    routeProgress = null;
    _roadIntelligenceRefreshTimer?.cancel();
    _roadIntelligenceRefreshTimer = null;
    _localLocationFilter.reset();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _spokenAlerts.clear();
    _cameraLifecycle.reset();
    _route = null;
    routeCameras = const [];
    upcomingRoadEvents = const [];
    active = false;
    guidanceRunning = false;
    upcomingCamera = null;
    upcomingCameraDistanceMeters = null;
    passedCamera = null;
    cameraAlertState = const CameraAlertState.idle();
    navInfo = null;
    speedKph = 0;
    speedLimitKph = null;
    speedLimitZoneName = null;
    _lastSpeedLimitLocation = null;
    _lastSnappedLocation = null;
    _roadSnappedFixCompleter = null;
    _lastSpeedLimitLookup = null;
    _lastRoadEventEvaluationAt = null;
    _lastRoadEventEvaluationLocation = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    active = false;
    ++_locationSession;
    unawaited(WakelockPlus.disable().catchError((Object _) {}));
    _roadIntelligenceRefreshTimer?.cancel();
    _trafficFlowRefreshTimer?.cancel();
    _trafficFlowRepository.dispose();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_voiceEngine.dispose());
    super.dispose();
  }
}
