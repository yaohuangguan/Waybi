import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_friends/waybi_friends.dart' show GameController;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data/account_repository.dart';
import 'data/friends_backup_service.dart';
import 'data/brand_migration.dart';
import 'data/app_store_billing.dart';
import 'data/explore_repository.dart';
import 'data/place_details_repository.dart';
import 'data/parking_repository.dart';
import 'data/quick_location_store.dart';
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
import 'domain/traffic_flow.dart';
import 'domain/transit_lane.dart';
import 'domain/transit_review_corridor.dart';
import 'drive/device_heading.dart';
import 'drive/journey_tracker.dart';
import 'drive/navigation_language.dart';
import 'drive/navigation_location_filter.dart';
import 'drive/route_origin_location.dart';
import 'drive/reliable_location_feed.dart';
import 'drive/location_permission_gate.dart';
import 'widgets/status_banner.dart';
import 'drive/independent_navigation_camera.dart';
import 'drive/navigation_motion.dart';
import 'drive/route_progress_tracker.dart';
import 'services/native_map_language.dart';
import 'services/external_navigation_inbox.dart';
import 'widgets/journey_summary_sheet.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

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
import 'widgets/full_screen_search.dart';
import 'widgets/companion_search_prompt.dart';
import 'widgets/place_details_content.dart';
import 'widgets/profile_page.dart';
import 'widgets/map_layer_sheet.dart';
import 'widgets/splash_gate.dart';
import 'widgets/route_preview_sheet.dart';
import 'widgets/road_event_details_sheet.dart';
import 'widgets/transit_trip_overlay.dart';
import 'widgets/trips_page.dart';

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

class _OnboardingFeature extends StatelessWidget {
  const _OnboardingFeature({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: WaybiColors.ice,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: WaybiColors.ocean, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: WaybiColors.deepOcean,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: WaybiColors.lightTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

enum _LocationNoticeAction { retry, appSettings, locationSettings }

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
  late final _friendsBackup = FriendsBackupService(_account);
  late final _plusBilling = AppStoreBillingGateway(_account);
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
  final Map<String, PlaceSummary> _quickLocations = {};
  final Map<String, MapProvider> _quickLocationProviders = {};
  bool _syncingQuickLocations = false;

  double _navigationTopInset = 125;
  double _navigationBottomInset = 215;
  ReliableLocationFeed? _browseLocationFeed;
  final _locationPermission = LocationPermissionGate();
  _LocationNoticeAction? _locationNoticeAction;
  String? _browseLocationMessage;
  Position? _lastReliableBrowsePosition;
  final _independentCamera = IndependentNavigationCamera();
  final _driveCameraFollow = DriveCameraFollow();
  final _browseMotion = NavigationMotionEstimator();
  StreamSubscription<double>? _headingSubscription;
  Timer? _mapRefreshTimer;
  LatLng? _gpsLocation;
  final _routeOriginLocation = RouteOriginLocation();
  LatLng? get _locationForRoute {
    final point = _routeOriginLocation.point;
    return point == null
        ? null
        : LatLng(latitude: point.latitude, longitude: point.longitude);
  }

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
  final Map<String, RouteOption> _quickCommuteRoutes = {};
  final Map<String, RouteOption> _smartCommuteRoutes = {};
  DateTime? _smartCommuteRefreshedAt;
  bool _smartCommuteRefreshing = false;
  DateTime? _quickCommuteRefreshedAt;
  LatLng? _quickCommuteOrigin;
  bool _quickCommuteRefreshing = false;
  int _quickCommuteRequest = 0;
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
  double? _gpsAccuracy;
  final NavigationLocationFilter _browseLocationFilter =
      NavigationLocationFilter();
  double? _deviceHeading;
  double? _travelHeading;

  bool _following = true;
  bool _routeOverviewActive = false;
  bool _voiceEnabled = true;
  bool _keepScreenAwake = true;
  bool _settingsLoaded = false;
  bool _endingNavigation = false;
  bool _appForeground = true;
  final _systemNavigation = SystemNavigation();
  DateTime? _lastDrivePositionAt;
  JourneyTracker? _journey;
  Future<void>? _pendingRouteFlush;
  bool _lanesEnabled = true;
  bool _notifySafetyCameras = false;
  bool _notifyRoadIncidents = false;
  bool _notifyCommunityReports = false;
  bool _notifySavedRouteDisruptions = false;
  String _destinationTitle = 'Destination';
  RoutePlan? _routePlan;
  Map<String, RouteCameraSummary> _routeCameraSummaries = const {};
  Map<String, RoutePreferenceSummary> _routePreferenceSummaries = const {};
  WaybiTravelMode _selectedMode = WaybiTravelMode.drive;
  String? _selectedRouteId;
  bool _routePreviewLoading = false;
  RouteFilter _routeFilter = RouteFilter.recommended;
  String? _routeRecoveryMessage;
  bool _recoveringRoute = false;
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
  bool _transitTripRunning = false;
  RouteOption? _activeTransitRoute;
  RouteOption? _activeNavigationRoute;
  final List<DestinationSuggestion> _routeStops = <DestinationSuggestion>[];
  List<ParkingPlace> _parkingPlaces = const [];
  ParkingPlace? _selectedParking;
  PlaceSummary? _parkingOriginalPlace;
  bool _parkingLoading = false;
  bool _parkingLegFinished = false;
  PlaceSummary? _parkedCarPlace;
  DateTime? _parkedCarAt;
  int _parkingRequest = 0;
  PlaceSummary? _activeDestinationPlace;
  PlaceDetails? _arrivalPlaceDetails;
  List<ParkingPlace> _arrivalParkingPlaces = const [];
  bool _arrivalMode = false;
  bool _arrivalPrefetching = false;
  bool _arrivalPrefetched = false;
  int _arrivalRequest = 0;
  DateTime? _lastCorridorCacheAt;
  bool _offlineCorridorReady = false;

  SelectedPlace? _selectedPlace;
  JourneyPhase _journeyPhase = JourneyPhase.idle;
  PointOfInterest? get _selectedPoi {
    final place = _selectedPlace?.place;
    if (place == null) return null;
    return PointOfInterest(
      placeID: place.reference?.provider == 'google' ? place.reference!.id : '',
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
  bool _guidanceRunning = false;
  bool _busy = false;
  bool _checkingRouteWatchAlerts = false;
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
      ),
    );
    _independentNavigation.addListener(_onIndependentNavigationChanged);
    unawaited(WaybiNotificationService.instance.initialize());
    _account.addListener(_onAccountChanged);
    _driveEngine.addListener(_onEngineChanged);
    _plusBilling.initialize();
    unawaited(_account.restore().then((_) => _friendsBackup.start()));
    unawaited(_driveEngine.loadCameras());
    unawaited(_driveEngine.loadTransitLanes());
    unawaited(
      _restoreMapSettings().then((_) async {
        if ((_layers.traffic)) {
          await _driveEngine.startTrafficFlowRefresh();
        }
        await _maybeShowCoreOnboarding();
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
    if (pending.request != _externalRequest ||
        !identical(pending.selected, _selectedPlace) ||
        _driveEngine.active ||
        _transitTripRunning) {
      _externalPreview = null;
      return;
    }
    if (_locationForRoute == null || _selectedPoi == null || _busy) return;
    _externalPreview = null;
    unawaited(_loadRoutePreview(_selectedPoi!, preferredMode: pending.mode));
  }

  Future<void> _maybeShowCoreOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('waybi.onboarding.core.v1') == true) return;
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 6),
        contentPadding: const EdgeInsets.fromLTRB(24, 10, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
        title: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [WaybiColors.ocean, WaybiColors.teal],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.navigation_rounded, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _text('Welcome to Waybi', '欢迎使用 Waybi'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _OnboardingFeature(
              icon: Icons.route_rounded,
              title: _text('Navigation first', '专注导航'),
              body: _text(
                'Clear route guidance, traffic-aware routing and a focused Drive Mode.',
                '清晰路线指引、实时交通路线，以及专注驾驶的 Drive Mode。',
              ),
            ),
            _OnboardingFeature(
              icon: Icons.shield_outlined,
              title: _text('Road Intelligence', '道路情报'),
              body: _text(
                'Worldwide road reports and route guidance, with official safety cameras in New Zealand.',
                '全球道路上报与路线提示，新西兰另有官方安全摄像头数据。',
              ),
            ),
            _OnboardingFeature(
              icon: Icons.add_alert_rounded,
              title: _text('Report the road', '上报道路情况'),
              body: _text(
                'Share crashes, hazards, roadworks, flooding and congestion with other Waybi drivers.',
                '向其他 Waybi 用户分享事故、危险、施工、积水与拥堵。',
              ),
            ),
            _OnboardingFeature(
              icon: Icons.explore_rounded,
              title: _text('Made for New Zealand', '为新西兰道路设计'),
              body: _text(
                'Waybi location marker, NZ road data and a calm lime driving interface.',
                'Waybi 定位标记、新西兰道路数据，以及 Waybi lime 驾驶界面。',
              ),
            ),
          ],
        ),
        actions: [
          FilledButton.icon(
            onPressed: () async {
              await prefs.setBool('waybi.onboarding.core.v1', true);
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(_text('Start exploring', '开始探索')),
          ),
        ],
      ),
    );
  }

  void _onAccountChanged() {
    if (mounted) setState(() {});
    if (_settingsLoaded && _account.signedIn && _account.profile != null) {
      unawaited(_syncQuickLocationsWithAccount());
    } else if (_settingsLoaded && !_account.signedIn) {
      unawaited(_restoreGuestQuickLocations());
    }
    if (_account.profile?.isPlus == true && _account.signedIn) {
      unawaited(_deliverRouteWatchAlerts());
    }
  }

  Future<void> _restoreGuestQuickLocations() async {
    final shortcuts = await QuickLocationStore().load();
    if (!mounted || _account.signedIn) return;
    setState(() {
      for (final label in const ['Home', 'Work']) {
        _quickLocations.remove(label);
        _quickLocationProviders.remove(label);
      }
      for (final entry in shortcuts.entries) {
        _quickLocations[entry.key] = entry.value.place;
        _quickLocationProviders[entry.key] = entry.value.provider;
      }
    });
    unawaited(_refreshQuickCommutes(force: true));
  }

  Future<void> _syncQuickLocationsWithAccount() async {
    if (_syncingQuickLocations ||
        !_settingsLoaded ||
        !_account.signedIn ||
        _account.profile == null) {
      return;
    }
    _syncingQuickLocations = true;
    try {
      final profile = _account.profile!;
      final store = QuickLocationStore();
      final cachedOwner = await store.ownerUserId();
      final cached = await store.load(ownerUserId: profile.id);
      final remote = <String, ({PlaceSummary place, MapProvider provider})>{};
      for (final item in profile.quickLocations) {
        final label = item['label']?.toString();
        final latitude = item['latitude'];
        final longitude = item['longitude'];
        if ((label != 'Home' && label != 'Work') ||
            latitude is! num ||
            longitude is! num) {
          continue;
        }
        final point = GeoPoint(latitude.toDouble(), longitude.toDouble());
        if (!point.isValid) continue;
        const provider = MapProvider.independent;
        remote[label!] = (
          place: PlaceSummary(
            name: item['name']?.toString() ?? label,
            address: item['address']?.toString() ?? '',
            location: point,
          ),
          provider: provider,
        );
      }

      var changed = false;
      if (cachedOwner != null && cachedOwner != profile.id) {
        for (final label in const ['Home', 'Work']) {
          changed = _quickLocations.remove(label) != null || changed;
          _quickLocationProviders.remove(label);
        }
      }

      for (final label in const ['Home', 'Work']) {
        final remoteValue = remote[label];
        if (remoteValue != null) {
          _quickLocations[label] = remoteValue.place;
          _quickLocationProviders[label] = remoteValue.provider;
          await store.save(
            label,
            remoteValue.place,
            remoteValue.provider,
            ownerUserId: profile.id,
          );
          changed = true;
          continue;
        }

        final localValue = cached[label];
        if (localValue == null) continue;
        _quickLocations[label] = localValue.place;
        _quickLocationProviders[label] = localValue.provider;
        try {
          await _account.saveQuickLocation(
            label: label,
            name: localValue.place.name,
            address: localValue.place.address,
            latitude: localValue.place.location.latitude,
            longitude: localValue.place.location.longitude,
            provider: localValue.provider.name,
          );
          await store.save(
            label,
            localValue.place,
            localValue.provider,
            ownerUserId: profile.id,
          );
          changed = true;
        } catch (_) {
          // Keep local shortcuts usable offline; the next account refresh retries sync.
        }
      }
      if (changed && mounted) {
        setState(() {});
        unawaited(_refreshQuickCommutes(force: true));
      }
    } finally {
      _syncingQuickLocations = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appForeground = state == AppLifecycleState.resumed;
    if (!_appForeground) {
      _mapRefreshTimer?.cancel();
      _mapRefreshTimer = null;
      _driveEngine.stopTrafficFlowRefresh();
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_friendsBackup.sync());
      if (_driveEngine.active) {
        unawaited(_driveEngine.recoverLocalLocation());
      } else {
        unawaited(_resumeBrowseTracking());
      }
      _scheduleExternalNavigation();
      _queueMapRefresh();
      if (_guidanceRunning) {
        unawaited(
          _systemNavigation.update(_systemNavigationState(), force: true),
        );
      }
      unawaited(_deliverRouteWatchAlerts());
      unawaited(_refreshQuickCommutes(force: true));
      if (_driveEngine.active || ((_layers.traffic))) {
        unawaited(_driveEngine.startTrafficFlowRefresh(force: true));
      }
    }
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
    _independentNavigation.checkClosureUpdates();
    final position = _driveEngine.latestPosition;
    if (position != null && position.timestamp != _lastDrivePositionAt) {
      _lastDrivePositionAt = position.timestamp;
      _onPosition(position);
    }
    if (_guidanceRunning) {
      unawaited(_systemNavigation.update(_systemNavigationState()));
    }
    _journey?.cameraPassed(_driveEngine.passedCamera?.id);
    unawaited(_notifyRoadIntelligence());
    final reportIds = _visibleRoadEvents.map((event) => event.id).join(',');
    final signature =
        '${_driveEngine.cameras.length}:${_driveEngine.routeCameras.map((match) => match.camera.id).join(',')}:$reportIds:${_layers.markerSignature}:${_driveEngine.trafficFlowRevision}';
    if (signature != _markerSignature) {
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
      if (_arrivalMode && mounted) setState(() => _arrivalMode = false);
      return;
    }
    if (remaining <= 800 && !_arrivalPrefetching && !_arrivalPrefetched) {
      unawaited(_prefetchArrivalExperience());
    }
    final active = remaining <= 300;
    if (active != _arrivalMode && mounted) {
      setState(() => _arrivalMode = active);
    }
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
    setState(() {
      _parkingOriginalPlace = destination;
      _selectedParking = parking;
      _parkingLegFinished = false;
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

  String _roadEventLabel(RoadEventType type) => switch (type) {
    RoadEventType.incident => _text('Crash / hazard', '事故 / 危险'),
    RoadEventType.roadworks => _text('Roadworks', '道路施工'),
    RoadEventType.roadClosure => _text('Road closed', '道路封闭'),
    RoadEventType.congestion => _text('Heavy traffic', '严重拥堵'),
    RoadEventType.flooding => _text('Flooding', '积水 / 洪水'),
    RoadEventType.slip => _text('Slip / debris', '滑坡 / 道路杂物'),
    _ => _text('Road report', '道路报告'),
  };

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

  Future<void> _showCameraDetails(SafetyCamera camera) async {
    final kind = CameraKindLabel.fromCamera(camera);
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        Widget row(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 19, color: scheme.primary),
              const SizedBox(width: 11),
              SizedBox(
                width: 72,
                child: Text(
                  label,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      Icons.photo_camera_rounded,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          kind.localizedLabel(_appLanguage),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          camera.location,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              row(Icons.map_outlined, _text('Region', '区域'), camera.region),
              row(
                Icons.location_city_rounded,
                _text('Suburb', '地区'),
                camera.suburb,
              ),
              row(
                Icons.pin_drop_outlined,
                _text('Location', '位置'),
                camera.location,
              ),
              row(
                Icons.speed_rounded,
                _text('Camera type', '摄像头类型'),
                camera.type,
              ),
              row(
                Icons.gps_fixed_rounded,
                'GPS',
                '${camera.latitude.toStringAsFixed(6)}, '
                    '${camera.longitude.toStringAsFixed(6)}',
              ),
              const SizedBox(height: 4),
              Text(
                _text(
                  'Published by NZ Transport Agency · fixed safety camera location',
                  'NZ Transport Agency 公开 · 固定安全摄像头位置',
                ),
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showTransitLaneDetails(TransitLane lane) async {
    final active = lane.schedule.activeAt(DateTime.now());
    final status = switch (active) {
      true => _text('Operating now', '当前生效'),
      false => _text('Outside published hours', '当前不在公布时段内'),
      null => _text('Hours not confirmed', '时段尚未确认'),
    };
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              lane.roadName.isEmpty ? lane.label(_appLanguage) : lane.roadName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(lane.label(_appLanguage)),
            const SizedBox(height: 8),
            Text(status, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(lane.schedule.label(_appLanguage)),
            const SizedBox(height: 14),
            Text(
              _text(
                'Auckland Transport published lane geometry. Dashed lines do not mean the entire road is restricted. Check roadside signs before entering.',
                '奥克兰交通局公布的专用车道位置。虚线不代表整条道路禁止通行，驶入前请以现场标志为准。',
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '© Auckland Transport · CC BY 4.0',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showTransitReviewDetails(TransitReviewCorridor corridor) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              corridor.roadName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(corridor.city),
            const SizedBox(height: 12),
            Text(
              _text(
                'Review-only road corridor · Not verified lane limits',
                '待核实道路走廊 · 不是已确认的公交车道边界',
              ),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _appLanguage == 'zh'
                  ? corridor.ruleSummaryZh
                  : corridor.ruleSummary,
            ),
            const SizedBox(height: 12),
            Text(
              _text(
                'This line is an approximate council STREET CENTRELINE, not the physical bus lane. Published rules may cover only part of the road and one direction. It is not used for route blocking or automatic lane alerts. Always follow roadside signs.',
                '此线仅为市议会道路中心线示意，不是实际公交车道的精确边界。官方规则可能只覆盖部分路段或某个方向；Waybi 不会据此封禁路线或自动提醒违规。请以现场路牌为准。',
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 10),
            Text(
              '© ${corridor.authority}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            TextButton.icon(
              onPressed: () => unawaited(
                launchUrl(
                  Uri.parse(corridor.ruleSource),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(_text('Council source', '查看市议会来源')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRoadEventDetails(RoadEvent event) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .8,
      ),
      builder: (_) => RoadEventDetailsSheet(
        event: event,
        title: _roadEventLabel(event.type),
        language: _appLanguage,
      ),
    );
  }

  Future<void> _restoreMapSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('waybi.map.provider', MapProvider.independent.name);
    _locationMarker = LocationMarkerStyle.values.firstWhere(
      (value) => value.name == prefs.getString('waybi.map.location_marker'),
      orElse: () => LocationMarkerStyle.kiwi,
    );
    _quickActions = prefs.getStringList('waybi.quick_actions') ?? _quickActions;
    _restoreGoogleRecent(prefs);
    final shortcuts = await QuickLocationStore().load();
    for (final entry in shortcuts.entries) {
      _quickLocations[entry.key] = entry.value.place;
      _quickLocationProviders[entry.key] = entry.value.provider;
    }
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
            name: item['name']?.toString() ?? 'Parked car',
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
    await NativeMapLanguage.apply(_appLanguage);
    _settingsLoaded = true;
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
    await _driveEngine.setVoiceLanguage(_voiceLanguage);

    {}
    if (mounted) setState(() {});
    if (_account.signedIn && _account.profile != null) {
      unawaited(_syncQuickLocationsWithAccount());
    }
    unawaited(_refreshQuickCommutes(force: true));
    unawaited(_deliverRouteWatchAlerts());
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
            label: item['label']?.toString() ?? 'Recent destination',
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
    unawaited(_browseLocationFeed?.stop());
    _headingSubscription?.cancel();
    _mapRefreshTimer?.cancel();
    _account.removeListener(_onAccountChanged);
    _driveEngine.removeListener(_onEngineChanged);
    unawaited(_systemNavigation.stop());
    _systemNavigation.dispose();
    _independentNavigation.dispose();
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

  Future<bool> _ensureLocationPermission({
    bool requestPermission = true,
  }) async {
    try {
      final access = await _locationPermission.ensure(
        requestPermission: requestPermission,
      );
      if (access.isGranted || access.isLimited) return true;
      if (!mounted) return false;
      final settings = access.isPermanentlyDenied || access.isRestricted;
      _showLocationIssue(
        settings
            ? _text(
                'Location is disabled for Waybi. Enable it in system settings.',
                'Waybi 的定位权限已关闭，请在系统设置中开启。',
              )
            : _text(
                'Allow location access to find your position and navigate.',
                '允许定位权限后，即可获取当前位置并开始导航。',
              ),
        settings
            ? _LocationNoticeAction.appSettings
            : _LocationNoticeAction.retry,
      );
    } catch (_) {
      if (mounted) {
        _showLocationIssue(
          _text(
            'Location is temporarily unavailable. Try again.',
            '定位暂不可用，请重试。',
          ),
          _LocationNoticeAction.retry,
        );
      }
    }
    return false;
  }

  void _showLocationIssue(String message, _LocationNoticeAction action) {
    if (!mounted) return;
    setState(() {
      _browseLocationMessage = message;
      _locationNoticeAction = action;
      _message = message;
    });
  }

  Future<void> _resolveLocationIssue() async {
    try {
      switch (_locationNoticeAction) {
        case _LocationNoticeAction.appSettings:
          await openAppSettings();
        case _LocationNoticeAction.locationSettings:
          await Geolocator.openLocationSettings();
        case _LocationNoticeAction.retry:
        case null:
          if (_driveEngine.active) {
            await _driveEngine.recoverLocalLocation();
          } else {
            await _recoverRouteLocation();
          }
      }
    } catch (_) {
      if (mounted) {
        _showLocationIssue(
          _text(
            'Could not recover location. Check system location settings.',
            '暂时无法恢复定位，请检查系统定位设置。',
          ),
          _LocationNoticeAction.appSettings,
        );
      }
    }
  }

  Future<void> _resumeBrowseTracking() async {
    await _startTracking();
    await _browseLocationFeed?.recover(force: true);
  }

  Future<void> _startTracking({bool requestPermission = false}) async {
    if (_driveEngine.active ||
        _browseLocationFeed?.running == true ||
        !await _ensureLocationPermission(
          requestPermission: requestPermission,
        )) {
      return;
    }
    if (!mounted ||
        _driveEngine.active ||
        _browseLocationFeed?.running == true) {
      return;
    }
    _headingSubscription ??= DeviceHeading.readings.listen(
      (heading) {
        _deviceHeading = heading;
        _queueMapRefresh();
      },
      onError: (_) {
        /* iOS simulator and non-iOS use GPS course. */
      },
    );
    _browseLocationFeed = ReliableLocationFeed(
      settings: defaultTargetPlatform == TargetPlatform.iOS
          ? AppleSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              distanceFilter: 0,
              pauseLocationUpdatesAutomatically: false,
              allowBackgroundLocationUpdates: false,
            )
          : const LocationSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              distanceFilter: 0,
            ),
      onPosition: _onPosition,
      onIssue: _onBrowseLocationIssue,
    )..start();
  }

  void _onBrowseLocationIssue(Object? error) {
    if (!mounted || _driveEngine.active) return;
    if (error == null) {
      if (_message == _browseLocationMessage) setState(() => _message = null);
      _browseLocationMessage = null;
      _locationNoticeAction = null;
      return;
    }
    if (_externalPreview == null &&
        _locationForRoute != null &&
        error is! PermissionDeniedException &&
        error is! LocationServiceDisabledException) {
      return;
    }
    final message = error is LocationServiceDisabledException
        ? _text(
            'Location services are off. Enable them in Settings.',
            '系统定位已关闭，请在系统设置中打开定位。',
          )
        : error is PermissionDeniedException
        ? _text(
            'Location access is disabled. Allow Waybi to use your location in Settings.',
            '定位权限已关闭，请在系统设置中允许 Waybi 使用定位。',
          )
        : _text(
            'Waiting for a reliable location. Retrying automatically…',
            '暂时未获取到可靠定位，正在自动重试…',
          );
    _showLocationIssue(
      message,
      error is LocationServiceDisabledException
          ? _LocationNoticeAction.locationSettings
          : error is PermissionDeniedException
          ? _LocationNoticeAction.appSettings
          : _LocationNoticeAction.retry,
    );
  }

  bool _onPosition(Position position) {
    if (!mounted) return false;
    _gpsAccuracy = position.accuracy.isFinite ? position.accuracy : null;
    final motion = _browseMotion.update(
      NavigationLocationFix(
        point: GeoPoint(position.latitude, position.longitude),
        accuracyMeters: position.accuracy,
        speedMetresPerSecond: position.speed.isFinite && position.speed > 0
            ? position.speed
            : 0,
        timestamp: position.timestamp,
      ),
      heading: position.heading,
    );
    final speedMetresPerSecond = _driveEngine.active
        ? _driveEngine.speedKph / 3.6
        : motion.speedMetresPerSecond;
    final accepted = _browseLocationFilter.accept(
      NavigationLocationFix(
        point: GeoPoint(position.latitude, position.longitude),
        accuracyMeters: position.accuracy,
        speedMetresPerSecond: speedMetresPerSecond,
        timestamp: position.timestamp,
      ),
    );

    _routeOriginLocation.update(
      NavigationLocationFix(
        point: GeoPoint(position.latitude, position.longitude),
        accuracyMeters: position.accuracy,
        speedMetresPerSecond: speedMetresPerSecond,
        timestamp: position.timestamp,
      ),
      confirmed: accepted != null,
    );
    // Keep the last reliable browse fix instead of letting a single indoor
    // GPS jump move route origins, arrival checks and the map by 50–100 m.
    if (accepted == null) {
      _retryExternalPreview();
      setState(() {});
      final place = _selectedPlace?.place;
      if (place != null && !_driveEngine.active && _routePlan == null) {
        unawaited(_loadPlaceQuickRoute(place));
      }
      return _browseLocationFilter.accepted?.timestamp == position.timestamp &&
          DateTime.now().difference(position.timestamp) <=
              const Duration(seconds: 10);
    }

    _lastReliableBrowsePosition = position;
    _gpsLocation = LatLng(
      latitude: accepted.point.latitude,
      longitude: accepted.point.longitude,
    );
    if (speedMetresPerSecond >= .8 && motion.heading != null) {
      _travelHeading = motion.heading;
    } else {
      _travelHeading = null;
    }
    _retryExternalPreview();
    if (_guidanceRunning &&
        !_endingNavigation &&
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
    unawaited(_refreshQuickCommutes());
    final selected = _selectedPlace?.place;
    if (selected != null && _routePlan == null && !_driveEngine.active) {
      unawaited(_loadPlaceQuickRoute(selected));
    }
    return true;
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

  Future<void> _loadPlaceQuickRoute(PlaceSummary place) async {
    if (!mounted || _driveEngine.active || _routePlan != null) return;
    if (!place.location.isValid) return;
    final origin = _manualOrigin?.location ?? _locationForRoute;
    if (origin == null) return;
    final key = _placeRouteKey(place);
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
      if (_placeRouteKey(_selectedPlace?.place ?? place) == key && mounted) {
        setState(() {
          _placeQuickRoute = cached;
          _placeQuickRouteIssue = null;
          _placeQuickRouteLoading = false;
          _placeQuickRouteLoadingKey = null;
        });
      }
      return;
    }
    if (_placeQuickRouteLoading && _placeQuickRouteLoadingKey == key) return;

    final request = ++_placeQuickRouteRequest;
    if (mounted) {
      setState(() {
        _placeQuickRoute = null;
        _placeQuickRouteIssue = null;
        _placeQuickRouteLoading = true;
        _placeQuickRouteLoadingKey = key;
      });
    }
    try {
      final plan = await _driveRoutePlan(
        origin: origin,
        destination: LatLng(
          latitude: place.location.latitude,
          longitude: place.location.longitude,
        ),
        mode: WaybiTravelMode.drive,
      );
      final driving = plan.forMode(WaybiTravelMode.drive).toList()
        ..sort((a, b) => a.durationSeconds.compareTo(b.durationSeconds));
      if (!mounted || request != _placeQuickRouteRequest) return;
      if (driving.isEmpty) {
        setState(() {
          _placeQuickRoute = null;
          _placeQuickRouteIssue = routeFailureMessage(
            StateError('No routes available'),
            _appLanguage,
          );
          _placeQuickRouteLoading = false;
          _placeQuickRouteLoadingKey = null;
        });
        return;
      }
      if (_selectedPlace == null ||
          _placeRouteKey(_selectedPlace!.place) != key ||
          _routePlan != null) {
        return;
      }
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
      setState(() {
        _placeQuickRoute = route;
        _placeQuickRouteIssue = null;
        _placeQuickRouteLoading = false;
        _placeQuickRouteLoadingKey = null;
      });
    } catch (error) {
      if (!mounted || request != _placeQuickRouteRequest) return;
      setState(() {
        _placeQuickRoute = null;
        _placeQuickRouteIssue = routeFailureMessage(error, _appLanguage);
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

  Future<void> _refreshQuickCommutes({bool force = false}) async {
    if (!mounted || !_settingsLoaded || _driveEngine.active) return;
    if (_quickCommuteRefreshing && !force) return;
    final origin = _gpsLocation;
    if (origin == null) return;

    final targets = <String, PlaceSummary>{};
    for (final action in const ['Home', 'Work']) {
      final place = _quickLocations[action];
      if (place != null) targets[action] = place;
    }
    if (targets.isEmpty) {
      if (_quickCommuteRoutes.isNotEmpty && mounted) {
        setState(_quickCommuteRoutes.clear);
      }
      return;
    }

    final now = DateTime.now();
    final lastOrigin = _quickCommuteOrigin;
    final movedMeters = lastOrigin == null
        ? double.infinity
        : distanceMeters(
            origin.latitude,
            origin.longitude,
            lastOrigin.latitude,
            lastOrigin.longitude,
          );
    final stillFresh =
        _quickCommuteRefreshedAt != null &&
        now.difference(_quickCommuteRefreshedAt!) < const Duration(minutes: 10);
    if (!force && stillFresh && movedMeters < 800) return;

    final request = ++_quickCommuteRequest;
    _quickCommuteRefreshing = true;
    final results = <String, RouteOption>{};
    try {
      await Future.wait(
        targets.entries.map((entry) async {
          try {
            final plan = await _driveRoutePlan(
              origin: origin,
              destination: LatLng(
                latitude: entry.value.location.latitude,
                longitude: entry.value.location.longitude,
              ),
              mode: WaybiTravelMode.drive,
            );
            final driving = plan.forMode(WaybiTravelMode.drive).toList()
              ..sort((a, b) => a.durationSeconds.compareTo(b.durationSeconds));
            if (driving.isNotEmpty) results[entry.key] = driving.first;
          } catch (_) {
            // Commute ETA is a progressive enhancement. Keep shortcuts usable
            // even when routing or traffic data is temporarily unavailable.
          }
        }),
      );
      if (!mounted || request != _quickCommuteRequest) return;
      setState(() {
        _quickCommuteRoutes
          ..clear()
          ..addAll(results);
        _quickCommuteRefreshedAt = now;
        _quickCommuteOrigin = origin;
      });
    } finally {
      if (request == _quickCommuteRequest) {
        _quickCommuteRefreshing = false;
      }
    }
  }

  Future<void> _refreshSmartCommutes({bool force = false}) async {
    if (!mounted || _driveEngine.active || _account.profile?.isPlus != true) {
      if (_smartCommuteRoutes.isNotEmpty && mounted) {
        setState(_smartCommuteRoutes.clear);
      }
      return;
    }
    if (_smartCommuteRefreshing) return;
    final home = _quickLocations['Home'];
    final work = _quickLocations['Work'];
    if (home == null || work == null) {
      if (_smartCommuteRoutes.isNotEmpty && mounted) {
        setState(_smartCommuteRoutes.clear);
      }
      return;
    }
    final now = DateTime.now();
    final fresh =
        _smartCommuteRefreshedAt != null &&
        now.difference(_smartCommuteRefreshedAt!) < const Duration(minutes: 10);
    if (!force && fresh) return;

    _smartCommuteRefreshing = true;
    final results = <String, RouteOption>{};
    Future<void> load(
      String label,
      PlaceSummary origin,
      PlaceSummary destination,
    ) async {
      try {
        final plan = await _driveRoutePlan(
          origin: LatLng(
            latitude: origin.location.latitude,
            longitude: origin.location.longitude,
          ),
          destination: LatLng(
            latitude: destination.location.latitude,
            longitude: destination.location.longitude,
          ),
          mode: WaybiTravelMode.drive,
        );
        final driving = plan.forMode(WaybiTravelMode.drive).toList()
          ..sort((a, b) => a.durationSeconds.compareTo(b.durationSeconds));
        if (driving.isNotEmpty) results[label] = driving.first;
      } catch (_) {
        // Smart Commute remains useful with the saved baseline if live routing
        // is temporarily unavailable.
      }
    }

    try {
      await Future.wait([
        load('home-work', home, work),
        load('work-home', work, home),
      ]);
      if (!mounted) return;
      setState(() {
        _smartCommuteRoutes
          ..clear()
          ..addAll(results);
        _smartCommuteRefreshedAt = now;
      });
    } finally {
      _smartCommuteRefreshing = false;
    }
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
        await _browseRenderer!.moveTo(viewport);
      }
      return;
    }
  }

  void _recenter() {
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
    final choices = <(String, String, String, IconData)>[
      ('incident', 'Crash / hazard', '事故 / 危险', Icons.car_crash_rounded),
      ('roadworks', 'Roadworks', '道路施工', Icons.construction_rounded),
      ('roadClosure', 'Road closed', '道路封闭', Icons.block_rounded),
      ('congestion', 'Heavy traffic', '严重拥堵', Icons.traffic_rounded),
      ('flooding', 'Flooding', '积水 / 洪水', Icons.water_rounded),
      ('slip', 'Slip / debris', '滑坡 / 道路杂物', Icons.landslide_rounded),
    ];
    final selected = await showModalBottomSheet<(String, String)>(
      context: context,
      useSafeArea: true,
      showDragHandle: false,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _text('Report road issue', '上报道路情况'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                _text(
                  'Reports are shared with Waybi drivers for about 2 hours.',
                  '上报内容将在约 2 小时内共享给 Waybi 驾驶用户。',
                ),
              ),
            ),
            for (final choice in choices)
              ListTile(
                leading: Icon(choice.$4, color: WaybiColors.ocean),
                title: Text(_text(choice.$2, choice.$3)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () =>
                    Navigator.pop(sheetContext, (choice.$1, choice.$2)),
              ),
          ],
        ),
      ),
    );
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
            'Could not submit road report: $error',
            '道路上报失败：$error',
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
    final renderer = _browseRenderer;
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
    final renderer = _browseRenderer;
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
    _driveEngine.setRoute(null);

    {}
    final renderer = _browseRenderer;
    if (renderer is PlaceFocusMapRenderer) {
      try {
        await renderer.clearContentPadding();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _routePlan = null;
      _selectedRouteId = null;
      _selectedMode = WaybiTravelMode.drive;
      _routePreviewLoading = false;
      if (_recoveringRoute) {
        _busy = false;
        _recoveringRoute = false;
      }
      _routeRecoveryMessage = null;
      _routeFilter = RouteFilter.recommended;
      _selectedPlace = null;
      _journeyPhase = JourneyPhase.idle;
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
      _parkingLegFinished = false;
      _following = true;
    });
    _queueMapRefresh();
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
      _parkingLegFinished = false;
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
      _parkingLegFinished = false;
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
    setState(() {
      _parkingOriginalPlace = null;
      _selectedParking = null;
      _parkingLegFinished = false;
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
      await _startTracking(requestPermission: true);
      await _browseLocationFeed?.recover(force: true);
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
      setState(() {
        _routePreviewLoading = false;
        _message = const NoSurfaceRouteException().localized(_appLanguage);
      });
      return;
    }
    final request = ++_routeRequest;
    setState(() {
      if (_recoveringRoute) {
        _busy = false;
        _recoveringRoute = false;
      }
      _routePreviewLoading = true;
      _routeRecoveryMessage = null;
      _routeFilter = RouteFilter.recommended;
      _routePlan = null;
      _routeCameraSummaries = const {};
      _routePreferenceSummaries = const {};
      _selectedMode = preferredMode;
      _selectedRouteId = null;
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
        _selectedRouteId = preferredRoute?.id;
        _journeyPhase = JourneyPhase.routePreview;
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
        setState(() => _routePreviewLoading = false);
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
    final matcher = const RouteCameraMatcher();
    for (final route in plan.options) {
      if (route.mode != WaybiTravelMode.drive) continue;
      var congestionScore =
          (route.trafficDelaySeconds ?? 0) +
          route.traffic.trafficJam * 300 +
          route.traffic.slow * 90;
      if (route.provider == 'independent' && route.points.length >= 2) {
        for (final segment in _driveEngine.trafficFlowSegments) {
          final midpoint = GeoPoint(
            (segment.start.latitude + segment.end.latitude) / 2,
            (segment.start.longitude + segment.end.longitude) / 2,
          );
          final projection = matcher.project(midpoint, route.points);
          if (projection == null || projection.offsetMeters > 130) continue;
          final flowBearing = bearingDegrees(
            segment.start.latitude,
            segment.start.longitude,
            segment.end.latitude,
            segment.end.longitude,
          );
          if (angleDifference(flowBearing, projection.bearingDegrees) > 75) {
            continue;
          }
          congestionScore += switch (segment.level) {
            TrafficFlowLevel.heavy => 600,
            TrafficFlowLevel.moderate => 180,
            TrafficFlowLevel.unknown => 30,
            TrafficFlowLevel.free => 0,
          };
        }
      }
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
    setState(() {
      _busy = true;
      _recoveringRoute = true;
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
        setState(() {
          _busy = false;
          _recoveringRoute = false;
        });
      }
    }
  }

  List<MapRoutePath> get _visibleIndependentRoutePaths {
    final navigationRoute = _independentNavigation.route;
    if (navigationRoute != null) {
      return _independentNavigation.displayPaths;
    }
    if (_driveEngine.active) return _driveEngine.trailPaths;
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
      if (mounted) setState(() => _message = '$error');
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
    final comment = TextEditingController(
      text: existing?['comment'] as String? ?? '',
    );
    var rating = (existing?['rating'] as num?)?.round() ?? 5;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            'My review · ${poi.name}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: rating,
                decoration: const InputDecoration(labelText: 'Rating'),
                items: [
                  for (var value = 1; value <= 5; value++)
                    DropdownMenuItem(
                      value: value,
                      child: Text('${'★' * value} ($value/5)'),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) update(() => rating = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: comment,
                maxLines: 4,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Private comment',
                  border: OutlineInputBorder(),
                ),
              ),
              const Text(
                'Saved to Waybi only; not published to Google.',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      try {
        await _account.saveReview(
          placeId: _placeKey(poi),
          placeName: poi.name,
          rating: rating,
          comment: comment.text.trim(),
        );
      } catch (error) {
        if (mounted) setState(() => _message = '$error');
      }
    }
    comment.dispose();
  }

  Future<void> _renderRoutePreview() async {
    _following = false;
    {
      final renderer = _browseRenderer;
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
    final current = _routePlan;
    if (poi == null || origin == null || current == null) return const [];

    setState(() {
      _routePreviewLoading = true;
      _message = _text('Calculating public transport…', '正在计算公交路线…');
    });
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
      if (!mounted || transit.isEmpty) return transit;
      setState(() {
        _routePlan = RoutePlan(
          options: [
            ...current.options.where(
              (route) => route.mode != WaybiTravelMode.transit,
            ),
            ...transit,
          ],
          trafficAvailable: current.trafficAvailable,
          provider: current.provider,
          stopsApplied: current.stopsApplied,
        );
        _message = null;
      });
      return transit;
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = _text(
            'Could not calculate public transport: $error',
            '公交路线计算失败：$error',
          );
        });
      }
      return const [];
    } finally {
      if (mounted) setState(() => _routePreviewLoading = false);
    }
  }

  Future<void> _selectMode(WaybiTravelMode mode) async {
    final plan = _routePlan;
    if (plan == null) return;
    var routes = plan.forMode(mode).take(3).toList(growable: false);
    if ((routes.isEmpty && mode == WaybiTravelMode.transit)) {
      routes = await _loadIndependentTransitRoutes();
    }
    if (routes.isEmpty) {
      final poi = _selectedPoi;
      if (poi != null && mode != WaybiTravelMode.transit) {
        await _loadRoutePreview(poi, preferredMode: mode);
      } else {}
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
    if (stop == null || _selectedPoi == null) return;
    setState(() => _routeStops.add(stop));
    await _loadRoutePreview(_selectedPoi!);
  }

  Future<void> _saveCurrentRoute() async {
    final poi = _selectedPoi;
    final selected = _selectedRoute;
    if (poi == null || selected == null) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('waybi.saved.routes') ?? <String>[];
    final record = jsonEncode({
      'savedAt': DateTime.now().toIso8601String(),
      'destination': {
        'name': poi.name,
        'latitude': poi.latLng.latitude,
        'longitude': poi.latLng.longitude,
      },
      'mode': selected.mode.apiValue,
      'provider': selected.provider,
      'durationSeconds': selected.durationSeconds,
      'distanceMeters': selected.distanceMeters,
      'stops': _routeStops
          .map(
            (stop) => {
              'label': stop.label,
              'latitude': stop.location.latitude,
              'longitude': stop.location.longitude,
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
        const SnackBar(content: Text('Route saved on this device')),
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
    final feed = _browseLocationFeed;
    _browseLocationFeed = null;
    await feed?.stop();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        if (await Geolocator.getLocationAccuracy() ==
            LocationAccuracyStatus.reduced) {
          await Geolocator.requestTemporaryFullAccuracy(
            purposeKey: 'WaybiNavigation',
          );
        }
      } catch (_) {
        /* Navigation can still wait for a usable GPS fix. */
      }
    }
    _lastDrivePositionAt = null;
  }

  Future<void> _startTransitTrip(PointOfInterest poi, RouteOption route) async {
    setState(() {
      _transitTripRunning = true;
      _activeTransitRoute = route;
      _destinationTitle = poi.name;
      _selectedPlace = null;
      _journeyPhase = JourneyPhase.idle;
      _following = true;
    });
    await _driveEngine.speakMessage(
      'Transit trip started. Follow the itinerary.',
    );
    _queueMapRefresh();
  }

  Future<void> _stopTransitTrip() async {
    if (!_transitTripRunning) return;
    setState(() {
      _transitTripRunning = false;
      _activeTransitRoute = null;
      _destinationTitle = 'Destination';
    });
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

    setState(() {
      _busy = true;
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
      final restricted = transitRoadBlocks(
        selectedRoute,
        laneMatches,
        DateTime.now(),
      );
      if (!mounted) return;
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

      {
        if (!await _ensureLocationPermission()) return;
        await _pauseBrowseLocation();
        _independentCamera.reset();
        await _independentNavigation.start(
          selectedRoute,
          initialPosition: _lastReliableBrowsePosition,
        );
        // Independent guidance has no paid navigation SKU.
        if (!mounted) return;
        setState(() {
          _guidanceRunning = true;
          _destinationTitle = poi.name;
          _activeNavigationRoute = selectedRoute;
          _routePlan = null;
          _selectedRouteId = null;
          _selectedPlace = null;
          _journeyPhase = JourneyPhase.navigating;
          _routeStops.clear();
          _following = true;
          _routeOverviewActive = false;
          _cameraMode = NavigationCameraMode.headingUpFlat;
          _activeDestinationPlace = destinationPlace;
          _arrivalMode = false;
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
        return;
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Could not start navigation: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
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
    if (!_guidanceRunning || _endingNavigation) return;
    _endingNavigation = true;
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
    await _systemNavigation.stop();
    final route = _activeNavigationRoute;
    final summary = _journey?.finish(arrived: arrived);
    final reward = summary?.arrived == true
        ? _navigationRewards
              .complete(summary!, country: _journeyCountry)
              .catchError((Object _) => null)
        : null;
    _journeyCountry = null;
    _journey = null;
    try {
      if (_independentNavigation.active) {
        await _independentNavigation.stop();
      } else {
        await GoogleMapsNavigator.stopGuidance();
        await GoogleMapsNavigator.clearDestinations();

        {}
        await _driveEngine.stop();
        if ((_appForeground) && _layers.traffic) {
          unawaited(_driveEngine.startTrafficFlowRefresh(force: true));
        }
        {}
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
            await _queueAccountJourney(
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
            await _recordGuestJourney(summary);
          } catch (_) {
            // Navigation still ends if local persistence is unavailable.
          }
        }
      }
      if (!mounted) return;
      ++_arrivalRequest;
      setState(() {
        _guidanceRunning = false;
        ++_roadNotificationSession;
        _notifiedRoadEventIds.clear();
        _pendingRoadNotifications.clear();
        _roadNotificationRetryAfter.clear();

        _activeNavigationRoute = null;
        _activeDestinationPlace = null;
        _lastCorridorCacheAt = null;
        _destinationTitle = _text('Destination', '目的地');
        _journeyPhase = JourneyPhase.idle;
        _cameraMode = NavigationCameraMode.northUpFlat;
        _following = true;
        _routeOverviewActive = false;
        _arrivalMode = false;
        _arrivalPrefetching = false;
        _arrivalPrefetched = false;
        _arrivalParkingPlaces = const [];
        _arrivalPlaceDetails = null;
        _offlineCorridorReady = false;
        _parkingLegFinished =
            reachedParking &&
            _parkingOriginalPlace != null &&
            _selectedMode == WaybiTravelMode.drive;
      });
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
    } finally {
      _endingNavigation = false;
      if (mounted && !_driveEngine.active) unawaited(_startTracking());
    }
  }

  Future<void> _startDriveMode() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _prepareRoadNotifications();
      if (_gpsLocation == null) {
        await _startTracking();
      }
      if (_gpsLocation == null) {
        if (mounted) {
          setState(
            () => _message =
                'Waiting for current GPS position before opening Drive Mode.',
          );
        }
        return;
      }
      {
        // A preview or place focus must not retain camera ownership in Drive.
        await _clearRoutePreview();
        _driveCameraFollow.reset();
        _independentCamera.reset();
        await _pauseBrowseLocation();
        await _driveEngine.startLocal(
          initialPosition: _lastReliableBrowsePosition,
        );
        if (mounted) {
          setState(() {
            _following = true;
            _cameraMode = NavigationCameraMode.headingUpFlat;
          });
        }
        _queueMapRefresh();
        return;
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'Could not start Drive Mode: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _stopDriveMode() async {
    if (_guidanceRunning) await _stopNavigation();
    await _driveEngine.stop();
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
    } catch (_) {
      if (!mounted || request != _placeDetailsRequest) return;
      setState(() => _placeDetailsLoading = false);
    }
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
      setState(() => _message = 'This place belongs to another map provider.');
      return;
    }
    setState(() {
      ++_routeRequest;
      if (_recoveringRoute) {
        _busy = false;
        _recoveringRoute = false;
      }
      _routeRecoveryMessage = null;
      _selectedPlace = SelectedPlace(place, source, originMap: _mapProvider);
      _journeyPhase = JourneyPhase.placeSelected;
      ++_parkingRequest;
      _parkingPlaces = const [];
      _parkingOriginalPlace = null;
      _selectedParking = null;
      _parkingLoading = false;
      _parkingLegFinished = false;
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

  Future<void> _deliverRouteWatchAlerts() async {
    if (_checkingRouteWatchAlerts ||
        !_account.signedIn ||
        _account.profile?.isPlus != true ||
        !_notifySavedRouteDisruptions) {
      return;
    }
    _checkingRouteWatchAlerts = true;
    try {
      final alerts = await _account.routeWatchAlerts();
      if (alerts.isEmpty) return;

      final latestByWatch = <String, Map<String, dynamic>>{};
      for (final alert in alerts) {
        final watchId = alert['routeWatchId']?.toString() ?? '';
        if (watchId.isEmpty || latestByWatch.containsKey(watchId)) continue;
        latestByWatch[watchId] = alert;
      }

      final selected = latestByWatch.values.take(4).toList(growable: false);
      for (final alert in selected.reversed) {
        final id = alert['id']?.toString() ?? '';
        final label = alert['label']?.toString().trim();
        final status = alert['status']?.toString() ?? 'warning';
        final events = (alert['events'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList(growable: false);
        final first = events.isEmpty ? null : events.first;
        final road = first?['roadName']?.toString().trim();
        final impact = first?['impact']?.toString().trim();
        final routeName = label == null || label.isEmpty
            ? _text('Saved commute', '已保存通勤')
            : label;
        final title = status == 'disrupted'
            ? _text('$routeName route disrupted', '$routeName 路线出现严重影响')
            : _text('$routeName route changed', '$routeName 路线出现变化');
        final body = road != null && road.isNotEmpty
            ? _text(
                impact != null && impact.isNotEmpty
                    ? '$road · $impact'
                    : 'Road event detected on $road',
                '检测到 $road 上的道路事件',
              )
            : _text(
                '${events.length} road event${events.length == 1 ? '' : 's'} may affect this route.',
                '${events.length} 个道路事件可能影响这条路线。',
              );
        if (id.isNotEmpty) {
          await WaybiNotificationService.instance.showPlusCommuteAlert(
            id: id,
            title: title,
            body: body,
          );
        }
      }

      final ids = alerts
          .map((alert) => alert['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList(growable: false);
      if (ids.isNotEmpty) {
        await _account.markRouteWatchAlertsRead(ids);
      }
    } catch (_) {
      // Route Watch is additive; map and navigation remain usable offline.
    } finally {
      _checkingRouteWatchAlerts = false;
    }
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
      unawaited(_deliverRouteWatchAlerts());
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
    final applied = await NativeMapLanguage.apply(next);
    if (!applied && mounted) {
      setState(
        () => _message = _text(
          'Navigation text updated. Change the app language in system Settings for Google map labels, then reopen Waybi.',
          '导航文字已更新。Google 地图标签请在系统设置中选择应用语言，然后重新打开 Waybi。',
        ),
      );
    }
    if (_routePlan != null && _selectedPoi != null) {
      unawaited(_loadRoutePreview(_selectedPoi!));
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
      await (_browseRenderer as RouteMapRenderer).fitRoute(
        route.points,
        bottomInset: bottomInset,
      );
    }
    {}

    if (!mounted) return;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final sheetColor = dark ? WaybiColors.darkOcean : scheme.surface;
    final headerColor = dark ? WaybiColors.darkSurface : scheme.surface;
    final badgeColor = dark
        ? WaybiColors.deepTeal.withValues(alpha: .38)
        : scheme.primaryContainer;
    final badgeForeground = dark ? WaybiColors.sky : scheme.onPrimaryContainer;
    final secondaryColor = dark
        ? WaybiColors.darkTextSecondary
        : scheme.onSurfaceVariant;
    final dividerColor = dark ? WaybiColors.darkBorder : theme.dividerColor;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: sheetColor,
      barrierColor: Colors.black.withValues(alpha: dark ? .46 : .28),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      clipBehavior: Clip.antiAlias,
      constraints: BoxConstraints(maxHeight: sheetHeight),
      builder: (sheetContext) {
        return Material(
          color: sheetColor,
          elevation: 0,
          child: Column(
            children: [
              ColoredBox(
                color: headerColor,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 8, 4),
                  child: Column(
                    children: [
                      Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: dividerColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: badgeColor,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Icon(
                              Icons.route_rounded,
                              color: badgeForeground,
                              size: 19,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _text('Directions', '路线指引'),
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  _text(
                                    '${(route.distanceMeters / 1000).toStringAsFixed(1)} km · ${route.steps.length} steps',
                                    '${(route.distanceMeters / 1000).toStringAsFixed(1)} 公里 · ${route.steps.length} 个步骤',
                                  ),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: secondaryColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: _text('Close', '关闭'),
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: dividerColor),
              Expanded(
                child: route.steps.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            _text(
                              'Turn list is not available for this route.',
                              '这条路线暂时没有逐步指引。',
                            ),
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 3, 12, 18),
                        itemCount: route.steps.length,
                        separatorBuilder: (_, _) =>
                            Divider(height: 1, color: dividerColor),
                        itemBuilder: (context, index) {
                          final step = route.steps[index];
                          return ListTile(
                            dense: true,
                            minTileHeight: 48,
                            visualDensity: VisualDensity.compact,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            leading: Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: badgeColor,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: badgeForeground,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            title: Text(
                              routeStepInstruction(step, _appLanguage),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            trailing: Text(
                              step.distanceMeters >= 1000
                                  ? '${(step.distanceMeters / 1000).toStringAsFixed(1)} km'
                                  : '${step.distanceMeters} m',
                              style: TextStyle(
                                color: secondaryColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 10,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );

    {}
  }

  Future<void> _shareTripSnapshot() async {
    final nav = _driveEngine.navInfo;
    final remaining = _independentNavigation.active
        ? _independentNavigation.remainingDistanceMeters
        : nav?.distanceToFinalDestinationMeters;
    final arrival = _independentNavigation.active
        ? _independentNavigation.remainingSeconds
        : nav?.timeToFinalDestinationSeconds;
    final details =
        'Waybi trip to $_destinationTitle. '
        'Remaining: ${remaining == null ? 'unknown' : '${(remaining / 1000).toStringAsFixed(1)} km'}. '
        'ETA: ${arrival == null ? 'unknown' : DateTime.now().add(Duration(seconds: arrival)).toLocal().toString().substring(0, 16)}. '
        'This is an ETA snapshot, not live location sharing.';
    if (!mounted) return;
    try {
      await const MethodChannel('waybi/share')
          .invokeMethod<void>('shareText', {'text': details});
    } on MissingPluginException {
      await Clipboard.setData(ClipboardData(text: details));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ETA snapshot copied to clipboard')),
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
              throw StateError('Place has no location');
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

  List<Map<String, double>> _routeWatchPoints(List<GeoPoint> points) {
    if (points.length < 2) return const [];
    const maxPoints = 220;
    final sampled = points.length <= maxPoints
        ? points
        : List<GeoPoint>.generate(
            maxPoints,
            (index) =>
                points[(index * (points.length - 1) / (maxPoints - 1)).round()],
            growable: false,
          );
    return sampled
        .map(
          (point) => <String, double>{
            'latitude': point.latitude,
            'longitude': point.longitude,
          },
        )
        .toList(growable: false);
  }

  Future<void> _setRouteWatch(
    String label,
    RouteWatchItem? current,
    bool enabled,
  ) async {
    if (!_account.signedIn) throw StateError('Sign in to use Route Watch');
    if (_account.profile?.isPlus != true) {
      throw StateError(
        _text('Smart Commute is a Waybi Plus feature.', '智能通勤是 Waybi Plus 功能。'),
      );
    }
    if (!enabled) {
      if (current != null) await _account.deleteRouteWatch(current.id);
      return;
    }

    final pair = switch (label) {
      'home-work' => ('Home', 'Work'),
      'work-home' => ('Work', 'Home'),
      _ => throw StateError('Unknown Route Watch'),
    };
    final origin = _quickLocations[pair.$1];
    final destination = _quickLocations[pair.$2];
    if (origin == null || destination == null) {
      throw StateError(
        _text(
          'Set both Home and Work before enabling Route Watch.',
          '请先同时设置“家”和“公司”，再开启路线监控。',
        ),
      );
    }

    final plan = await _driveRoutePlan(
      origin: LatLng(
        latitude: origin.location.latitude,
        longitude: origin.location.longitude,
      ),
      destination: LatLng(
        latitude: destination.location.latitude,
        longitude: destination.location.longitude,
      ),
      mode: WaybiTravelMode.drive,
    );
    final driving = plan.forMode(WaybiTravelMode.drive).toList()
      ..sort((a, b) => a.durationSeconds.compareTo(b.durationSeconds));
    if (driving.isEmpty || driving.first.points.length < 2) {
      throw StateError(
        _text(
          'A live driving route is required before Route Watch can start.',
          '需要先获取实时驾车路线，才能开启路线监控。',
        ),
      );
    }
    final route = driving.first;

    await _account.saveRouteWatch(
      label: label,
      originName: origin.name,
      originLatitude: origin.location.latitude,
      originLongitude: origin.location.longitude,
      destinationName: destination.name,
      latitude: destination.location.latitude,
      longitude: destination.location.longitude,
      routeProvider: route.provider,
      routePoints: _routeWatchPoints(route.points),
      durationSeconds: route.durationSeconds,
      distanceMeters: route.distanceMeters,
    );
  }

  String _newJourneyId() =>
      'wb_${DateTime.now().microsecondsSinceEpoch}_${math.Random.secure().nextInt(0x7fffffff).toRadixString(16)}';

  Future<void> _queueAccountJourney({
    required String destinationName,
    required double latitude,
    required double longitude,
    required String mode,
    required int distanceMeters,
    required int durationSeconds,
  }) async {
    final userId = _account.profile?.id;
    if (userId == null || userId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final journeyId = _newJourneyId();
    final key = 'waybi.companion.outbox.v1.$userId.$journeyId';
    // Persist before network I/O: offline trips survive app restarts.
    await prefs.setString(
      key,
      jsonEncode({
        'journeyId': journeyId,
        'destinationName': destinationName,
        'latitude': latitude,
        'longitude': longitude,
        'mode': mode,
        'distanceMeters': distanceMeters,
        'durationSeconds': durationSeconds,
      }),
    );
    unawaited(_syncPendingAccountJourneys().catchError((Object _) {}));
  }

  Future<void> _syncPendingAccountJourneys() {
    final active = _pendingRouteFlush;
    if (active != null) return active;
    final future = _flushPendingAccountJourneys();
    _pendingRouteFlush = future;
    return future.whenComplete(() => _pendingRouteFlush = null);
  }

  Future<void> _flushPendingAccountJourneys() async {
    final userId = _account.profile?.id;
    if (userId == null ||
        userId.isEmpty ||
        !_account.signedIn ||
        _account.profile?.companionTotals == null) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'waybi.companion.outbox.v1.$userId.';
    final keys = prefs.getKeys().where((key) => key.startsWith(prefix)).toList()
      ..sort();
    for (final key in keys) {
      if (_account.profile?.id != userId || !_account.signedIn) break;
      final raw = prefs.getString(key);
      if (raw == null) continue;
      try {
        final route = jsonDecode(raw) as Map<String, dynamic>;
        await _account.recordRoute(
          journeyId: route['journeyId'] as String,
          destinationName: route['destinationName'] as String,
          latitude: (route['latitude'] as num).toDouble(),
          longitude: (route['longitude'] as num).toDouble(),
          mode: route['mode'] as String,
          distanceMeters: (route['distanceMeters'] as num).toInt(),
          durationSeconds: (route['durationSeconds'] as num).toInt(),
        );
        await prefs.remove(key); // Only after the backend confirms success.
      } catch (_) {
        // Keep the exact same idempotent payload for the next reconnect.
        break;
      }
    }
  }

  Future<void> _syncGuestCompanionJourneys() async {
    if (!_account.signedIn || _account.profile?.companionTotals == null) return;
    final prefs = await SharedPreferences.getInstance();
    const prefix = 'waybi.companion.guest.v1.';
    final trips = prefs.getInt('${prefix}trips') ?? 0;
    if (trips <= 0) return;
    var importId = prefs.getString('${prefix}import_id');
    if (importId == null) {
      importId = _newJourneyId();
      await prefs.setString('${prefix}import_id', importId);
    }
    try {
      await _account.importGuestJourneys(
        importId: importId,
        distanceMeters: prefs.getInt('${prefix}distance') ?? 0,
        tripCount: trips,
        durationSeconds: prefs.getInt('${prefix}duration') ?? 0,
      );
      // The import ID ensures a retry after a crash cannot double count.
      await prefs.remove('${prefix}distance');
      await prefs.remove('${prefix}duration');
      await prefs.remove('${prefix}trips');
      await prefs.remove('${prefix}import_id');
    } catch (_) {
      // Preserve local totals and import ID until a later successful sync.
    }
  }

  Future<void> _recordGuestJourney(JourneySummary summary) async {
    final prefs = await SharedPreferences.getInstance();
    const prefix = 'waybi.companion.guest.v1.';
    await prefs.setInt(
      '${prefix}distance',
      (prefs.getInt('${prefix}distance') ?? 0) + summary.distanceMeters.round(),
    );
    await prefs.setInt(
      '${prefix}duration',
      (prefs.getInt('${prefix}duration') ?? 0) +
          summary.elapsed.inSeconds.clamp(0, 86400),
    );
    await prefs.setInt(
      '${prefix}trips',
      (prefs.getInt('${prefix}trips') ?? 0) + 1,
    );
  }

  Future<TripsSnapshot> _loadTripsSnapshot() async {
    if (_account.signedIn) {
      try {
        await _account.refresh(); // Detect newly deployed lifetime API.
      } catch (_) {
        // Cached profile and local guest totals still work offline.
      }
      await _syncGuestCompanionJourneys();
      await _syncPendingAccountJourneys();
    }
    await _refreshQuickCommutes(force: true);

    final quickPlaces = <String, TripDestination>{};
    for (final label in const ['Home', 'Work']) {
      final place = _quickLocations[label];
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

    final routeWatches = <String, RouteWatchItem>{};
    if (_account.signedIn && _account.profile?.isPlus == true) {
      try {
        for (final item in await _account.routeWatches()) {
          final watch = RouteWatchItem.fromJson(item);
          if (watch.id.isNotEmpty && watch.label.isNotEmpty) {
            routeWatches[watch.label] = watch;
          }
        }
      } catch (_) {
        // Trips and navigation stay usable if Smart Commute is temporarily unavailable.
      }
    }
    if (routeWatches.isNotEmpty) {
      await _refreshSmartCommutes();
    } else if (_smartCommuteRoutes.isNotEmpty && mounted) {
      setState(_smartCommuteRoutes.clear);
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
      quickRoutes: Map<String, RouteOption>.from(_quickCommuteRoutes),
      recent: recent,
      history: history,
      routeWatches: routeWatches,
      smartCommuteRoutes: Map<String, RouteOption>.from(_smartCommuteRoutes),
      signedIn: _account.signedIn,
      isPlus: _account.profile?.isPlus == true,
    );
  }

  Future<void> _showTrips() async {
    final result = await Navigator.of(context).push<TripsResult>(
      MaterialPageRoute(
        builder: (_) => TripsPage(
          language: _appLanguage,
          loader: _loadTripsSnapshot,
          onRouteWatchChanged: _setRouteWatch,
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
          await _browseRenderer?.moveTo(
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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * .65,
        child: ListView(
          children: [
            ListTile(
              title: Text(
                _text('Saved places & routes', '收藏地点与路线'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final place in favoritePlaces)
              ListTile(
                leading: const Icon(Icons.bookmark_rounded),
                title: Text(place['name']?.toString() ?? 'Saved place'),
                onTap: () {
                  final latitude = place['latitude'],
                      longitude = place['longitude'];
                  if (latitude is! num || longitude is! num) return;
                  final id = place['placeId']?.toString() ?? '';
                  if ((id.isNotEmpty) &&
                      !id.startsWith('coords:') &&
                      !id.startsWith('osm:')) {
                    Navigator.of(sheetContext).pop();
                    setState(
                      () => _message = 'This saved Google place is available on Google Maps.',
                    );
                    return;
                  }
                  Navigator.of(sheetContext).pop();
                  _selectPlace(
                    PlaceSummary(
                      name: place['name']?.toString() ?? 'Saved place',
                      address: place['address']?.toString() ?? '',
                      location: GeoPoint(
                        latitude.toDouble(),
                        longitude.toDouble(),
                      ),
                      reference: id.startsWith('osm:')
                          ? ProviderReference('osm', id.substring(4))
                          : null,
                    ),
                    SelectionSource.saved,
                  );
                },
              ),
            for (final record in savedRoutes)
              Builder(
                builder: (context) {
                  try {
                    final data = jsonDecode(record) as Map<String, dynamic>;
                    final place = data['destination'] as Map<String, dynamic>;
                    return ListTile(
                      leading: const Icon(Icons.route_rounded),
                      title: Text(place['name']?.toString() ?? 'Saved route'),
                      onTap: () {
                        if ((data['provider'] != 'independent')) {
                          Navigator.of(sheetContext).pop();
                          setState(
                            () => _message =
                                'This saved route belongs to Google Maps.',
                          );
                          return;
                        }
                        Navigator.of(sheetContext).pop();
                        _selectPlace(
                          PlaceSummary(
                            name: place['name']?.toString() ?? 'Saved route',
                            location: GeoPoint(
                              (place['latitude'] as num).toDouble(),
                              (place['longitude'] as num).toDouble(),
                            ),
                          ),
                          SelectionSource.saved,
                        );
                      },
                    );
                  } catch (_) {
                    return const SizedBox.shrink();
                  }
                },
              ),
            if (savedRoutes.isEmpty && favoritePlaces.isEmpty)
              ListTile(
                title: Text(_text('No saved places yet', '还没有收藏地点')),
                subtitle: Text(
                  _text(
                    'Tap the bookmark on a place to keep it here.',
                    '打开地点后点收藏，就会出现在这里。',
                  ),
                ),
              ),
          ],
        ),
      ),
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
    setState(() => _journeyPhase = JourneyPhase.searching);
    final SearchProvider provider = _independentSearch;
    final place = await Navigator.of(context).push<PlaceSummary>(
      PageRouteBuilder<PlaceSummary>(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (_, animation, secondaryAnimation) => FullScreenSearch(
          provider: provider,
          resolve: (candidate) async {
            if (candidate.location != null) {
              return candidate.toPlace(candidate.location!);
            }
            final reference = candidate.reference;
            if (reference == null) {
              throw StateError('Place has no location');
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
    if (place == null) {
      setState(
        () => _journeyPhase = _selectedPlace == null
            ? JourneyPhase.idle
            : JourneyPhase.placeSelected,
      );
      return null;
    }
    if (!selectResult) {
      setState(
        () => _journeyPhase = _selectedPlace == null
            ? JourneyPhase.idle
            : JourneyPhase.placeSelected,
      );
      return place;
    }
    if (saveAs != null) {
      _quickLocations[saveAs] = place;
      _quickLocationProviders[saveAs] = _mapProvider;
      unawaited(_refreshQuickCommutes(force: true));
      await QuickLocationStore().save(
        saveAs,
        place,
        _mapProvider,
        ownerUserId: _account.signedIn ? _account.profile?.id : null,
      );
      if (_account.signedIn) {
        try {
          await _account.saveQuickLocation(
            label: saveAs,
            name: place.name,
            address: place.address,
            latitude: place.location.latitude,
            longitude: place.location.longitude,
            provider: _mapProvider.name,
          );
        } catch (_) {
          // Local shortcut remains available and will retry on the next account sync.
        }
      }
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
    await _browseRenderer?.moveTo(_viewport.copyWith(center: place.location));
    return place;
  }

  IconData _quickActionIcon(String action) => switch (action) {
    'Home' => Icons.home_rounded,
    'Work' => Icons.work_rounded,
    'Frequent' => Icons.history_rounded,
    'Restaurants' => Icons.restaurant_rounded,
    'Shopping' => Icons.shopping_bag_rounded,
    'Gas' => Icons.local_gas_station_rounded,
    _ => Icons.place_rounded,
  };

  String _quickCommuteEta(RouteOption route) {
    final minutes = (route.durationSeconds / 60).ceil().clamp(1, 999);
    if (minutes < 60) return _text('$minutes min', '$minutes 分钟');
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    if (remainder == 0) return _text('${hours}h', '$hours 小时');
    return _text('${hours}h ${remainder}m', '$hours 小时 $remainder 分');
  }

  Color _quickCommuteColor(RouteOption route) {
    final delay = route.trafficDelaySeconds ?? 0;
    if (delay >= 600) return WaybiColors.danger;
    if (delay >= 180 || route.traffic.trafficJam > 0) {
      return WaybiColors.warning;
    }
    return WaybiColors.ocean;
  }

  Widget _quickActionLabel(String action) {
    final route = _quickCommuteRoutes[action];
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          action,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
        if (route != null) ...[
          const SizedBox(width: 6),
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: _quickCommuteColor(route),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            _quickCommuteEta(route),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildQuickActions() => SizedBox(
    height: 34,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final action in _quickActions)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ActionChip(
              avatar: Icon(
                _quickActionIcon(action),
                size: 15,
                color: WaybiColors.ocean,
              ),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 7),
              backgroundColor: Theme.of(context).colorScheme.surface
                  .withValues(alpha: .96),
              side: BorderSide(color: WaybiColors.sky.withValues(alpha: .28)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
              label: _quickActionLabel(action),
              onPressed: () => _onQuickAction(action),
            ),
          ),
        SizedBox(
          width: 34,
          height: 34,
          child: IconButton.filledTonal(
            padding: EdgeInsets.zero,
            tooltip: _text('Edit shortcuts', '编辑快捷入口'),
            onPressed: _editQuickActions,
            icon: const Icon(Icons.tune_rounded, size: 17),
          ),
        ),
      ],
    ),
  );

  void _onQuickAction(String action) {
    if (action == 'Home' || action == 'Work') {
      final place = _quickLocations[action];
      if (place != null && _quickLocationProviders[action] == _mapProvider) {
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
    unawaited(_openSearch(query: action == 'Frequent' ? '' : action));
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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, updateSheet) => SafeArea(
          child: SizedBox(
            height: 430,
            child: Column(
              children: [
                ListTile(
                  title: Text(_text('Edit shortcuts', '编辑快捷入口')),
                  subtitle: Text(
                    _text(
                      'Drag to reorder. Remove or add shortcuts any time.',
                      '拖动排序，可随时移除或添加。',
                    ),
                  ),
                ),
                Expanded(
                  child: ReorderableListView(
                    onReorderItem: (oldIndex, newIndex) {
                      updateSheet(() {
                        final item = actions.removeAt(oldIndex);
                        actions.insert(newIndex, item);
                      });
                    },
                    children: [
                      for (final action in actions)
                        ListTile(
                          key: ValueKey(action),
                          title: Text(action),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (action == 'Home' || action == 'Work')
                                IconButton(
                                  tooltip: _text('Set location', '设置地点'),
                                  icon: const Icon(
                                    Icons.edit_location_alt_outlined,
                                  ),
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    unawaited(_openSearch(saveAs: action));
                                  },
                                ),
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: () =>
                                    updateSheet(() => actions.remove(action)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 4,
                  children: [
                    for (final action in [
                      'Home',
                      'Work',
                      'Frequent',
                      'Restaurants',
                      'Shopping',
                      'Gas',
                    ])
                      if (!actions.contains(action))
                        ActionChip(
                          label: Text('+ $action'),
                          onPressed: () =>
                              updateSheet(() => actions.add(action)),
                        ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: () async {
                      setState(() => _quickActions = actions);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setStringList('waybi.quick_actions', actions);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    child: Text(_text('Done', '完成')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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

  Widget _buildBottomBar() {
    Widget item(IconData icon, String label, VoidCallback action) => Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: action,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 22,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .96),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .25),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x2220351C),
              blurRadius: 22,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: Row(
            children: [
              item(Icons.map_outlined, _text('Map', '地图'), _recenter),
              item(
                Icons.travel_explore_outlined,
                _text('Discover', '发现'),
                () => unawaited(_showDiscover()),
              ),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(17),
                  onTap: _showGoSearch,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 3,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 55,
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [WaybiColors.ocean, WaybiColors.teal],
                            ),
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x30486B29),
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.navigation_rounded,
                            size: 22,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _text('Start', '出发'),
                          style: TextStyle(
                            color: WaybiColors.ocean,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              item(
                Icons.route_rounded,
                _text('Trips', '行程'),
                () => unawaited(_showTrips()),
              ),
              item(
                Icons.person_outline_rounded,
                _text('Me', '我的'),
                _showProfile,
              ),
            ],
          ),
        ),
      ),
    );
  }

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
    return Scaffold(
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
              onTransitLane: (lane) => unawaited(_showTransitLaneDetails(lane)),
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
                      onSearch: (query) => unawaited(_openSearch(query: query)),
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
              actionLabel: switch (_locationNoticeAction) {
                _LocationNoticeAction.appSettings ||
                _LocationNoticeAction.locationSettings => _text(
                  'Open settings',
                  '打开设置',
                ),
                _ => _text('Retry location', '重试定位'),
              },
              onAction:
                  _message == _browseLocationMessage &&
                      _locationNoticeAction != null
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
                onEnd: () => setState(() {
                  _parkingLegFinished = false;
                  _parkingOriginalPlace = null;
                  _selectedParking = null;
                }),
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
                    onFavorite: () => unawaited(_toggleFavorite(_selectedPoi!)),
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
                onRoadEvent: (event) => unawaited(_showRoadEventDetails(event)),
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
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({
    required this.selectedPlace,
    required this.details,
    required this.detailsLoading,
    required this.detailsError,
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
