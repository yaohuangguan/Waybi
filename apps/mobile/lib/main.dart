import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

import 'data/account_repository.dart';
import 'data/brand_migration.dart';
import 'data/app_store_billing.dart';
import 'data/explore_repository.dart';
import 'data/place_details_repository.dart';
import 'data/parking_repository.dart';
import 'data/route_repository.dart';
import 'data/quick_location_store.dart';
import 'data/usage_telemetry_repository.dart';
import 'data/navigation_reward_repository.dart';
import 'data/navigation_feedback_repository.dart';
import 'domain/radar_geometry.dart';
import 'domain/map_layer_settings.dart';
import 'domain/map_provider.dart';
import 'domain/navigation_link.dart';
import 'domain/navigation_camera_mode.dart';
import 'domain/geo_math.dart';
import 'domain/route_option.dart';
import 'domain/route_preference.dart';
import 'domain/road_event.dart';
import 'domain/safety_camera.dart';
import 'domain/traffic_flow.dart';
import 'drive/device_heading.dart';
import 'drive/journey_tracker.dart';
import 'drive/navigation_language.dart';
import 'drive/navigation_location_filter.dart';
import 'drive/reliable_location_feed.dart';
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
import 'providers/google_map_renderer.dart';
import 'providers/independent_map_renderer.dart';
import 'providers/independent_navigation_engine.dart';
import 'providers/independent_routing_provider.dart';
import 'providers/independent_transit_routing_provider.dart';
import 'providers/place_search_providers.dart';
import 'providers/provider_contracts.dart';
import 'services/notification_service.dart';
import 'theme/waybi_theme.dart';
import 'widgets/arrival_experience_panel.dart';
import 'widgets/map_symbols.dart';
import 'widgets/independent_navigation_overlay.dart';
import 'widgets/drive_hud.dart';
import 'widgets/explore_search.dart';
import 'widgets/explore_page.dart';
import 'widgets/full_screen_search.dart';
import 'widgets/companion_search_prompt.dart';
import 'widgets/navigation_overlay.dart';
import 'widgets/place_details_content.dart';
import 'widgets/profile_page.dart';
import 'widgets/map_layer_sheet.dart';
import 'widgets/splash_gate.dart';
import 'widgets/route_preview_sheet.dart';
import 'widgets/transit_trip_overlay.dart';
import 'widgets/trips_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ExternalNavigationInbox.instance.start();
  await migrateWaybiPreferences(await SharedPreferences.getInstance());
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

class _TransientWaybiBanner extends StatefulWidget {
  const _TransientWaybiBanner({
    super.key,
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  State<_TransientWaybiBanner> createState() => _TransientWaybiBannerState();
}

class _TransientWaybiBannerState extends State<_TransientWaybiBanner> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 4), widget.onDismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 76, 20, 0),
        child: PointerInterceptor(
          child: Material(
            color: WaybiColors.darkOcean.withValues(alpha: .96),
            elevation: 8,
            borderRadius: BorderRadius.circular(15),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 9, 5, 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: WaybiColors.sky,
                    size: 19,
                  ),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Dismiss',
                    onPressed: widget.onDismiss,
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class MapHomePage extends StatefulWidget {
  const MapHomePage({
    super.key,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    this.onAppLanguageChanged,
  });

  final ThemeMode themeMode;
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
  static const _mapId = String.fromEnvironment('MAP_ID');
  static const _auckland = LatLng(latitude: -36.8485, longitude: 174.7633);

  final DriveEngine _driveEngine = DriveEngine();
  late final IndependentNavigationEngine _independentNavigation;
  final AccountRepository _account = AccountRepository();
  late final _plusBilling = AppStoreBillingGateway(_account);
  final PlaceDetailsRepository _placeDetailsRepository =
      PlaceDetailsRepository();
  final RouteRepository _routeRepository = RouteRepository();
  final UsageTelemetryRepository _usageTelemetry = UsageTelemetryRepository();
  final _navigationRewards = NavigationRewardRepository();
  final _navigationFeedback = NavigationFeedbackRepository();
  Future<String?>? _journeyCountry;
  final ParkingRepository _parkingRepository = ParkingRepository();
  final WorkerSearchProvider _workerSearch = WorkerSearchProvider();
  final IndependentSearchProvider _independentSearch =
      IndependentSearchProvider(useWorkerSuggestions: true);
  final IndependentRoutingProvider _independentRoutes =
      IndependentRoutingProvider();
  final IndependentTransitRoutingProvider _independentTransitRoutes =
      IndependentTransitRoutingProvider();
  MapProvider _mapProvider = MapProvider.google;
  MapProvider? _requestedMapProvider;
  Future<void> _providerSwitchQueue = Future<void>.value();
  LocationMarkerStyle _locationMarker = LocationMarkerStyle.kiwi;
  MapRenderer? _browseRenderer;
  MapViewportState _viewport = const MapViewportState(
    center: GeoPoint(-36.8485, 174.7633),
  );
  GeoPoint _areaSearchAnchor = const GeoPoint(-36.8485, 174.7633);
  bool _showSearchArea = false;
  List<PlaceSummary> _exploreResults = const [];
  List<Marker> _exploreMarkers = [];
  final Map<String, PlaceSummary> _exploreMarkerPlaces = {};
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
  GoogleMapViewController? _browseController;
  GoogleNavigationViewController? _navigationController;
  Brightness? _lastMapBrightness;
  double _navigationTopInset = 125;
  double _navigationBottomInset = 215;
  ReliableLocationFeed? _browseLocationFeed;
  Position? _lastReliableBrowsePosition;
  final _independentCamera = IndependentNavigationCamera();
  final _browseMotion = NavigationMotionEstimator();
  StreamSubscription<double>? _headingSubscription;
  Timer? _mapRefreshTimer;
  LatLng? _gpsLocation;
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
  String? _placeQuickRouteLoadingKey;
  int _placeQuickRouteRequest = 0;
  final Map<String, RouteOption> _placeQuickRouteCache = {};
  final Map<String, DateTime> _placeQuickRouteCachedAt = {};
  final Map<String, LatLng> _placeQuickRouteOrigins = {};
  CameraPosition? _lastBrowseCamera;
  List<Marker> _cameraMarkers = [];
  List<Marker> _roadEventMarkers = [];
  Marker? _destinationMarker;
  Marker? _carMarker;
  Circle? _accuracyCircle;
  String _markerSignature = '';
  bool _markerSyncing = false;
  bool _useCarMarker = false;
  MapLayerSettings _layers = const MapLayerSettings();
  NavigationCameraMode _cameraMode = NavigationCameraMode.northUpFlat;
  String _appLanguage = 'en';
  String _voiceLanguage = 'en-NZ';
  double? _gpsAccuracy;
  final NavigationLocationFilter _browseLocationFilter =
      NavigationLocationFilter();
  double? _deviceHeading;
  double? _travelHeading;
  double? _smoothedLocationHeading;
  List<Polygon> _radarPolygons = [];
  bool _mapRefreshing = false;
  bool _refreshAgain = false;
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
  bool _navigationSessionInitialized = false;
  bool _guidanceRunning = false;
  bool _busy = false;
  bool _checkingRouteWatchAlerts = false;
  String? _message;
  String? _lastNotifiedCameraId;
  final Set<String> _notifiedRoadEventIds = <String>{};

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
        headingDegrees: _driveEngine.speedKph > 10
            ? _driveEngine.rawHeadingDegrees
            : null,
      ),
    );
    _independentNavigation.addListener(_onIndependentNavigationChanged);
    unawaited(WaybiNotificationService.instance.initialize());
    _account.addListener(_onAccountChanged);
    _driveEngine.addListener(_onEngineChanged);
    _plusBilling.initialize();
    unawaited(_account.restore());
    unawaited(_driveEngine.loadCameras());
    unawaited(
      _restoreMapSettings().then((_) async {
        if (_mapProvider == MapProvider.independent && _layers.traffic) {
          await _driveEngine.startTrafficFlowRefresh();
        }
        await _maybeShowCoreOnboarding();
        if (!mounted) return;
        _externalNavigationReady = true;
        _scheduleExternalNavigation();
      }),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_startTracking());
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
      if (_manualOrigin == null && _gpsLocation == null) {
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
    if (_gpsLocation == null || _selectedPoi == null || _busy) return;
    _externalPreview = null;
    unawaited(_loadRoutePreview(_selectedPoi!, preferredMode: pending.mode));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (_lastMapBrightness == brightness) return;
    _lastMapBrightness = brightness;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = _driveEngine.active
          ? _navigationController
          : _browseController;
      if (controller != null) {
        unawaited(_applyMapLayers(controller));
      }
    });
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
        final provider = MapProvider.values.firstWhere(
          (value) => value.name == item['provider']?.toString(),
          orElse: () => MapProvider.google,
        );
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
      if (_driveEngine.active) {
        unawaited(_driveEngine.recoverLocalLocation());
      } else {
        unawaited(_startTracking());
        unawaited(_browseLocationFeed?.recover(force: true));
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
      if (_driveEngine.active ||
          (_mapProvider == MapProvider.independent && _layers.traffic)) {
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
    final reportIds = _communityRoadEvents.map((event) => event.id).join(',');
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
      unawaited(_syncCameraMarkers());
      if (_routePlan != null || _mapProvider == MapProvider.independent) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      }
    }
    _updateArrivalExperience();
    unawaited(_cacheNavigationCorridor());
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

  NavigationGuidance? _offlineGoogleGuidance() {
    if (_account.profile?.isPlus != true) return null;
    if (!_guidanceRunning ||
        _independentNavigation.active ||
        !_driveEngine.nativeGuidanceStale) {
      return null;
    }
    final route = _activeNavigationRoute;
    final progress = _driveEngine.routeProgress;
    if (route == null || progress == null || route.points.length < 2) {
      return null;
    }
    final matcher = const RouteCameraMatcher();
    final geometry = RouteProgressTracker.geometryLength(route.points);
    if (geometry <= 0) return null;
    RouteStepInfo? next;
    var distanceToStep = double.infinity;
    for (final step in route.steps) {
      final along = matcher.project(step.location, route.points)?.alongMeters;
      if (along == null) continue;
      final ahead = along - progress.alongMeters;
      if (ahead >= 5 && ahead < distanceToStep) {
        distanceToStep = ahead;
        next = step;
      }
    }
    final fraction = (progress.alongMeters / geometry).clamp(0.0, 1.0);
    final remainingMeters = route.distanceMeters * (1 - fraction);
    final remainingSeconds = (route.durationSeconds * (1 - fraction)).round();
    return NavigationGuidance(
      instruction: routeStepInstruction(next, _appLanguage),
      maneuverIcon: independentManeuverIcon(next),
      stepMeters: distanceToStep.isFinite ? distanceToStep : remainingMeters,
      remainingMeters: remainingMeters,
      remainingSeconds: remainingSeconds,
      lanes: [
        for (final lane in next?.lanes ?? const <RouteLane>[])
          NavigationLane(
            lane.indications
                .map(
                  (name) => name.contains('left')
                      ? '←'
                      : name.contains('right')
                      ? '→'
                      : name == 'uturn'
                      ? '↶'
                      : '↑',
                )
                .toSet()
                .join(),
            lane.recommended,
          ),
      ],
    );
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
          allowGoogleFallback: _mapProvider == MapProvider.google,
          language: _appLanguage,
        );
      } catch (_) {}
    }
    final reference = destination.reference;
    if (reference?.provider == 'google' && reference!.id.isNotEmpty) {
      try {
        details = await _placeDetailsRepository.fetch(
          reference.id,
          language: _appLanguage,
        );
      } catch (_) {}
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

  List<RoadEvent> get _communityRoadEvents => _driveEngine.roadEvents
      .where(
        (event) =>
            event.metadata['userReported'] == true &&
            event.isCurrent(DateTime.now()),
      )
      .toList(growable: false);

  String _roadEventLabel(RoadEventType type) => switch (type) {
    RoadEventType.incident => _text('Crash / hazard', '事故 / 危险'),
    RoadEventType.roadworks => _text('Roadworks', '道路施工'),
    RoadEventType.roadClosure => _text('Road closed', '道路封闭'),
    RoadEventType.congestion => _text('Heavy traffic', '严重拥堵'),
    RoadEventType.flooding => _text('Flooding', '积水 / 洪水'),
    RoadEventType.slip => _text('Slip / debris', '滑坡 / 道路杂物'),
    _ => _text('Road report', '道路报告'),
  };

  String _relativeTime(DateTime? date) {
    if (date == null) return _text('recently', '刚刚');
    final delta = DateTime.now().difference(date);
    if (delta.inMinutes < 1) return _text('just now', '刚刚');
    if (delta.inMinutes < 60) {
      return _text('${delta.inMinutes} min ago', '${delta.inMinutes} 分钟前');
    }
    if (delta.inHours < 24) {
      return _text('${delta.inHours} hr ago', '${delta.inHours} 小时前');
    }
    return _text('${delta.inDays} d ago', '${delta.inDays} 天前');
  }

  String _remainingTime(DateTime? date) {
    if (date == null) return '';
    final delta = date.difference(DateTime.now());
    if (delta.isNegative) return _text('expired', '已过期');
    if (delta.inMinutes < 60) {
      return _text('${delta.inMinutes} min left', '剩余 ${delta.inMinutes} 分钟');
    }
    return _text('${delta.inHours} hr left', '剩余 ${delta.inHours} 小时');
  }

  Future<void> _notifyRoadIntelligence() async {
    if (!_driveEngine.active) return;
    final camera = _driveEngine.upcomingCamera;
    final cameraDistance = _driveEngine.upcomingCameraDistanceMeters;
    if (_notifySafetyCameras &&
        camera != null &&
        cameraDistance != null &&
        cameraDistance <= 600 &&
        _lastNotifiedCameraId != camera.id) {
      _lastNotifiedCameraId = camera.id;
      final cameraType = CameraKindLabel.fromCamera(camera)
          .localizedLabel(_appLanguage);
      await WaybiNotificationService.instance.showRoadAlert(
        id: 'camera:${camera.id}',
        title: _text('Safety camera ahead', '前方安全摄像头'),
        body: _text(
          '$cameraType · ${cameraDistance.round()} m',
          '$cameraType · ${cameraDistance.round()} 米',
        ),
      );
    }
    if (camera == null) _lastNotifiedCameraId = null;

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
      if (!enabled || !_notifiedRoadEventIds.add(event.id)) continue;
      final reporter = event.metadata['reporterName']?.toString();
      await WaybiNotificationService.instance.showRoadAlert(
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

  Future<void> _showRoadEventDetails(RoadEvent event) async {
    final reporter =
        event.metadata['reporterName']?.toString() ??
        _text('Waybi driver', 'Waybi 用户');
    final description = event.metadata['description']?.toString();
    final reportedAt =
        DateTime.tryParse(event.metadata['reportedAt']?.toString() ?? '') ??
        event.source.updatedAt;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: WaybiColors.ice,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.add_alert_rounded,
                    color: WaybiColors.ocean,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _roadEventLabel(event.type),
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: WaybiColors.deepOcean,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              _text(
                '$reporter reported this ${_relativeTime(reportedAt)}',
                '$reporter · ${_relativeTime(reportedAt)}报告',
              ),
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: WaybiColors.deepOcean,
              ),
            ),
            if (description != null && description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(description),
            ],
            const SizedBox(height: 8),
            Text(
              _remainingTime(event.validUntil),
              style: const TextStyle(
                color: WaybiColors.lightTextSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _restoreMapSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _useCarMarker = prefs.getBool('waybi.map.car_marker') ?? false;
    _mapProvider = MapProvider.values.firstWhere(
      (value) => value.name == prefs.getString('waybi.map.provider'),
      orElse: () =>
          const String.fromEnvironment('WAYBI_DEFAULT_MAP_PROVIDER') ==
              'independent'
          ? MapProvider.independent
          : MapProvider.google,
    );
    if (prefs.getString('waybi.map.provider') == 'mapbox') {
      _mapProvider = MapProvider.independent;
    }
    _locationMarker = LocationMarkerStyle.values.firstWhere(
      (value) => value.name == prefs.getString('waybi.map.location_marker'),
      orElse: () => LocationMarkerStyle.kiwi,
    );
    _useCarMarker = _locationMarker != LocationMarkerStyle.classic;
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
      style: BaseMapStyle.values.firstWhere(
        (value) => value.name == prefs.getString('waybi.layers.style'),
        orElse: () => BaseMapStyle.standard,
      ),
    );
    _driveEngine.setCameraAlertFilter(_layers.alerts);
    await _driveEngine.setVoiceLanguage(_voiceLanguage);
    final controller = _driveEngine.active
        ? _navigationController
        : _browseController;
    if (controller != null) {
      await _applyMapLayers(controller);
      await controller.setMyLocationEnabled(
        _driveEngine.active || !_useCarMarker,
      );
      _markerSignature = '';
      unawaited(_syncCameraMarkers());
      _queueMapRefresh();
    }
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
    _account.dispose();
    _usageTelemetry.dispose();
    _navigationRewards.dispose();
    _navigationFeedback.dispose();
    _placeDetailsRepository.dispose();
    _parkingRepository.dispose();
    _driveEngine.dispose();
    if (_navigationSessionInitialized) {
      GoogleMapsNavigator.cleanup();
    }
    super.dispose();
  }

  Future<bool> _ensureLocationPermission() async {
    final whenInUse = await Permission.locationWhenInUse.request();
    if (whenInUse.isGranted || whenInUse.isLimited) return true;

    if (!mounted) return false;
    setState(() {
      _message = whenInUse.isPermanentlyDenied
          ? 'Location is disabled for Waybi. Enable it in system settings.'
          : 'Location permission is required for navigation.';
    });
    return false;
  }

  Future<void> _startTracking() async {
    if (_driveEngine.active ||
        _browseLocationFeed?.running == true ||
        !await _ensureLocationPermission()) {
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
    if (!mounted ||
        _driveEngine.active ||
        _browseLocationFeed?.running == true) {
      return;
    }
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
      onIssue: (error) {
        if (!mounted || error == null || _driveEngine.active) return;
        // Navigation and route requests show actionable status at the point of use.
        debugPrint('Location recovery: ${error.runtimeType}');
      },
    )..start();
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

    // Keep the last reliable browse fix instead of letting a single indoor
    // GPS jump move route origins, arrival checks and the map by 50–100 m.
    if (accepted == null) {
      setState(() {});
      return _browseLocationFilter.accepted?.timestamp == position.timestamp &&
          DateTime.now().difference(position.timestamp) <=
              const Duration(seconds: 10);
    }

    _lastReliableBrowsePosition = position;
    _gpsLocation = LatLng(
      latitude: accepted.point.latitude,
      longitude: accepted.point.longitude,
    );
    _retryExternalPreview();
    if (speedMetresPerSecond >= .8 && motion.heading != null) {
      _travelHeading = motion.heading;
    } else {
      _travelHeading = null;
    }
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

  Future<void> _loadPlaceQuickRoute(PlaceSummary place) async {
    if (!mounted || _driveEngine.active || _routePlan != null) return;
    if (!place.location.isValid) return;
    final origin = _gpsLocation;
    if (origin == null) return;
    final key = _placeRouteKey(place);
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
      if (driving.isEmpty || !mounted || request != _placeQuickRouteRequest) {
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
        _placeQuickRouteLoading = false;
        _placeQuickRouteLoadingKey = null;
      });
    } catch (_) {
      if (!mounted || request != _placeQuickRouteRequest) return;
      setState(() {
        _placeQuickRoute = null;
        _placeQuickRouteLoading = false;
        _placeQuickRouteLoadingKey = null;
      });
    }
  }

  Future<RoutePlan> _driveRoutePlan({
    required LatLng origin,
    required LatLng destination,
    WaybiTravelMode? mode,
  }) => _mapProvider == MapProvider.independent
      ? _independentRoutes.route(
          origin: GeoPoint(origin.latitude, origin.longitude),
          destination: GeoPoint(destination.latitude, destination.longitude),
          language: _appLanguage,
          mode: mode ?? WaybiTravelMode.drive,
        )
      : _routeRepository.fetch(
          origin: origin,
          destination: destination,
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
        final plan = await _routeRepository.fetch(
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
    final smoothNavigation =
        _mapProvider == MapProvider.independent &&
        _independentNavigation.active;
    _mapRefreshTimer = Timer(
      Duration(milliseconds: smoothNavigation ? 180 : 350),
      () => unawaited(_refreshMap()),
    );
  }

  Future<void> _refreshMap() async {
    if (_mapProvider == MapProvider.independent) {
      final location = _driveEngine.active
          ? _driveEngine.snappedLocation ?? _gpsLocation
          : _gpsLocation;
      final routePreviewOwnsCamera =
          _journeyPhase == JourneyPhase.routePreview && _routePlan != null;
      final placeDeckOwnsCamera = _selectedPlace != null && _routePlan == null;
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
        final viewport = navigating
            ? _independentCamera.update(
                location: point,
                heading: heading,
                speedKph: _driveEngine.speedKph,
                mode: _activeNavigationRoute?.mode ?? _selectedMode,
                visibleHeight:
                    MediaQuery.sizeOf(context).height -
                    _navigationTopInset -
                    _navigationBottomInset,
                distanceToStep: _independentNavigation.distanceToStepMeters,
                nextStep: _independentNavigation.nextStep,
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
    if (_mapRefreshing) {
      _refreshAgain = true;
      return;
    }
    final controller = _driveEngine.active
        ? _navigationController
        : _browseController;
    final location = _driveEngine.active
        ? _driveEngine.snappedLocation ?? _gpsLocation
        : _gpsLocation;
    final heading = _driveEngine.active
        ? _driveEngine.snappedHeadingDegrees ?? _travelHeading
        : _deviceHeading ?? _travelHeading;
    if (controller == null || location == null) return;
    _mapRefreshing = true;
    try {
      if (heading != null && !_driveEngine.active) {
        final layers = headingLightLayers(location, heading);
        final options = [
          for (final layer in layers)
            PolygonOptions(
              points: layer.$1,
              fillColor: WaybiColors.sky.withValues(alpha: layer.$2),
              strokeColor: Colors.transparent,
              strokeWidth: 0,
              geodesic: true,
              zIndex: 5,
            ),
        ];
        if (_radarPolygons.length != options.length) {
          if (_radarPolygons.isNotEmpty) {
            await controller.removePolygons(_radarPolygons);
          }
          _radarPolygons = (await controller.addPolygons(options))
              .whereType<Polygon>()
              .toList();
        } else {
          _radarPolygons = (await controller.updatePolygons([
            for (var i = 0; i < options.length; i++)
              _radarPolygons[i].copyWith(options: options[i]),
          ])).whereType<Polygon>().toList();
        }
      } else if (_radarPolygons.isNotEmpty) {
        await controller.removePolygons(_radarPolygons);
        _radarPolygons = [];
      }
      if (_useCarMarker && !_driveEngine.active) {
        await _syncCarMarker(controller, location);
      }
      // During Drive/Navigation the native SDK owns the camera. Manually
      // moving it on every GPS/heading update causes visible tug-of-war.
      final routePreviewOwnsCamera =
          _journeyPhase == JourneyPhase.routePreview && _routePlan != null;
      final placeDeckOwnsCamera = _selectedPlace != null && _routePlan == null;
      if (_following &&
          !_driveEngine.active &&
          !routePreviewOwnsCamera &&
          !placeDeckOwnsCamera) {
        await controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: location,
              bearing: _cameraMode.northUp
                  ? 0
                  : (_travelHeading ?? _deviceHeading ?? 0),
              tilt: _cameraMode.tilted ? 45 : 0,
              zoom: _viewport.zoom,
            ),
          ),
        );
      }
    } catch (_) {
      /* View may have been replaced during a mode change. */
    } finally {
      _mapRefreshing = false;
      if (_refreshAgain) {
        _refreshAgain = false;
        _queueMapRefresh();
      }
    }
  }

  CameraPerspective get _navigationFollowPerspective => switch (_cameraMode) {
    NavigationCameraMode.northUpFlat => CameraPerspective.topDownNorthUp,
    NavigationCameraMode.headingUpFlat => CameraPerspective.topDownHeadingUp,
    NavigationCameraMode.headingUpPerspective => CameraPerspective.tilted,
  };

  double get _navigationFollowZoom {
    final speed = _driveEngine.speedKph;
    if (speed >= 90) return 17.0;
    if (speed >= 60) return 17.35;
    return 17.7;
  }

  Future<void> _followNavigationCamera(
    GoogleNavigationViewController controller, {
    double? zoomLevel,
  }) async {
    await controller.followMyLocation(
      _navigationFollowPerspective,
      zoomLevel: zoomLevel ?? _navigationFollowZoom,
    );
    await controller.setMyLocationEnabled(true);
    await controller.setRecenterButtonEnabled(false);
  }

  void _recenter() {
    _independentCamera.reset();
    setState(() {
      _following = true;
      _routeOverviewActive = false;
    });
    if (_mapProvider == MapProvider.independent) {
      _queueMapRefresh();
      return;
    }
    final navigationController = _navigationController;
    if (_driveEngine.active && navigationController != null) {
      unawaited(_followNavigationCamera(navigationController));
      return;
    }
    _queueMapRefresh();
  }

  IconData get _locationControlIcon {
    if (!_following) return Icons.my_location_outlined;
    return _cameraMode.northUp ? Icons.north_rounded : Icons.navigation_rounded;
  }

  String get _locationControlTooltip {
    if (!_following) return _text('Return to my location', '回到我的位置');
    if (_mapProvider == MapProvider.independent && !_cameraMode.northUp) {
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
    if (_following &&
        _navigationController != null &&
        defaultTargetPlatform == TargetPlatform.iOS) {
      unawaited(
        const MethodChannel('waybi/navigation_camera')
            .invokeMethod<void>('pauseFollowing')
            .catchError((Object e) {
              debugPrint('Pause follow: $e');
            }),
      );
    }
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
      unawaited(_syncCameraMarkers());
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
    if (_mapProvider == MapProvider.independent &&
        renderer is RouteMapRenderer &&
        route != null) {
      unawaited(
        renderer.fitRoute(
          route.points,
          bottomInset: _navigationBottomInset + 30,
        ),
      );
      return;
    }
    final controller = _navigationController;
    if (controller != null) unawaited(controller.showRouteOverview());
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
    final controller = _browseController;
    if (controller != null) {
      try {
        await controller.clearPolylines();
        if (_destinationMarker != null) {
          await controller.removeMarkers([_destinationMarker!]);
          _destinationMarker = null;
        }
        await controller.setPadding(EdgeInsets.zero);
      } catch (_) {}
    }
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
      _selectedPlace = null;
      _journeyPhase = JourneyPhase.idle;
      _placeDetails = null;
      _placeDetailsLoading = false;
      _placeDetailsError = null;
      _placeDetailsRequest++;
      _placeQuickRoute = null;
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
        allowGoogleFallback: _mapProvider == MapProvider.google,
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

  Future<void> _loadRoutePreview(
    PointOfInterest poi, {
    WaybiTravelMode preferredMode = WaybiTravelMode.drive,
  }) async {
    _externalPreview = null;
    final origin = _manualOrigin?.location ?? _gpsLocation;
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
      unawaited(_startTracking());
      unawaited(_browseLocationFeed?.recover(force: true));
      return;
    }
    final request = ++_routeRequest;
    setState(() {
      _routePreviewLoading = true;
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
      final plan = _mapProvider == MapProvider.independent
          ? await _independentRoutes.route(
              origin: GeoPoint(origin.latitude, origin.longitude),
              destination: GeoPoint(poi.latLng.latitude, poi.latLng.longitude),
              stops: _routeStops
                  .map(
                    (stop) => GeoPoint(
                      stop.location.latitude,
                      stop.location.longitude,
                    ),
                  )
                  .toList(growable: false),
              language: _appLanguage,
              mode: preferredMode,
            )
          : await _routeRepository.fetch(
              origin: origin,
              destination: poi.latLng,
              stops: _routeStops
                  .map((stop) => stop.location)
                  .toList(growable: false),
              mode: preferredMode,
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
      final preferredRoute = preferredMode == WaybiTravelMode.drive
          ? recommendedRoute(preferredRoutes, preferenceSummaries)
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
        setState(() => _message = 'Could not preview routes: $error');
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

  RouteOption? get _selectedRoute {
    final plan = _routePlan;
    if (plan == null) return null;
    for (final route in plan.forMode(_selectedMode)) {
      if (route.id == _selectedRouteId) return route;
    }
    return plan.forMode(_selectedMode).firstOrNull;
  }

  List<MapRoutePath> get _visibleIndependentRoutePaths {
    final navigationRoute = _independentNavigation.route;
    if (navigationRoute != null) {
      return [
        MapRoutePath(
          id: navigationRoute.id,
          points: navigationRoute.points,
          active: true,
        ),
      ];
    }
    final plan = _routePlan;
    if (plan == null) return const [];
    return plan
        .forMode(_selectedMode)
        .take(3)
        .map(
          (route) => MapRoutePath(
            id: route.id,
            points: route.points,
            active: route.id == _selectedRouteId,
          ),
        )
        .toList(growable: false);
  }

  Color _trafficColor(String speed, bool active) {
    final alpha = active ? 0xFF : 0x66;
    final rgb = speed == 'trafficJam'
        ? 0xE5484D
        : speed == 'slow'
        ? 0xF59E0B
        : 0x486B29;
    return Color((alpha << 24) | rgb);
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
              unawaited(_syncCameraMarkers());
            }
            return snapshot;
          },
          onMapProviderChanged: (value) async {
            await _setMapProvider(value);
            return _mapProvider;
          },
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
    if (_mapProvider == MapProvider.independent) {
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
    final controller = _browseController;
    final plan = _routePlan;
    if (controller == null || plan == null) return;
    final sheetInset = (MediaQuery.sizeOf(context).height * .44).clamp(
      330.0,
      420.0,
    );
    await controller.clearPolylines();
    final selected = _selectedRoute;
    final options = <PolylineOptions>[];

    for (final route in plan.forMode(_selectedMode)) {
      if (route.points.length < 2) continue;
      final active = route.id == selected?.id;
      options.add(
        PolylineOptions(
          points: route.points
              .map(
                (point) => LatLng(
                  latitude: point.latitude,
                  longitude: point.longitude,
                ),
              )
              .toList(growable: false),
          strokeColor: active
              ? WaybiColors.ocean.withValues(alpha: .92)
              : WaybiColors.sky.withValues(alpha: .38),
          strokeWidth: active ? 8 : 6,
          zIndex: active ? 18 : 8,
          clickable: false,
        ),
      );

      if (_layers.traffic && _selectedMode == WaybiTravelMode.drive) {
        final intervals = route.trafficIntervals.isEmpty
            ? <TrafficInterval>[
                TrafficInterval(
                  startPolylinePointIndex: 0,
                  endPolylinePointIndex: route.points.length - 1,
                  speed: 'unknown',
                ),
              ]
            : route.trafficIntervals;
        for (final interval in intervals) {
          final start = interval.startPolylinePointIndex
              .clamp(0, route.points.length - 1)
              .toInt();
          if (start >= route.points.length - 1) continue;
          final end = interval.endPolylinePointIndex
              .clamp(start + 1, route.points.length - 1)
              .toInt();
          final segment = route.points.sublist(start, end + 1);
          if (segment.length < 2) continue;
          options.add(
            PolylineOptions(
              points: segment
                  .map(
                    (point) => LatLng(
                      latitude: point.latitude,
                      longitude: point.longitude,
                    ),
                  )
                  .toList(growable: false),
              strokeColor: _trafficColor(interval.speed, active),
              strokeWidth: active ? 8 : 6,
              zIndex: active ? 25 : 12,
              clickable: false,
            ),
          );
        }
      }
    }

    if (options.isNotEmpty) await controller.addPolylines(options);
    await _syncDestinationMarker(controller);
    if (selected != null && selected.points.length >= 2) {
      await controller.setPadding(EdgeInsets.fromLTRB(24, 76, 24, sheetInset));
      final bounds = LatLngBounds.createBoundsFromPoints(
        selected.points
            .map(
              (point) =>
                  LatLng(latitude: point.latitude, longitude: point.longitude),
            )
            .toList(growable: false),
      );
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, padding: 36),
        duration: const Duration(milliseconds: 420),
      );
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
    if (routes.isEmpty &&
        mode == WaybiTravelMode.transit &&
        _mapProvider == MapProvider.independent) {
      routes = await _loadIndependentTransitRoutes();
    }
    if (routes.isEmpty) {
      final poi = _selectedPoi;
      if (poi != null && mode != WaybiTravelMode.transit) {
        await _loadRoutePreview(poi, preferredMode: mode);
      } else if (poi != null && _mapProvider == MapProvider.google) {
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
    if (_account.profile != null && _mapProvider == MapProvider.google) {
      try {
        await _account.recordRoute(
          destinationName: poi.name,
          latitude: poi.latLng.latitude,
          longitude: poi.latLng.longitude,
          mode: selected.mode.apiValue,
          distanceMeters: selected.distanceMeters,
          durationSeconds: selected.durationSeconds,
        );
      } catch (_) {
        /* The on-device save remains available while offline. */
      }
    }
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
    if (_mapProvider == MapProvider.independent ||
        !_navigationSessionInitialized) {
      return;
    }
    unawaited(
      GoogleMapsNavigator.setAudioGuidance(
        NavigationAudioGuidanceSettings(
          guidanceType: NavigationAudioGuidanceType.silent,
          isBluetoothAudioEnabled: true,
          isVibrationEnabled: true,
        ),
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

  Future<bool> _ensureNavigationSession() async {
    final nativeInitialized = await GoogleMapsNavigator.isInitialized();
    if (_navigationSessionInitialized && nativeInitialized) {
      if (!_driveEngine.active) {
        await _pauseBrowseLocation();
        await _driveEngine.start();
      }
      return true;
    }
    _navigationSessionInitialized = false;
    if (!await _ensureLocationPermission()) return false;

    if (!await GoogleMapsNavigator.areTermsAccepted()) {
      final accepted = await GoogleMapsNavigator.showTermsAndConditionsDialog(
        'Waybi Navigation',
        'Waybi',
      );
      if (!accepted) return false;
    }

    try {
      await GoogleMapsNavigator.initializeNavigationSession(
        taskRemovedBehavior: TaskRemovedBehavior.continueService,
      );
    } on SessionInitializationException catch (error) {
      if (!mounted) return false;
      final message = switch (error.code) {
        SessionInitializationError.termsNotAccepted =>
          'Accept the Google Navigation terms to continue.',
        SessionInitializationError.locationPermissionMissing =>
          'Location permission is required for navigation.',
        SessionInitializationError.notAuthorized => 'Navigation SDK authorization failed. Check the iOS API key and Bundle ID.',
      };
      setState(() => _message = message);
      return false;
    }
    await GoogleMapsNavigator.setAudioGuidance(
      NavigationAudioGuidanceSettings(
        guidanceType: NavigationAudioGuidanceType.silent,
        isBluetoothAudioEnabled: true,
        isVibrationEnabled: true,
      ),
    );
    for (var attempt = 0; attempt < 10; attempt++) {
      _navigationSessionInitialized = await GoogleMapsNavigator.isInitialized();
      if (_navigationSessionInitialized) break;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    if (!_navigationSessionInitialized) {
      if (mounted) {
        setState(
          () => _message = 'Navigation session did not finish initializing. Please try again.',
        );
      }
      return false;
    }
    await _pauseBrowseLocation();
    try {
      await _driveEngine.start();
    } on SessionNotInitializedException {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!await GoogleMapsNavigator.isInitialized()) {
        await GoogleMapsNavigator.initializeNavigationSession(
          taskRemovedBehavior: TaskRemovedBehavior.continueService,
        );
      }
      for (var attempt = 0; attempt < 10; attempt++) {
        _navigationSessionInitialized =
            await GoogleMapsNavigator.isInitialized();
        if (_navigationSessionInitialized) break;
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      if (!_navigationSessionInitialized) return false;
      await _driveEngine.start();
    }
    return true;
  }

  NavigationTravelMode? get _nativeTravelMode => switch (_selectedMode) {
    WaybiTravelMode.drive => NavigationTravelMode.driving,
    WaybiTravelMode.walk => NavigationTravelMode.walking,
    WaybiTravelMode.bicycle => NavigationTravelMode.cycling,
    WaybiTravelMode.transit => null,
  };

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
    final route = _activeTransitRoute;
    if (_account.profile != null && route != null && route.points.isNotEmpty) {
      final destination = route.points.last;
      unawaited(
        _account
            .recordRoute(
              destinationName: _destinationTitle,
              latitude: destination.latitude,
              longitude: destination.longitude,
              mode: WaybiTravelMode.transit.apiValue,
              distanceMeters: route.distanceMeters,
              durationSeconds: route.durationSeconds,
            )
            .catchError((_) {}),
      );
    }
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

      if (_mapProvider == MapProvider.independent) {
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
        await _startSystemNavigation();
        unawaited(_cacheNavigationCorridor(force: true));
        _queueMapRefresh();
        return;
      }

      if (!await _ensureNavigationSession()) return;

      final hasNavigationLocation = await _driveEngine
          .waitForRoadSnappedLocation();
      if (!hasNavigationLocation) {
        if (mounted) {
          setState(() {
            _message =
                'Waiting for an accurate GPS fix before starting navigation.';
          });
        }
        return;
      }

      final routeToken = selectedRoute.routeToken;
      final travelMode = _nativeTravelMode!;
      final useRouteToken =
          _selectedMode == WaybiTravelMode.drive &&
          routeToken != null &&
          routeToken.isNotEmpty;
      final status = await GoogleMapsNavigator.setDestinations(
        Destinations(
          waypoints: <NavigationWaypoint>[
            for (final stop in _routeStops)
              NavigationWaypoint.withLatLngTarget(
                title: stop.label,
                target: stop.location,
              ),
            if (poi.placeID.isNotEmpty)
              NavigationWaypoint.withPlaceID(
                title: poi.name,
                placeID: poi.placeID,
              )
            else
              NavigationWaypoint.withLatLngTarget(
                title: poi.name,
                target: poi.latLng,
              ),
          ],
          displayOptions: NavigationDisplayOptions(
            showDestinationMarkers: false,
            showStopSigns: true,
            showTrafficLights: true,
          ),
          routeTokenOptions: useRouteToken
              ? RouteTokenOptions(
                  routeToken: routeToken,
                  travelMode: travelMode,
                )
              : null,
          routingOptions: !useRouteToken
              ? RoutingOptions(
                  travelMode: travelMode,
                  alternateRoutesStrategy:
                      NavigationAlternateRoutesStrategy.one,
                )
              : null,
        ),
      );

      if (status != NavigationRouteStatus.statusOk) {
        if (!mounted) return;
        setState(() {
          _message =
              status == NavigationRouteStatus.locationUnavailable ||
                  status == NavigationRouteStatus.locationUnknown
              ? 'Waiting for a GPS fix. Try again once your location is available.'
              : 'Route unavailable: ${status.name}';
        });
        return;
      }

      _driveEngine.setRoute(selectedRoute);
      unawaited(
        _usageTelemetry.record(
          'google_navigation_destination',
          units: _routeStops.length + 1,
        ),
      );
      await GoogleMapsNavigator.startGuidance();
      await _navigationController?.setNavigationUIEnabled(true);
      final navigationController = _navigationController;
      if (navigationController != null) {
        await _applyWaybiNavigationChrome(navigationController);
        await _followNavigationCamera(navigationController);
        await navigationController.setReportIncidentButtonEnabled(false);
      }
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
        _activeDestinationPlace = destinationPlace;
        _arrivalMode = false;
        _arrivalPrefetching = false;
        _arrivalPrefetched = false;
        _arrivalParkingPlaces = const [];
        _arrivalPlaceDetails = null;
        _offlineCorridorReady = false;
      });
      _beginJourney(poi);
      await _startSystemNavigation();
      unawaited(_cacheNavigationCorridor(force: true));
      final activeNavigationController = _navigationController;
      if (activeNavigationController != null) {
        unawaited(_syncDestinationMarker(activeNavigationController));
      }
      _queueMapRefresh();
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
        final navigationController = _navigationController;
        if (navigationController != null && _destinationMarker != null) {
          try {
            await navigationController.removeMarkers([_destinationMarker!]);
          } catch (_) {}
          _destinationMarker = null;
        }
        await _driveEngine.stop();
        if (_appForeground &&
            _mapProvider == MapProvider.independent &&
            _layers.traffic) {
          unawaited(_driveEngine.startTrafficFlowRefresh(force: true));
        }
        await navigationController?.setNavigationUIEnabled(false);
      }
      if (_account.profile != null &&
          route?.provider != 'independent' &&
          route != null &&
          route.points.isNotEmpty) {
        final destination = route.points.last;
        unawaited(
          _account
              .recordRoute(
                destinationName: _destinationTitle,
                latitude: destination.latitude,
                longitude: destination.longitude,
                mode: _selectedMode.apiValue,
                distanceMeters:
                    summary?.distanceMeters.round() ?? route.distanceMeters,
                durationSeconds:
                    summary?.elapsed.inSeconds ?? route.durationSeconds,
              )
              .catchError((_) {}),
        );
      }
      if (!mounted) return;
      ++_arrivalRequest;
      setState(() {
        _guidanceRunning = false;

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
            _selectedParking != null &&
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
      if (_mapProvider == MapProvider.independent) {
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
      _lastBrowseCamera =
          await _browseController?.getCameraPosition() ?? _lastBrowseCamera;
      if (!await _ensureNavigationSession()) return;
      if (mounted) setState(() {});
      await WidgetsBinding.instance.endOfFrame;
      final hasFix = await _driveEngine.waitForRoadSnappedLocation(
        timeout: const Duration(seconds: 6),
      );
      if (!hasFix && mounted) {
        setState(
          () => _message = _text(
            'Drive Mode is running while GPS settles. Keep the phone near a clear view of the sky.',
            '驾驶模式已启动，正在等待 GPS 稳定，请保持手机能够正常接收定位信号。',
          ),
        );
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
    if (mounted &&
        _appForeground &&
        _mapProvider == MapProvider.independent &&
        _layers.traffic) {
      unawaited(_driveEngine.startTrafficFlowRefresh(force: true));
    }
    if (mounted) unawaited(_startTracking());
    if (_navigationSessionInitialized) {
      await GoogleMapsNavigator.cleanup();
      _navigationSessionInitialized = false;
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadPlaceDetails(PointOfInterest poi) async {
    final request = ++_placeDetailsRequest;
    if (poi.placeID.isEmpty) {
      if (mounted) {
        setState(() {
          _placeDetails = null;
          _placeDetailsLoading = false;
          _placeDetailsError = null;
        });
      }
      return;
    }
    setState(() {
      _placeDetails = null;
      _placeDetailsLoading = true;
      _placeDetailsError = null;
    });
    try {
      final details = await _placeDetailsRepository.fetch(
        poi.placeID,
        language: _appLanguage,
      );
      if (!mounted || request != _placeDetailsRequest) return;
      setState(() {
        _placeDetails = details;
        _placeDetailsLoading = false;
      });
    } catch (_) {
      if (!mounted || request != _placeDetailsRequest) return;
      setState(() {
        _placeDetailsLoading = false;
        _placeDetailsError = 'More place details are temporarily unavailable.';
      });
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
      if (!mounted ||
          request != _placeDetailsRequest ||
          _mapProvider != MapProvider.independent) {
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

  void _onPoiClicked(PointOfInterest poi) {
    if (_driveEngine.active || _transitTripRunning) return;
    _selectPlace(
      PlaceSummary(
        name: poi.name,
        location: GeoPoint(poi.latLng.latitude, poi.latLng.longitude),
        reference: poi.placeID.isEmpty
            ? null
            : ProviderReference('google', poi.placeID),
      ),
      SelectionSource.map,
    );
  }

  void _selectPlace(
    PlaceSummary place,
    SelectionSource source, {
    PlaceDetails? seedDetails,
  }) {
    if (_driveEngine.active || _transitTripRunning) return;
    _externalPreview = null;
    if (!const ProviderPolicy(MapProvider.google).canDisplay(place.reference) &&
        _mapProvider == MapProvider.google) {
      setState(() => _message = 'This place cannot be shown on Google Maps.');
      return;
    }
    if (_mapProvider == MapProvider.independent &&
        !const ProviderPolicy(MapProvider.independent)
            .canDisplay(place.reference)) {
      setState(() => _message = 'This place belongs to another map provider.');
      return;
    }
    setState(() {
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
      _placeQuickRouteLoading = false;
      _placeQuickRouteLoadingKey = null;
      _message = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusSelectedPlace();
      unawaited(_loadPlaceQuickRoute(place));
    });
    if (place.reference?.provider == 'google') {
      unawaited(_loadPlaceDetails(_selectedPoi!));
    } else if (_mapProvider == MapProvider.independent && seedDetails == null) {
      unawaited(_loadIndependentPlaceDetails(place));
    } else {
      _placeDetailsRequest++;
      _placeDetails = seedDetails;
      _placeDetailsLoading = false;
      _placeDetailsError = null;
    }
    if (_mapProvider == MapProvider.independent &&
        (source == SelectionSource.map ||
            source == SelectionSource.longPress) &&
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
      if (!mounted ||
          resolved == null ||
          _mapProvider != MapProvider.independent ||
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

  Future<void> _syncDestinationMarker(
    GoogleMapViewController controller,
  ) async {
    try {
      if (_destinationMarker != null) {
        await controller.removeMarkers([_destinationMarker!]);
        _destinationMarker = null;
      }
      final route = _driveEngine.active
          ? _activeNavigationRoute
          : _selectedRoute;
      if (route == null || route.points.isEmpty) return;
      try {
        await MapSymbols.ensureRegistered();
      } catch (_) {}
      final destination = route.points.last;
      final markers = await controller.addMarkers([
        MarkerOptions(
          position: LatLng(
            latitude: destination.latitude,
            longitude: destination.longitude,
          ),
          icon: MapSymbols.finish ?? ImageDescriptor.defaultImage,
          zIndex: 90,
          flat: false,
          anchor: const MarkerAnchor(u: 0.32, v: 1.0),
          consumeTapEvents: false,
          infoWindow: InfoWindow(
            title: _destinationTitle,
            snippet: _text('Finish', '终点'),
          ),
        ),
      ]);
      _destinationMarker = markers.whereType<Marker>().firstOrNull;
    } catch (_) {
      _destinationMarker = null;
    }
  }

  Future<void> _syncCameraMarkers() async {
    if (_markerSyncing) return;
    final controller = _driveEngine.active
        ? _navigationController
        : _browseController;
    if (controller == null) return;
    _markerSyncing = true;
    final reportIds = _communityRoadEvents.map((event) => event.id).join(',');
    final signature =
        '${_driveEngine.cameras.length}:${_driveEngine.routeCameras.map((match) => match.camera.id).join(',')}:$reportIds:${_layers.markerSignature}:${_driveEngine.trafficFlowRevision}';
    try {
      try {
        await MapSymbols.ensureRegistered();
      } catch (_) {
        /* Default pins remain visible. */
      }
      if (_cameraMarkers.isNotEmpty) {
        await controller.removeMarkers(_cameraMarkers);
      }
      if (_roadEventMarkers.isNotEmpty) {
        await controller.removeMarkers(_roadEventMarkers);
      }
      final onRoute = _driveEngine.routeCameras
          .map((match) => match.camera.id)
          .toSet();
      final options = [
        for (final camera in _driveEngine.cameras)
          if (_layers.shows(camera))
            MarkerOptions(
              position: LatLng(
                latitude: camera.latitude,
                longitude: camera.longitude,
              ),
              icon:
                  MapSymbols.camera(
                    CameraKindLabel.fromCamera(camera),
                    onRoute: onRoute.contains(camera.id),
                  ) ??
                  ImageDescriptor.defaultImage,
              zIndex: onRoute.contains(camera.id) ? 40 : 12,
              infoWindow: InfoWindow(
                title:
                    '${CameraKindLabel.fromCamera(camera).localizedLabel(_appLanguage)} · ${camera.location}',
                snippet:
                    '${camera.region} · ${camera.suburb} · GPS ${camera.latitude.toStringAsFixed(5)}, ${camera.longitude.toStringAsFixed(5)}',
              ),
            ),
      ];
      _cameraMarkers = options.isEmpty
          ? []
          : (await controller.addMarkers(options)).whereType<Marker>().toList();
      final roadEventOptions = [
        for (final event in _communityRoadEvents)
          MarkerOptions(
            position: LatLng(
              latitude: event.location.latitude,
              longitude: event.location.longitude,
            ),
            icon:
                MapSymbols.roadEvent(event.type) ??
                ImageDescriptor.defaultImage,
            zIndex: 35,
            infoWindow: InfoWindow(
              title: _roadEventLabel(event.type),
              snippet: () {
                final reporter =
                    event.metadata['reporterName']?.toString() ??
                    _text('Waybi driver', 'Waybi 用户');
                final time = _relativeTime(
                  DateTime.tryParse(
                        event.metadata['reportedAt']?.toString() ?? '',
                      ) ??
                      event.source.updatedAt,
                );
                final remaining = _remainingTime(event.validUntil);
                return '$reporter · $time · $remaining';
              }(),
            ),
          ),
      ];
      _roadEventMarkers = roadEventOptions.isEmpty
          ? []
          : (await controller.addMarkers(roadEventOptions))
                .whereType<Marker>()
                .toList();
      _markerSignature = signature;
    } catch (_) {
      _markerSignature = signature;
    } finally {
      _markerSyncing = false;
      final latestReportIds = _communityRoadEvents
          .map((event) => event.id)
          .join(',');
      final latest =
          '${_driveEngine.cameras.length}:${_driveEngine.routeCameras.map((match) => match.camera.id).join(',')}:$latestReportIds:${_layers.markerSignature}';
      if (mounted && _markerSignature != latest) {
        Future<void>.delayed(
          const Duration(milliseconds: 200),
          _syncCameraMarkers,
        );
      }
    }
  }

  Future<void> _syncCarMarker(
    GoogleMapViewController controller,
    LatLng location, {
    double? headingOverride,
  }) async {
    if (_driveEngine.active) return;
    try {
      await MapSymbols.ensureRegistered();
      final heading = headingOverride ?? _travelHeading ?? _deviceHeading ?? 0;
      final previous = _smoothedLocationHeading;
      final delta = previous == null
          ? 0.0
          : (heading - previous + 540) % 360 - 180;
      final headingSmoothing = _driveEngine.active ? 0.62 : 0.35;
      _smoothedLocationHeading = previous == null
          ? heading
          : (previous + delta * headingSmoothing + 360) % 360;
      final options = MarkerOptions(
        position: location,
        icon:
            MapSymbols.location(_locationMarker) ??
            MapSymbols.car ??
            ImageDescriptor.defaultImage,
        zIndex: 80,
        flat: true,
        rotation: _smoothedLocationHeading!,
        anchor: const MarkerAnchor(u: 0.5, v: 0.5),
      );
      if (_carMarker == null) {
        _carMarker = (await controller.addMarkers([options])).first;
      } else {
        _carMarker = (await controller.updateMarkers([
          _carMarker!.copyWith(options: options),
        ])).first;
      }
      final accuracy = _gpsAccuracy;
      if (!_guidanceRunning && accuracy != null && accuracy > 0) {
        final halo = CircleOptions(
          position: location,
          radius: accuracy.clamp(5, 150).toDouble(),
          strokeWidth: 1,
          strokeColor: const Color(0x88729F36),
          fillColor: const Color(0x22729F36),
          zIndex: 1,
        );
        if (_accuracyCircle == null) {
          _accuracyCircle = (await controller.addCircles([halo])).first;
        } else {
          _accuracyCircle = (await controller.updateCircles([
            _accuracyCircle!.copyWith(options: halo),
          ])).first;
        }
      } else if (_accuracyCircle != null) {
        try {
          await controller.removeCircles([_accuracyCircle!]);
        } catch (_) {}
        _accuracyCircle = null;
      }
    } catch (_) {
      /* The native location indicator remains the fallback. */
    }
  }

  Future<void> _setCarMarker(bool value) async {
    setState(() => _useCarMarker = value);
    final controller = _driveEngine.active
        ? _navigationController
        : _browseController;
    if (controller != null) {
      await controller.setMyLocationEnabled(_driveEngine.active || !value);
      if ((!value || _driveEngine.active) && _carMarker != null) {
        try {
          await controller.removeMarkers([_carMarker!]);
        } catch (_) {}
        _carMarker = null;
      } else if (value && !_driveEngine.active && _gpsLocation != null) {
        final markerLocation =
            (_driveEngine.active ? _driveEngine.snappedLocation : null) ??
            _gpsLocation!;
        await _syncCarMarker(
          controller,
          markerLocation,
          headingOverride: _driveEngine.active
              ? _driveEngine.snappedHeadingDegrees
              : null,
        );
      }
      if ((!value || _guidanceRunning) && _accuracyCircle != null) {
        try {
          await controller.removeCircles([_accuracyCircle!]);
        } catch (_) {}
        _accuracyCircle = null;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('waybi.map.car_marker', value);
    _queueMapRefresh();
  }

  Future<void> _setLocationMarker(LocationMarkerStyle style) async {
    setState(() => _locationMarker = style);
    await _setCarMarker(style != LocationMarkerStyle.classic);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('waybi.map.location_marker', style.name);
    if (_carMarker != null) {
      final controller = _driveEngine.active
          ? _navigationController
          : _browseController;
      if (controller != null) {
        try {
          await controller.removeMarkers([_carMarker!]);
        } catch (_) {}
        _carMarker = null;
      }
    }
    _queueMapRefresh();
  }

  Future<void> _setMapProvider(MapProvider provider) {
    _requestedMapProvider = provider;
    _providerSwitchQueue = _providerSwitchQueue
        .then((_) {
          if (_requestedMapProvider != provider) return Future<void>.value();
          return _applyMapProvider(provider);
        })
        .catchError((Object error) {
          if (mounted) {
            setState(() => _message = 'Could not switch maps: $error');
          }
        });
    return _providerSwitchQueue;
  }

  Future<void> _applyMapProvider(MapProvider provider) async {
    if (provider == _mapProvider) return;
    if (_guidanceRunning || _driveEngine.active || _transitTripRunning) {
      setState(
        () =>
            _message = 'End the current trip before changing the map provider.',
      );
      return;
    }
    final googleCamera = await _browseController?.getCameraPosition();
    if (!mounted) return;
    if (googleCamera != null) {
      _viewport = MapViewportState(
        center: GeoPoint(
          googleCamera.target.latitude,
          googleCamera.target.longitude,
        ),
        zoom: googleCamera.zoom,
        bearing: googleCamera.bearing,
        pitch: googleCamera.tilt,
      );
    } else if (_browseRenderer != null) {
      _viewport = _browseRenderer!.viewport;
    }
    _browseController = null;
    _browseRenderer = null;
    _lastBrowseCamera = null;
    _cameraMarkers = [];
    _roadEventMarkers = [];
    _destinationMarker = null;
    _carMarker = null;
    _accuracyCircle = null;
    _exploreMarkers = [];
    _exploreMarkerPlaces.clear();
    _exploreResults = const [];
    _guestRecent.clear();
    _showSearchArea = false;
    _areaSearchAnchor = _viewport.center;
    _radarPolygons = [];
    _markerSignature = '';
    final wasPreviewing = _journeyPhase == JourneyPhase.routePreview;
    final selected = _selectedPlace;
    _routePlan = null;
    _selectedRouteId = null;
    _driveEngine.setRoute(null);
    ++_routeRequest;
    final needsNewPlaceContent =
        selected != null &&
        (selected.originMap != provider &&
                selected.place.kind != PlaceKind.coordinate ||
            !ProviderPolicy(provider).canDisplay(selected.place.reference));
    if (needsNewPlaceContent) {
      _selectedPlace = SelectedPlace(
        PlaceSummary(
          name:
              '${selected.place.location.latitude.toStringAsFixed(5)}, '
              '${selected.place.location.longitude.toStringAsFixed(5)}',
          location: selected.place.location,
          kind: PlaceKind.coordinate,
        ),
        selected.source,
        originMap: provider,
      );
      _placeDetails = null;
      _placeDetailsLoading = false;
      _placeDetailsError = null;
    }
    setState(() {
      _mapProvider = provider;
      _journeyPhase = selected == null
          ? JourneyPhase.idle
          : JourneyPhase.placeSelected;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('waybi.map.provider', provider.name);
    if (provider == MapProvider.google) _restoreGoogleRecent(prefs);
    if (provider == MapProvider.independent && _layers.traffic) {
      unawaited(_driveEngine.startTrafficFlowRefresh(force: true));
    } else if (!_driveEngine.active) {
      _driveEngine.stopTrafficFlowRefresh();
    }
    if (wasPreviewing && _selectedPoi != null) {
      unawaited(_loadRoutePreview(_selectedPoi!));
    }
    if (provider == MapProvider.independent && needsNewPlaceContent) {
      unawaited(
        _enrichIndependentSelection(_selectedPlace!.place, selected.source),
      );
    }
  }

  Future<void> _applyMapLayers(GoogleMapViewController controller) async {
    final dark = Theme.of(context).brightness == Brightness.dark;
    await controller.settings.setTrafficEnabled(_layers.traffic);
    final style = _driveEngine.active && _layers.style == BaseMapStyle.terrain
        ? BaseMapStyle.standard
        : _layers.style;

    // Use the Google Maps SDK's native light/dark schemes instead of a
    // hand-authored legacy JSON style. This keeps roads, POIs, labels and
    // traffic contrast consistent with the Google Maps app and allows the
    // platform view to switch appearance without being recreated.
    if (_mapId.isEmpty) {
      await controller.setMapStyle(null);
    }
    await controller.setMapColorScheme(
      dark ? MapColorScheme.dark : MapColorScheme.light,
    );
    if (controller is GoogleNavigationViewController) {
      await controller.setForceNightMode(
        dark
            ? NavigationForceNightMode.forceNight
            : NavigationForceNightMode.forceDay,
      );
    }

    await controller.setMapType(
      mapType: switch (style) {
        BaseMapStyle.standard => MapType.normal,
        BaseMapStyle.satellite => MapType.satellite,
        BaseMapStyle.terrain => MapType.terrain,
        BaseMapStyle.hybrid => MapType.hybrid,
      },
    );
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
      prefs.setString('waybi.layers.style', value.style.name),
    ]);
    if (trafficJustEnabled && _mapProvider == MapProvider.independent) {
      await _driveEngine.startTrafficFlowRefresh(force: true);
    } else if (!value.traffic && !_driveEngine.active) {
      _driveEngine.stopTrafficFlowRefresh();
    }
    final controller = _driveEngine.active
        ? _navigationController
        : _browseController;
    if (controller != null) {
      await _applyMapLayers(controller);
      unawaited(_syncCameraMarkers());
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

    final controller = _navigationController;
    final size = MediaQuery.sizeOf(context);
    final sheetHeight = (size.height * .40).clamp(300.0, 390.0);
    final bottomInset = sheetHeight - 14;

    if (_mapProvider == MapProvider.independent &&
        _browseRenderer is RouteMapRenderer) {
      _following = false;
      await (_browseRenderer as RouteMapRenderer).fitRoute(
        route.points,
        bottomInset: bottomInset,
      );
    }
    if (controller != null) {
      _following = false;
      await controller.setPadding(EdgeInsets.fromLTRB(24, 82, 24, bottomInset));
      await controller.showRouteOverview();
      await Future<void>.delayed(const Duration(milliseconds: 160));
      await controller.showRouteOverview();
    }

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

    if (controller != null) {
      await controller.setPadding(EdgeInsets.zero);
      if (mounted) _recenter();
    }
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

  void _showAlongRouteSearch() {
    if (_independentNavigation.active) {
      unawaited(_searchIndependentStop());
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          18,
          16,
          MediaQuery.viewInsetsOf(sheetContext).bottom + 18,
        ),
        child: ExploreSearch(
          currentLocation: _gpsLocation,
          recent: _recentDestinations,
          onSelected: (selection) {
            Navigator.of(sheetContext).pop();
            unawaited(_addAlongRouteStop(selection));
          },
        ),
      ),
    );
  }

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
          recent: const [],
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

  Future<void> _addAlongRouteStop(DestinationSuggestion stop) async {
    final route = _activeNavigationRoute;
    final origin = _driveEngine.snappedLocation ?? _gpsLocation;
    if (route == null || route.points.isEmpty || origin == null) return;
    final destination = route.points.last;
    try {
      final plan = await _routeRepository.fetch(
        origin: origin,
        destination: LatLng(
          latitude: destination.latitude,
          longitude: destination.longitude,
        ),
        stops: [stop.location],
      );
      final next = plan.forMode(_selectedMode).firstOrNull;
      if (next == null) throw StateError('No route via this stop');
      final status = await GoogleMapsNavigator.setDestinations(
        Destinations(
          waypoints: [
            NavigationWaypoint.withLatLngTarget(
              title: stop.label,
              target: stop.location,
            ),
            NavigationWaypoint.withLatLngTarget(
              title: _destinationTitle,
              target: LatLng(
                latitude: destination.latitude,
                longitude: destination.longitude,
              ),
            ),
          ],
          displayOptions: NavigationDisplayOptions(
            showDestinationMarkers: false,
          ),
          routingOptions: RoutingOptions(
            travelMode: _nativeTravelMode!,
            alternateRoutesStrategy: NavigationAlternateRoutesStrategy.one,
          ),
        ),
      );
      if (status != NavigationRouteStatus.statusOk) {
        throw StateError(status.name);
      }
      unawaited(
        _usageTelemetry.record('google_navigation_destination', units: 2),
      );
      _driveEngine.setRoute(next);
      setState(() => _activeNavigationRoute = next);
    } catch (error) {
      if (mounted) setState(() => _message = 'Could not add stop: $error');
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

    final plan = await _routeRepository.fetch(
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

  Future<TripsSnapshot> _loadTripsSnapshot() async {
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
          createdAt: DateTime.tryParse(record['createdAt']?.toString() ?? ''),
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

    return TripsSnapshot(
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
                  if (_mapProvider == MapProvider.independent &&
                      id.isNotEmpty &&
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
                      reference: id.isNotEmpty && !id.startsWith('coords:')
                          ? ProviderReference('google', id)
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
                        if (_mapProvider == MapProvider.independent &&
                            data['provider'] != 'independent') {
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
    final SearchProvider provider = _mapProvider == MapProvider.independent
        ? _independentSearch
        : _workerSearch;
    return provider.search(query, proximity: point, language: _appLanguage);
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
    final controller = _browseController;
    if (controller != null) {
      unawaited(
        controller.animateCamera(
          CameraUpdate.newLatLng(
            LatLng(
              latitude: place.location.latitude,
              longitude: place.location.longitude,
            ),
          ),
        ),
      );
    }
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
    final SearchProvider provider = _mapProvider == MapProvider.independent
        ? _independentSearch
        : _workerSearch;
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
    final controller = _browseController;
    if (controller != null) {
      unawaited(
        controller.animateCamera(
          CameraUpdate.newLatLng(
            LatLng(
              latitude: place.location.latitude,
              longitude: place.location.longitude,
            ),
          ),
        ),
      );
    }
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

  Future<void> _syncExploreMarkers() async {
    final controller = _browseController;
    if (controller == null || _mapProvider != MapProvider.google) return;
    try {
      if (_exploreMarkers.isNotEmpty) {
        await controller.removeMarkers(_exploreMarkers);
      }
      _exploreMarkers = [];
      _exploreMarkerPlaces.clear();
      if (_exploreResults.isEmpty) return;
      final markers = await controller.addMarkers([
        for (final place in _exploreResults)
          MarkerOptions(
            position: LatLng(
              latitude: place.location.latitude,
              longitude: place.location.longitude,
            ),
            zIndex: 30,
            consumeTapEvents: true,
            infoWindow: InfoWindow(title: place.name, snippet: place.address),
          ),
      ]);
      _exploreMarkers = markers.whereType<Marker>().toList(growable: false);
      for (
        var index = 0;
        index < _exploreMarkers.length && index < _exploreResults.length;
        index++
      ) {
        _exploreMarkerPlaces[_exploreMarkers[index].markerId] =
            _exploreResults[index];
      }
    } catch (_) {
      // The map may be recreated while changing providers.
    }
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
          mapCompatible: _mapProvider == MapProvider.independent,
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
      seedDetails:
          _mapProvider == MapProvider.independent &&
              place.photoUrl?.isNotEmpty == true
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
                Icons.explore_outlined,
                _text('Explore', '探索'),
                () => unawaited(_showExplore()),
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

  Future<void> _onMapViewCreated(GoogleMapViewController controller) async {
    _browseController = controller;
    _cameraMarkers = [];
    _roadEventMarkers = [];
    _destinationMarker = null;
    _carMarker = null;
    _accuracyCircle = null;
    _markerSignature = '';
    _navigationController = null;
    _radarPolygons = [];
    await _applyMapLayers(controller);
    await controller.settings.setCompassEnabled(true);
    await controller.settings.setRotateGesturesEnabled(true);
    await controller.settings.setTiltGesturesEnabled(true);
    await controller.settings.setScrollGesturesDuringRotateOrZoomEnabled(true);
    if (await Permission.locationWhenInUse.isGranted) {
      await controller.setMyLocationEnabled(
        _driveEngine.active || !_useCarMarker,
      );
    }
    await controller.settings.setMyLocationButtonEnabled(false);
    await controller.setRecenterButtonEnabled(false);
    await _syncCameraMarkers();
    await _syncExploreMarkers();
    _queueMapRefresh();
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
    if (_mapProvider == MapProvider.independent && mounted) {
      setState(() {});
      if (_following) _queueMapRefresh();
    }
    final controller = _navigationController;
    if (controller != null && _guidanceRunning) {
      unawaited(
        controller
            .setPadding(
              EdgeInsets.fromLTRB(
                16,
                _navigationTopInset,
                16,
                _navigationBottomInset,
              ),
            )
            .catchError((Object error) {
              debugPrint('Navigation layout update: $error');
            }),
      );
    }
  }

  Future<void> _applyWaybiNavigationChrome(
    GoogleNavigationViewController controller,
  ) async {
    await controller.setMyLocationEnabled(
      _driveEngine.active || !_useCarMarker,
    );
    await controller.setNavigationHeaderEnabled(false);
    await controller.setNavigationFooterEnabled(false);
    await controller.settings.setMyLocationButtonEnabled(false);
    await controller.setRecenterButtonEnabled(false);
    await controller.setReportIncidentButtonEnabled(false);
    // ignore: experimental_member_use
    await controller.setNavigationTripProgressBarEnabled(false);
    await controller.setSpeedometerEnabled(false);
    await controller.setSpeedLimitIconEnabled(false);
  }

  Future<void> _onNavigationViewCreated(
    GoogleNavigationViewController controller,
  ) async {
    await controller.setMyLocationEnabled(
      _driveEngine.active || !_useCarMarker,
    );
    await _applyMapLayers(controller);
    await controller.settings.setCompassEnabled(false);
    await controller.settings.setRotateGesturesEnabled(true);
    await controller.settings.setTiltGesturesEnabled(true);
    await controller.settings.setScrollGesturesDuringRotateOrZoomEnabled(true);
    _navigationController = controller;
    _browseController = null;
    _cameraMarkers = [];
    _roadEventMarkers = [];
    _destinationMarker = null;
    _carMarker = null;
    _accuracyCircle = null;
    _markerSignature = '';
    _radarPolygons = [];
    await controller.setNavigationUIEnabled(_guidanceRunning);
    await _applyWaybiNavigationChrome(controller);
    if (_driveEngine.snappedLocation != null) {
      await _followNavigationCamera(controller);
      await controller.setReportIncidentButtonEnabled(false);
    }
    await controller.setTrafficIncidentCardsEnabled(true);
    await controller.setTrafficPromptsEnabled(true);
    await controller.setPadding(
      EdgeInsets.fromLTRB(
        16,
        _guidanceRunning ? _navigationTopInset : 125,
        16,
        _navigationBottomInset,
      ),
    );
    // The SDK owns the current route and its live traffic colors. A preview
    // polyline here would conceal congestion and remain stale after reroutes.
    await _syncDestinationMarker(controller);
    await _syncCameraMarkers();
    _queueMapRefresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!_settingsLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final cachedGoogleGuidance = _offlineGoogleGuidance();
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
            child: _driveEngine.active && _mapProvider == MapProvider.google
                ? GoogleMapsNavigationView(
                    key: ValueKey('navigation-view-$_appLanguage'),
                    onViewCreated: _onNavigationViewCreated,
                    mapId: _mapId.isEmpty ? null : _mapId,
                    initialCameraPosition:
                        _lastBrowseCamera ??
                        CameraPosition(
                          target: _gpsLocation ?? _auckland,
                          zoom: 16,
                        ),
                    onCameraMoveStarted: (_, isGesture) {
                      if (isGesture) _markMapManuallyMoved();
                    },
                    initialNavigationUIEnabledPreference: _guidanceRunning
                        ? NavigationUIEnabledPreference.automatic
                        : NavigationUIEnabledPreference.disabled,
                    initialCompassEnabled: false,
                    initialRotateGesturesEnabled: true,
                    initialTiltGesturesEnabled: true,
                    initialScrollGesturesEnabledDuringRotateOrZoom: true,
                    initialForceNightMode:
                        Theme.of(context).brightness == Brightness.dark
                        ? NavigationForceNightMode.forceNight
                        : NavigationForceNightMode.forceDay,
                    onPoiClicked: _onPoiClicked,
                  )
                : _mapProvider == MapProvider.independent
                ? IndependentMapRenderer(
                    key: const ValueKey('independent-browse-view'),
                    initialViewport: _viewport,
                    layers: _layers,
                    locationMarker: _locationMarker,
                    locationEnabled: _gpsLocation != null,
                    following: _following,
                    navigating: _independentNavigation.active,
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
                    roadEvents: _communityRoadEvents,
                    onRoadEvent: (event) =>
                        unawaited(_showRoadEventDetails(event)),
                    trafficSegments: _driveEngine.trafficFlowSegments,
                    trafficTileOverlay: _driveEngine.trafficTileOverlay,
                    trafficFresh: _driveEngine.trafficFlowStatus == 'live',
                    routePaths: _visibleIndependentRoutePaths,
                    selectedPlace: _selectedPlace?.place,
                    explorePlaces: _exploreResults,
                    onExplorePlace: (place) =>
                        _exploreMarkerFocus.value = place,
                    onReady: (renderer) {
                      _browseRenderer = renderer;
                      if (_journeyPhase == JourneyPhase.routePreview) {
                        unawaited(_renderRoutePreview());
                      } else {
                        _queueMapRefresh();
                      }
                    },
                    onViewportChanged: (viewport) => _viewport = viewport,
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
                  )
                : GoogleMapRenderer(
                    key: ValueKey('browse-map-view-$_appLanguage'),
                    onControllerCreated: _onMapViewCreated,
                    onReady: (renderer) => _browseRenderer = renderer,
                    mapId: _mapId.isEmpty ? null : _mapId,
                    initialViewport: _lastBrowseCamera == null
                        ? _viewport.copyWith(
                            center: _gpsLocation == null
                                ? _viewport.center
                                : GeoPoint(
                                    _gpsLocation!.latitude,
                                    _gpsLocation!.longitude,
                                  ),
                          )
                        : MapViewportState(
                            center: GeoPoint(
                              _lastBrowseCamera!.target.latitude,
                              _lastBrowseCamera!.target.longitude,
                            ),
                            zoom: _lastBrowseCamera!.zoom,
                            bearing: _lastBrowseCamera!.bearing,
                            pitch: _lastBrowseCamera!.tilt,
                          ),
                    onViewportChanged: (viewport) {
                      _viewport = viewport;
                      _lastBrowseCamera = CameraPosition(
                        target: LatLng(
                          latitude: viewport.center.latitude,
                          longitude: viewport.center.longitude,
                        ),
                        zoom: viewport.zoom,
                        bearing: viewport.bearing,
                        tilt: viewport.pitch,
                      );
                    },
                    onUserPan: () => _markMapManuallyMoved(searchArea: true),
                    onMapPlace: (place) => _selectPlace(
                      place,
                      place.kind == PlaceKind.coordinate
                          ? SelectionSource.longPress
                          : SelectionSource.map,
                    ),
                    onExploreMarker: (markerId) {
                      final place = _exploreMarkerPlaces[markerId];
                      if (place != null) {
                        _exploreMarkerFocus.value = place;
                      }
                    },
                    onBlankTap: () {
                      if (_selectedPoi != null || _routePlan != null) {
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
          if (_driveEngine.active &&
              _mapProvider == MapProvider.google &&
              _selectedPoi == null &&
              !_transitTripRunning)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _driveEngine,
                builder: (context, _) => _guidanceRunning
                    ? NavigationOverlay(
                        systemStatus: SystemNavigationStatus(
                          navigation: _systemNavigation,
                          language: _appLanguage,
                        ),
                        engine: _driveEngine,
                        guidance: cachedGoogleGuidance,
                        onTopInsetChanged: _updateNavigationTopInset,
                        language: _appLanguage,
                        destinationTitle: _destinationTitle,
                        gpsAccuracy: _gpsAccuracy,
                        voiceEnabled: _voiceEnabled,
                        lanesEnabled: _lanesEnabled,
                        onEnd: () => unawaited(_stopNavigation()),
                        onRecenter: _recenter,
                        onOverview: _showRouteOverview,
                        following: _following,
                        overviewMode: _routeOverviewActive,
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
                            _offlineCorridorReady,
                        usingOfflineGuidance: cachedGoogleGuidance != null,
                        offlineCachedAt: _lastCorridorCacheAt,
                      )
                    : DriveHud(
                        engine: _driveEngine,
                        onStop: () => unawaited(_stopDriveMode()),
                      ),
              ),
            ),
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
          if (_mapProvider == MapProvider.independent &&
              _driveEngine.active &&
              !_guidanceRunning)
            Positioned.fill(
              child: DriveHud(
                engine: _driveEngine,
                onStop: () => unawaited(_stopDriveMode()),
              ),
            ),
          if (_message != null)
            _TransientWaybiBanner(
              key: ValueKey(_message),
              message: _message!,
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
                    navigationAvailable: _selectedPlace!.place.location.isValid,
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
                canRequestTransit: _mapProvider == MapProvider.independent,
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
                        ? _text('Starting…', '正在开始…')
                        : _selectedMode == WaybiTravelMode.transit
                        ? _text('Start trip', '开始行程')
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
