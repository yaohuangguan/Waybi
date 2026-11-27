import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/scheduler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_friends/waybi_friends.dart'
    show GameController, JourneyMemory;
import 'package:flutter/services.dart';

import 'data/account_repository.dart';
import 'data/friends_backup_service.dart';
import 'data/brand_migration.dart';
import 'data/app_store_billing.dart';
import 'data/explore_repository.dart';
import 'data/place_details_repository.dart';
import 'data/parking_repository.dart';
import 'data/usage_telemetry_repository.dart';
import 'data/navigation_reward_repository.dart';
import 'data/navigation_feedback_repository.dart';
import 'domain/map_layer_settings.dart';
import 'domain/map_provider.dart';
import 'domain/navigation_camera_mode.dart';
import 'domain/geo_math.dart';
import 'domain/route_option.dart';
import 'domain/route_reachability.dart';
import 'domain/route_preference.dart';
import 'domain/routing_origin.dart';
import 'domain/road_event.dart';
import 'domain/route_road_events.dart' as road_routes;
import 'domain/safety_camera.dart';
import 'domain/transit_lane.dart';
import 'domain/transit_review_corridor.dart';
import 'drive/journey_tracker.dart';
import 'drive/navigation_location_filter.dart';
import 'widgets/status_banner.dart';
import 'drive/independent_navigation_camera.dart';
import 'services/native_map_language.dart';
import 'services/external_navigation_inbox.dart';
import 'widgets/journey_summary_sheet.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/home_sheets.dart';
import 'app/trip_state.dart';
import 'drive/custom_voice.dart';
import 'drive/drive_engine.dart';
import 'drive/system_navigation.dart';
import 'widgets/system_navigation_status.dart';
import 'providers/independent_map_renderer.dart';
import 'providers/independent_navigation_engine.dart';
import 'providers/independent_routing_provider.dart';
import 'providers/independent_transit_routing_provider.dart';
import 'providers/place_search_providers.dart';
import 'providers/provider_contracts.dart';
import 'services/notification_service.dart';
import 'theme/waybi_theme.dart';
import 'widgets/arrival_experience_panel.dart';
import 'widgets/independent_navigation_overlay.dart';
import 'widgets/drive_hud.dart';
import 'widgets/discover_page.dart';
import 'widgets/explore_search.dart';
import 'widgets/explore_page.dart';
import 'widgets/friendly_error.dart';
import 'widgets/full_screen_search.dart';
import 'widgets/companion_search_prompt.dart';
import 'widgets/place_details_content.dart';
import 'widgets/profile_page.dart';
import 'widgets/map_layer_sheet.dart';
import 'widgets/splash_gate.dart';
import 'widgets/route_preview_sheet.dart';
import 'widgets/transit_trip_overlay.dart';
import 'widgets/trips_page.dart';
import 'app/commute_controller.dart';
import 'app/home_chrome.dart';
import 'app/location_controller.dart';
import 'app/road_alerts.dart';
import 'app/journey_store.dart';
import 'app/navigation_session_controller.dart';
import 'app/place_selection_controller.dart';
import 'app/route_preview_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ExternalNavigationInbox.instance.start();
  final prefs = await SharedPreferences.getInstance();
  await migrateWaybiPreferences(prefs);
  if (prefs.containsKey(GameController.embedded.pendingRestoreKey)) {
    try {
      await GameController.embedded.load();
    } catch (_) {
      // Keep the archive for retry; the room presents its existing load error UI.
    }
  }
  runApp(const WaybiApp());
}

class WaybiApp extends StatefulWidget {
  const WaybiApp({super.key});

  @override
  State<WaybiApp> createState() => _WaybiAppState();
}

class _WaybiAppState extends State<WaybiApp> {
  ThemeMode _themeMode = ThemeMode.system;
  Locale _locale = const Locale('en');

  @override
  void initState() {
    super.initState();
    unawaited(_restoreAppearance());
  }

  Future<void> _restoreAppearance() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('waybi.appearance') ?? 'system';
    final mode = switch (saved) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    if (mounted) {
      setState(() {
        _themeMode = mode;
        _locale = Locale(prefs.getString('waybi.app.language') ?? 'en');
      });
    }
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    setState(() => _themeMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('waybi.appearance', switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Waybi',
      locale: _locale,
      supportedLocales: const [Locale('en'), Locale('zh')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      debugShowCheckedModeBanner: false,
      theme: WaybiTheme.lightFor(_locale.languageCode),
      darkTheme: WaybiTheme.darkFor(_locale.languageCode),
      themeMode: _themeMode,
      home: SplashGate(
        language: _locale.languageCode,
        child: MapHomePage(
          themeMode: _themeMode,
          onAppLanguageChanged: (value) =>
              setState(() => _locale = Locale(value)),
          onThemeModeChanged: (mode) => unawaited(_setThemeMode(mode)),
        ),
      ),
    );
  }
}

class MapHomePage extends StatefulWidget {
  const MapHomePage({
    super.key,
    this.themeMode = ThemeMode.system,
    this.driveEngine,
    this.onThemeModeChanged,
    this.onAppLanguageChanged,
  });

  final ThemeMode themeMode;

  /// Optional data adapters for embedding and tests; this page owns the engine's lifetime.
  final DriveEngine? driveEngine;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final ValueChanged<String>? onAppLanguageChanged;

  @override
  State<MapHomePage> createState() => _MapHomePageState();
}

class _MapHomePageState extends State<MapHomePage>
    with WidgetsBindingObserver
    implements TripHost {
  bool _externalNavigationReady = false;

  late final DriveEngine _driveEngine = widget.driveEngine ?? DriveEngine();
  late final IndependentNavigationEngine _independentNavigation;
  final AccountRepository _account = AccountRepository();
  late final _friendsBackup = FriendsBackupService(
    _account,
    deferWhile: () => _driveEngine.active,
  );
  late final _plusBilling = AppStoreBillingGateway(_account);
  final CustomVoiceController _customVoice = CustomVoiceController(
    rootDirectory: getApplicationDocumentsDirectory,
  );
  final PlaceDetailsRepository _placeDetailsRepository =
      PlaceDetailsRepository();

  final UsageTelemetryRepository _usageTelemetry = UsageTelemetryRepository();
  final _navigationRewards = NavigationRewardRepository();
  final _navigationFeedback = NavigationFeedbackRepository();
  final ParkingRepository _parkingRepository = ParkingRepository();
  final WorkerSearchProvider _workerSearch = WorkerSearchProvider();
  final IndependentSearchProvider _independentSearch =
      IndependentSearchProvider(useWorkerSuggestions: true);
  final IndependentRoutingProvider _independentRoutes =
      IndependentRoutingProvider(useWaybiProxy: true);
  final IndependentTransitRoutingProvider _independentTransitRoutes =
      IndependentTransitRoutingProvider();
  // The mobile product uses Waybi exclusively, including migrated settings.
  static const _mapProvider = MapProvider.independent;

  LocationMarkerStyle _locationMarker = LocationMarkerStyle.kiwi;
  MapRenderer? _browseRenderer;
  MapViewportState _viewport = const MapViewportState(
    center: GeoPoint(-36.8485, 174.7633),
  );
  GeoPoint _areaSearchAnchor = const GeoPoint(-36.8485, 174.7633);
  bool _showSearchArea = false;
  final List<PlaceSummary> _exploreResults = const [];

  final ValueNotifier<PlaceSummary?> _exploreMarkerFocus =
      ValueNotifier<PlaceSummary?>(null);
  List<String> _quickActions = [
    'Home',
    'Work',
    'Frequent',
    'Restaurants',
    'Shopping',
    'Gas',
  ];

  /// Home/Work, their ETAs, Smart Commute and Route Watch.
  late final _commute = CommuteController(
    account: _account,
    bestDriveRoute: _bestDriveRoute,
    origin: () {
      final point = _gpsLocation;
      return point == null ? null : GeoPoint(point.latitude, point.longitude);
    },
    paused: () => _driveEngine.active,
    language: () => _appLanguage,
    routeWatchAlertsEnabled: () => _notifySavedRouteDisruptions,
  );

  double _navigationTopInset = 125;
  double _navigationBottomInset = 215;

  /// Browse GPS, compass and fix filtering.
  late final _location = LocationController(
    driveActive: () => _driveEngine.active,
    driveSpeedKph: () => _driveEngine.speedKph,
    language: () => _appLanguage,
  );

  /// The location issue last mirrored into the banner.
  String? _shownLocationIssue;

  /// (has a location, has a route origin) when the page last rebuilt for it.
  (bool, bool) _locationAvailability = (false, false);

  /// GPS accuracy as the HUDs show it (whole metres): changes far less
  /// often than fixes arrive.
  final _gpsAccuracyShown = ValueNotifier<int?>(null);

  /// What the map redraws for without rebuilding the page: location,
  /// compass, drive ticks and route progress.
  final _mapTicks = _FrameSafeNotifier();
  late final Listenable _mapSources = Listenable.merge([
    _location.locationListenable,
    _location.deviceHeadingListenable,
    _driveEngine,
    _independentNavigation.displayPathsListenable,
  ]);
  final _independentCamera = IndependentNavigationCamera();
  final _driveCameraFollow = DriveCameraFollow();
  Timer? _mapRefreshTimer;

  static LatLng? _latLng(GeoPoint? point) => point == null
      ? null
      : LatLng(latitude: point.latitude, longitude: point.longitude);
  LatLng? get _gpsLocation => _latLng(_location.location);
  LatLng? get _locationForRoute => _latLng(_location.routeOrigin);
  Position? get _lastReliableBrowsePosition => _location.lastReliablePosition;
  double? get _gpsAccuracy => _location.accuracy;
  double? get _deviceHeading => _location.deviceHeading;
  double? get _travelHeading => _location.travelHeading;

  // Use course only while actually moving on a recent, accurate GPS fix.
  // A phone compass or an old course can snap a parked origin backwards.
  double? get _currentRoutingHeading {
    final active = _driveEngine.active;
    final position = active
        ? _driveEngine.latestPosition
        : _lastReliableBrowsePosition;
    if (position == null || (active && !_driveEngine.hasReliableLocation)) {
      return null;
    }
    return routingOriginHeading(
      heading: active ? _driveEngine.rawHeadingDegrees : _travelHeading,
      speedMetresPerSecond: active
          ? _driveEngine.speedKph / 3.6
          : position.speed,
      accuracyMeters: position.accuracy,
      timestamp: position.timestamp,
      now: DateTime.now(),
    );
  }

  final List<DestinationSuggestion> _guestRecent = [];

  String _markerSignature = '';

  MapLayerSettings _layers = const MapLayerSettings();
  NavigationCameraMode _cameraMode = NavigationCameraMode.northUpFlat;
  String _appLanguage = 'en';
  String _voiceLanguage = 'en-NZ';

  bool _following = true;
  bool _routeOverviewActive = false;
  bool _voiceEnabled = true;
  bool _settingsLoaded = false;
  bool _appForeground = true;
  final _systemNavigation = SystemNavigation();
  DateTime? _lastDrivePositionAt;
  late final _journeys = JourneyStore(_account);
  bool _lanesEnabled = true;
  bool _notifySafetyCameras = false;
  bool _notifyRoadIncidents = false;
  bool _notifyCommunityReports = false;
  bool _notifySavedRouteDisruptions = false;
  PointOfInterest? get _selectedPoi {
    final place = _selectedPlace?.place;
    if (place == null) return null;
    return PointOfInterest(
      placeID: ['google', 'google-ui-kit'].contains(place.reference?.provider)
          ? place.reference!.id
          : '',
      name: place.name,
      latLng: LatLng(
        latitude: place.location.latitude,
        longitude: place.location.longitude,
      ),
    );
  }

  /// The place card: selection, details and drive ETA.
  late final _places = PlaceSelectionController(
    fetchDetails: _placeDetailsRepository.fetchIndependent,
    reverse: (point, preferredName) => _independentSearch.reverseNear(
      point,
      language: _appLanguage,
      preferredName: preferredName,
    ),
    route: (origin, destination) async {
      final route = await _bestDriveRoute(origin, destination);
      if (route == null) throw StateError('No routes available');
      return route;
    },
    language: () => _appLanguage,
    quickRouteSuppressed: () => _driveEngine.active || _preview.plan != null,
  );
  SelectedPlace? get _selectedPlace => _places.selected;

  void _loadPlaceQuickRoute() =>
      unawaited(_places.loadQuickRoute(_preview.origin));

  /// The route preview: plan, mode, route, filter, stops and parking.
  late final RoutePreviewController _preview = RoutePreviewController(
    trip: _trip,
    places: _places,
    planner:
        ({
          required origin,
          required destination,
          required stops,
          required mode,
          required headingDegrees,
          required avoid,
        }) => _independentRoutes.route(
          origin: origin,
          destination: destination,
          stops: stops,
          language: _appLanguage,
          mode: mode,
          headingDegrees: headingDegrees,
          avoid: avoid,
        ),
    transit: ({required origin, required destination}) =>
        _independentTransitRoutes.route(
          origin: origin,
          destination: destination,
          language: _appLanguage,
        ),
    parking: (destination) => _parkingRepository.nearby(
      destination: destination,
      allowGoogleFallback: false,
      language: _appLanguage,
    ),
    routeLocation: () => _location.routeOrigin,
    gpsLocation: () => _location.location,
    heading: () => _currentRoutingHeading,
    cameras: () => _driveEngine.cameras,
    roadEvents: () => _driveEngine.roadEvents,
    cameraDataReady: () =>
        !_driveEngine.loadingCameras && _driveEngine.cameras.isNotEmpty,
    setDriveRoute: _driveEngine.setRoute,
    navigationOwnsRoute: () => _independentNavigation.route != null,
    driveActive: () => _driveEngine.active,
    notice: _notice,
    language: () => _appLanguage,
    showRoute: _renderRoutePreview,
    beforeLoad: () => FocusManager.instance.primaryFocus?.unfocus(),
    onLoadStarted: (mode) {
      _following = false;
      unawaited(_driveEngine.loadCameras());
      if (mode == WaybiTravelMode.drive) {
        unawaited(_driveEngine.loadTrafficFlow());
      }
    },
    recoverLocation: () => unawaited(_recoverRouteLocation()),
  );

  /// The one trip state; the getters below are views of it.
  final _trip = TripMachine();
  TripState get _tripState => _trip.value;
  bool get _guidanceRunning => _tripState.guidanceRunning;
  bool get _transitTripRunning => _tripState is TripTransit;
  bool get _busy => _tripState.busy;
  bool get _recoveringRoute =>
      _tripState == const TripPreviewing(PreviewActivity.findingDetour);
  bool get _routePreviewLoading => _tripState.previewLoading;
  bool get _parkingLegFinished => _tripState is TripParkingLeg;
  bool get _arrivalMode => _tripState == const TripNavigating(arrival: true);
  JourneyPhase get _journeyPhase => _tripState.journeyPhase;

  void _onTripChanged() {
    if (mounted) setState(() {});
  }

  /// The status banner's message; the banner listens to it.
  final _notice = ValueNotifier<String?>(null);
  String? get _message => _notice.value;
  set _message(String? value) => _notice.value = value;

  /// Guidance, Just Drive, transit trips and navigation links.
  late final NavigationSessionController _nav = NavigationSessionController(
    trip: _trip,
    preview: _preview,
    places: _places,
    drive: _driveEngine,
    guidance: _independentNavigation,
    system: _systemNavigation,
    host: this,
    notice: _notice,
    roadAlerts: _roadAlerts,
    journeys: _journeys,
    rewards: _navigationRewards,
    feedback: _navigationFeedback,
    parking: (destination) => _parkingRepository.nearby(
      destination: destination,
      allowGoogleFallback: false,
      language: _appLanguage,
    ),
    fetchDetails: _placeDetailsRepository.fetchIndependent,
    isPlus: () => _account.profile?.isPlus == true,
    hasAccount: () => _account.profile != null,
    language: () => _appLanguage,
  );

  /// Background notifications for cameras and road events ahead.
  late final _roadAlerts = RoadAlerts(
    settings: () => (
      cameras: _notifySafetyCameras,
      incidents: _notifyRoadIncidents,
      community: _notifyCommunityReports,
    ),
    language: () => _appLanguage,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _independentNavigation = IndependentNavigationEngine(
      _driveEngine,
      reroute: (origin, previous, stops) => _independentRoutes.reroute(
        origin: origin,
        destination: previous.points.last,
        mode: previous.mode,
        stops: stops,
        language: _appLanguage,
        headingDegrees: _currentRoutingHeading,
        avoid: road_routes.closureExclusions(
          previous,
          _preview.closuresOn(previous),
        ),
        // Abort the HTTP request before the engine stops waiting, so a slow
        // reroute never overlaps the next attempt.
        timeout: IndependentRoutingProvider.rerouteTimeout,
      ),
    );
    // The trip hears the engines before the page does.
    _nav.addListener(_onTripChanged);
    _independentNavigation.addListener(_onIndependentNavigationChanged);
    _trip.addListener(_onTripChanged);
    _commute.addListener(_onTripChanged);
    _places.addListener(_onTripChanged);
    _preview.addListener(_onTripChanged);
    _location
      ..onFix = _onLocationFix
      ..onIssue = _onLocationIssue
      ..reportTransientIssues = () => _preview.hasPending;
    _location.deviceHeadingListenable.addListener(_queueMapRefresh);
    _mapSources.addListener(_mapTicks.ping);
    unawaited(WaybiNotificationService.instance.initialize());
    _account.addListener(_onAccountChanged);
    _driveEngine.addListener(_onEngineChanged);
    _driveEngine.customVoice = _customVoice;
    _syncCustomVoiceEntitlement();
    unawaited(_customVoice.load());
    _plusBilling.initialize();
    unawaited(_account.restore().then((_) => _friendsBackup.start()));
    unawaited(_driveEngine.loadCameras());
    unawaited(_driveEngine.loadTransitLanes());
    unawaited(
      _restoreMapSettings().then((_) async {
        if ((_layers.traffic)) {
          await _driveEngine.startTrafficFlowRefresh();
        }
        try {
          await _maybeShowCoreOnboarding();
        } catch (_) {
          // A failed preference read must not block external links.
        }
        if (!mounted) return;
        _externalNavigationReady = true;
        _nav.scheduleHandOff();
      }),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_startTracking(requestPermission: true));
    });
  }

  // ---------------------------------------------------------------------
  // TripHost: what a trip asks of the page.

  @override
  void resetTripCamera({required bool drive}) {
    if (drive) _driveCameraFollow.reset();
    _independentCamera.reset();
  }

  @override
  void followTrip([NavigationCameraMode? mode]) {
    if (!mounted) return;
    setState(() {
      _following = true;
      _routeOverviewActive = false;
      if (mode != null) _cameraMode = mode;
    });
  }

  @override
  void setTripCameraMode(NavigationCameraMode mode) {
    if (mounted) setState(() => _cameraMode = mode);
  }

  @override
  void refreshTripMap() {
    if (mounted) _queueMapRefresh();
  }

  @override
  void resumeTrafficRefresh() {
    if (mounted && _appForeground && _layers.traffic) {
      unawaited(_driveEngine.startTrafficFlowRefresh(force: true));
    }
  }

  @override
  GeoPoint? get browseLocation => _location.location;

  @override
  Position? get lastReliablePosition => _location.lastReliablePosition;

  @override
  Future<bool> ensureLocationPermission() => _location.ensurePermission();

  @override
  Future<void> pauseBrowseLocation() async {
    await _location.pauseForDrive();
    _lastDrivePositionAt = null;
  }

  @override
  Future<void> startBrowseLocation() => _startTracking();

  @override
  Future<void> clearPreview() => _clearRoutePreview();

  @override
  void showJourneySummary(
    JourneySummary summary,
    Future<JourneyMemory?>? reward,
  ) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) => Localizations.override(
          context: sheetContext,
          locale: Locale(_appLanguage),
          child: JourneySummarySheet(
            summary: summary,
            language: _appLanguage,
            reward: reward,
            feedback: _navigationFeedback,
          ),
        ),
      ),
    );
  }

  @override
  bool get handOffReady =>
      mounted && _externalNavigationReady && _appForeground;

  @override
  void popToHome() => Navigator.of(context).popUntil((route) => route.isFirst);

  @override
  Future<bool> confirmSwitchTrip(String destination) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_text('Switch destination?', '切换目的地？')),
          content: Text(
            _text(
              'End the current trip and open $destination?',
              '结束当前行程并打开 $destination？',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_text('Keep current trip', '继续当前行程')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(_text('Switch', '切换')),
            ),
          ],
        ),
      ) ==
      true;

  @override
  Future<PlaceSummary?> searchHandOffTarget(
    String query,
    String purpose,
    bool Function() current,
  ) => _openSearch(
    query: query,
    selectResult: false,
    isCurrent: current,
    searchPurpose: purpose,
  );

  @override
  void showHandOffError(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  @override
  void selectHandOffPlace(PlaceSummary place) =>
      _selectPlace(place, SelectionSource.search);

  @override
  void afterFrame(VoidCallback callback) {
    WidgetsBinding.instance.addPostFrameCallback((_) => callback());
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _maybeShowCoreOnboarding() =>
      maybeShowCoreOnboarding(context, _appLanguage);

  /// Custom voice is Plus-only: a lapsed or signed-out account immediately
  /// falls back to the standard voice (recordings stay on the device).
  void _syncCustomVoiceEntitlement() => _customVoice.setPlus(
    _account.signedIn && _account.profile?.isPlus == true,
  );

  void _onAccountChanged() {
    _syncCustomVoiceEntitlement();
    if (mounted) setState(() {});
    _commute.onAccountChanged();
  }

  /// Resume work that costs network or battery runs at most this often;
  /// permission dialogs and Control Centre bounce the lifecycle constantly.
  static const _resumeRefreshInterval = Duration(minutes: 3);
  DateTime? _lastResumeRefreshAt;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `inactive` is transient (a permission prompt, Control Centre, an
    // incoming call banner): the app is still visible, so keep everything.
    if (state == AppLifecycleState.inactive) return;
    final wasForeground = _appForeground;
    _appForeground = state == AppLifecycleState.resumed;
    if (!_appForeground) {
      _mapRefreshTimer?.cancel();
      _mapRefreshTimer = null;
      _driveEngine.stopTrafficFlowRefresh();
      // Browsing needs no GPS in the background; Drive keeps its own feed.
      unawaited(_location.pauseInBackground());
      return;
    }
    if (wasForeground) return;
    if (_driveEngine.active) {
      unawaited(_driveEngine.recoverLocalLocation());
    } else {
      unawaited(_location.resume());
    }
    _nav.scheduleHandOff();
    _queueMapRefresh();
    _nav.onResumed();
    if (_driveEngine.active || _layers.traffic) {
      // Not forced: the snapshot is reused within its 45 s freshness window.
      unawaited(_driveEngine.startTrafficFlowRefresh());
    }
    final now = DateTime.now();
    final last = _lastResumeRefreshAt;
    if (last != null && now.difference(last) < _resumeRefreshInterval) return;
    _lastResumeRefreshAt = now;
    unawaited(_friendsBackup.sync());
    unawaited(_commute.deliverRouteWatchAlerts());
    unawaited(_commute.refreshQuick(force: true));
  }

  void _onIndependentNavigationChanged() {
    if (mounted && _following) _queueMapRefresh();
  }

  void _onEngineChanged() {
    if (!mounted) return;
    _independentNavigation.checkClosureUpdates();
    final position = _driveEngine.latestPosition;
    if (position != null && position.timestamp != _lastDrivePositionAt) {
      _lastDrivePositionAt = position.timestamp;
      _location.handlePosition(position);
    }
    final reportIds = _visibleRoadEvents.map((event) => event.id).join(',');
    // Everything the page itself draws from the engine (the HUDs listen to it
    // directly). Rebuild only when one of these changed, not on every tick.
    final signature =
        '${_driveEngine.active}:${_driveEngine.loadingCameras}:'
        '${_driveEngine.cameras.length}:${_driveEngine.routeCameras.map((match) => match.camera.id).join(',')}:$reportIds:${_layers.markerSignature}:${_driveEngine.trafficFlowRevision}:'
        '${_driveEngine.trafficFlowStatus}:${_driveEngine.transitSnapshot?.lanes.length}:'
        '${_driveEngine.transitReviewCorridors.length}';
    if (signature != _markerSignature) {
      _markerSignature = signature;
      _preview.refreshSummaries();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
    if (!_following &&
        _driveEngine.active &&
        !_guidanceRunning &&
        !_independentNavigation.active &&
        _selectedPlace == null &&
        _preview.plan == null &&
        _driveCameraFollow.shouldResume(
          now: DateTime.now(),
          speedKph: _driveEngine.speedKph,
          reliableLocation: _driveEngine.hasReliableLocation,
        )) {
      _independentCamera.reset();
      setState(() => _following = true);
    }
    if (_following && _driveEngine.active) _queueMapRefresh();
  }

  ({List<RoadEvent> source, bool shown, int minute, List<RoadEvent> value})?
  _visibleRoadEventsMemo;

  /// The road events the map draws. The same list instance is returned until
  /// the engine's events, the layer or the minute change, so the renderer's
  /// identity check skips re-syncing them on every rebuild.
  List<RoadEvent> get _visibleRoadEvents {
    final source = _driveEngine.roadEvents;
    final shown = _layers.roadEvents;
    final minute = DateTime.now().millisecondsSinceEpoch ~/ 60000;
    final memo = _visibleRoadEventsMemo;
    if (memo != null &&
        identical(memo.source, source) &&
        memo.shown == shown &&
        memo.minute == minute) {
      return memo.value;
    }
    final value = _computeVisibleRoadEvents();
    _visibleRoadEventsMemo = (
      source: source,
      shown: shown,
      minute: minute,
      value: value,
    );
    return value;
  }

  List<RoadEvent> _computeVisibleRoadEvents() => _layers.roadEvents
      ? _driveEngine.roadEvents
            .where(
              (event) =>
                  (event.metadata['userReported'] == true ||
                      (event.observation == RoadEventObservation.official &&
                          {
                            RoadEventType.roadClosure,
                            RoadEventType.roadworks,
                            RoadEventType.incident,
                            RoadEventType.flooding,
                            RoadEventType.slip,
                          }.contains(event.type))) &&
                  event.isCurrent(DateTime.now()),
            )
            .toList(growable: false)
      : const [];

  Future<void> _showCameraDetails(SafetyCamera camera) =>
      showCameraDetailsSheet(context, camera, _appLanguage);

  Future<void> _showTransitLaneDetails(TransitLane lane) =>
      showTransitLaneDetailsSheet(context, lane, _appLanguage);

  Future<void> _showTransitReviewDetails(TransitReviewCorridor corridor) =>
      showTransitReviewDetailsSheet(context, corridor, _appLanguage);

  Future<void> _showRoadEventDetails(RoadEvent event) =>
      showRoadEventDetails(context, event, _appLanguage);

  /// Never leaves the page on its loading spinner: a failing platform call
  /// or damaged preference falls back to defaults and the map still opens.
  Future<void> _restoreMapSettings() async {
    try {
      await _readMapSettings();
    } catch (error) {
      debugPrint('Waybi settings restore failed: $error');
    } finally {
      if (!_settingsLoaded) {
        _settingsLoaded = true;
        if (mounted) setState(() {});
      }
    }
  }

  Future<void> _readMapSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('waybi.map.provider', MapProvider.independent.name);
    _locationMarker = LocationMarkerStyle.values.firstWhere(
      (value) => value.name == prefs.getString('waybi.map.location_marker'),
      orElse: () => LocationMarkerStyle.kiwi,
    );
    _quickActions = prefs.getStringList('waybi.quick_actions') ?? _quickActions;
    _restoreGoogleRecent(prefs);
    await _commute.loadSaved();
    await _nav.restoreSettings(prefs);
    _appLanguage = prefs.getString('waybi.app.language') ?? 'en';
    _voiceLanguage = prefs.getString('waybi.voice.language') ?? 'en-NZ';
    _voiceEnabled = prefs.getBool('waybi.voice.enabled') ?? true;
    _lanesEnabled = prefs.getBool('waybi.nav.lanes') ?? true;
    _driveEngine.navigationLanguage = _appLanguage;
    await _applyNativeMapLanguage(_appLanguage);
    _settingsLoaded = true;
    _commute.ready = true;
    _notifySafetyCameras =
        prefs.getBool('waybi.notifications.safety_cameras') ?? false;
    _notifyRoadIncidents =
        prefs.getBool('waybi.notifications.road_incidents') ?? false;
    _notifyCommunityReports =
        prefs.getBool('waybi.notifications.community_reports') ?? false;
    _notifySavedRouteDisruptions =
        prefs.getBool('waybi.notifications.saved_route_disruptions') ?? false;
    _driveEngine.voiceEnabled = _voiceEnabled;
    _layers = MapLayerSettings(
      cameras: prefs.getBool('waybi.layers.cameras') ?? true,
      spotSpeed:
          prefs.getBool('waybi.layers.spot_speed') ??
          prefs.getBool('waybi.layers.speed') ??
          true,
      averageSpeed: prefs.getBool('waybi.layers.average_speed') ?? true,
      redLight: prefs.getBool('waybi.layers.red_light') ?? true,
      dualRedLightSpeed: prefs.getBool('waybi.layers.dual_red_speed') ?? true,
      busLane: prefs.getBool('waybi.layers.bus_lane') ?? true,
      other: prefs.getBool('waybi.layers.other') ?? true,
      alertSpotSpeed: prefs.getBool('waybi.alerts.spot_speed') ?? true,
      alertAverageSpeed: prefs.getBool('waybi.alerts.average_speed') ?? true,
      alertRedLight: prefs.getBool('waybi.alerts.red_light') ?? true,
      alertDualRedLightSpeed:
          prefs.getBool('waybi.alerts.dual_red_speed') ?? true,
      alertBusLane: prefs.getBool('waybi.alerts.bus_lane') ?? true,
      alertOther: prefs.getBool('waybi.alerts.other_camera') ?? false,
      traffic: prefs.getBool('waybi.layers.traffic') ?? true,
      roadEvents: prefs.getBool('waybi.layers.road_events') ?? true,
      transitLanes: prefs.getBool('waybi.layers.transit_lanes') ?? true,
      style: BaseMapStyle.values.firstWhere(
        (value) => value.name == prefs.getString('waybi.layers.style'),
        orElse: () => BaseMapStyle.standard,
      ),
    );
    _driveEngine.setCameraAlertFilter(_layers.alerts);
    try {
      await _driveEngine.setVoiceLanguage(_voiceLanguage);
    } catch (_) {
      // The default voice remains available.
    }
    if (mounted) setState(() {});
    if (_account.signedIn && _account.profile != null) {
      unawaited(_commute.syncWithAccount());
    }
    unawaited(_commute.refreshQuick(force: true));
    unawaited(_commute.deliverRouteWatchAlerts());
  }

  List<DestinationSuggestion> get _recentDestinations {
    final profile = _account.profile;
    if (profile == null) return _guestRecent;
    return profile.recentDestinations
        .map((item) {
          final latitude = item['latitude'];
          final longitude = item['longitude'];
          if (latitude is! num || longitude is! num) return null;
          return DestinationSuggestion(
            label:
                item['label']?.toString() ??
                _text('Recent destination', '最近目的地'),
            location: LatLng(
              latitude: latitude.toDouble(),
              longitude: longitude.toDouble(),
            ),
          );
        })
        .whereType<DestinationSuggestion>()
        .toList(growable: false);
  }

  @override
  void dispose() {
    _nav.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _location.deviceHeadingListenable.removeListener(_queueMapRefresh);
    _mapSources.removeListener(_mapTicks.ping);
    _mapTicks.dispose();
    _location.dispose();
    _gpsAccuracyShown.dispose();
    _mapRefreshTimer?.cancel();
    _account.removeListener(_onAccountChanged);
    _driveEngine.customVoice = null;
    _customVoice.dispose();
    _driveEngine.removeListener(_onEngineChanged);
    unawaited(_systemNavigation.stop());
    _systemNavigation.dispose();
    _independentNavigation.dispose();
    _trip.dispose();
    _commute.dispose();
    _preview.dispose();
    _places.dispose();
    _notice.dispose();
    _exploreMarkerFocus.dispose();
    _workerSearch.dispose();
    _independentSearch.dispose();
    _independentRoutes.dispose();
    _independentTransitRoutes.dispose();
    _plusBilling.dispose();
    _friendsBackup.dispose();
    _account.dispose();
    _usageTelemetry.dispose();
    _navigationRewards.dispose();
    _navigationFeedback.dispose();
    _placeDetailsRepository.dispose();
    _parkingRepository.dispose();
    _driveEngine.dispose();
    super.dispose();
  }

  void _onLocationIssue(String? message) {
    if (!mounted) return;
    final shown = _shownLocationIssue;
    _shownLocationIssue = message;
    if (message != null) {
      _message = message;
    } else if (_message == shown) {
      _message = null;
    }
  }

  Future<void> _resolveLocationIssue() => _location.resolveIssue(
    recoverDrive: _driveEngine.recoverLocalLocation,
    recoverBrowse: _recoverRouteLocation,
  );

  Future<void> _startTracking({bool requestPermission = false}) =>
      _location.start(requestPermission: requestPermission);

  /// Decisions on every processed fix; the puck itself redraws from the
  /// controller's listenable.
  void _onLocationFix(NavigationLocationFix? accepted, Position position) {
    if (!mounted) return;
    _gpsAccuracyShown.value = _gpsAccuracy?.round();
    // The puck, heading and accuracy redraw through listenables. The page
    // itself only rebuilds when having a location (or a route origin) at all
    // changes what it shows.
    final availability = (_gpsLocation != null, _locationForRoute != null);
    if (availability != _locationAvailability) {
      _locationAvailability = availability;
      setState(() {});
    }
    // The filter held the last reliable fix (an indoor jump).
    if (accepted == null) {
      _preview.retryPending();
      final place = _selectedPlace?.place;
      if (place != null && !_driveEngine.active && _preview.plan == null) {
        _loadPlaceQuickRoute();
      }
      return;
    }
    _preview.retryPending();
    _nav.onLocationFix(accepted, position);
    _queueMapRefresh();
    unawaited(_commute.refreshQuick());
    final selected = _selectedPlace?.place;
    if (selected != null && _preview.plan == null && !_driveEngine.active) {
      _loadPlaceQuickRoute();
    }
  }

  bool get _selectedPlaceHasCrossTasmanDrive {
    final destination = _selectedPlace?.place.location;
    final origin = _preview.origin;
    if (origin == null || destination == null) return false;
    return isCrossTasmanSurfaceRoute([origin, destination]);
  }

  Future<RouteOption?> _bestDriveRoute(
    GeoPoint origin,
    GeoPoint destination,
  ) async {
    final plan = await _independentRoutes.route(
      origin: origin,
      destination: destination,
      language: _appLanguage,
      mode: WaybiTravelMode.drive,
    );
    return filterRoutes(
      plan.forMode(WaybiTravelMode.drive).toList(),
      RouteFilter.recommended,
      const {},
    ).firstOrNull;
  }

  void _queueMapRefresh() {
    if (!_appForeground || (_mapRefreshTimer?.isActive ?? false)) return;
    final smoothNavigation = (_driveEngine.active);
    _mapRefreshTimer = Timer(
      Duration(milliseconds: smoothNavigation ? 180 : 350),
      () => unawaited(_refreshMap()),
    );
  }

  Future<void> _refreshMap() async {
    final location = _driveEngine.active
        ? _driveEngine.snappedLocation ?? _gpsLocation
        : _gpsLocation;
    final routePreviewOwnsCamera =
        !_driveEngine.active &&
        _journeyPhase == JourneyPhase.routePreview &&
        _preview.plan != null;
    final placeDeckOwnsCamera =
        !_driveEngine.active && _selectedPlace != null && _preview.plan == null;
    if (_following &&
        !routePreviewOwnsCamera &&
        !placeDeckOwnsCamera &&
        location != null &&
        _browseRenderer != null) {
      final navigating = _independentNavigation.active;
      final heading = navigationForwardBearing(
        speedKph: _driveEngine.active ? _driveEngine.speedKph : 0,
        course: _driveEngine.snappedHeadingDegrees ?? _travelHeading,
        compass: _deviceHeading,
        routeBearing: _routeInitialBearing,
      );
      final point = GeoPoint(location.latitude, location.longitude);
      final viewport = _driveEngine.active
          ? _independentCamera.update(
              location: point,
              heading: heading,
              speedKph: _driveEngine.speedKph,
              mode: navigating
                  ? _nav.activeRoute?.mode ?? _preview.mode
                  : WaybiTravelMode.drive,
              visibleHeight:
                  MediaQuery.sizeOf(context).height -
                  _navigationTopInset -
                  _navigationBottomInset,
              distanceToStep: navigating
                  ? _independentNavigation.distanceToStepMeters
                  : double.infinity,
              nextStep: navigating ? _independentNavigation.nextStep : null,
              northUp: _cameraMode.northUp,
              tilted: _cameraMode.tilted,
              now: DateTime.now(),
              offRoute: _independentNavigation.offRoute,
            )
          : _viewport.copyWith(
              center: GeoPoint(location.latitude, location.longitude),
              bearing: _cameraMode.northUp ? 0 : heading,
              pitch: _cameraMode.tilted ? 48 : 0,
            );
      // A north-up map that is standing still produces the same viewport
      // for every compass reading; do not animate the camera to where it
      // already is.
      if (_sameViewport(viewport, _lastCameraTarget)) return;
      _lastCameraTarget = viewport;
      await _browseRenderer!.moveTo(viewport);
    }
  }

  MapViewportState? _lastCameraTarget;

  /// The renderer for a camera move other than following (a route fit, place
  /// focus, search result): following must move again afterwards.
  MapRenderer? _takeCamera() {
    _lastCameraTarget = null;
    return _browseRenderer;
  }

  static bool _sameViewport(MapViewportState a, MapViewportState? b) {
    if (b == null) return false;
    double bearingDelta() {
      final delta = (a.bearing - b.bearing).abs() % 360;
      return delta > 180 ? 360 - delta : delta;
    }

    return (a.zoom - b.zoom).abs() < .01 &&
        (a.pitch - b.pitch).abs() < .5 &&
        bearingDelta() < 1 &&
        distanceMeters(
              a.center.latitude,
              a.center.longitude,
              b.center.latitude,
              b.center.longitude,
            ) <
            .5;
  }

  void _recenter() {
    _lastCameraTarget = null;
    if (_driveEngine.active) {
      unawaited(_driveEngine.recoverLocalLocation());
    } else {
      unawaited(_recoverRouteLocation());
    }
    _independentCamera.reset();
    setState(() {
      _following = true;
      _routeOverviewActive = false;
    });
    _queueMapRefresh();
  }

  IconData get _locationControlIcon {
    if (!_following) return Icons.my_location_outlined;
    return _cameraMode.northUp ? Icons.north_rounded : Icons.navigation_rounded;
  }

  String get _locationControlTooltip {
    if (!_following) return _text('Return to my location', '回到我的位置');
    if ((!_cameraMode.northUp)) {
      return _text('Switch to north-up', '切换到北向俯视');
    }
    return switch (_cameraMode) {
      NavigationCameraMode.headingUpFlat => _text(
        'Switch to perspective view',
        '切换到透视跟车',
      ),
      NavigationCameraMode.headingUpPerspective => _text(
        'Switch to north-up',
        '切换到指北俯视',
      ),
      NavigationCameraMode.northUpFlat => _text(
        'Switch to heading-up',
        '切换到车头朝上俯视',
      ),
    };
  }

  LatLng? get _displayLocation => _driveEngine.active
      ? _driveEngine.snappedLocation ?? _gpsLocation
      : _gpsLocation;

  double? get _routeInitialBearing {
    final points = _nav.activeRoute?.points;
    if (points == null || points.length < 2) return null;
    final first = points.first;
    final next = points
        .skip(1)
        .where(
          (p) =>
              distanceMeters(
                first.latitude,
                first.longitude,
                p.latitude,
                p.longitude,
              ) >
              3,
        )
        .firstOrNull;
    return next == null
        ? null
        : bearingDegrees(
            first.latitude,
            first.longitude,
            next.latitude,
            next.longitude,
          );
  }

  EdgeInsets get _independentNavigationPadding {
    final available =
        (MediaQuery.sizeOf(context).height -
                _navigationTopInset -
                _navigationBottomInset)
            .clamp(0.0, 900.0);
    return EdgeInsets.fromLTRB(
      16,
      _navigationTopInset + available * .28,
      16,
      _navigationBottomInset,
    );
  }

  void _markMapManuallyMoved({bool searchArea = false}) {
    _lastCameraTarget = null;
    _driveCameraFollow.pause(DateTime.now());
    if (mounted && (_following || _routeOverviewActive)) {
      setState(() {
        _following = false;
        _routeOverviewActive = false;
      });
    } else {
      _following = false;
      _routeOverviewActive = false;
    }
    if (searchArea) _maybeShowSearchArea();
  }

  void _cycleLocationCamera() {
    if (!_following) {
      setState(() {
        _following = true;
        _cameraMode = _driveEngine.active
            ? NavigationCameraMode.headingUpFlat
            : NavigationCameraMode.northUpFlat;
      });
    } else {
      _toggleCompass();
      return;
    }
    _recenter();
  }

  Future<void> _showRoadReport() async {
    final location = _gpsLocation;
    if (location == null) {
      _message = _text(
        'Current location is required to report a road issue.',
        '需要获取当前位置才能上报道路情况。',
      );
      return;
    }
    final selected = await showRoadReportPicker(context, _appLanguage);
    if (selected == null) return;
    try {
      await _account.submitRoadReport(
        type: selected.$1,
        latitude: location.latitude,
        longitude: location.longitude,
        headingDegrees: _travelHeading ?? _deviceHeading,
        description: selected.$2,
      );
      await _driveEngine.loadCameras(force: true);
      _markerSignature = '';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_text('Road report submitted', '道路情况已上报'))),
        );
      }
    } catch (error) {
      if (mounted) {
        _message = _text(
          'Could not submit road report. ${friendlyErrorMessage(error, _appLanguage)}',
          '道路上报失败。${friendlyErrorMessage(error, _appLanguage)}',
        );
      }
    }
  }

  void _showRouteOverview() {
    setState(() {
      _following = false;
      _routeOverviewActive = true;
    });
    final renderer = _takeCamera();
    final route = _independentNavigation.route;
    if ((renderer is RouteMapRenderer) && route != null) {
      unawaited(
        renderer.fitRoute(
          route.points,
          bottomInset: _navigationBottomInset + 30,
        ),
      );
      return;
    }
  }

  void _toggleCompass() {
    setState(() => _cameraMode = _cameraMode.next);
    _recenter();
  }

  double _placeDeckInset({required bool expanded}) {
    final height = MediaQuery.sizeOf(context).height;
    final deckHeight = expanded
        ? (height * .72).clamp(430.0, 660.0)
        : (height * .38).clamp(285.0, 340.0);
    return deckHeight + MediaQuery.paddingOf(context).bottom + 24;
  }

  void _focusSelectedPlace({bool expanded = false}) {
    if (!mounted ||
        _preview.plan != null ||
        _driveEngine.active ||
        _transitTripRunning) {
      return;
    }
    final place = _selectedPlace?.place;
    final renderer = _takeCamera();
    if (place == null || renderer is! PlaceFocusMapRenderer) return;
    unawaited(
      renderer.focusPlace(
        place.location,
        bottomInset: _placeDeckInset(expanded: expanded),
      ),
    );
  }

  Future<void> _clearRoutePreview() async {
    if (!mounted) return;
    // Reset synchronously: a place selected while the map padding animates
    // must not be cleared afterwards.
    _following = true;
    _preview.clear();
    _queueMapRefresh();
    final renderer = _takeCamera();
    if (renderer is PlaceFocusMapRenderer) {
      try {
        await renderer.clearContentPadding();
      } catch (_) {
        // The map keeps its previous padding until the next focus.
      }
    }
  }

  /// Back from a route preview to the place card it was opened from.
  void _closeRoutePreviewToPlace() {
    final original = _preview.parkingOriginalPlace;
    if (original != null) {
      _preview.releaseDriveRoute();
      _selectPlace(original, SelectionSource.map);
      return;
    }
    if (_selectedPlace == null) {
      unawaited(_clearRoutePreview());
      return;
    }
    _message = null;
    _preview.closeToPlace();
    _focusSelectedPlace();
    _loadPlaceQuickRoute();
  }

  /// Android back: unwind one layer (preview, place card, Drive Mode) and
  /// confirm before ending guidance or a transit trip.
  bool get _canPopHome =>
      _tripState is TripIdle && !_driveEngine.active && _selectedPlace == null;

  Future<void> _handleBack() async {
    switch (_tripState) {
      case TripNavigating():
        if (await _confirmEnd(
              _text('End navigation?', '结束导航？'),
              _text('Keep navigating', '继续导航'),
            ) &&
            mounted) {
          await _nav.stop();
        }
      case TripTransit():
        if (await _confirmEnd(
              _text('End this transit trip?', '结束这次公交行程？'),
              _text('Keep trip', '继续行程'),
            ) &&
            mounted) {
          await _nav.stopTransit();
        }
      case TripPreviewing() || TripStarting():
        // Closing a starting preview also cancels the start.
        _closeRoutePreviewToPlace();
      case TripPlaceSelected(:final routing):
        if (routing) {
          _closeRoutePreviewToPlace();
        } else {
          await _clearRoutePreview();
        }
      case TripJustDrive():
        await _nav.stopDrive();
      case TripParkingLeg():
        _nav.dismissParkingLeg();
      case TripEnding():
        break;
      case TripIdle():
        if (_driveEngine.active) {
          await _nav.stopDrive();
        } else if (_selectedPlace != null) {
          await _clearRoutePreview();
        }
    }
  }

  Future<bool> _confirmEnd(String title, String keepLabel) async {
    final end = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(keepLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_text('End', '结束')),
          ),
        ],
      ),
    );
    return end == true;
  }

  void _showParkedCar() {
    final parked = _nav.parkedCar;
    if (parked == null) return;
    _selectPlace(
      PlaceSummary(
        name: _text('Parked car · ${parked.name}', '停车位置 · ${parked.name}'),
        address: parked.address,
        location: parked.location,
      ),
      SelectionSource.frequent,
    );
    if (mounted) {
      _message = _nav.parkedCarLabel();
    }
  }

  Future<void> _recoverRouteLocation() async {
    try {
      await _location.recover();
      _preview.retryPending();
    } catch (_) {
      if (mounted && _preview.hasPending) {
        _message = _text(
          'Location unavailable. Check location access and try again.',
          '暂时无法定位，请检查定位权限后重试。',
        );
      }
    }
  }

  List<MapRoutePath> get _visibleIndependentRoutePaths {
    final navigationRoute = _independentNavigation.route;
    if (navigationRoute != null) {
      return _independentNavigation.displayPaths;
    }
    if (_driveEngine.active) return _driveEngine.trailPaths;
    if (_transitTripRunning && _nav.transitRoute != null) {
      return _nav.transitPaths;
    }
    return _preview.paths;
  }

  String _placeKey(PointOfInterest poi) => poi.placeID.isNotEmpty
      ? (_selectedPlace?.place.reference?.provider == 'osm'
            ? 'osm:${poi.placeID}'
            : poi.placeID)
      : 'coords:${poi.latLng.latitude.toStringAsFixed(5)},${poi.latLng.longitude.toStringAsFixed(5)}';

  bool _isFavorite(PointOfInterest poi) =>
      _account.profile?.places.any(
        (place) =>
            place['placeId'] == _placeKey(poi) && place['isFavorite'] == true,
      ) ??
      false;

  void _showProfile() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfilePage(
          account: _account,
          friendsBackup: _friendsBackup,
          plusBilling: _plusBilling,
          customVoice: _customVoice,
          voiceEnabled: _voiceEnabled,
          lanesEnabled: _lanesEnabled,
          keepScreenAwake: _nav.keepScreenAwake,
          onKeepScreenAwakeChanged: (value) =>
              unawaited(_nav.setKeepScreenAwake(value)),
          onNativeLanguageSettings: () =>
              unawaited(NativeMapLanguage.openSettings()),
          appLanguage: _appLanguage,
          voiceLanguage: _voiceLanguage,
          themeMode: widget.themeMode,
          onThemeModeChanged: (mode) => widget.onThemeModeChanged?.call(mode),
          onVoiceChanged: _setVoiceEnabled,
          onLanesChanged: _setLanesEnabled,
          onAppLanguageChanged: (value) => unawaited(_setAppLanguage(value)),
          onLanguageChanged: (value) => unawaited(_setVoiceLanguage(value)),
          onMapLayers: _showMapLayers,
          mapProvider: _mapProvider,
          locationMarker: _locationMarker,
          notifySafetyCameras: _notifySafetyCameras,
          notifyRoadIncidents: _notifyRoadIncidents,
          notifyCommunityReports: _notifyCommunityReports,
          notifySavedRouteDisruptions: _notifySavedRouteDisruptions,
          onNotifySafetyCamerasChanged: (value) => unawaited(
            _setNotificationPreference(
              'waybi.notifications.safety_cameras',
              value,
            ),
          ),
          onNotifyRoadIncidentsChanged: (value) => unawaited(
            _setNotificationPreference(
              'waybi.notifications.road_incidents',
              value,
            ),
          ),
          onNotifyCommunityReportsChanged: (value) => unawaited(
            _setNotificationPreference(
              'waybi.notifications.community_reports',
              value,
            ),
          ),
          onNotifySavedRouteDisruptionsChanged: (value) => unawaited(
            _setNotificationPreference(
              'waybi.notifications.saved_route_disruptions',
              value,
            ),
          ),
          cameraSnapshot: _driveEngine.cameraSnapshot,
          onReloadCameraData: () async {
            await _driveEngine.loadCameras(force: true);
            final snapshot = _driveEngine.cameraSnapshot;
            if (snapshot == null) {
              throw StateError(
                _text(
                  'Camera data is unavailable. Try again when connected.',
                  '摄像头数据暂不可用，请联网后重试。',
                ),
              );
            }
            if (mounted) {
              setState(() {});
            }
            return snapshot;
          },
          onSyncCameraData: () async {
            final token = _account.sessionToken;
            if (token == null) {
              throw StateError(
                _text('Sign in to use Plus camera sync', '请先登录后使用 Plus 摄像头同步'),
              );
            }
            final snapshot = await _driveEngine.syncCameraData(
              sessionToken: token,
            );
            if (mounted) {
              setState(() {});
            }
            return snapshot;
          },
          onMapProviderChanged: (_) async => _mapProvider,
          onLocationMarkerChanged: (value) =>
              unawaited(_setLocationMarker(value)),
        ),
      ),
    );
  }

  Future<void> _toggleFavorite(PointOfInterest poi) async {
    if (_selectedPlace?.place.reference?.provider == 'google-ui-kit') {
      _message = _text(
        'You can navigate here. To save it, first confirm the place on the map.',
        '可直接导航到此地点。收藏时，请先在地图上确认地点。',
      );
      return;
    }
    if (_account.profile == null) {
      _showProfile();
      return;
    }
    try {
      await _account.saveFavorite(
        placeId: _placeKey(poi),
        name: poi.name,
        latitude: poi.latLng.latitude,
        longitude: poi.latLng.longitude,
        favorite: !_isFavorite(poi),
      );
    } catch (error) {
      if (mounted) {
        _message = _text(
          'Could not update your saved places. ${friendlyErrorMessage(error, _appLanguage)}',
          '无法更新收藏。${friendlyErrorMessage(error, _appLanguage)}',
        );
      }
    }
  }

  Future<void> _reviewPlace(PointOfInterest poi) async {
    if (_account.profile == null) {
      _showProfile();
      return;
    }
    final existing = _account.profile?.reviews
        .where((review) => review['placeId'] == _placeKey(poi))
        .firstOrNull;
    final review = await showPlaceReviewDialog(
      context,
      language: _appLanguage,
      placeName: poi.name,
      initialRating: (existing?['rating'] as num?)?.round() ?? 5,
      initialComment: existing?['comment'] as String? ?? '',
    );
    if (review == null) return;
    try {
      await _account.saveReview(
        placeId: _placeKey(poi),
        placeName: poi.name,
        rating: review.rating,
        comment: review.comment,
      );
    } catch (error) {
      if (mounted) {
        _message = _text(
          'Could not save your review. ${friendlyErrorMessage(error, _appLanguage)}',
          '无法保存评价。${friendlyErrorMessage(error, _appLanguage)}',
        );
      }
    }
  }

  Future<void> _renderRoutePreview() async {
    _following = false;
    final renderer = _takeCamera();
    final route = _preview.selectedRoute;
    if (renderer is RouteMapRenderer && route != null) {
      await renderer.fitRoute(
        route.points,
        bottomInset: (MediaQuery.sizeOf(context).height * .44).clamp(330, 420),
      );
    }
  }

  Future<void> _addStop() async {
    final stop = await showModalBottomSheet<DestinationSuggestion>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 18,
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 18,
        ),
        child: ExploreSearch(
          language: _appLanguage,
          currentLocation: _gpsLocation,
          onSelected: (selection) => Navigator.of(sheetContext).pop(selection),
        ),
      ),
    );
    if (!mounted || stop == null || _selectedPoi == null) return;
    await _preview.addStop(stop);
  }

  Future<void> _saveCurrentRoute() async {
    if (!await _preview.saveCurrentRoute() || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_text('Route saved on this device', '路线已保存在本机'))),
    );
  }

  void _toggleVoice() => _setVoiceEnabled(!_voiceEnabled);

  void _setVoiceEnabled(bool value) {
    setState(() => _voiceEnabled = value);
    _driveEngine.voiceEnabled = value;
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setBool('waybi.voice.enabled', value),
      ),
    );
  }

  void _setLanesEnabled(bool value) {
    setState(() => _lanesEnabled = value);
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setBool('waybi.nav.lanes', value),
      ),
    );
  }

  void _selectPlace(
    PlaceSummary place,
    SelectionSource source, {
    PlaceDetails? seedDetails,
  }) {
    if (_driveEngine.active || _transitTripRunning) return;
    _preview.cancelPending();
    if ((!const ProviderPolicy(MapProvider.independent)
        .canDisplay(place.reference))) {
      _message = _text(
        'This place belongs to another map provider.',
        '这个地点来自其他地图服务，无法在 Waybi 中打开。',
      );
      return;
    }
    // A new place supersedes the last place's preview, ETA and start.
    _message = null;
    _preview.beginPlace();
    _places.select(
      place,
      source,
      originMap: _mapProvider,
      seedDetails: seedDetails,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusSelectedPlace();
      _loadPlaceQuickRoute();
    });
  }

  void _rememberDestination(DestinationSuggestion suggestion) {
    _guestRecent.removeWhere((item) => item.label == suggestion.label);
    _guestRecent.insert(0, suggestion);
    if (_guestRecent.length > 12) _guestRecent.removeLast();
    unawaited(_persistGoogleRecent());
    if (_account.profile != null) {
      unawaited(
        _account
            .recordDestination(
              label: suggestion.label,
              latitude: suggestion.location.latitude,
              longitude: suggestion.location.longitude,
            )
            .catchError((_) {}),
      );
    }
  }

  void _restoreGoogleRecent(SharedPreferences prefs) {
    _guestRecent.clear();
    for (final record
        in prefs.getStringList('waybi.recent.google') ?? const []) {
      try {
        final item = jsonDecode(record) as Map<String, dynamic>;
        _guestRecent.add(
          DestinationSuggestion(
            label: item['label']?.toString() ?? '',
            name: item['name']?.toString(),
            address: item['address']?.toString(),
            location: LatLng(
              latitude: (item['latitude'] as num).toDouble(),
              longitude: (item['longitude'] as num).toDouble(),
            ),
          ),
        );
      } catch (_) {
        // A malformed historic record should not prevent search.
      }
    }
  }

  Future<void> _persistGoogleRecent() async {
    final records = [
      for (final item in _guestRecent)
        jsonEncode({
          'label': item.label,
          'name': item.name,
          'address': item.address,
          'latitude': item.location.latitude,
          'longitude': item.location.longitude,
        }),
    ];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('waybi.recent.google', records);
  }

  Future<void> _setCarMarker(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('waybi.map.car_marker', value);
    _queueMapRefresh();
  }

  Future<void> _setLocationMarker(LocationMarkerStyle style) async {
    setState(() => _locationMarker = style);
    await _setCarMarker(style != LocationMarkerStyle.classic);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('waybi.map.location_marker', style.name);
    _queueMapRefresh();
  }

  Future<void> _setMapLayers(MapLayerSettings value) async {
    final trafficJustEnabled = value.traffic && !_layers.traffic;
    setState(() => _layers = value);
    _driveEngine.setCameraAlertFilter(value.alerts);
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setBool('waybi.layers.cameras', value.cameras),
      prefs.setBool('waybi.layers.spot_speed', value.spotSpeed),
      prefs.setBool('waybi.layers.average_speed', value.averageSpeed),
      prefs.setBool('waybi.layers.red_light', value.redLight),
      prefs.setBool('waybi.layers.dual_red_speed', value.dualRedLightSpeed),
      prefs.setBool('waybi.layers.bus_lane', value.busLane),
      prefs.setBool('waybi.layers.other', value.other),
      prefs.setBool('waybi.alerts.spot_speed', value.alertSpotSpeed),
      prefs.setBool('waybi.alerts.average_speed', value.alertAverageSpeed),
      prefs.setBool('waybi.alerts.red_light', value.alertRedLight),
      prefs.setBool(
        'waybi.alerts.dual_red_speed',
        value.alertDualRedLightSpeed,
      ),
      prefs.setBool('waybi.alerts.bus_lane', value.alertBusLane),
      prefs.setBool('waybi.alerts.other_camera', value.alertOther),
      prefs.setBool('waybi.layers.traffic', value.traffic),
      prefs.setBool('waybi.layers.road_events', value.roadEvents),
      prefs.setBool('waybi.layers.transit_lanes', value.transitLanes),
      prefs.setString('waybi.layers.style', value.style.name),
    ]);
    if ((trafficJustEnabled)) {
      await _driveEngine.startTrafficFlowRefresh(force: true);
    } else if (!value.traffic && !_driveEngine.active) {
      _driveEngine.stopTrafficFlowRefresh();
    }
  }

  void _showMapLayers() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (_) => MapLayerSheet(
        settings: _layers,
        mapProvider: _mapProvider,
        language: _appLanguage,
        trafficStatus: _driveEngine.trafficFlowStatus,
        trafficSegmentCount: _driveEngine.trafficFlowSegments
            .where((s) => s.hasRoadGeometry)
            .length,
        transitLaneCount: _driveEngine.transitSnapshot?.lanes.length ?? 0,
        reviewCorridorCount: _driveEngine.transitReviewCorridors.length,
        onChanged: (value) => unawaited(_setMapLayers(value)),
      ),
    );
  }

  Future<void> _setNotificationPreference(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    if (value) {
      await WaybiNotificationService.instance.requestPermission();
    }
    if (!mounted) return;
    setState(() {
      switch (key) {
        case 'waybi.notifications.safety_cameras':
          _notifySafetyCameras = value;
        case 'waybi.notifications.road_incidents':
          _notifyRoadIncidents = value;
        case 'waybi.notifications.community_reports':
          _notifyCommunityReports = value;
        case 'waybi.notifications.saved_route_disruptions':
          _notifySavedRouteDisruptions = value;
      }
    });
    if (value && key == 'waybi.notifications.saved_route_disruptions') {
      unawaited(_commute.deliverRouteWatchAlerts(force: true));
    }
  }

  Future<void> _setVoiceLanguage(String language) async {
    setState(() => _voiceLanguage = language);
    await _driveEngine.setVoiceLanguage(language);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('waybi.voice.language', language);
  }

  Future<void> _setAppLanguage(String language) async {
    final next = language == 'zh' ? 'zh' : 'en';
    setState(() => _appLanguage = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('waybi.app.language', next);
    _driveEngine.navigationLanguage = next;
    widget.onAppLanguageChanged?.call(next);
    final applied = await _applyNativeMapLanguage(next);
    if (!applied && mounted) {
      _message = _text(
        'Navigation text updated. Change the app language in system Settings for Google map labels, then reopen Waybi.',
        '导航文字已更新。Google 地图标签请在系统设置中选择应用语言，然后重新打开 Waybi。',
      );
    }
    if (_preview.plan != null && _selectedPoi != null) {
      unawaited(_preview.load(mode: _preview.mode));
    }
  }

  static Future<bool> _applyNativeMapLanguage(String language) async {
    try {
      return await NativeMapLanguage.apply(language);
    } catch (_) {
      return false;
    }
  }

  String _text(String english, String chinese) =>
      _appLanguage == 'zh' ? chinese : english;

  void _showNavigationSettings() => _showProfile();

  Future<void> _showDirections() async {
    final route = _nav.activeRoute;
    if (route == null) return;

    final size = MediaQuery.sizeOf(context);
    final sheetHeight = (size.height * .40).clamp(300.0, 390.0);
    final bottomInset = sheetHeight - 14;

    if ((_browseRenderer is RouteMapRenderer)) {
      _following = false;
      await (_takeCamera() as RouteMapRenderer).fitRoute(
        route.points,
        bottomInset: bottomInset,
      );
    }

    if (!mounted) return;
    await showDirectionsSheet(
      context,
      route,
      language: _appLanguage,
      sheetHeight: sheetHeight,
    );
  }

  Future<void> _shareTripSnapshot() async {
    final details = _nav.tripSnapshot();
    if (!mounted) return;
    try {
      await const MethodChannel('waybi/share')
          .invokeMethod<void>('shareText', {'text': details});
    } on MissingPluginException {
      await Clipboard.setData(ClipboardData(text: details));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _text('ETA snapshot copied to clipboard', '到达时间快照已复制'),
            ),
          ),
        );
      }
    }
  }

  void _showAlongRouteSearch() => unawaited(_searchIndependentStop());

  Future<void> _searchIndependentStop() async {
    final current = _driveEngine.snappedLocation ?? _gpsLocation;
    final selected = await Navigator.of(context).push<PlaceSummary>(
      MaterialPageRoute(
        builder: (_) => FullScreenSearch(
          provider: _independentSearch,
          resolve: (candidate) async {
            if (candidate.location == null) {
              throw StateError(
                _text('This place has no location.', '这个地点没有位置信息。'),
              );
            }
            return candidate.toPlace(candidate.location!);
          },
          language: _appLanguage,
          marker: _locationMarker,
          recent: _recentDestinations
              .map(
                (item) => PlaceSummary(
                  name: item.name ?? item.label,
                  address: item.address ?? '',
                  location: GeoPoint(
                    item.location.latitude,
                    item.location.longitude,
                  ),
                ),
              )
              .toList(growable: false),
          currentLocation: current == null
              ? null
              : GeoPoint(current.latitude, current.longitude),
        ),
      ),
    );
    if (!mounted || selected == null || !_independentNavigation.active) {
      return;
    }
    final route = _independentNavigation.route!;
    final location = _driveEngine.snappedLocation ?? _gpsLocation;
    if (location == null) return;
    try {
      final updated = await _independentRoutes.reroute(
        origin: GeoPoint(location.latitude, location.longitude),
        destination: route.points.last,
        mode: route.mode,
        stops: [selected.location, ..._independentNavigation.remainingStops],
        language: _appLanguage,
      );
      if (!mounted ||
          !_independentNavigation.active ||
          !identical(route, _independentNavigation.route)) {
        return;
      }
      await _independentNavigation.start(updated);
      _recenter();
    } catch (_) {
      if (mounted) {
        _message = _text(
          'Could not add this stop. Your current route is still active.',
          '无法添加途经点，当前导航路线继续有效。',
        );
      }
    }
  }

  Future<TripsSnapshot> _readTripsSnapshot({
    Map<String, RouteWatchItem> routeWatches = const {},
  }) async {
    final quickPlaces = <String, TripDestination>{};
    for (final label in const ['Home', 'Work']) {
      final place = _commute.places[label];
      if (place == null) continue;
      quickPlaces[label] = TripDestination(
        name: place.name,
        address: place.address,
        location: place.location,
      );
    }

    final recent = _recentDestinations
        .map(
          (item) => TripDestination(
            name: item.name ?? item.label,
            address: item.address ?? '',
            location: GeoPoint(item.location.latitude, item.location.longitude),
          ),
        )
        .toList(growable: false);

    final history = <TripHistoryItem>[];
    for (final record
        in _account.profile?.routes ?? const <Map<String, dynamic>>[]) {
      final latitude = record['latitude'];
      final longitude = record['longitude'];
      final distance = record['distanceMeters'];
      final duration = record['durationSeconds'];
      if (latitude is! num ||
          longitude is! num ||
          distance is! num ||
          duration is! num) {
        continue;
      }
      history.add(
        TripHistoryItem(
          destination: TripDestination(
            name:
                record['destinationName']?.toString() ??
                _text('Recent trip', '最近行程'),
            location: GeoPoint(latitude.toDouble(), longitude.toDouble()),
          ),
          mode: record['mode']?.toString() ?? 'drive',
          distanceMeters: distance.toInt(),
          durationSeconds: duration.toInt(),
          createdAt: record['startedAt'] is num
              ? DateTime.fromMillisecondsSinceEpoch(
                  (record['startedAt'] as num).toInt(),
                )
              : DateTime.tryParse(
                  (record['createdAt'] ?? record['startedAt'])?.toString() ??
                      '',
                ),
        ),
      );
    }

    final prefs = await SharedPreferences.getInstance();
    const guestPrefix = 'waybi.companion.guest.v1.';
    return TripsSnapshot(
      lifetimeDistanceMeters: _account.profile?.companionTotals?.distanceMeters,
      lifetimeTripCount: _account.profile?.companionTotals?.tripCount,
      lifetimeDurationSeconds:
          _account.profile?.companionTotals?.durationSeconds,
      guestDistanceMeters: prefs.getInt('${guestPrefix}distance') ?? 0,
      guestTripCount: prefs.getInt('${guestPrefix}trips') ?? 0,
      guestDurationSeconds: prefs.getInt('${guestPrefix}duration') ?? 0,
      quickPlaces: quickPlaces,
      quickRoutes: _commute.quickRoutes,
      recent: recent,
      history: history,
      routeWatches: routeWatches,
      smartCommuteRoutes: _commute.smartRoutes,
      signedIn: _account.signedIn,
      isPlus: _account.profile?.isPlus == true,
    );
  }

  Stream<TripsSnapshot> _loadTripsProgressively() {
    final session = _account.sessionToken;
    final watches = <String, RouteWatchItem>{};
    return loadTripsInStages(
      readSnapshot: () => _readTripsSnapshot(
        routeWatches: _account.sessionToken == session
            ? Map.of(watches)
            : const {},
      ),
      refreshers: [
        if (_account.signedIn)
          (publish) async {
            try {
              await _account.refresh();
            } catch (_) {
              /* Keep cached profile. */
            }
            publish();
            if (!mounted || _account.sessionToken != session) return;
            await _journeys.syncGuestCompanionJourneys();
            publish();
            if (!mounted || _account.sessionToken != session) return;
            await _journeys.syncPendingAccountJourneys();
          },
        (_) => _commute.refreshQuick(),
        if (_account.signedIn && _account.profile?.isPlus == true)
          (publish) async {
            for (final item in await _account.routeWatches()) {
              if (!mounted || _account.sessionToken != session) return;
              final watch = RouteWatchItem.fromJson(item);
              if (watch.id.isNotEmpty && watch.label.isNotEmpty) {
                watches[watch.label] = watch;
              }
            }
            publish();
            if (watches.isNotEmpty) {
              await _commute.refreshSmart();
            } else {
              _commute.clearSmart();
            }
          },
      ],
    );
  }

  Future<TripsSnapshot> _loadTripsSnapshot() => _loadTripsProgressively().last;

  Future<void> _showTrips() async {
    final result = await Navigator.of(context).push<TripsResult>(
      MaterialPageRoute(
        builder: (_) => TripsPage(
          language: _appLanguage,
          loader: _loadTripsSnapshot,
          progressiveLoader: _loadTripsProgressively,
          onRouteWatchChanged: _commute.setRouteWatch,
        ),
      ),
    );
    if (!mounted || result == null) return;

    final configureLabel = result.configureLabel;
    if (configureLabel != null) {
      await _openSearch(saveAs: configureLabel);
      return;
    }

    final destination = result.destination;
    if (destination == null) return;
    _selectPlace(
      PlaceSummary(
        name: destination.name,
        address: destination.address,
        location: destination.location,
      ),
      SelectionSource.frequent,
    );
  }

  Future<void> _showDiscover() async {
    final origin = _gpsLocation == null
        ? _viewport.center
        : GeoPoint(_gpsLocation!.latitude, _gpsLocation!.longitude);
    final action = await Navigator.of(context).push<DiscoverAction>(
      MaterialPageRoute(
        builder: (_) => DiscoverPage(
          language: _appLanguage,
          loader: _loadTripsSnapshot,
          roadLoader: () async {
            await _driveEngine.loadCameras(force: true, center: origin);
            return DiscoverRoadSnapshot(
              events: _driveEngine.roadEvents,
              status: _driveEngine.roadEventSyncStatus,
              checkedAt: _driveEngine.roadEventCheckedAt,
              officialCoverage: _driveEngine.roadEventOfficialCoverage,
            );
          },
          origin: origin,
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action.kind) {
      case DiscoverActionKind.search:
        _showGoSearch();
      case DiscoverActionKind.trips:
        await _showTrips();
      case DiscoverActionKind.destination:
        final place = action.destination!;
        _selectPlace(
          PlaceSummary(
            name: place.name,
            address: place.address,
            location: place.location,
          ),
          SelectionSource.frequent,
        );
      case DiscoverActionKind.direction:
        await _showExplore(center: action.center);
      case DiscoverActionKind.roadEvent:
        final event = action.event!;
        await _setMapLayers(_layers.copyWith(roadEvents: true));
        if (!_driveEngine.active) {
          setState(() => _following = false);
          await _takeCamera()?.moveTo(
            _viewport.copyWith(
              center: event.location,
              zoom: 15.5,
              bearing: 0,
              pitch: 0,
            ),
          );
        }
        if (mounted) await _showRoadEventDetails(event);
    }
  }

  Future<void> _showSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final savedRoutes = prefs.getStringList('waybi.saved.routes') ?? [];
    final favoritePlaces =
        (_account.profile?.places ?? <Map<String, dynamic>>[])
            .where((item) => item['isFavorite'] == true)
            .toList(growable: false);
    if (!mounted) return;
    showSavedSheet(
      context,
      language: _appLanguage,
      savedRoutes: savedRoutes,
      favoritePlaces: favoritePlaces,
      onPlace: (place) => _selectPlace(place, SelectionSource.saved),
      onNotice: (message) => _message = message,
    );
  }

  Future<List<PlaceCandidate>> _loadMapSearchSuggestions(String query) {
    final point = _gpsLocation == null
        ? _viewport.center
        : GeoPoint(_gpsLocation!.latitude, _gpsLocation!.longitude);
    final SearchProvider provider = _independentSearch;
    return provider.search(query, proximity: point, language: _appLanguage);
  }

  List<PlaceCandidate> _cachedMapSearchSuggestions(String query) {
    final point = _gpsLocation == null
        ? _viewport.center
        : GeoPoint(_gpsLocation!.latitude, _gpsLocation!.longitude);
    final CachedSearchProvider provider = _independentSearch;
    return provider.cachedSuggestions(
      query,
      proximity: point,
      language: _appLanguage,
    );
  }

  void _selectMapSearchSuggestion(PlaceCandidate candidate) {
    final location = candidate.location;
    if (location == null) {
      unawaited(_openSearch(query: candidate.name));
      return;
    }
    final place = candidate.toPlace(location);
    _rememberDestination(
      DestinationSuggestion(
        label: place.name,
        name: place.name,
        address: place.address,
        location: LatLng(
          latitude: place.location.latitude,
          longitude: place.location.longitude,
        ),
      ),
    );
    _selectPlace(place, SelectionSource.search);
  }

  void _showGoSearch() => unawaited(_openSearch());

  Future<PlaceSummary?> _openSearch({
    String query = '',
    String? saveAs,
    bool selectResult = true,
    bool Function()? isCurrent,
    String? searchPurpose,
  }) async {
    final SearchProvider provider = _independentSearch;
    final place = await Navigator.of(context).push<PlaceSummary>(
      PageRouteBuilder<PlaceSummary>(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (_, animation, secondaryAnimation) => FullScreenSearch(
          preferGoogle: true,
          provider: provider,
          resolve: (candidate) async {
            if (candidate.location != null) {
              return candidate.toPlace(candidate.location!);
            }
            final reference = candidate.reference;
            if (reference == null) {
              throw StateError(
                _text('This place has no location.', '这个地点没有位置信息。'),
              );
            }
            return _independentSearch.resolve(
              reference,
              language: _appLanguage,
            );
          },
          language: _appLanguage,
          marker: _locationMarker,
          currentLocation: _gpsLocation == null
              ? _viewport.center
              : GeoPoint(_gpsLocation!.latitude, _gpsLocation!.longitude),
          recent: _recentDestinations
              .map(
                (item) => PlaceSummary(
                  name: item.name ?? item.label,
                  address: item.address ?? '',
                  location: GeoPoint(
                    item.location.latitude,
                    item.location.longitude,
                  ),
                ),
              )
              .toList(growable: false),
          initialQuery: query,
          purpose: searchPurpose,
          onDriveMode: selectResult ? () => unawaited(_nav.startDrive()) : null,
        ),
        transitionsBuilder: (_, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
    if (!mounted || (isCurrent != null && !isCurrent())) return null;
    if (place == null) return null;
    if (place.reference?.provider == 'google-ui-kit') {
      _preview.rememberSessionCoordinate(place.location);
    }
    if (!selectResult) return place;
    if (place.reference?.provider == 'google-ui-kit') {
      // The selected UI Kit coordinate is used for this navigation session.
      // Persist only independently retrieved addresses, never Google content.
      _selectPlace(place, SelectionSource.search);
      if (saveAs != null) {
        List<PlaceCandidate> matching = const [];
        try {
          matching = await _independentSearch.search(
            place.name,
            proximity: place.location,
            language: _appLanguage,
          );
        } catch (_) {
          /* Navigation remains available. */
        }
        final independent = matching
            .where(
              (candidate) =>
                  candidate.location != null &&
                  candidate.category != 'approximate_address' &&
                  place.name.toLowerCase().startsWith(
                    candidate.name.toLowerCase(),
                  ) &&
                  distanceMeters(
                        place.location.latitude,
                        place.location.longitude,
                        candidate.location!.latitude,
                        candidate.location!.longitude,
                      ) <
                      75,
            )
            .firstOrNull;
        if (independent != null && mounted) {
          await _commute.setPlace(
            saveAs,
            independent.toPlace(independent.location!),
            _mapProvider,
          );
        } else {
          _message = _text(
            'Place selected. To save Home or Work, first confirm it on the map.',
            '地点已选中。保存家或公司时，请先在地图上确认地点。',
          );
        }
      }
      if (!mounted) return place;
      return place;
    }
    if (saveAs != null) {
      await _commute.setPlace(saveAs, place, _mapProvider);
    }
    _rememberDestination(
      DestinationSuggestion(
        label: place.name,
        name: place.name,
        address: place.address,
        location: LatLng(
          latitude: place.location.latitude,
          longitude: place.location.longitude,
        ),
      ),
    );
    _selectPlace(place, SelectionSource.search);
    await _takeCamera()?.moveTo(_viewport.copyWith(center: place.location));
    return place;
  }

  Widget _buildQuickActions() => QuickActionsBar(
    actions: _quickActions,
    language: _appLanguage,
    commuteRoutes: _commute.quickRoutes,
    onAction: _onQuickAction,
    onEdit: _editQuickActions,
  );

  void _onQuickAction(String action) {
    if (action == 'Home' || action == 'Work') {
      final place = _commute.places[action];
      if (place != null && _commute.providerOf(action) == _mapProvider) {
        _selectPlace(
          place,
          action == 'Home' ? SelectionSource.home : SelectionSource.work,
        );
        return;
      }
      unawaited(_openSearch(saveAs: action));
      return;
    }
    if (action == 'Frequent') {
      final recent = _recentDestinations;
      if (recent.isNotEmpty) {
        final item = recent.first;
        _selectPlace(
          PlaceSummary(
            name: item.name ?? item.label,
            address: item.address ?? '',
            location: GeoPoint(item.location.latitude, item.location.longitude),
          ),
          SelectionSource.frequent,
        );
        return;
      }
    }
    unawaited(
      _openSearch(
        query: action == 'Frequent'
            ? ''
            : quickActionQuery(action, _appLanguage),
      ),
    );
  }

  void _maybeShowSearchArea() {
    final center = _viewport.center;
    final moved = distanceMeters(
      center.latitude,
      center.longitude,
      _areaSearchAnchor.latitude,
      _areaSearchAnchor.longitude,
    );
    if (moved > 350 && !_showSearchArea && mounted) {
      setState(() => _showSearchArea = true);
    }
  }

  void _editQuickActions() {
    final actions = [..._quickActions];
    showQuickActionsEditor(
      context,
      language: _appLanguage,
      actions: actions,
      onSetLocation: (action) => unawaited(_openSearch(saveAs: action)),
      onDone: (actions) async {
        setState(() => _quickActions = actions);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('waybi.quick_actions', actions);
      },
    );
  }

  void _searchThisArea() {
    setState(() {
      _showSearchArea = false;
      _areaSearchAnchor = _viewport.center;
    });
    _showExplore(center: _viewport.center);
  }

  Future<void> _showExplore({GeoPoint? center}) async {
    final searchCenter =
        center ??
        (_gpsLocation == null
            ? _viewport.center
            : GeoPoint(_gpsLocation!.latitude, _gpsLocation!.longitude));
    final current = LatLng(
      latitude: searchCenter.latitude,
      longitude: searchCenter.longitude,
    );
    final place = await Navigator.of(context).push<ExplorePlace>(
      MaterialPageRoute(
        builder: (_) => ExplorePage(
          currentLocation: current,
          language: _appLanguage,
          mapCompatible: true,
        ),
      ),
    );
    if (!mounted || place == null) return;
    _selectPlace(
      PlaceSummary(
        name: place.name,
        address: place.address,
        category: place.primaryType,
        location: GeoPoint(place.latitude, place.longitude),
        reference: ProviderReference(place.provider, place.placeId),
      ),
      SelectionSource.explore,
      seedDetails: (place.photoUrl?.isNotEmpty == true)
          ? PlaceDetails.fromJson({
              'placeId': place.placeId,
              'name': place.name,
              'address': place.address,
              'primaryType': place.primaryType,
              'photos': [
                {
                  'url': place.photoUrl,
                  'attribution': place.photoAttribution,
                  'sourceUrl': place.photoCredit?['sourceUrl'] ?? '',
                  'licenseUrl': place.photoCredit?['licenseUrl'] ?? '',
                },
              ],
            })
          : null,
    );
  }

  Widget _buildBottomBar() => HomeBottomBar(
    language: _appLanguage,
    onMap: _recenter,
    onDiscover: () => unawaited(_showDiscover()),
    onStart: _showGoSearch,
    onTrips: () => unawaited(_showTrips()),
    onMe: _showProfile,
  );

  void _updateNavigationTopInset(double inset) {
    _navigationTopInset = inset;
    _applyNavigationPadding();
  }

  void _updateNavigationBottomInset(double inset) {
    _navigationBottomInset = inset;
    _applyNavigationPadding();
  }

  void _applyNavigationPadding() {
    if ((mounted)) {
      setState(() {});
      if (_following) _queueMapRefresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_settingsLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final arrivalPhotos = _nav.arrivalDetails?.photos ?? const <PlacePhoto>[];
    final arrivalDestination = _nav.destination;
    // The remaining distance changes every tick: only the panel listens.
    final arrivalPanel =
        _arrivalMode &&
            _nav.remainingMeters != null &&
            arrivalDestination != null
        ? ListenableBuilder(
            listenable: _independentNavigation,
            builder: (context, _) => ArrivalExperiencePanel(
              language: _appLanguage,
              destinationTitle: _nav.destinationTitle,
              destinationAddress: arrivalDestination.address,
              remainingMeters: _nav.remainingMeters ?? 0,
              photoUrl: arrivalPhotos.isEmpty ? null : arrivalPhotos.first.url,
              selectedParkingTitle: _preview.selectedParking?.name,
              parkingPlaces: _nav.arrivalParking,
              parkingLoading: _nav.arrivalPrefetching,
              onParkingSelected: (parking) =>
                  unawaited(_nav.routeToArrivalParking(parking)),
            ),
          )
        : null;
    return PopScope(
      canPop: _canPopHome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_handleBack());
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              // Location, compass, drive ticks and route progress redraw only
              // the map; the rest of the page rebuilds on real changes.
              child: ListenableBuilder(
                listenable: _mapTicks,
                builder: (context, _) => IndependentMapRenderer(
                  key: const ValueKey('independent-browse-view'),
                  initialViewport: _viewport,
                  layers: _layers,
                  locationMarker: _locationMarker,
                  locationEnabled: _gpsLocation != null,
                  following: _following,
                  navigating: _independentNavigation.active,
                  driving: _driveEngine.active,
                  location: _displayLocation == null
                      ? null
                      : GeoPoint(
                          _displayLocation!.latitude,
                          _displayLocation!.longitude,
                        ),
                  heading: navigationForwardBearing(
                    speedKph: _driveEngine.active ? _driveEngine.speedKph : 0,
                    course:
                        _driveEngine.snappedHeadingDegrees ?? _travelHeading,
                    compass: _deviceHeading,
                    routeBearing: _routeInitialBearing,
                  ),
                  contentPadding: _guidanceRunning
                      ? _independentNavigationPadding
                      : EdgeInsets.only(
                          bottom: _selectedPlace == null
                              ? 96
                              : _placeDeckInset(expanded: false),
                        ),
                  moving: _travelHeading != null,
                  language: _appLanguage,
                  cameras: _driveEngine.cameras,
                  onCamera: (camera) => unawaited(_showCameraDetails(camera)),
                  roadEvents: _visibleRoadEvents,
                  transitLanes: _driveEngine.transitSnapshot?.lanes ?? const [],
                  transitReviewCorridors: _driveEngine.transitReviewCorridors,
                  onTransitReviewCorridor: (corridor) =>
                      unawaited(_showTransitReviewDetails(corridor)),
                  onTransitLane: (lane) =>
                      unawaited(_showTransitLaneDetails(lane)),
                  onRoadEvent: (event) =>
                      unawaited(_showRoadEventDetails(event)),
                  trafficSegments: _driveEngine.trafficFlowSegments,
                  trafficTileOverlay: _driveEngine.trafficTileOverlay,
                  trafficFresh: _driveEngine.trafficFlowStatus == 'live',
                  routePaths: _visibleIndependentRoutePaths,
                  selectedPlace: _selectedPlace?.place,
                  explorePlaces: _exploreResults,
                  onExplorePlace: (place) => _exploreMarkerFocus.value = place,
                  onReady: (renderer) {
                    _browseRenderer = renderer;
                    if (_journeyPhase == JourneyPhase.routePreview) {
                      unawaited(_renderRoutePreview());
                    } else {
                      _queueMapRefresh();
                    }
                  },
                  onViewportChanged: (viewport) => _viewport = viewport,
                  onGestureChanged: (touching) =>
                      _driveCameraFollow.touch(touching, DateTime.now()),
                  onUserPan: () => _markMapManuallyMoved(searchArea: true),
                  onMapPlace: (place) {
                    _selectPlace(
                      place,
                      place.kind == PlaceKind.coordinate
                          ? SelectionSource.longPress
                          : SelectionSource.map,
                    );
                  },
                  onBlankTap: () {
                    if (_selectedPlace != null || _preview.plan != null) {
                      unawaited(_clearRoutePreview());
                    }
                  },
                ),
              ),
            ),
            if (!_driveEngine.active && !_transitTripRunning)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                top:
                    MediaQuery.paddingOf(context).top +
                    (_showSearchArea ? 190 : 130),
                right: 16,
                child: PointerInterceptor(
                  child: Column(
                    children: [
                      if (_account.profile?.isPlus == true &&
                          _nav.parkedCar != null) ...[
                        Material(
                          color: Theme.of(context).colorScheme.surface,
                          elevation: 5,
                          borderRadius: BorderRadius.circular(14),
                          child: IconButton(
                            tooltip: _nav.parkedCarLabel(),
                            icon: const Icon(
                              Icons.directions_car_filled_rounded,
                              color: WaybiColors.ocean,
                            ),
                            onPressed: _showParkedCar,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Material(
                        color: Theme.of(context).colorScheme.surface,
                        elevation: 5,
                        borderRadius: BorderRadius.circular(14),
                        child: IconButton(
                          tooltip: _text('Saved places', '收藏地点'),
                          icon: const Icon(Icons.bookmark_outline_rounded),
                          onPressed: () => unawaited(_showSaved()),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Material(
                        color: Theme.of(context).colorScheme.surface,
                        elevation: 5,
                        borderRadius: BorderRadius.circular(14),
                        child: IconButton(
                          tooltip: _text('Map layers', '地图图层'),
                          icon: const Icon(Icons.layers_rounded),
                          onPressed: _showMapLayers,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Material(
                        color: Theme.of(context).colorScheme.surface,
                        elevation: 5,
                        borderRadius: BorderRadius.circular(14),
                        child: IconButton(
                          tooltip: _text('Report road issue', '上报道路情况'),
                          icon: const Icon(
                            Icons.add_alert_rounded,
                            color: WaybiColors.ocean,
                          ),
                          onPressed: () => unawaited(_showRoadReport()),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Material(
                        color: Theme.of(context).colorScheme.surface,
                        elevation: 5,
                        borderRadius: BorderRadius.circular(14),
                        child: IconButton(
                          tooltip: _locationControlTooltip,
                          icon: Icon(
                            _locationControlIcon,
                            color: _following
                                ? WaybiColors.ocean
                                : WaybiColors.deepOcean,
                          ),
                          onPressed: _cycleLocationCamera,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (!_driveEngine.active && !_transitTripRunning)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                top: MediaQuery.paddingOf(context).top + 8,
                left: 16,
                right: 16,
                child: PointerInterceptor(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ValueListenableBuilder<GeoPoint?>(
                        valueListenable: _location.locationListenable,
                        builder: (context, location, _) =>
                            CompanionSearchPrompt(
                              marker: _locationMarker,
                              language: _appLanguage,
                              currentLocation: location ?? _viewport.center,
                              loadSuggestions: _loadMapSearchSuggestions,
                              cachedSuggestions: _cachedMapSearchSuggestions,
                              onSuggestionSelected: _selectMapSearchSuggestion,
                              onSearch: (query) =>
                                  unawaited(_openSearch(query: query)),
                            ),
                      ),
                      const SizedBox(height: 9),
                      _buildQuickActions(),
                      if (_showSearchArea)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: FilledButton.icon(
                            onPressed: _searchThisArea,
                            icon: const Icon(Icons.refresh_rounded, size: 17),
                            label: Text(_text('Search this area', '搜索此区域')),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (_independentNavigation.active)
              Positioned.fill(
                child: ValueListenableBuilder<int?>(
                  valueListenable: _gpsAccuracyShown,
                  builder: (context, accuracy, _) =>
                      IndependentNavigationOverlay(
                        systemStatus: SystemNavigationStatus(
                          navigation: _systemNavigation,
                          language: _appLanguage,
                        ),
                        onTopInsetChanged: _updateNavigationTopInset,
                        onBottomInsetChanged: _updateNavigationBottomInset,
                        engine: _independentNavigation,
                        drive: _driveEngine,
                        destination: _nav.destinationTitle,
                        language: _appLanguage,
                        onEnd: () => unawaited(_nav.stop()),
                        onRecenter: _recenter,
                        onOverview: _showRouteOverview,
                        following: _following,
                        overviewMode: _routeOverviewActive,
                        gpsAccuracy: accuracy?.toDouble(),
                        voiceEnabled: _voiceEnabled,
                        lanesEnabled: _lanesEnabled,
                        northUp: _cameraMode.northUp,
                        perspectiveTilted: _cameraMode.tilted,
                        onCompassToggle: _toggleCompass,
                        onReport: () => unawaited(_showRoadReport()),
                        onSearchAlongRoute: _showAlongRouteSearch,
                        onDirections: _showDirections,
                        onShare: _shareTripSnapshot,
                        onSettings: _showNavigationSettings,
                        onLayers: _showMapLayers,
                        onVoiceToggle: _toggleVoice,
                        onLanesToggle: () => _setLanesEnabled(!_lanesEnabled),
                        arrivalPanel: arrivalPanel,
                        offlineReady:
                            _account.profile?.isPlus == true &&
                            _nav.offlineReady,
                        offlineCachedAt: _nav.corridorCachedAt,
                      ),
                ),
              ),
            if ((_driveEngine.active) && !_guidanceRunning)
              Positioned.fill(
                child: DriveHud(
                  language: _appLanguage,
                  following: _following,
                  onRecenter: _recenter,
                  engine: _driveEngine,
                  onStop: () => unawaited(_nav.stopDrive()),
                ),
              ),
            // Positioned: an empty banner must not size the stack.
            Positioned.fill(
              child: ValueListenableBuilder<String?>(
                valueListenable: _notice,
                builder: (context, message, _) => message == null
                    ? const SizedBox.shrink()
                    : WaybiStatusBanner(
                        key: ValueKey(message),
                        message: message,
                        dismissLabel: _text('Dismiss', '关闭'),
                        actionLabel: switch (_location.issueAction) {
                          LocationNoticeAction.appSettings ||
                          LocationNoticeAction.locationSettings => _text(
                            'Open settings',
                            '打开设置',
                          ),
                          _ => _text('Retry location', '重试定位'),
                        },
                        onAction:
                            message == _location.issueMessage &&
                                _location.issueAction != null
                            ? () => unawaited(_resolveLocationIssue())
                            : null,
                        onDismiss: () {
                          if (mounted) _message = null;
                        },
                      ),
              ),
            ),
            if (_parkingLegFinished &&
                _preview.parkingOriginalPlace != null &&
                _preview.selectedParking != null &&
                !_guidanceRunning)
              Align(
                alignment: Alignment.bottomCenter,
                child: ParkingContinuationCard(
                  destinationTitle: _preview.parkingOriginalPlace!.name,
                  parkingTitle: _preview.selectedParking!.name,
                  isChinese: _appLanguage == 'zh',
                  carRemembered: _account.profile?.isPlus == true,
                  onContinue: () => unawaited(_preview.continueOnFoot()),
                  onEnd: _nav.dismissParkingLeg,
                ),
              ),
            if (!_driveEngine.active &&
                !_transitTripRunning &&
                _selectedPoi == null &&
                !_parkingLegFinished)
              Align(
                alignment: Alignment.bottomCenter,
                child: PointerInterceptor(child: _buildBottomBar()),
              ),
            if (_selectedPoi != null &&
                !_driveEngine.active &&
                !_guidanceRunning &&
                !_transitTripRunning &&
                _preview.plan == null)
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  minimum: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: PointerInterceptor(
                    child: _PlaceCard(
                      selectedPlace: _selectedPlace!.place,
                      details: _places.details,
                      detailsLoading: _places.detailsLoading,
                      detailsError: _places.detailsError,
                      onRetryDetails: _places.retryDetails,
                      busy: _routePreviewLoading,
                      quickRoute: _places.quickRoute,
                      quickRouteLoading: _places.quickRouteLoading,
                      quickRouteIssue: _places.quickRouteIssue,
                      navigationAvailable:
                          _selectedPlace!.place.location.isValid &&
                          !_selectedPlaceHasCrossTasmanDrive,
                      navigationUnavailableReason:
                          _selectedPlaceHasCrossTasmanDrive
                          ? const NoSurfaceRouteException().localized(
                              _appLanguage,
                            )
                          : null,
                      onClose: () => unawaited(_clearRoutePreview()),
                      onNavigate: () => unawaited(_preview.load()),
                      isFavorite: _isFavorite(_selectedPoi!),
                      onFavorite: () =>
                          unawaited(_toggleFavorite(_selectedPoi!)),
                      onReview: () => unawaited(_reviewPlace(_selectedPoi!)),
                      language: _appLanguage,
                      onExpandedChanged: (expanded) =>
                          _focusSelectedPlace(expanded: expanded),
                      warnFarDestination:
                          _selectedPlace!.source == SelectionSource.search,
                    ),
                  ),
                ),
              ),
            if (_transitTripRunning && _nav.transitRoute != null)
              Positioned.fill(
                child: ValueListenableBuilder<int?>(
                  valueListenable: _gpsAccuracyShown,
                  builder: (context, accuracy, _) => TransitTripOverlay(
                    language: _appLanguage,
                    destinationTitle: _nav.destinationTitle,
                    route: _nav.transitRoute!,
                    gpsAccuracy: accuracy?.toDouble(),
                    onEnd: () => unawaited(_nav.stopTransit()),
                    onRecenter: _recenter,
                  ),
                ),
              ),
            if (_selectedPoi != null &&
                _preview.plan != null &&
                !_driveEngine.active &&
                !_guidanceRunning &&
                !_transitTripRunning) ...[
              Align(
                alignment: Alignment.bottomCenter,
                child: RoutePreviewSheet(
                  destinationTitle: _selectedPoi!.name,
                  destinationKind: _selectedPlace!.place.kind,
                  destinationCategory: _selectedPlace!.place.category,
                  // Only a search result can be the wrong same-named place;
                  // Home, Work, saved and recent places were chosen on purpose.
                  warnFarDestination:
                      _selectedPlace!.source == SelectionSource.search,
                  originTitle:
                      _preview.manualOrigin?.label ??
                      _text('Current location', '当前位置'),
                  plan: _preview.plan!,
                  selectedMode: _preview.mode,
                  selectedRouteId: _preview.selectedRouteId,
                  busy: _busy,
                  stopCount: _preview.stops.length,
                  cameraCount: _driveEngine.routeCameraCount,
                  routeCameraSummaries: _preview.cameraSummaries,
                  routePreferenceSummaries: _preview.preferenceSummaries,
                  filter: _preview.filter,
                  onFilterChanged: _preview.selectFilter,
                  cameraDataReady:
                      !_driveEngine.loadingCameras &&
                      _driveEngine.cameras.isNotEmpty,
                  statusMessage: _preview.recoveryMessage,
                  onRetry: () => unawaited(_preview.recoverBlockedRoute()),
                  routeClosures: _preview.closuresByRoute,
                  onRoadEvent: (event) =>
                      unawaited(_showRoadEventDetails(event)),
                  canRequestTransit: true,
                  canRequestModes: true,
                  customOrigin: _preview.manualOrigin != null,
                  parkingPlaces: _preview.parkingPlaces,
                  selectedParkingId: _preview.selectedParking?.id,
                  finalDestinationTitle: _preview.parkingOriginalPlace?.name,
                  parkingLoading: _preview.parkingLoading,
                  isChinese: _appLanguage == 'zh',
                  onParkingSelected: (parking) =>
                      unawaited(_preview.selectParking(parking)),
                  onDirectDestination: _preview.parkingOriginalPlace == null
                      ? null
                      : () => unawaited(_preview.restoreDirectDestination()),
                  onModeChanged: (mode) => unawaited(_preview.selectMode(mode)),
                  onRouteSelected: _preview.selectRoute,
                  onStart: () => unawaited(_nav.start()),
                  onAddStop: () => unawaited(_addStop()),
                  onSave: () => unawaited(_saveCurrentRoute()),
                  isFavorite: _isFavorite(_selectedPoi!),
                  onFavorite: () => unawaited(_toggleFavorite(_selectedPoi!)),
                  onReview: () => unawaited(_reviewPlace(_selectedPoi!)),
                  onClose: () => unawaited(_clearRoutePreview()),
                ),
              ),
              Positioned(
                right: 18,
                bottom: MediaQuery.paddingOf(context).bottom + 18,
                child: PointerInterceptor(child: _buildStartButton()),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStartButton() {
    final route = _preview.selectedRoute;
    return FloatingActionButton.extended(
      key: const Key('routeStartFloatingButton'),
      heroTag: 'route-start-floating',
      elevation: 9,
      onPressed: _busy
          ? null
          : route == null
          ? () => _preview.selectFilter(RouteFilter.recommended)
          : () => unawaited(_nav.start()),
      backgroundColor: WaybiColors.ocean,
      foregroundColor: Colors.white,
      icon: _busy
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
        _busy
            ? (_recoveringRoute
                  ? _text('Planning…', '正在规划…')
                  : _text('Starting…', '正在开始…'))
            : route == null
            ? _text('Show all routes', '查看全部路线')
            : _preview.mode == WaybiTravelMode.transit
            ? _text('Start trip', '开始行程')
            : _preview.needsRecovery(route)
            ? _text('Find detour', '规划绕行')
            : _text('Start', '开始导航'),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Notifies listeners, but never while widgets are building: a source that
/// changes during a build (the drive engine starting a camera reload from a
/// page's initState) is passed on after that frame instead.
class _FrameSafeNotifier extends ChangeNotifier {
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

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({
    required this.selectedPlace,
    required this.details,
    required this.detailsLoading,
    required this.detailsError,
    required this.onRetryDetails,
    required this.busy,
    required this.quickRoute,
    required this.quickRouteLoading,
    required this.quickRouteIssue,
    required this.navigationUnavailableReason,
    required this.navigationAvailable,
    required this.onClose,
    required this.onNavigate,
    required this.isFavorite,
    required this.onFavorite,
    required this.onReview,
    required this.language,
    required this.onExpandedChanged,
    required this.warnFarDestination,
  });

  final PlaceSummary selectedPlace;
  final PlaceDetails? details;
  final bool detailsLoading;
  final String? detailsError;
  final VoidCallback onRetryDetails;
  final bool busy;
  final RouteOption? quickRoute;
  final bool quickRouteLoading;
  final String? quickRouteIssue;
  final String? navigationUnavailableReason;
  final bool navigationAvailable;
  final VoidCallback onClose;
  final VoidCallback onNavigate;
  final bool isFavorite;
  final VoidCallback onFavorite;
  final VoidCallback onReview;
  final String language;
  final ValueChanged<bool> onExpandedChanged;
  final bool warnFarDestination;

  @override
  Widget build(BuildContext context) {
    return PlaceDetailsContent(
      selectedPlace: selectedPlace,
      details: details,
      detailsLoading: detailsLoading,
      detailsError: detailsError,
      onRetryDetails: onRetryDetails,
      routeBusy: busy,
      quickRoute: quickRoute,
      quickRouteLoading: quickRouteLoading,
      quickRouteIssue: quickRouteIssue,
      navigationUnavailableReason: navigationUnavailableReason,
      navigationAvailable: navigationAvailable,
      isFavorite: isFavorite,
      onClose: onClose,
      onNavigate: onNavigate,
      onFavorite: onFavorite,
      onReview: onReview,
      language: language,
      onExpandedChanged: onExpandedChanged,
      warnFarDestination: warnFarDestination,
    );
  }
}
