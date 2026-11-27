import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_friends/waybi_friends.dart' show GameController;
import 'package:flutter/services.dart';

import 'data/account_repository.dart';
import 'data/friends_backup_service.dart';
import 'data/http_guard.dart' show RateLimitedException;
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
import 'domain/navigation_link.dart';
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
import 'drive/navigation_language.dart';
import 'drive/navigation_location_filter.dart';
import 'widgets/status_banner.dart';
import 'drive/independent_navigation_camera.dart';
import 'drive/route_progress_tracker.dart';
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
import 'drive/route_camera_matcher.dart';
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
import 'widgets/waybi_format.dart';
import 'app/commute_controller.dart';
import 'app/home_chrome.dart';
import 'app/location_controller.dart';
import 'app/journey_store.dart';

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

class _MapHomePageState extends State<MapHomePage> with WidgetsBindingObserver {
  final _externalNavigation = ExternalNavigationInbox.instance;
  bool _externalNavigationReady = false;
  int _externalRequest = 0;
  Timer? _externalRetry;
  ({int request, SelectedPlace selected, WaybiTravelMode mode})?
  _externalPreview;

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
  Future<String?>? _journeyCountry;
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
  double? get _routingHeading =>
      _manualOrigin == null ? _currentRoutingHeading : null;

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

  DestinationSuggestion? _manualOrigin;
  final List<DestinationSuggestion> _guestRecent = [];
  RouteOption? _placeQuickRoute;
  bool _placeQuickRouteLoading = false;
  String? _placeQuickRouteIssue;
  String? _placeQuickRouteLoadingKey;
  int _placeQuickRouteRequest = 0;
  final Map<String, RouteOption> _placeQuickRouteCache = {};
  final Map<String, DateTime> _placeQuickRouteCachedAt = {};
  final Map<String, LatLng> _placeQuickRouteOrigins = {};

  String _markerSignature = '';

  MapLayerSettings _layers = const MapLayerSettings();
  NavigationCameraMode _cameraMode = NavigationCameraMode.northUpFlat;
  String _appLanguage = 'en';
  String _voiceLanguage = 'en-NZ';

  bool _following = true;
  bool _routeOverviewActive = false;
  bool _voiceEnabled = true;
  bool _keepScreenAwake = true;
  bool _settingsLoaded = false;
  bool _appForeground = true;
  final _systemNavigation = SystemNavigation();
  DateTime? _lastDrivePositionAt;
  JourneyTracker? _journey;
  late final _journeys = JourneyStore(_account);
  bool _lanesEnabled = true;
  bool _notifySafetyCameras = false;
  bool _notifyRoadIncidents = false;
  bool _notifyCommunityReports = false;
  bool _notifySavedRouteDisruptions = false;
  late String _destinationTitle = _text('Destination', '目的地');
  RoutePlan? _routePlan;
  Map<String, RouteCameraSummary> _routeCameraSummaries = const {};
  Map<String, RoutePreferenceSummary> _routePreferenceSummaries = const {};
  WaybiTravelMode _selectedMode = WaybiTravelMode.drive;
  String? _selectedRouteId;
  RouteFilter _routeFilter = RouteFilter.recommended;
  String? _routeRecoveryMessage;
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

  List<RoadEvent> _closuresOnRoute(RouteOption route) {
    final cached = _closureCache[route.id];
    final now = DateTime.now();
    if (cached != null &&
        identical(cached.route, route) &&
        identical(cached.events, _driveEngine.roadEvents) &&
        now.difference(cached.checkedAt).inSeconds < 30) {
      return cached.matches;
    }
    final matches = road_routes.routeClosures(
      route,
      _driveEngine.roadEvents,
      now: now,
    );
    if (_closureCache.length >= 12) {
      _closureCache.remove(_closureCache.keys.first);
    }
    _closureCache[route.id] = (
      route: route,
      events: _driveEngine.roadEvents,
      checkedAt: now,
      matches: matches,
    );
    return matches;
  }

  int _routeRequest = 0;
  RouteOption? _activeTransitRoute;
  RouteOption? _activeNavigationRoute;
  final List<DestinationSuggestion> _routeStops = <DestinationSuggestion>[];
  final Set<(double, double)> _googleSessionCoordinates = {};
  List<ParkingPlace> _parkingPlaces = const [];
  ParkingPlace? _selectedParking;
  PlaceSummary? _parkingOriginalPlace;
  bool _parkingLoading = false;
  PlaceSummary? _parkedCarPlace;
  DateTime? _parkedCarAt;
  int _parkingRequest = 0;
  PlaceSummary? _activeDestinationPlace;
  PlaceDetails? _arrivalPlaceDetails;
  List<ParkingPlace> _arrivalParkingPlaces = const [];
  bool _arrivalPrefetching = false;
  bool _arrivalPrefetched = false;
  int _arrivalRequest = 0;
  DateTime? _lastCorridorCacheAt;
  bool _offlineCorridorReady = false;

  SelectedPlace? _selectedPlace;
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

  PlaceDetails? _placeDetails;
  bool _placeDetailsLoading = false;
  String? _placeDetailsError;
  int _placeDetailsRequest = 0;

  /// The one trip state; the getters below are views of it.
  final _trip = TripMachine();
  TripState get _tripState => _trip.value;
  bool get _guidanceRunning => _tripState.guidanceRunning;
  bool get _endingNavigation => _tripState is TripEnding;
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

  String? _message;
  final Set<String> _notifiedRoadEventIds = <String>{};
  final Set<String> _pendingRoadNotifications = {};
  final Map<String, DateTime> _roadNotificationRetryAfter = {};
  int _roadNotificationSession = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _externalNavigation.addListener(_scheduleExternalNavigation);
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
          _closuresOnRoute(previous),
        ),
        // Abort the HTTP request before the engine stops waiting, so a slow
        // reroute never overlaps the next attempt.
        timeout: IndependentRoutingProvider.rerouteTimeout,
      ),
    );
    _independentNavigation.addListener(_onIndependentNavigationChanged);
    _trip.addListener(_onTripChanged);
    _commute.addListener(_onTripChanged);
    _location
      ..onFix = _onLocationFix
      ..onIssue = _onLocationIssue
      ..reportTransientIssues = () => _externalPreview != null;
    _location.deviceHeadingListenable.addListener(_queueMapRefresh);
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
        _scheduleExternalNavigation();
      }),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_startTracking(requestPermission: true));
    });
  }

  void _scheduleExternalNavigation() {
    if (!mounted ||
        !_externalNavigationReady ||
        !_appForeground ||
        !_externalNavigation.hasPending) {
      return;
    }
    if (_busy || _endingNavigation) {
      _externalRetry ??= Timer(const Duration(milliseconds: 200), () {
        _externalRetry = null;
        _scheduleExternalNavigation();
      });
      return;
    }
    final value = _externalNavigation.takePending();
    if (value == null) return;
    final request = ++_externalRequest;
    _externalPreview = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || request != _externalRequest) return;
      unawaited(
        _handleExternalNavigation(value, request).catchError((Object _) {
          if (mounted && request == _externalRequest) {
            _showExternalError(
              _text(
                'Could not open this destination. Try searching for it.',
                '无法打开这个目的地，请尝试搜索。',
              ),
            );
          }
        }),
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _showExternalError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleExternalNavigation(String value, int request) async {
    bool current() => mounted && request == _externalRequest;
    NavigationLink? parsed;
    try {
      parsed = NavigationLink.parse(value);
    } on FormatException {
      _showExternalError(
        _text(
          'This navigation link has an invalid destination.',
          '这个导航链接的目的地无效。',
        ),
      );
      return;
    }
    final link = parsed;
    if (link == null || !current()) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    if (_guidanceRunning || _driveEngine.active || _transitTripRunning) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_text('Switch destination?', '切换目的地？')),
          content: Text(
            _text(
              'End the current trip and open ${link.destination.label}?',
              '结束当前行程并打开 ${link.destination.label}？',
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
      );
      if (replace != true || !current()) return;
      if (_guidanceRunning) await _stopNavigation(showSummary: false);
      if (!current()) return;
      if (_transitTripRunning) await _stopTransitTrip();
      if (!current()) return;
      if (_driveEngine.active) await _stopDriveMode();
      if (!current()) return;
    }
    // Resolve every text location through the selected map provider. Never
    // silently use the first result or discard an explicit source/waypoint.
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
      return _openSearch(
        query: target.label,
        selectResult: false,
        isCurrent: current,
        searchPurpose: purpose,
      );
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
      stops.add(
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
    }
    if (!current()) return;
    setState(() {
      ++_routeRequest;
      _manualOrigin = source == null
          ? null
          : DestinationSuggestion(
              label: source.name,
              name: source.name,
              address: source.address,
              location: LatLng(
                latitude: source.location.latitude,
                longitude: source.location.longitude,
              ),
            );
      _routeStops
        ..clear()
        ..addAll(stops);
      _selectedMode = link.mode;
    });
    _selectPlace(destination, SelectionSource.search);
    if (!link.showPlaceOnly && _selectedPoi != null) {
      if (_manualOrigin == null && _locationForRoute == null) {
        _externalPreview = (
          request: request,
          selected: _selectedPlace!,
          mode: link.mode,
        );
        setState(
          () => _message = _text(
            'Waiting for your location to preview the route…',
            '正在等待定位以预览路线…',
          ),
        );
      } else {
        await _loadRoutePreview(_selectedPoi!, preferredMode: link.mode);
      }
    }
  }

  void _retryExternalPreview() {
    final pending = _externalPreview;
    if (pending == null) return;
    // Reverse geocoding replaces the selection with an enriched copy of the
    // same place, so match by location rather than identity.
    if (pending.request != _externalRequest ||
        !_samePlaceLocation(pending.selected.place, _selectedPlace?.place) ||
        _driveEngine.active ||
        _transitTripRunning) {
      _externalPreview = null;
      return;
    }
    if (_locationForRoute == null || _selectedPoi == null || _busy) return;
    _externalPreview = null;
    unawaited(_loadRoutePreview(_selectedPoi!, preferredMode: pending.mode));
  }

  static bool _samePlaceLocation(PlaceSummary a, PlaceSummary? b) =>
      b != null &&
      a.location.latitude == b.location.latitude &&
      a.location.longitude == b.location.longitude;

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
    _scheduleExternalNavigation();
    _queueMapRefresh();
    if (_guidanceRunning) {
      unawaited(
        _systemNavigation.update(_systemNavigationState(), force: true),
      );
    }
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
    if (!mounted) return;
    if (_independentNavigation.route != null) {
      _activeNavigationRoute = _independentNavigation.route;
    }
    setState(() {});
    if (_guidanceRunning) {
      unawaited(_systemNavigation.update(_systemNavigationState()));
    }
    _updateArrivalExperience();
    unawaited(_cacheNavigationCorridor());
    if (_following) _queueMapRefresh();
  }

  void _onEngineChanged() {
    if (!mounted) return;
    if (_tripState == const TripJustDrive() && !_driveEngine.active) {
      // The engine stopped on its own (for example location was revoked).
      _trip.dispatch(const DriveEnded());
    }
    _independentNavigation.checkClosureUpdates();
    final position = _driveEngine.latestPosition;
    if (position != null && position.timestamp != _lastDrivePositionAt) {
      _lastDrivePositionAt = position.timestamp;
      _location.handlePosition(position);
    }
    if (_guidanceRunning) {
      unawaited(_systemNavigation.update(_systemNavigationState()));
    }
    _journey?.cameraPassed(_driveEngine.passedCamera?.id);
    unawaited(_notifyRoadIntelligence());
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
      final plan = _routePlan;
      if (plan != null) {
        _routeCameraSummaries = _summarizeRouteCameras(plan);
        _routePreferenceSummaries = _summarizeRoutePreferences(
          plan,
          _routeCameraSummaries,
        );
      }

      {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      }
    }
    _updateArrivalExperience();
    unawaited(_cacheNavigationCorridor());
    if (!_following &&
        _driveEngine.active &&
        !_guidanceRunning &&
        !_independentNavigation.active &&
        _selectedPlace == null &&
        _routePlan == null &&
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

  double? get _navigationRemainingMeters {
    if (_independentNavigation.active) {
      return _independentNavigation.remainingDistanceMeters;
    }
    final native = _driveEngine.navInfo?.distanceToFinalDestinationMeters;
    if (native != null && native.isFinite) return native.toDouble();
    final route = _activeNavigationRoute;
    final progress = _driveEngine.routeProgress;
    if (route == null || progress == null || route.points.length < 2) {
      return null;
    }
    final geometry = RouteProgressTracker.geometryLength(route.points);
    if (geometry <= 0) return route.distanceMeters.toDouble();
    final fraction = (progress.alongMeters / geometry).clamp(0.0, 1.0);
    return route.distanceMeters * (1 - fraction);
  }

  void _updateArrivalExperience() {
    final remaining = _navigationRemainingMeters;
    final eligible =
        _account.profile?.isPlus == true &&
        _guidanceRunning &&
        _selectedMode == WaybiTravelMode.drive &&
        remaining != null;
    if (!eligible) {
      _trip.dispatch(const ArrivalChanged(false));
      return;
    }
    if (remaining <= 800 && !_arrivalPrefetching && !_arrivalPrefetched) {
      unawaited(_prefetchArrivalExperience());
    }
    _trip.dispatch(ArrivalChanged(remaining <= 300));
  }

  Future<void> _prefetchArrivalExperience() async {
    if (_account.profile?.isPlus != true) return;
    final destination = _activeDestinationPlace;
    if (destination == null || _arrivalPrefetching) return;
    final request = ++_arrivalRequest;
    _arrivalPrefetching = true;
    if (mounted) setState(() {});
    var parking = _arrivalParkingPlaces;
    var details = _arrivalPlaceDetails;
    if (_selectedParking == null) {
      try {
        parking = await _parkingRepository.nearby(
          destination: destination.location,
          allowGoogleFallback: false,
          language: _appLanguage,
        );
      } catch (_) {}
    }
    try {
      details = await _placeDetailsRepository.fetchIndependent(destination);
    } catch (_) {
      // Arrival guidance and parking remain usable without extra place details.
    }
    if (!mounted || request != _arrivalRequest) return;
    setState(() {
      _arrivalParkingPlaces = parking;
      _arrivalPlaceDetails = details;
      _arrivalPrefetching = false;
      _arrivalPrefetched = true;
    });
  }

  Future<void> _routeToArrivalParking(ParkingPlace parking) async {
    final destination = _activeDestinationPlace;
    if (destination == null || _endingNavigation) return;
    await _stopNavigation(showSummary: false);
    if (!mounted) return;
    _trip.dispatch(const PlaceChosen());
    setState(() {
      _parkingOriginalPlace = destination;
      _selectedParking = parking;
      _selectedPlace = SelectedPlace(
        parking.toPlaceSummary(),
        SelectionSource.map,
        originMap: _mapProvider,
      );
      _routeStops.clear();
    });
    final poi = _selectedPoi;
    if (poi == null) return;
    await _loadRoutePreview(poi);
    if (mounted && _selectedRoute != null) {
      await _navigateToSelectedPoi();
    }
  }

  Future<void> _cacheNavigationCorridor({bool force = false}) async {
    if (_account.profile?.isPlus != true) {
      if (_offlineCorridorReady && mounted) {
        setState(() => _offlineCorridorReady = false);
      }
      return;
    }
    final route = _activeNavigationRoute;
    if (!_guidanceRunning || route == null || route.points.length < 2) return;
    final now = DateTime.now();
    if (!force &&
        _lastCorridorCacheAt != null &&
        now.difference(_lastCorridorCacheAt!) < const Duration(seconds: 30)) {
      return;
    }
    final start = _driveEngine.routeProgress?.alongMeters ?? 0.0;
    final end = start + 6000;
    final corridor = <GeoPoint>[];
    var travelled = 0.0;
    for (var index = 0; index < route.points.length - 1; index++) {
      final a = route.points[index];
      final b = route.points[index + 1];
      final segment = distanceMeters(
        a.latitude,
        a.longitude,
        b.latitude,
        b.longitude,
      );
      final segmentEnd = travelled + segment;
      if (segmentEnd >= start - 100 && travelled <= end + 100) {
        if (corridor.isEmpty) corridor.add(a);
        corridor.add(b);
      }
      travelled = segmentEnd;
      if (travelled > end + 100) break;
    }
    final matcher = const RouteCameraMatcher();
    final steps = <Map<String, Object?>>[];
    for (final step in route.steps) {
      final along = matcher.project(step.location, route.points)?.alongMeters;
      if (along == null || along < start - 50 || along > end) continue;
      steps.add({
        'instruction': routeStepInstruction(step, _appLanguage),
        'roadName': step.roadName,
        'maneuverType': step.maneuverType,
        'maneuverModifier': step.maneuverModifier,
        'distanceMeters': step.distanceMeters,
        'alongMeters': along,
        'latitude': step.location.latitude,
        'longitude': step.location.longitude,
      });
    }
    final cameras = [
      for (final match in _driveEngine.routeCameras)
        if (match.alongMeters >= start - 50 && match.alongMeters <= end)
          {
            'id': match.camera.id,
            'type': match.camera.type,
            'location': match.camera.location,
            'latitude': match.camera.latitude,
            'longitude': match.camera.longitude,
            'alongMeters': match.alongMeters,
          },
    ];
    final events = [
      for (final event in _driveEngine.upcomingRoadEvents)
        if ((event.distanceFromDriver ?? double.infinity) <= 6000)
          {
            'id': event.id,
            'type': event.type.name,
            'roadName': event.roadName,
            'latitude': event.location.latitude,
            'longitude': event.location.longitude,
            'distanceFromDriver': event.distanceFromDriver,
            'distanceAlongRoute': event.distanceAlongRoute,
            'severity': event.severity.name,
          },
    ];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'waybi.navigation.offline_corridor.v1',
        jsonEncode({
          'cachedAt': now.toIso8601String(),
          'destination': _destinationTitle,
          'routeId': route.id,
          'fromAlongMeters': start,
          'aheadMeters': 6000,
          'geometry': [
            for (final point in corridor) [point.latitude, point.longitude],
          ],
          'steps': steps,
          'cameras': cameras,
          'roadEvents': events,
        }),
      );
      _lastCorridorCacheAt = now;
      if (mounted && !_offlineCorridorReady) {
        setState(() => _offlineCorridorReady = true);
      }
    } catch (_) {
      // Navigation remains usable from its in-memory route if persistence fails.
    }
  }

  List<RoadEvent> get _visibleRoadEvents => _layers.roadEvents
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

  String _roadEventLabel(RoadEventType type) =>
      roadEventLabel(type, _appLanguage);

  Future<void> _notifyRoadIntelligence() async {
    if (!_driveEngine.active) return;
    final camera = _driveEngine.upcomingCamera;
    final cameraDistance = _driveEngine.upcomingCameraDistanceMeters;
    if (_notifySafetyCameras &&
        camera != null &&
        cameraDistance != null &&
        cameraDistance > 0 &&
        cameraDistance <= 800) {
      final cameraType = CameraKindLabel.fromCamera(camera)
          .cameraLabel(_appLanguage);
      await _showNavigationNotification(
        id: 'camera:${camera.id}',
        title: _text('$cameraType ahead', '前方$cameraType'),
        body: _text(
          '${cameraDistance.round()} m · ${camera.location}',
          '${cameraDistance.round()} 米 · ${camera.location}',
        ),
      );
    }

    for (final event in _driveEngine.upcomingRoadEvents) {
      final distance = event.distanceAlongRoute ?? event.distanceFromDriver;
      if (distance == null || distance > 1500) continue;
      final community = event.metadata['userReported'] == true;
      final importantOfficial =
          event.severity == RoadEventSeverity.warning ||
          event.severity == RoadEventSeverity.critical;
      final enabled = community
          ? _notifyCommunityReports
          : _notifyRoadIncidents && importantOfficial;
      if (!enabled || event.type == RoadEventType.safetyCamera) continue;
      final reporter = event.metadata['reporterName']?.toString();
      await _showNavigationNotification(
        id: event.id,
        title: _roadEventLabel(event.type),
        body: reporter == null
            ? _text('${distance.round()} m ahead', '前方 ${distance.round()} 米')
            : _text(
                '${distance.round()} m ahead · reported by $reporter',
                '前方 ${distance.round()} 米 · $reporter 报告',
              ),
      );
    }
  }

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
    final parkedCarRecord = prefs.getString('waybi.plus.parked_car.v1');
    if (parkedCarRecord != null) {
      try {
        final item = jsonDecode(parkedCarRecord) as Map<String, dynamic>;
        final parkedAt = DateTime.tryParse(item['parkedAt']?.toString() ?? '');
        final latitude = item['latitude'];
        final longitude = item['longitude'];
        if (parkedAt != null &&
            latitude is num &&
            longitude is num &&
            DateTime.now().difference(parkedAt) < const Duration(hours: 72)) {
          _parkedCarAt = parkedAt;
          _parkedCarPlace = PlaceSummary(
            name: item['name']?.toString() ?? _text('Parked car', '停车位置'),
            address: item['address']?.toString() ?? '',
            location: GeoPoint(latitude.toDouble(), longitude.toDouble()),
          );
        } else {
          await prefs.remove('waybi.plus.parked_car.v1');
        }
      } catch (_) {
        await prefs.remove('waybi.plus.parked_car.v1');
      }
    }
    _appLanguage = prefs.getString('waybi.app.language') ?? 'en';
    _voiceLanguage = prefs.getString('waybi.voice.language') ?? 'en-NZ';
    _voiceEnabled = prefs.getBool('waybi.voice.enabled') ?? true;
    _lanesEnabled = prefs.getBool('waybi.nav.lanes') ?? true;
    _keepScreenAwake = prefs.getBool('waybi.nav.keep_screen_awake') ?? true;
    _driveEngine.navigationLanguage = _appLanguage;
    await _driveEngine.setKeepScreenAwake(_keepScreenAwake);
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

    {}
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
    _externalNavigation.removeListener(_scheduleExternalNavigation);
    _externalRetry?.cancel();
    ++_externalRequest;
    WidgetsBinding.instance.removeObserver(this);
    _location.deviceHeadingListenable.removeListener(_queueMapRefresh);
    _location.dispose();
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
      setState(() => _message = message);
    } else if (_message == shown) {
      setState(() => _message = null);
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
    // The filter held the last reliable fix (an indoor jump).
    if (accepted == null) {
      _retryExternalPreview();
      setState(() {});
      final place = _selectedPlace?.place;
      if (place != null && !_driveEngine.active && _routePlan == null) {
        unawaited(_loadPlaceQuickRoute(place));
      }
      return;
    }
    _retryExternalPreview();
    if (_tripState is TripNavigating &&
        DateTime.now().difference(position.timestamp).abs() <=
            const Duration(seconds: 10)) {
      final arrived =
          _journey?.update(
            accepted.point,
            accuracyMeters: accepted.accuracyMeters,
            time: accepted.timestamp,
          ) ??
          false;
      if (arrived) unawaited(_stopNavigation(arrived: true));
    }
    setState(() {});
    _queueMapRefresh();
    unawaited(_commute.refreshQuick());
    final selected = _selectedPlace?.place;
    if (selected != null && _routePlan == null && !_driveEngine.active) {
      unawaited(_loadPlaceQuickRoute(selected));
    }
  }

  String _placeRouteKey(PlaceSummary place) {
    final reference = place.reference;
    if (reference != null) return '${reference.provider}:${reference.id}';
    return '${place.location.latitude.toStringAsFixed(5)},${place.location.longitude.toStringAsFixed(5)}';
  }

  bool get _selectedPlaceHasCrossTasmanDrive {
    final destination = _selectedPlace?.place.location;
    final origin = _manualOrigin?.location ?? _locationForRoute;
    if (origin == null || destination == null) return false;
    return isCrossTasmanSurfaceRoute([
      GeoPoint(origin.latitude, origin.longitude),
      destination,
    ]);
  }

  /// A failed place ETA is retried with backoff (15 s doubling to 5 min, or
  /// the server's Retry-After), not on every GPS fix.
  final Map<String, ({DateTime retryAt, int failures, String message})>
  _placeQuickRouteFailures = {};

  static Duration _quickRouteBackoff(int failures, Object error) {
    final base = Duration(
      seconds: (15 * math.pow(2, (failures - 1).clamp(0, 5))).round().clamp(
        15,
        300,
      ),
    );
    if (error is RateLimitedException && error.retryAfter > base) {
      return error.retryAfter;
    }
    return base;
  }

  bool _isSelectedPlaceKey(String key) {
    final selected = _selectedPlace?.place;
    return selected != null && _placeRouteKey(selected) == key;
  }

  Future<void> _loadPlaceQuickRoute(PlaceSummary place) async {
    if (!mounted || _driveEngine.active || _routePlan != null) return;
    if (!place.location.isValid) return;
    final origin = _manualOrigin?.location ?? _locationForRoute;
    if (origin == null) return;
    final key = _placeRouteKey(place);
    if (!_isSelectedPlaceKey(key)) return;
    final crossTasman = isCrossTasmanSurfaceRoute([
      GeoPoint(origin.latitude, origin.longitude),
      place.location,
    ]);
    if (crossTasman) {
      ++_placeQuickRouteRequest;
      setState(() {
        _placeQuickRoute = null;
        _placeQuickRouteLoading = false;
        _placeQuickRouteLoadingKey = null;
        _placeQuickRouteIssue = const NoSurfaceRouteException().localized(
          _appLanguage,
        );
      });
      return;
    }
    final cached = _placeQuickRouteCache[key];
    final cachedAt = _placeQuickRouteCachedAt[key];
    final cachedOrigin = _placeQuickRouteOrigins[key];
    final movedMeters = cachedOrigin == null
        ? double.infinity
        : distanceMeters(
            origin.latitude,
            origin.longitude,
            cachedOrigin.latitude,
            cachedOrigin.longitude,
          );
    final fresh =
        cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < const Duration(minutes: 5) &&
        movedMeters < 300;
    if (fresh) {
      if (!identical(_placeQuickRoute, cached) ||
          _placeQuickRouteIssue != null ||
          _placeQuickRouteLoading) {
        setState(() {
          _placeQuickRoute = cached;
          _placeQuickRouteIssue = null;
          _placeQuickRouteLoading = false;
          _placeQuickRouteLoadingKey = null;
        });
      }
      return;
    }
    final failure = _placeQuickRouteFailures[key];
    if (failure != null && DateTime.now().isBefore(failure.retryAt)) {
      if (_placeQuickRouteIssue != failure.message || _placeQuickRouteLoading) {
        setState(() {
          _placeQuickRoute = null;
          _placeQuickRouteIssue = failure.message;
          _placeQuickRouteLoading = false;
          _placeQuickRouteLoadingKey = null;
        });
      }
      return;
    }
    if (_placeQuickRouteLoading && _placeQuickRouteLoadingKey == key) return;

    final request = ++_placeQuickRouteRequest;
    // Keep a previous failure visible until the retry answers; clearing it
    // first makes the card flash on every attempt.
    setState(() {
      _placeQuickRoute = null;
      _placeQuickRouteLoading = true;
      _placeQuickRouteLoadingKey = key;
    });
    // Only this request, for the place still selected, may change the card.
    bool current() =>
        mounted &&
        request == _placeQuickRouteRequest &&
        _routePlan == null &&
        _isSelectedPlaceKey(key);
    try {
      final plan = await _driveRoutePlan(
        origin: origin,
        destination: LatLng(
          latitude: place.location.latitude,
          longitude: place.location.longitude,
        ),
        mode: WaybiTravelMode.drive,
      );
      final driving = filterRoutes(
        plan.forMode(WaybiTravelMode.drive).toList(),
        RouteFilter.recommended,
        const {},
      );
      if (driving.isEmpty) throw StateError('No routes available');
      _placeQuickRouteFailures.remove(key);
      final route = driving.first;
      if (_placeQuickRouteCache.length >= 20 &&
          !_placeQuickRouteCache.containsKey(key)) {
        final oldestKey = _placeQuickRouteCachedAt.entries
            .reduce((a, b) => a.value.isBefore(b.value) ? a : b)
            .key;
        _placeQuickRouteCache.remove(oldestKey);
        _placeQuickRouteCachedAt.remove(oldestKey);
        _placeQuickRouteOrigins.remove(oldestKey);
      }
      _placeQuickRouteCache[key] = route;
      _placeQuickRouteCachedAt[key] = DateTime.now();
      _placeQuickRouteOrigins[key] = origin;
      if (!current()) return;
      setState(() {
        _placeQuickRoute = route;
        _placeQuickRouteIssue = null;
        _placeQuickRouteLoading = false;
        _placeQuickRouteLoadingKey = null;
      });
    } catch (error) {
      final failures = (_placeQuickRouteFailures[key]?.failures ?? 0) + 1;
      final message = routeFailureMessage(error, _appLanguage);
      _placeQuickRouteFailures[key] = (
        retryAt: DateTime.now().add(_quickRouteBackoff(failures, error)),
        failures: failures,
        message: message,
      );
      if (_placeQuickRouteFailures.length > 20) {
        _placeQuickRouteFailures.remove(_placeQuickRouteFailures.keys.first);
      }
      if (!current()) return;
      setState(() {
        _placeQuickRoute = null;
        _placeQuickRouteIssue = message;
        _placeQuickRouteLoading = false;
        _placeQuickRouteLoadingKey = null;
      });
    }
  }

  Future<RoutePlan> _driveRoutePlan({
    required LatLng origin,
    required LatLng destination,
    WaybiTravelMode? mode,
  }) => _independentRoutes.route(
    origin: GeoPoint(origin.latitude, origin.longitude),
    destination: GeoPoint(destination.latitude, destination.longitude),
    language: _appLanguage,
    mode: mode ?? WaybiTravelMode.drive,
  );

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
    {
      final location = _driveEngine.active
          ? _driveEngine.snappedLocation ?? _gpsLocation
          : _gpsLocation;
      final routePreviewOwnsCamera =
          !_driveEngine.active &&
          _journeyPhase == JourneyPhase.routePreview &&
          _routePlan != null;
      final placeDeckOwnsCamera =
          !_driveEngine.active && _selectedPlace != null && _routePlan == null;
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
                    ? _activeNavigationRoute?.mode ?? _selectedMode
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
      return;
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
    {
      _queueMapRefresh();
      return;
    }
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
    final points = _activeNavigationRoute?.points;
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
    {}
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
      setState(
        () => _message = _text(
          'Current location is required to report a road issue.',
          '需要获取当前位置才能上报道路情况。',
        ),
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
        setState(
          () => _message = _text(
            'Could not submit road report. ${friendlyErrorMessage(error, _appLanguage)}',
            '道路上报失败。${friendlyErrorMessage(error, _appLanguage)}',
          ),
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

    {}
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
        _routePlan != null ||
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
    ++_routeRequest;
    ++_parkingRequest;
    ++_placeQuickRouteRequest;
    // A navigation that is starting owns the drive route: it notices the
    // cancelled request and stops the engine itself. Clearing the route under
    // it would leave guidance frozen on its first step.
    if (_independentNavigation.route == null) _driveEngine.setRoute(null);
    if (!mounted) return;
    // Reset synchronously: a place selected while the map padding animates
    // must not be cleared afterwards.
    _trip.dispatch(const PlaceCleared());
    setState(() {
      _routePlan = null;
      _selectedRouteId = null;
      _selectedMode = WaybiTravelMode.drive;
      _routeRecoveryMessage = null;
      _routeFilter = RouteFilter.recommended;
      _selectedPlace = null;
      _placeDetails = null;
      _placeDetailsLoading = false;
      _placeDetailsError = null;
      _placeDetailsRequest++;
      _placeQuickRoute = null;
      _placeQuickRouteIssue = null;
      _placeQuickRouteLoading = false;
      _placeQuickRouteLoadingKey = null;
      _routeStops.clear();
      _parkingPlaces = const [];
      _parkingOriginalPlace = null;
      _selectedParking = null;
      _parkingLoading = false;
      _following = true;
    });
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
    final original = _parkingOriginalPlace;
    if (original != null) {
      if (_independentNavigation.route == null) _driveEngine.setRoute(null);
      _selectPlace(original, SelectionSource.map);
      return;
    }
    final selected = _selectedPlace;
    if (selected == null) {
      unawaited(_clearRoutePreview());
      return;
    }
    ++_routeRequest;
    ++_parkingRequest;
    if (_independentNavigation.route == null) _driveEngine.setRoute(null);
    _trip.dispatch(const PreviewClosed());
    setState(() {
      _routePlan = null;
      _selectedRouteId = null;
      _selectedMode = WaybiTravelMode.drive;
      _routeRecoveryMessage = null;
      _routeFilter = RouteFilter.recommended;
      _routeStops.clear();
      _parkingPlaces = const [];
      _parkingLoading = false;
      _message = null;
    });
    _focusSelectedPlace();
    unawaited(_loadPlaceQuickRoute(selected.place));
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
          await _stopNavigation();
        }
      case TripTransit():
        if (await _confirmEnd(
              _text('End this transit trip?', '结束这次公交行程？'),
              _text('Keep trip', '继续行程'),
            ) &&
            mounted) {
          await _stopTransitTrip();
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
        await _stopDriveMode();
      case TripParkingLeg():
        _dismissParkingLeg();
      case TripEnding():
        break;
      case TripIdle():
        if (_driveEngine.active) {
          await _stopDriveMode();
        } else if (_selectedPlace != null) {
          await _clearRoutePreview();
        }
    }
  }

  void _dismissParkingLeg() {
    _trip.dispatch(const ParkingLegDismissed());
    setState(() {
      _parkingOriginalPlace = null;
      _selectedParking = null;
    });
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

  Future<void> _rememberParkedCar(ParkingPlace parking) async {
    if (_account.profile?.isPlus != true) return;
    final parkedAt = DateTime.now();
    final place = parking.toPlaceSummary();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'waybi.plus.parked_car.v1',
      jsonEncode({
        'name': place.name,
        'address': place.address,
        'latitude': place.location.latitude,
        'longitude': place.location.longitude,
        'parkedAt': parkedAt.toIso8601String(),
      }),
    );
    if (!mounted) return;
    setState(() {
      _parkedCarPlace = place;
      _parkedCarAt = parkedAt;
    });
  }

  String _parkedCarAgeLabel() {
    final parkedAt = _parkedCarAt;
    if (parkedAt == null) return _text('Parked car', '停车位置');
    final age = DateTime.now().difference(parkedAt);
    if (age.inMinutes < 2) return _text('Parked just now', '刚刚停车');
    if (age.inHours < 1) {
      return _text('Parked ${age.inMinutes} min ago', '停车 ${age.inMinutes} 分钟');
    }
    if (age.inHours < 24) {
      return _text('Parked ${age.inHours} h ago', '停车 ${age.inHours} 小时');
    }
    return _text('Parked ${age.inDays} d ago', '停车 ${age.inDays} 天');
  }

  void _showParkedCar() {
    final parked = _parkedCarPlace;
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
      setState(() => _message = _parkedCarAgeLabel());
    }
  }

  Future<void> _loadParking(PlaceSummary destination) async {
    final request = ++_parkingRequest;
    setState(() {
      _parkingPlaces = const [];
      _parkingLoading = true;
    });
    try {
      final places = await _parkingRepository.nearby(
        destination: destination.location,
        allowGoogleFallback: false,
        language: _appLanguage,
      );
      if (!mounted || request != _parkingRequest) return;
      setState(() => _parkingPlaces = places);
    } catch (_) {
      if (mounted && request == _parkingRequest) {
        setState(() => _parkingPlaces = const []);
      }
    } finally {
      if (mounted && request == _parkingRequest) {
        setState(() => _parkingLoading = false);
      }
    }
  }

  Future<void> _selectParking(ParkingPlace parking) async {
    final original = _parkingOriginalPlace ?? _selectedPlace?.place;
    if (original == null) return;
    ++_parkingRequest;
    setState(() {
      _parkingOriginalPlace = original;
      _selectedParking = parking;
      _parkingLoading = false;
      _selectedPlace = SelectedPlace(
        parking.toPlaceSummary(),
        SelectionSource.map,
        originMap: _mapProvider,
      );
      _routeStops.clear();
    });
    final poi = _selectedPoi;
    if (poi != null) await _loadRoutePreview(poi);
  }

  Future<void> _restoreDirectDestination() async {
    final original = _parkingOriginalPlace;
    if (original == null) return;
    setState(() {
      _parkingOriginalPlace = null;
      _selectedParking = null;
      _selectedPlace = SelectedPlace(
        original,
        SelectionSource.map,
        originMap: _mapProvider,
      );
    });
    final poi = _selectedPoi;
    if (poi != null) await _loadRoutePreview(poi);
  }

  Future<void> _continueOnFoot() async {
    final original = _parkingOriginalPlace;
    if (original == null) return;
    _trip.dispatch(const PlaceChosen());
    setState(() {
      _parkingOriginalPlace = null;
      _selectedParking = null;
      _parkingPlaces = const [];
      _manualOrigin = null;
      _routeStops.clear();
      _selectedPlace = SelectedPlace(
        original,
        SelectionSource.map,
        originMap: _mapProvider,
      );
    });
    final poi = _selectedPoi;
    if (poi != null) {
      await _loadRoutePreview(poi, preferredMode: WaybiTravelMode.walk);
    }
  }

  Future<void> _recoverRouteLocation() async {
    try {
      await _location.recover();
      _retryExternalPreview();
    } catch (_) {
      if (mounted && _externalPreview != null) {
        setState(
          () => _message = _text(
            'Location unavailable. Check location access and try again.',
            '暂时无法定位，请检查定位权限后重试。',
          ),
        );
      }
    }
  }

  Future<void> _showNavigationNotification({
    required String id,
    required String title,
    required String body,
  }) async {
    if (_notifiedRoadEventIds.contains(id) ||
        _pendingRoadNotifications.contains(id) ||
        (_roadNotificationRetryAfter[id]?.isAfter(DateTime.now()) ?? false)) {
      return;
    }
    _pendingRoadNotifications.add(id);
    final session = _roadNotificationSession;
    try {
      final shown = await WaybiNotificationService.instance.showRoadAlert(
        id: id,
        title: title,
        body: body,
      );
      if (session != _roadNotificationSession) return;
      if (shown) {
        _notifiedRoadEventIds.add(id);
      } else {
        _roadNotificationRetryAfter[id] = DateTime.now().add(
          const Duration(seconds: 20),
        );
      }
    } catch (_) {
      if (session == _roadNotificationSession) {
        _roadNotificationRetryAfter[id] = DateTime.now().add(
          const Duration(seconds: 20),
        );
      }
    } finally {
      if (session == _roadNotificationSession) {
        _pendingRoadNotifications.remove(id);
      }
    }
  }

  Future<void> _prepareRoadNotifications() async {
    if (!_notifySafetyCameras &&
        !_notifyRoadIncidents &&
        !_notifyCommunityReports) {
      return;
    }
    try {
      await WaybiNotificationService.instance.requestPermission();
    } catch (_) {
      // OS notifications are optional; navigation and spoken guidance continue.
    }
  }

  Future<void> _loadRoutePreview(
    PointOfInterest poi, {
    WaybiTravelMode preferredMode = WaybiTravelMode.drive,
  }) async {
    FocusManager.instance.primaryFocus?.unfocus();
    _externalPreview = null;
    final origin = _manualOrigin?.location ?? _locationForRoute;
    if (origin == null) {
      final selected = _selectedPlace;
      if (selected != null) {
        _externalPreview = (
          selected: selected,
          mode: preferredMode,
          request: _externalRequest,
        );
      }
      setState(
        () => _message = _text(
          'Getting your location. The route will appear automatically.',
          '正在获取位置，定位成功后会自动显示路线。',
        ),
      );
      unawaited(_recoverRouteLocation());
      return;
    }
    if (isCrossTasmanSurfaceRoute([
      GeoPoint(origin.latitude, origin.longitude),
      for (final stop in _routeStops)
        GeoPoint(stop.location.latitude, stop.location.longitude),
      GeoPoint(poi.latLng.latitude, poi.latLng.longitude),
    ])) {
      _trip.dispatch(PreviewSettled(hasPlan: _routePlan != null));
      setState(
        () =>
            _message = const NoSurfaceRouteException().localized(_appLanguage),
      );
      return;
    }
    final request = ++_routeRequest;
    // A reload (new stop, language, mode) keeps the loaded plan and mode on
    // screen until the replacement arrives; a failure leaves them usable.
    _trip.dispatch(const PreviewRequested());
    setState(() {
      _routeRecoveryMessage = null;
      _following = false;
      _message = null;
    });
    if (preferredMode == WaybiTravelMode.drive &&
        _selectedParking == null &&
        _selectedPlace != null) {
      unawaited(_loadParking(_selectedPlace!.place));
    }
    unawaited(_driveEngine.loadCameras());
    if (preferredMode == WaybiTravelMode.drive) {
      unawaited(_driveEngine.loadTrafficFlow());
    }
    try {
      final plan = await _independentRoutes.route(
        origin: GeoPoint(origin.latitude, origin.longitude),
        destination: GeoPoint(poi.latLng.latitude, poi.latLng.longitude),
        stops: _routeStops
            .map(
              (stop) =>
                  GeoPoint(stop.location.latitude, stop.location.longitude),
            )
            .toList(growable: false),
        language: _appLanguage,
        mode: preferredMode,
        headingDegrees: preferredMode == WaybiTravelMode.drive
            ? _routingHeading
            : null,
      );

      final cameraSummaries = _summarizeRouteCameras(plan);
      final preferenceSummaries = _summarizeRoutePreferences(
        plan,
        cameraSummaries,
      );
      final preferredRoutes = plan
          .forMode(preferredMode)
          .take(3)
          .toList(growable: false);
      final routesWithoutKnownClosures = preferredRoutes
          .where((route) => _closuresOnRoute(route).isEmpty)
          .toList(growable: false);
      final preferredRoute = preferredMode == WaybiTravelMode.drive
          ? recommendedRoute(
              routesWithoutKnownClosures.isEmpty
                  ? preferredRoutes
                  : routesWithoutKnownClosures,
              preferenceSummaries,
            )
          : preferredRoutes.firstOrNull;
      if (!mounted || request != _routeRequest) return;
      setState(() {
        _routePlan = plan;
        _routeCameraSummaries = cameraSummaries;
        _routePreferenceSummaries = preferenceSummaries;
        _routeFilter = RouteFilter.recommended;
        _selectedMode = preferredMode;
        _selectedRouteId = preferredRoute?.id;
      });
      _driveEngine.setRoute(
        preferredMode == WaybiTravelMode.drive ? preferredRoute : null,
      );
      await _renderRoutePreview();
    } catch (error) {
      if (mounted && request == _routeRequest) {
        setState(() => _message = routeFailureMessage(error, _appLanguage));
      }
    } finally {
      if (mounted && request == _routeRequest) {
        _trip.dispatch(PreviewSettled(hasPlan: _routePlan != null));
      }
    }
  }

  Map<String, RouteCameraSummary> _summarizeRouteCameras(RoutePlan plan) {
    final matcher = const RouteCameraMatcher();
    final summaries = <String, RouteCameraSummary>{};
    for (final route in plan.options) {
      if (route.mode != WaybiTravelMode.drive) {
        summaries[route.id] = const RouteCameraSummary();
        continue;
      }
      final matches = matcher.match(route, _driveEngine.cameras);
      final types = <String>{};
      for (final match in matches) {
        types.add(CameraKindLabel.fromCamera(match.camera).label);
      }
      summaries[route.id] = RouteCameraSummary(
        count: matches.length,
        types: types.toList(growable: false),
      );
    }
    return summaries;
  }

  Map<String, RoutePreferenceSummary> _summarizeRoutePreferences(
    RoutePlan plan,
    Map<String, RouteCameraSummary> cameraSummaries,
  ) {
    final summaries = <String, RoutePreferenceSummary>{};
    for (final route in plan.options) {
      if (route.mode != WaybiTravelMode.drive) continue;
      final congestionScore =
          (route.trafficDelaySeconds ?? 0) +
          route.traffic.trafficJam * 300 +
          route.traffic.slow * 90;
      summaries[route.id] = RoutePreferenceSummary(
        cameraCount: cameraSummaries[route.id]?.count ?? 0,
        congestionScore: congestionScore,
      );
    }
    return summaries;
  }

  bool get _routeCameraDataReady =>
      !_driveEngine.loadingCameras && _driveEngine.cameras.isNotEmpty;

  List<RouteOption> get _filteredPreviewRoutes {
    final routes =
        _routePlan?.forMode(_selectedMode).toList() ?? <RouteOption>[];
    if (_selectedMode != WaybiTravelMode.drive) return routes;
    return filterRoutes(
      routes,
      _routeFilter,
      _routeCameraDataReady ? _routePreferenceSummaries : const {},
      blockedIds: {
        for (final route in routes)
          if (_closuresOnRoute(route)
              .any((e) => e.observation == RoadEventObservation.official))
            route.id,
      },
    );
  }

  RouteOption? get _selectedRoute {
    final routes = _filteredPreviewRoutes;
    return routes.where((route) => route.id == _selectedRouteId).firstOrNull ??
        routes.firstOrNull;
  }

  bool _needsRouteRecovery(RouteOption route) =>
      route.blockedForDriving ||
      _closuresOnRoute(route)
          .any((e) => e.observation == RoadEventObservation.official);

  void _selectRouteFilter(RouteFilter filter) {
    setState(() {
      _routeFilter = filter;
      _selectedRouteId = _filteredPreviewRoutes.firstOrNull?.id;
      _routeRecoveryMessage = null;
    });
    _driveEngine.setRoute(_selectedRoute);
    unawaited(_renderRoutePreview());
  }

  Future<void> _recoverBlockedRoute() async {
    final previous = _selectedRoute;
    final poi = _selectedPoi;
    final plan = _routePlan;
    if (_busy || previous == null || poi == null || plan == null) return;
    final existing = _filteredPreviewRoutes
        .where((route) => !_needsRouteRecovery(route))
        .firstOrNull;
    if (existing != null) {
      _selectRoute(existing);
      setState(
        () => _routeRecoveryMessage = _text(
          'A clear alternative is selected. Start when ready.',
          '已切换到可通行的备选路线，可开始导航。',
        ),
      );
      return;
    }
    final origin = _manualOrigin?.location ?? _locationForRoute;
    if (origin == null) {
      setState(
        () => _routeRecoveryMessage = _text(
          'Waiting for your location. Try again when GPS is ready.',
          '正在获取位置，请定位成功后重试绕行。',
        ),
      );
      unawaited(_recoverRouteLocation());
      return;
    }
    final request = ++_routeRequest;
    _trip.dispatch(const DetourStarted());
    setState(() {
      _routeRecoveryMessage = _text(
        'Finding a route around closed roads…',
        '正在避开封闭路段规划路线…',
      );
    });
    try {
      final result = await _independentRoutes.route(
        origin: GeoPoint(origin.latitude, origin.longitude),
        destination: GeoPoint(poi.latLng.latitude, poi.latLng.longitude),
        stops: _routeStops
            .map((s) => GeoPoint(s.location.latitude, s.location.longitude))
            .toList(),
        language: _appLanguage,
        mode: WaybiTravelMode.drive,
        headingDegrees: _routingHeading,
        avoid: road_routes.closureExclusions(
          previous,
          _closuresOnRoute(previous),
        ),
      );
      if (!mounted || request != _routeRequest) return;
      final clear = result.options
          .where((route) => !_needsRouteRecovery(route))
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
      final cameras = _summarizeRouteCameras(updated);
      setState(() {
        _routePlan = updated;
        _routeCameraSummaries = cameras;
        _routePreferenceSummaries = _summarizeRoutePreferences(
          updated,
          cameras,
        );
        _selectedRouteId = _filteredPreviewRoutes.firstOrNull?.id;
        _routeRecoveryMessage = _selectedRouteId == null
            ? _text(
                'A detour is available. Change your filter to view it.',
                '已找到绕行路线，请切换筛选条件查看。',
              )
            : _text(
                'Detour ready. Review the route and start navigation.',
                '已规划绕行路线，确认后可开始导航。',
              );
      });
      _driveEngine.setRoute(_selectedRoute);
      await _renderRoutePreview();
    } catch (_) {
      if (mounted && request == _routeRequest) {
        setState(
          () => _routeRecoveryMessage = _text(
            'No verified detour is available right now. Retry or add a stop to try a different road.',
            '暂未找到可通行的绕行路线，请重试或添加途经点换一条路。',
          ),
        );
      }
    } finally {
      if (mounted && request == _routeRequest) {
        _trip.dispatch(PreviewSettled(hasPlan: _routePlan != null));
      }
    }
  }

  List<MapRoutePath> get _visibleIndependentRoutePaths {
    final navigationRoute = _independentNavigation.route;
    if (navigationRoute != null) {
      return _independentNavigation.displayPaths;
    }
    if (_driveEngine.active) return _driveEngine.trailPaths;
    final transit = _activeTransitRoute;
    if (_transitTripRunning && transit != null) {
      return _transitTripPaths ??= List.unmodifiable([
        MapRoutePath(id: transit.id, points: transit.points, active: true),
      ]);
    }
    final plan = _routePlan;
    if (plan == null) return const [];
    return _filteredPreviewRoutes
        .map(
          (route) => MapRoutePath(
            id: route.id,
            points: route.points,
            active: route.id == _selectedRouteId,
          ),
        )
        .toList(growable: false);
  }

  List<MapRoutePath>? _transitTripPaths;

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
          keepScreenAwake: _keepScreenAwake,
          onKeepScreenAwakeChanged: (value) =>
              unawaited(_setKeepScreenAwake(value)),
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
      setState(
        () => _message = _text(
          'You can navigate here. To save it, first confirm the place on the map.',
          '可直接导航到此地点。收藏时，请先在地图上确认地点。',
        ),
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
        setState(
          () => _message = _text(
            'Could not update your saved places. ${friendlyErrorMessage(error, _appLanguage)}',
            '无法更新收藏。${friendlyErrorMessage(error, _appLanguage)}',
          ),
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
        setState(
          () => _message = _text(
            'Could not save your review. ${friendlyErrorMessage(error, _appLanguage)}',
            '无法保存评价。${friendlyErrorMessage(error, _appLanguage)}',
          ),
        );
      }
    }
  }

  Future<void> _renderRoutePreview() async {
    _following = false;
    {
      final renderer = _takeCamera();
      final route = _selectedRoute;
      if (renderer is RouteMapRenderer && route != null) {
        await renderer.fitRoute(
          route.points,
          bottomInset: (MediaQuery.sizeOf(context).height * .44).clamp(
            330,
            420,
          ),
        );
      }
      return;
    }
  }

  Future<List<RouteOption>> _loadIndependentTransitRoutes() async {
    final poi = _selectedPoi;
    final origin = _manualOrigin?.location ?? _gpsLocation;
    if (poi == null || origin == null || _routePlan == null) return const [];

    // Closing the preview or picking another place invalidates this request:
    // a late answer must not revive a plan with no sheet (a ghost route).
    final request = _routeRequest;
    bool current() => mounted && request == _routeRequest;
    final calculating = _text('Calculating public transport…', '正在计算公交路线…');
    String noTransit() => _text(
      'No public transport routes were found for this trip.',
      '这段行程暂时没有可用的公共交通路线。',
    );
    _trip.dispatch(const TransitLoadStarted());
    setState(() => _message = calculating);
    try {
      final transitPlan = await _independentTransitRoutes.route(
        origin: GeoPoint(origin.latitude, origin.longitude),
        destination: GeoPoint(poi.latLng.latitude, poi.latLng.longitude),
        language: _appLanguage,
      );
      final transit = transitPlan
          .forMode(WaybiTravelMode.transit)
          .take(3)
          .toList(growable: false);
      final latest = _routePlan;
      if (!current() || latest == null) return const [];
      if (transit.isEmpty) {
        setState(() => _message = noTransit());
        return transit;
      }
      setState(() {
        _routePlan = RoutePlan(
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
        _message = null;
      });
      return transit;
    } catch (error) {
      if (current()) {
        setState(() {
          _message = _isNoTransitRoute(error)
              ? noTransit()
              : _text(
                  'Could not calculate public transport. ${friendlyErrorMessage(error, _appLanguage)}',
                  '公交路线计算失败。${friendlyErrorMessage(error, _appLanguage)}',
                );
        });
      }
      return const [];
    } finally {
      if (current()) {
        _trip.dispatch(PreviewSettled(hasPlan: _routePlan != null));
      } else if (mounted && _message == calculating) {
        setState(() => _message = null);
      }
    }
  }

  /// The transit provider's answer for "the network has no itinerary".
  static bool _isNoTransitRoute(Object error) =>
      error is StateError &&
      error.message.startsWith('No public-transport route');

  int _modeRequest = 0;

  Future<void> _selectMode(WaybiTravelMode mode) async {
    final plan = _routePlan;
    if (plan == null) return;
    // The last tapped mode wins: a slow transit answer must not flip a later
    // Drive choice back to Transit.
    final selection = ++_modeRequest;
    final request = _routeRequest;
    var routes = plan.forMode(mode).take(3).toList(growable: false);
    if ((routes.isEmpty && mode == WaybiTravelMode.transit)) {
      routes = await _loadIndependentTransitRoutes();
      if (!mounted || selection != _modeRequest || request != _routeRequest) {
        return;
      }
    }
    if (routes.isEmpty) {
      final poi = _selectedPoi;
      if (poi != null && mode != WaybiTravelMode.transit) {
        await _loadRoutePreview(poi, preferredMode: mode);
      }
      return;
    }

    final selected = mode == WaybiTravelMode.drive
        ? recommendedRoute(routes, _routePreferenceSummaries) ?? routes.first
        : routes.first;
    setState(() {
      _selectedMode = mode;
      _selectedRouteId = selected.id;
    });
    _driveEngine.setRoute(mode == WaybiTravelMode.drive ? selected : null);
    await _renderRoutePreview();
  }

  void _selectRoute(RouteOption route) {
    setState(() => _selectedRouteId = route.id);
    _driveEngine.setRoute(route.mode == WaybiTravelMode.drive ? route : null);
    unawaited(_renderRoutePreview());
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
    setState(() => _routeStops.add(stop));
    await _loadRoutePreview(_selectedPoi!, preferredMode: _selectedMode);
  }

  Future<void> _saveCurrentRoute() async {
    final poi = _selectedPoi;
    final selected = _selectedRoute;
    if (poi == null || selected == null) return;
    GeoPoint savedPoint(GeoPoint point) {
      if (!_googleSessionCoordinates.contains((
            point.latitude,
            point.longitude,
          )) ||
          selected.points.isEmpty) {
        return point;
      }
      // Persist Valhalla's independent road geometry rather than Google's input.
      return selected.points.reduce(
        (a, b) =>
            distanceMeters(
                  a.latitude,
                  a.longitude,
                  point.latitude,
                  point.longitude,
                ) <
                distanceMeters(
                  b.latitude,
                  b.longitude,
                  point.latitude,
                  point.longitude,
                )
            ? a
            : b,
      );
    }

    final destinationPoint = savedPoint(
      GeoPoint(poi.latLng.latitude, poi.latLng.longitude),
    );
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('waybi.saved.routes') ?? <String>[];
    final record = jsonEncode({
      'savedAt': DateTime.now().toIso8601String(),
      'destination': {
        'name': poi.name,
        'latitude': destinationPoint.latitude,
        'longitude': destinationPoint.longitude,
      },
      'mode': selected.mode.apiValue,
      'provider': selected.provider,
      'durationSeconds': selected.durationSeconds,
      'distanceMeters': selected.distanceMeters,
      'stops': _routeStops
          .map(
            (stop) => {
              'label': stop.label,
              'latitude': savedPoint(
                GeoPoint(stop.location.latitude, stop.location.longitude),
              ).latitude,
              'longitude': savedPoint(
                GeoPoint(stop.location.latitude, stop.location.longitude),
              ).longitude,
            },
          )
          .toList(),
    });
    saved.removeWhere((item) {
      try {
        final existing = jsonDecode(item) as Map<String, dynamic>;
        final destination = existing['destination'] as Map<String, dynamic>?;
        return destination?['name'] == poi.name;
      } catch (_) {
        return false;
      }
    });
    saved.insert(0, record);
    if (saved.length > 20) saved.removeRange(20, saved.length);
    await prefs.setStringList('waybi.saved.routes', saved);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_text('Route saved on this device', '路线已保存在本机')),
        ),
      );
    }
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
    {
      return;
    }
  }

  void _setLanesEnabled(bool value) {
    setState(() => _lanesEnabled = value);
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setBool('waybi.nav.lanes', value),
      ),
    );
  }

  Future<void> _pauseBrowseLocation() async {
    await _location.pauseForDrive();
    _lastDrivePositionAt = null;
  }

  Future<void> _startTransitTrip(PointOfInterest poi, RouteOption route) async {
    // The trip shows only its itinerary: drop the preview, its alternatives
    // and the drive route so none of them stay on the map during or after it.
    ++_routeRequest;
    ++_parkingRequest;
    _driveEngine.setRoute(null);
    _trip.dispatch(const TransitTripStarted());
    setState(() {
      _activeTransitRoute = route;
      _transitTripPaths = null;
      _destinationTitle = poi.name;
      _selectedPlace = null;
      _routePlan = null;
      _selectedRouteId = null;
      _routeStops.clear();
      _routeRecoveryMessage = null;
      _parkingPlaces = const [];
      _parkingOriginalPlace = null;
      _selectedParking = null;
      _parkingLoading = false;
      _following = true;
    });
    _queueMapRefresh();
    await _driveEngine.speakMessage(
      _text('Transit trip started. Follow the itinerary.', '公共交通行程已开始，请按行程乘车。'),
    );
  }

  Future<void> _stopTransitTrip() async {
    if (!_transitTripRunning) return;
    _trip.dispatch(const TransitTripEnded());
    setState(() {
      _activeTransitRoute = null;
      _transitTripPaths = null;
      _destinationTitle = _text('Destination', '目的地');
      _following = true;
    });
    _queueMapRefresh();
  }

  Future<void> _navigateToSelectedPoi() async {
    final poi = _selectedPoi;
    final selectedRoute = _selectedRoute;
    final destinationPlace = _selectedPlace?.place;
    if (poi == null ||
        selectedRoute == null ||
        destinationPlace == null ||
        _busy) {
      return;
    }

    if (_needsRouteRecovery(selectedRoute)) {
      await _recoverBlockedRoute();
      return;
    }

    // Closing the preview, choosing another place or pressing back while the
    // start awaits location, transit matching or the engine cancels it.
    // Starting also supersedes a preview reload still in flight.
    final request = ++_routeRequest;
    bool cancelled() => !mounted || request != _routeRequest;
    _trip.dispatch(const StartRequested());
    setState(() {
      _message = null;
      // Navigation always starts in a flat heading-up view. Users can switch
      // to perspective or north-up after the trip begins.
      _cameraMode = NavigationCameraMode.headingUpFlat;
    });

    try {
      if (_selectedMode == WaybiTravelMode.transit) {
        await _startTransitTrip(poi, selectedRoute);
        return;
      }

      final laneMatches = await _driveEngine.transitMatchesForRoute(
        selectedRoute,
      );
      if (cancelled()) return;
      final restricted = transitRoadBlocks(
        selectedRoute,
        laneMatches,
        DateTime.now(),
      );
      if (restricted.isNotEmpty) {
        setState(
          () => _message = _text(
            'Bus-only access on ${restricted.first.lane.roadName}. Choose another route.',
            '${restricted.first.lane.roadName} 当前禁止普通汽车通行，请选择其他路线。',
          ),
        );
        return;
      }

      await _prepareRoadNotifications();
      if (cancelled()) return;
      if (!await _location.ensurePermission() || cancelled()) return;
      await _pauseBrowseLocation();
      if (cancelled()) return;
      _independentCamera.reset();
      await _independentNavigation.start(
        selectedRoute,
        initialPosition: _lastReliableBrowsePosition,
      );
      if (cancelled()) {
        // The engine installed the route after the user backed out.
        await _independentNavigation.stop();
        return;
      }
      // Independent guidance has no paid navigation SKU.
      _trip.dispatch(const NavigationStarted());
      setState(() {
        _destinationTitle = poi.name;
        _activeNavigationRoute = selectedRoute;
        _routePlan = null;
        _selectedRouteId = null;
        _selectedPlace = null;
        _routeStops.clear();
        _following = true;
        _routeOverviewActive = false;
        _cameraMode = NavigationCameraMode.headingUpFlat;
        _activeDestinationPlace = destinationPlace;
        _arrivalPrefetching = false;
        _arrivalPrefetched = false;
        _arrivalParkingPlaces = const [];
        _arrivalPlaceDetails = null;
        _offlineCorridorReady = false;
      });
      _beginJourney(poi);
      _updateArrivalExperience();
      await _startSystemNavigation();
      unawaited(_cacheNavigationCorridor(force: true));
      _queueMapRefresh();
    } catch (error) {
      if (!mounted) return;
      if (!_guidanceRunning && _independentNavigation.route != null) {
        // A half-started engine must not keep the drive route or GPS feed.
        try {
          await _independentNavigation.stop();
        } catch (_) {}
      }
      if (!mounted || cancelled()) return;
      setState(
        () => _message = _text(
          'Could not start navigation. ${friendlyErrorMessage(error, _appLanguage)}',
          '无法开始导航。${friendlyErrorMessage(error, _appLanguage)}',
        ),
      );
    } finally {
      // A start that did not reach guidance (failed, bus-only road, no
      // permission) returns to its preview; a cancelled one already left it.
      _trip.dispatch(const StartAborted());
      if (mounted && !_driveEngine.active) unawaited(_startTracking());
    }
  }

  Future<void> _startSystemNavigation() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await Permission.notification.request();
    }
    await _systemNavigation.start(_systemNavigationState());
  }

  Map<String, Object?> _systemNavigationState() {
    final independent = _independentNavigation.active;
    final step = independent ? _independentNavigation.nextStep : null;
    final native = _driveEngine.navInfo;
    final instruction = independent
        ? routeStepInstruction(step, _appLanguage)
        : navigationInstruction(native?.currentStep, _appLanguage);
    final type = independent
        ? '${step?.maneuverType} ${step?.maneuverModifier}'
        : native?.currentStep?.maneuver.name.toLowerCase() ?? '';
    final offRoute = independent
        ? _independentNavigation.offRoute || _independentNavigation.rerouting
        : native?.navState == NavState.rerouting;
    final distance = independent
        ? _independentNavigation.distanceToStepMeters
        : native?.distanceToCurrentStepMeters;
    final remaining = _navigationRemainingMeters;
    final gpsReliable = !independent || _driveEngine.hasReliableLocation;
    final seconds = independent
        ? _independentNavigation.remainingSeconds
        : native?.timeToFinalDestinationSeconds ??
              _activeNavigationRoute?.durationSeconds ??
              0;
    return {
      'destination': _destinationTitle,
      'language': _appLanguage,
      'provider': independent ? 'independent' : 'google',
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
          : navigationMetres(distance, _appLanguage),
      'remaining': remaining == null
          ? '—'
          : navigationMetres(remaining, _appLanguage),
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

  Future<void> _stopNavigation({
    bool arrived = false,
    bool showSummary = true,
  }) async {
    if (_tripState is! TripNavigating) return;
    _trip.dispatch(const EndRequested());
    final parkingTarget = _selectedParking;
    final parkingFix = _gpsLocation;
    final reachedParking =
        parkingTarget != null &&
        (arrived ||
            (_driveEngine.hasReliableLocation &&
                parkingFix != null &&
                distanceMeters(
                      parkingFix.latitude,
                      parkingFix.longitude,
                      parkingTarget.location.latitude,
                      parkingTarget.location.longitude,
                    ) <=
                    75));
    final route = _activeNavigationRoute;
    final summary = _journey?.finish(arrived: arrived);
    final reward = summary?.arrived == true
        ? _navigationRewards
              .complete(summary!, country: _journeyCountry)
              .catchError((Object _) => null)
        : null;
    _journeyCountry = null;
    _journey = null;
    // Ending always ends: whatever fails below, the page leaves guidance and
    // returns to browsing instead of a "zombie" trip that cannot be stopped.
    try {
      try {
        await _systemNavigation.stop();
      } catch (_) {
        // The Live Activity / notification expires on its own.
      }
      try {
        if (_independentNavigation.route != null) {
          await _independentNavigation.stop();
        } else {
          await _driveEngine.stop();
        }
      } catch (_) {
        try {
          if (_driveEngine.active) await _driveEngine.stop();
        } catch (_) {
          // The engine is disposed with the page; nothing else can be done.
        }
      }
      // Only count GPS-tracked travel, never the entire planned route.
      if (summary != null &&
          summary.distanceMeters.isFinite &&
          summary.distanceMeters > 0) {
        if (_account.profile != null &&
            route != null &&
            route.points.isNotEmpty) {
          final destination = route.points.last;
          try {
            await _journeys.queueAccountJourney(
              destinationName: _destinationTitle,
              latitude: destination.latitude,
              longitude: destination.longitude,
              mode: _selectedMode.apiValue,
              distanceMeters: summary.distanceMeters.round(),
              durationSeconds: summary.elapsed.inSeconds.clamp(0, 2000000),
            );
          } catch (_) {
            // Navigation still ends if local persistence is unavailable.
          }
        } else {
          try {
            await _journeys.recordGuestJourney(summary);
          } catch (_) {
            // Navigation still ends if local persistence is unavailable.
          }
        }
      }
    } finally {
      final parkingLeg =
          reachedParking &&
          _parkingOriginalPlace != null &&
          _selectedMode == WaybiTravelMode.drive;
      _trip.dispatch(NavigationEnded(parkingLeg: parkingLeg));
      ++_arrivalRequest;
      ++_roadNotificationSession;
      _notifiedRoadEventIds.clear();
      _pendingRoadNotifications.clear();
      _roadNotificationRetryAfter.clear();
      if (mounted) {
        setState(() {
          _activeNavigationRoute = null;
          _activeDestinationPlace = null;
          _lastCorridorCacheAt = null;
          _destinationTitle = _text('Destination', '目的地');
          _cameraMode = NavigationCameraMode.northUpFlat;
          _following = true;
          _routeOverviewActive = false;
          _arrivalPrefetching = false;
          _arrivalPrefetched = false;
          _arrivalParkingPlaces = const [];
          _arrivalPlaceDetails = null;
          _offlineCorridorReady = false;
        });
        // DriveEngine.stop() also stopped the traffic refresh.
        if (_appForeground && _layers.traffic) {
          unawaited(_driveEngine.startTrafficFlowRefresh(force: true));
        }
        if (!_driveEngine.active) unawaited(_startTracking());
      }
    }
    if (!mounted) return;
    final parked = _parkingLegFinished ? _selectedParking : null;
    if (parked != null) {
      unawaited(_rememberParkedCar(parked));
    }
    if (arrived) {
      unawaited(
        _driveEngine.speakMessage(
          _text('You have arrived. Well done!', '已到达目的地，这段旅程辛苦啦！'),
        ),
      );
    }
    if (summary != null && showSummary) {
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
  }

  Future<void> _startDriveMode() async {
    if (_busy || _guidanceRunning || _transitTripRunning) return;
    setState(() => _message = null);
    try {
      await _prepareRoadNotifications();
      if (_gpsLocation == null) {
        await _startTracking();
      }
      if (!mounted) return;
      if (_gpsLocation == null) {
        setState(
          () => _message = _text(
            'Waiting for your current GPS position before opening Drive Mode.',
            '正在等待当前定位，定位成功后即可打开驾驶模式。',
          ),
        );
        return;
      }
      _trip.dispatch(const DriveRequested());
      // A preview or place focus must not retain camera ownership in Drive.
      await _clearRoutePreview();
      _driveCameraFollow.reset();
      _independentCamera.reset();
      await _pauseBrowseLocation();
      await _driveEngine.startLocal(
        initialPosition: _lastReliableBrowsePosition,
      );
      _trip.dispatch(
        _driveEngine.active ? const DriveStarted() : const DriveEnded(),
      );
      if (mounted) {
        setState(() {
          _following = true;
          _cameraMode = NavigationCameraMode.headingUpFlat;
        });
      }
      _queueMapRefresh();
    } catch (error) {
      _trip.dispatch(const DriveEnded());
      if (mounted) {
        setState(
          () => _message = _text(
            'Could not start Drive Mode. ${friendlyErrorMessage(error, _appLanguage)}',
            '无法打开驾驶模式。${friendlyErrorMessage(error, _appLanguage)}',
          ),
        );
      }
    } finally {
      if (mounted) {
        // The browse feed was paused for Drive; a failed start must not
        // leave the map without location.
        if (!_driveEngine.active) unawaited(_startTracking());
      }
    }
  }

  Future<void> _stopDriveMode() async {
    if (_guidanceRunning) await _stopNavigation();
    await _driveEngine.stop();
    _trip.dispatch(const DriveEnded());
    if (mounted) setState(() => _cameraMode = NavigationCameraMode.northUpFlat);
    if ((mounted && _appForeground) && _layers.traffic) {
      unawaited(_driveEngine.startTrafficFlowRefresh(force: true));
    }
    if (mounted) unawaited(_startTracking());
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadIndependentPlaceDetails(PlaceSummary place) async {
    final request = ++_placeDetailsRequest;
    setState(() {
      _placeDetails = null;
      _placeDetailsLoading = true;
      _placeDetailsError = null;
    });
    try {
      final details = await _placeDetailsRepository.fetchIndependent(place);
      if ((!mounted || request != _placeDetailsRequest)) {
        return;
      }
      setState(() {
        _placeDetails = details;
        _placeDetailsLoading = false;
      });
    } catch (error) {
      if (!mounted || request != _placeDetailsRequest) return;
      setState(() {
        _placeDetailsLoading = false;
        _placeDetailsError = friendlyErrorMessage(
          error,
          _appLanguage,
          fallback: _text(
            'Place details are unavailable right now.',
            '暂时无法加载地点详情。',
          ),
        );
      });
    }
  }

  void _retryPlaceDetails() {
    final place = _selectedPlace?.place;
    if (place != null) unawaited(_loadIndependentPlaceDetails(place));
  }

  void _selectPlace(
    PlaceSummary place,
    SelectionSource source, {
    PlaceDetails? seedDetails,
  }) {
    if (_driveEngine.active || _transitTripRunning) return;
    _externalPreview = null;
    if ((!const ProviderPolicy(MapProvider.independent)
        .canDisplay(place.reference))) {
      setState(
        () => _message = _text(
          'This place belongs to another map provider.',
          '这个地点来自其他地图服务，无法在 Waybi 中打开。',
        ),
      );
      return;
    }
    setState(() {
      // A new place supersedes the last place's preview, ETA and start.
      ++_routeRequest;
      ++_placeQuickRouteRequest;
      _trip.dispatch(const PlaceChosen());
      _routeRecoveryMessage = null;
      _selectedPlace = SelectedPlace(place, source, originMap: _mapProvider);
      ++_parkingRequest;
      _parkingPlaces = const [];
      _parkingOriginalPlace = null;
      _selectedParking = null;
      _parkingLoading = false;
      _routePlan = null;
      _selectedRouteId = null;
      _placeQuickRoute = null;
      _placeQuickRouteIssue = null;
      _placeQuickRouteLoading = false;
      _placeQuickRouteLoadingKey = null;
      _message = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusSelectedPlace();
      unawaited(_loadPlaceQuickRoute(place));
    });
    if (seedDetails == null) {
      unawaited(_loadIndependentPlaceDetails(place));
    } else {
      _placeDetailsRequest++;
      _placeDetails = seedDetails;
      _placeDetailsLoading = false;
      _placeDetailsError = null;
    }
    if (((source == SelectionSource.map ||
            source == SelectionSource.longPress)) &&
        place.address.isEmpty) {
      unawaited(_enrichIndependentSelection(place, source));
    }
  }

  Future<void> _enrichIndependentSelection(
    PlaceSummary original,
    SelectionSource source,
  ) async {
    try {
      final resolved = await _independentSearch.reverseNear(
        original.location,
        language: _appLanguage,
        preferredName:
            original.kind == PlaceKind.coordinate &&
                source != SelectionSource.longPress
            ? ''
            : original.name,
      );
      if ((!mounted || resolved == null) ||
          !identical(_selectedPlace?.place, original)) {
        return;
      }
      setState(
        () => _selectedPlace = SelectedPlace(
          PlaceSummary(
            name:
                original.kind == PlaceKind.coordinate &&
                    source != SelectionSource.longPress
                ? resolved.name
                : original.name,
            location: original.location,
            address: resolved.address,
            category: original.category.isEmpty
                ? resolved.category
                : original.category,
            kind:
                original.kind == PlaceKind.coordinate &&
                    source != SelectionSource.longPress
                ? resolved.kind
                : original.kind,
            reference: source == SelectionSource.longPress
                ? null
                : resolved.reference,
          ),
          source,
          originMap: _mapProvider,
        ),
      );
    } catch (_) {
      // A map feature remains selectable if reverse lookup is unavailable.
    }
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
    {}
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

    {}
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
      setState(
        () => _message = _text(
          'Navigation text updated. Change the app language in system Settings for Google map labels, then reopen Waybi.',
          '导航文字已更新。Google 地图标签请在系统设置中选择应用语言，然后重新打开 Waybi。',
        ),
      );
    }
    if (_routePlan != null && _selectedPoi != null) {
      unawaited(_loadRoutePreview(_selectedPoi!, preferredMode: _selectedMode));
    }
  }

  static Future<bool> _applyNativeMapLanguage(String language) async {
    try {
      return await NativeMapLanguage.apply(language);
    } catch (_) {
      return false;
    }
  }

  Future<void> _setKeepScreenAwake(bool value) async {
    setState(() => _keepScreenAwake = value);
    await _driveEngine.setKeepScreenAwake(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('waybi.nav.keep_screen_awake', value);
  }

  void _beginJourney(PointOfInterest poi) {
    _journeyCountry = _navigationRewards.countryAt(
      GeoPoint(poi.latLng.latitude, poi.latLng.longitude),
    );
    unawaited(_navigationFeedback.flush());
    _journey = JourneyTracker(
      target: GeoPoint(poi.latLng.latitude, poi.latLng.longitude),
      destination: poi.name,
    );
  }

  String _text(String english, String chinese) =>
      _appLanguage == 'zh' ? chinese : english;

  void _showNavigationSettings() => _showProfile();

  Future<void> _showDirections() async {
    final route = _activeNavigationRoute;
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
    {}

    if (!mounted) return;
    await showDirectionsSheet(
      context,
      route,
      language: _appLanguage,
      sheetHeight: sheetHeight,
    );
  }

  Future<void> _shareTripSnapshot() async {
    final nav = _driveEngine.navInfo;
    final remaining = _independentNavigation.active
        ? _independentNavigation.remainingDistanceMeters
        : nav?.distanceToFinalDestinationMeters;
    final arrival = _independentNavigation.active
        ? _independentNavigation.remainingSeconds
        : nav?.timeToFinalDestinationSeconds;
    final unknown = _text('unknown', '未知');
    final distance = remaining == null
        ? unknown
        : formatDistance(remaining, _appLanguage);
    final eta = arrival == null
        ? unknown
        : DateTime.now()
              .add(Duration(seconds: arrival))
              .toLocal()
              .toString()
              .substring(0, 16);
    final details = _text(
      'Waybi trip to $_destinationTitle. Remaining: $distance. ETA: $eta. '
          'This is an ETA snapshot, not live location sharing.',
      'Waybi 行程：前往 $_destinationTitle。剩余：$distance。预计到达：$eta。'
          '这是一次到达时间快照，不是实时位置共享。',
    );
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
        setState(
          () => _message = _text(
            'Could not add this stop. Your current route is still active.',
            '无法添加途经点，当前导航路线继续有效。',
          ),
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
      onNotice: (message) => setState(() => _message = message),
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

    {}
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
          onDriveMode: selectResult ? () => unawaited(_startDriveMode()) : null,
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
      _googleSessionCoordinates.add((
        place.location.latitude,
        place.location.longitude,
      ));
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
          setState(
            () => _message = _text(
              'Place selected. To save Home or Work, first confirm it on the map.',
              '地点已选中。保存家或公司时，请先在地图上确认地点。',
            ),
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

    {}
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

    {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_settingsLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final arrivalRemaining = _navigationRemainingMeters;
    final arrivalPhotos = _arrivalPlaceDetails?.photos ?? const <PlacePhoto>[];
    final arrivalPanel =
        _arrivalMode &&
            arrivalRemaining != null &&
            _activeDestinationPlace != null
        ? ArrivalExperiencePanel(
            language: _appLanguage,
            destinationTitle: _destinationTitle,
            destinationAddress: _activeDestinationPlace!.address,
            remainingMeters: arrivalRemaining,
            photoUrl: arrivalPhotos.isEmpty ? null : arrivalPhotos.first.url,
            selectedParkingTitle: _selectedParking?.name,
            parkingPlaces: _arrivalParkingPlaces,
            parkingLoading: _arrivalPrefetching,
            onParkingSelected: (parking) =>
                unawaited(_routeToArrivalParking(parking)),
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
              child: IndependentMapRenderer(
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
                  course: _driveEngine.snappedHeadingDegrees ?? _travelHeading,
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
                onRoadEvent: (event) => unawaited(_showRoadEventDetails(event)),
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
                  if (_selectedPlace != null || _routePlan != null) {
                    unawaited(_clearRoutePreview());
                  }
                },
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
                          _parkedCarPlace != null) ...[
                        Material(
                          color: Theme.of(context).colorScheme.surface,
                          elevation: 5,
                          borderRadius: BorderRadius.circular(14),
                          child: IconButton(
                            tooltip: _parkedCarAgeLabel(),
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
                      CompanionSearchPrompt(
                        marker: _locationMarker,
                        language: _appLanguage,
                        currentLocation: _gpsLocation == null
                            ? _viewport.center
                            : GeoPoint(
                                _gpsLocation!.latitude,
                                _gpsLocation!.longitude,
                              ),
                        loadSuggestions: _loadMapSearchSuggestions,
                        cachedSuggestions: _cachedMapSearchSuggestions,
                        onSuggestionSelected: _selectMapSearchSuggestion,
                        onSearch: (query) =>
                            unawaited(_openSearch(query: query)),
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
            ...const [],
            if (_independentNavigation.active)
              Positioned.fill(
                child: IndependentNavigationOverlay(
                  systemStatus: SystemNavigationStatus(
                    navigation: _systemNavigation,
                    language: _appLanguage,
                  ),
                  onTopInsetChanged: _updateNavigationTopInset,
                  onBottomInsetChanged: _updateNavigationBottomInset,
                  engine: _independentNavigation,
                  drive: _driveEngine,
                  destination: _destinationTitle,
                  language: _appLanguage,
                  onEnd: () => unawaited(_stopNavigation()),
                  onRecenter: _recenter,
                  onOverview: _showRouteOverview,
                  following: _following,
                  overviewMode: _routeOverviewActive,
                  gpsAccuracy: _gpsAccuracy,
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
                      _account.profile?.isPlus == true && _offlineCorridorReady,
                  offlineCachedAt: _lastCorridorCacheAt,
                ),
              ),
            if ((_driveEngine.active) && !_guidanceRunning)
              Positioned.fill(
                child: DriveHud(
                  language: _appLanguage,
                  following: _following,
                  onRecenter: _recenter,
                  engine: _driveEngine,
                  onStop: () => unawaited(_stopDriveMode()),
                ),
              ),
            if (_message != null)
              WaybiStatusBanner(
                key: ValueKey(_message),
                message: _message!,
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
                    _message == _location.issueMessage &&
                        _location.issueAction != null
                    ? () => unawaited(_resolveLocationIssue())
                    : null,
                onDismiss: () {
                  if (mounted) setState(() => _message = null);
                },
              ),
            if (_parkingLegFinished &&
                _parkingOriginalPlace != null &&
                _selectedParking != null &&
                !_guidanceRunning)
              Align(
                alignment: Alignment.bottomCenter,
                child: ParkingContinuationCard(
                  destinationTitle: _parkingOriginalPlace!.name,
                  parkingTitle: _selectedParking!.name,
                  isChinese: _appLanguage == 'zh',
                  carRemembered: _account.profile?.isPlus == true,
                  onContinue: () => unawaited(_continueOnFoot()),
                  onEnd: _dismissParkingLeg,
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
                _routePlan == null)
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  minimum: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: PointerInterceptor(
                    child: _PlaceCard(
                      selectedPlace: _selectedPlace!.place,
                      details: _placeDetails,
                      detailsLoading: _placeDetailsLoading,
                      detailsError: _placeDetailsError,
                      onRetryDetails: _retryPlaceDetails,
                      busy: _routePreviewLoading,
                      quickRoute: _placeQuickRoute,
                      quickRouteLoading: _placeQuickRouteLoading,
                      quickRouteIssue: _placeQuickRouteIssue,
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
                      onNavigate: () =>
                          unawaited(_loadRoutePreview(_selectedPoi!)),
                      isFavorite: _isFavorite(_selectedPoi!),
                      onFavorite: () =>
                          unawaited(_toggleFavorite(_selectedPoi!)),
                      onReview: () => unawaited(_reviewPlace(_selectedPoi!)),
                      language: _appLanguage,
                      onExpandedChanged: (expanded) =>
                          _focusSelectedPlace(expanded: expanded),
                    ),
                  ),
                ),
              ),
            if (_transitTripRunning && _activeTransitRoute != null)
              Positioned.fill(
                child: TransitTripOverlay(
                  language: _appLanguage,
                  destinationTitle: _destinationTitle,
                  route: _activeTransitRoute!,
                  gpsAccuracy: _gpsAccuracy,
                  onEnd: () => unawaited(_stopTransitTrip()),
                  onRecenter: _recenter,
                ),
              ),
            if (_selectedPoi != null &&
                _routePlan != null &&
                !_driveEngine.active &&
                !_guidanceRunning &&
                !_transitTripRunning)
              Align(
                alignment: Alignment.bottomCenter,
                child: RoutePreviewSheet(
                  destinationTitle: _selectedPoi!.name,
                  originTitle:
                      _manualOrigin?.label ?? _text('Current location', '当前位置'),
                  plan: _routePlan!,
                  selectedMode: _selectedMode,
                  selectedRouteId: _selectedRouteId,
                  busy: _busy,
                  stopCount: _routeStops.length,
                  cameraCount: _driveEngine.routeCameraCount,
                  routeCameraSummaries: _routeCameraSummaries,
                  routePreferenceSummaries: _routePreferenceSummaries,
                  filter: _routeFilter,
                  onFilterChanged: _selectRouteFilter,
                  cameraDataReady: _routeCameraDataReady,
                  statusMessage: _routeRecoveryMessage,
                  onRetry: () => unawaited(_recoverBlockedRoute()),
                  routeClosures: {
                    for (final route in _routePlan!.forMode(_selectedMode))
                      route.id: _closuresOnRoute(route),
                  },
                  onRoadEvent: (event) =>
                      unawaited(_showRoadEventDetails(event)),
                  canRequestTransit: true,
                  canRequestModes: true,
                  customOrigin: _manualOrigin != null,
                  parkingPlaces: _parkingPlaces,
                  selectedParkingId: _selectedParking?.id,
                  finalDestinationTitle: _parkingOriginalPlace?.name,
                  parkingLoading: _parkingLoading,
                  isChinese: _appLanguage == 'zh',
                  onParkingSelected: (parking) =>
                      unawaited(_selectParking(parking)),
                  onDirectDestination: _parkingOriginalPlace == null
                      ? null
                      : () => unawaited(_restoreDirectDestination()),
                  onModeChanged: (mode) => unawaited(_selectMode(mode)),
                  onRouteSelected: _selectRoute,
                  onStart: () => unawaited(_navigateToSelectedPoi()),
                  onAddStop: () => unawaited(_addStop()),
                  onSave: () => unawaited(_saveCurrentRoute()),
                  isFavorite: _isFavorite(_selectedPoi!),
                  onFavorite: () => unawaited(_toggleFavorite(_selectedPoi!)),
                  onReview: () => unawaited(_reviewPlace(_selectedPoi!)),
                  onClose: () => unawaited(_clearRoutePreview()),
                ),
              ),
            if (_selectedPoi != null &&
                _routePlan != null &&
                !_driveEngine.active &&
                !_guidanceRunning &&
                !_transitTripRunning)
              Positioned(
                right: 18,
                bottom: MediaQuery.paddingOf(context).bottom + 18,
                child: PointerInterceptor(
                  child: FloatingActionButton.extended(
                    key: const Key('routeStartFloatingButton'),
                    heroTag: 'route-start-floating',
                    elevation: 9,
                    onPressed: _busy
                        ? null
                        : _selectedRoute == null
                        ? () => _selectRouteFilter(RouteFilter.recommended)
                        : () => unawaited(_navigateToSelectedPoi()),
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
                          : _selectedRoute == null
                          ? _text('Show all routes', '查看全部路线')
                          : _selectedMode == WaybiTravelMode.transit
                          ? _text('Start trip', '开始行程')
                          : _selectedRoute != null &&
                                _needsRouteRecovery(_selectedRoute!)
                          ? _text('Find detour', '规划绕行')
                          : _text('Start', '开始导航'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
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
    );
  }
}
