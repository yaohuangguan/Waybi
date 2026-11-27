import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../data/http_guard.dart';
import '../domain/geo_math.dart';
import '../domain/map_provider.dart';
import '../domain/route_geometry.dart';
import '../domain/route_option.dart';
import '../domain/road_event.dart';
import '../domain/route_road_events.dart';
import '../domain/transit_lane.dart';
import '../drive/drive_engine.dart';
import '../drive/navigation_language.dart';
import '../drive/reroute_scheduler.dart';
import '../drive/route_camera_matcher.dart';
import '../drive/route_display.dart';
import 'provider_contracts.dart';

typedef IndependentReroute = Future<RouteOption> Function(
  GeoPoint origin,
  RouteOption previous,
  List<GeoPoint> remainingStops,
);

class IndependentNavigationEngine extends ChangeNotifier
    implements NavigationEngine<RouteOption> {
  IndependentNavigationEngine(
    this.drive, {
    this.reroute,
    DateTime Function()? clock,
    math.Random? random,
  }) : _clock = clock ?? DateTime.now,
       _scheduler = RerouteScheduler(random: random);
  final DriveEngine drive;
  final IndependentReroute? reroute;
  final DateTime Function() _clock;

  /// How long navigation waits for a replacement route. The routing provider
  /// aborts its HTTP request just before this, so requests never overlap.
  static const rerouteTimeout = Duration(seconds: 12);

  /// Off-route once the raw fix is this far from the route.
  double get _offRouteMeters =>
      math.max(40, drive.locationAccuracyMeters * 1.8);

  /// A replacement must fit clearly inside the off-route corridor, or a car
  /// 40–50 m from the road (a car park) would reroute forever.
  static double acceptanceMeters(double accuracyMeters) =>
      math.max(40, accuracyMeters * 1.8) * .75;

  final RerouteScheduler _scheduler;
  final RouteCameraMatcher _matcher = const RouteCameraMatcher();
  RouteOption? _route;
  RouteStepInfo? _nextStep;
  List<double> _stepPositions = const [];
  List<(GeoPoint, double)> _stops = const [];
  double _geometryMeters = 0;
  double _distanceToStep = 0;
  double _remainingMeters = 0;
  double _alongMeters = 0;
  int _remainingSeconds = 0;
  final Set<String> _spokenSteps = {};
  int _nextIndex = -1;
  int _session = 0;
  int _lastLocationRevision = -1;
  int _offRouteFixes = 0;
  int _arrivalFixes = 0;
  ({GeoPoint point, DateTime since})? _stationary;
  DateTime? _offRouteSince;
  DateTime? _lastDeviationAt;
  final List<({GeoPoint point, DateTime time})> _directionHistory = [];

  bool get _usableGps {
    final position = drive.latestPosition;
    if (position == null || drive.locationIssue != null) return false;
    final age = _clock().difference(position.timestamp);
    return position.accuracy.isFinite &&
        position.accuracy > 0 &&
        position.accuracy <= 35 &&
        age >= const Duration(seconds: -5) &&
        age <= const Duration(seconds: 10);
  }

  DateTime? _lastClosureCheck;
  bool _closureWarning = false;
  bool transitRestrictionAhead = false;

  /// Called when shared road events refresh, including while GPS is stationary.
  /// Official closures ahead can trigger rerouting before the car goes off-route.
  void checkClosureUpdates() {
    final route = _route;
    final location = drive.latestPosition;
    if (route == null ||
        route.mode != WaybiTravelMode.drive ||
        location == null ||
        arrived ||
        rerouting ||
        reroute == null) {
      return;
    }
    final now = _clock();
    if (_lastClosureCheck != null &&
        now.difference(_lastClosureCheck!).inSeconds < 15) {
      return;
    }
    _lastClosureCheck = now;
    final matches = routeClosures(
      route,
      drive.roadEvents
          .where((event) => event.observation == RoadEventObservation.official)
          .toList(),
      progressMeters: _alongMeters,
      now: now,
    );
    final restricted = transitRoadBlocks(
      route,
      drive.transitLaneMatches,
      now,
      progressMeters: _alongMeters,
    );
    transitRestrictionAhead = restricted.isNotEmpty;
    if (matches.isEmpty && restricted.isEmpty) {
      _scheduler.clearClosure();
      if (_closureWarning) {
        _closureWarning = false;
        error = null;
        notifyListeners();
      }
      return;
    }
    if (!_usableGps) return;
    final fingerprint = matches
        .map((event) => '${event.id}:${event.validFrom}:${event.validUntil}')
        .followedBy(restricted.map((m) => m.lane.id))
        .join('|');
    // Bounded retries with back-off while every alternative is also closed.
    if (!_scheduler.canRerouteForClosure(now, fingerprint)) return;
    unawaited(
      _reroute(
        GeoPoint(location.latitude, location.longitude),
        closureFingerprint: fingerprint,
        transitRestriction: restricted.isNotEmpty,
      ),
    );
  }

  bool rerouting = false;
  bool offRoute = false;
  bool arrived = false;
  String? error;

  RouteOption? get route => _route;
  List<MapRoutePath> get displayPaths => _route == null
      ? const []
      : navigationRoutePaths(_route!.id, _route!.points, _alongMeters);
  RouteStepInfo? get nextStep => _nextStep;
  RouteStepInfo? get followingStep {
    final route = _route;
    final next = _nextStep;
    if (route == null ||
        next == null ||
        _distanceToStep > 200 ||
        offRoute ||
        arrived) {
      return null;
    }
    final index = route.steps.indexOf(next);
    if (index < 0 || index + 1 >= route.steps.length) return null;
    final following = route.steps[index + 1];
    if (following.maneuverType == 'arrive' ||
        _stepPositions[index + 1] - _stepPositions[index] > 350) {
      return null;
    }
    return following;
  }

  double get distanceToStepMeters => _distanceToStep;
  double get remainingDistanceMeters => _remainingMeters;
  int get remainingSeconds => _remainingSeconds;
  bool get active => _route != null && drive.active;
  List<GeoPoint> get remainingStops => _stops
      .where((stop) => stop.$2 > _alongMeters + 30)
      .map((stop) => stop.$1)
      .toList(growable: false);

  void _setRoute(RouteOption route, {bool preserveAlerts = false}) {
    _route = route;
    final geometry = RouteGeometry.of(route.points);
    _geometryMeters = geometry.totalMeters;
    // In route order: a road used twice keeps both maneuvers, and a stop is
    // never "visited" because the route passed near it earlier.
    _stepPositions = routeStepPositions(route, geometry);
    final stopPositions = routeStopPositions(
      route,
      geometry: geometry,
      stepPositions: _stepPositions,
    );
    _stops = [
      for (var i = 0; i < stopPositions.length; i++)
        (route.waypoints[i + 1], stopPositions[i]),
    ];
    _spokenSteps.clear();
    _nextStep = route.steps.firstOrNull;
    _distanceToStep = 0;
    _remainingMeters = route.distanceMeters.toDouble();
    _remainingSeconds = route.durationSeconds;
    _alongMeters = 0;
    _offRouteFixes = 0;
    _offRouteSince = null;
    _arrivalFixes = 0;
    _stationary = null;
    _lastDeviationAt = null;
    _directionHistory.clear();
    offRoute = false;
    arrived = false;
    drive.setRoute(route, preserveAlerts: preserveAlerts);
  }

  @override
  Future<void> start(RouteOption route, {Position? initialPosition}) async {
    if (route.provider != 'independent' ||
        route.points.length < 2 ||
        route.blockedForDriving) {
      throw StateError(
        'Independent navigation requires a valid Independent route',
      );
    }
    if (transitRoadBlocks(
      route,
      await drive.transitMatchesForRoute(route),
      _clock(),
    ).isNotEmpty) {
      throw StateError(
        'This route uses a bus-only road during restricted hours',
      );
    }
    ++_session;
    drive.removeListener(_onLocation);
    _lastLocationRevision = -1;
    _scheduler.reset();
    _lastClosureCheck = null;
    _closureWarning = false;
    transitRestrictionAhead = false;
    rerouting = false;
    error = null;
    // Geolocator keeps the settings of its first active stream. Restart an
    // existing Drive session before installing the route so Android uses the
    // single navigation service rather than retaining a second notification.
    if (drive.active) await drive.stop();
    _setRoute(route);
    try {
      await drive.startLocal(initialPosition: initialPosition);
      drive.addListener(_onLocation);
      if (drive.voiceEnabled) {
        final opening = routeStepInstruction(
          route.steps.firstOrNull,
          drive.navigationLanguage,
        );
        if (opening.trim().isNotEmpty) {
          unawaited(drive.speakMessage(opening));
        }
      }
      _onLocation();
    } catch (_) {
      _route = null;
      drive.setRoute(null);
      rethrow;
    }
    notifyListeners();
  }

  void _onLocation() {
    final route = _route;
    final location = drive.rawLocation ?? drive.snappedLocation;
    if (route == null ||
        !drive.active ||
        location == null ||
        _lastLocationRevision == drive.locationRevision ||
        arrived) {
      return;
    }
    _lastLocationRevision = drive.locationRevision;
    if (!_usableGps) {
      _offRouteFixes = 0;
      _offRouteSince = null;
      _lastDeviationAt = null;
      _directionHistory.clear();
      return;
    }
    final point = GeoPoint(location.latitude, location.longitude);
    final progress = drive.routeProgress;
    if (progress == null) return;
    final now = _clock();
    _scheduler.anchorIfUnset(point);
    final destination = route.points.last;
    final toDestination = distanceMeters(
      point.latitude,
      point.longitude,
      destination.latitude,
      destination.longitude,
    );
    if (_stationaryNearEnd(point, now, toDestination)) {
      _arrive();
      notifyListeners();
      return;
    }
    // In the last ~50 m (car parks, driveways, venue entrances) leaving the
    // road is expected; never start a reroute loop there.
    final finalApproach =
        toDestination <= 50 || _geometryMeters - _alongMeters <= 50;
    _directionHistory.removeWhere(
      (sample) => now.difference(sample.time) > const Duration(seconds: 6),
    );
    final previousPoint = _directionHistory.isEmpty
        ? null
        : _directionHistory.first.point;
    _directionHistory.add((point: point, time: now));
    if (_directionHistory.length > 64) _directionHistory.removeAt(0);
    final moved = previousPoint == null
        ? 0.0
        : distanceMeters(
            previousPoint.latitude,
            previousPoint.longitude,
            point.latitude,
            point.longitude,
          );
    // A course sensor alone cannot justify a U-turn: real displacement must
    // corroborate it, with several fresh fixes outside the accuracy corridor.
    final wrongDirection =
        drive.speedKph >= 25 &&
        drive.locationAccuracyMeters <= 20 &&
        drive.rawHeadingDegrees != null &&
        previousPoint != null &&
        moved >= math.max(15, drive.locationAccuracyMeters * 1.5) &&
        angleDifference(drive.rawHeadingDegrees!, progress.bearingDegrees) >
            135 &&
        angleDifference(
              bearingDegrees(
                previousPoint.latitude,
                previousPoint.longitude,
                point.latitude,
                point.longitude,
              ),
              progress.bearingDegrees,
            ) >
            135;
    offRoute =
        !finalApproach &&
        (progress.offsetMeters > _offRouteMeters || wrongDirection);
    if (offRoute) {
      if (_lastDeviationAt != null &&
          now.difference(_lastDeviationAt!) > const Duration(seconds: 10)) {
        _offRouteFixes = 0;
        _offRouteSince = null;
      }
      _lastDeviationAt = now;
      _offRouteSince ??= now;
      _offRouteFixes++;
      if (_offRouteFixes >= 3 &&
          now.difference(_offRouteSince!).inMilliseconds >= 4000 &&
          !rerouting &&
          reroute != null &&
          _scheduler.canRerouteForDeviation(
            now,
            at: point,
            speedKph: drive.speedKph,
          )) {
        unawaited(_reroute(point));
      }
      notifyListeners();
      return;
    }
    _offRouteFixes = 0;
    _offRouteSince = null;
    _lastDeviationAt = null;
    if (!_closureWarning) error = null;
    if (progress.offsetMeters <= _offRouteMeters) {
      _scheduler.confirmOnRoute(now);
      // Off the road near the end the uncommitted projection is meaningless.
      _alongMeters = math.max(_alongMeters, progress.alongMeters);
    }
    final fraction = _geometryMeters > 0
        ? (_alongMeters / _geometryMeters).clamp(0.0, 1.0)
        : 0.0;
    _remainingMeters = route.distanceMeters * (1 - fraction);
    // Each step keeps its own duration, so slow local roads do not share the
    // same ETA rate as motorway segments.
    var seconds = 0.0;
    for (var i = 0; i < route.steps.length; i++) {
      final begin = _stepPositions[i];
      final end = i + 1 < _stepPositions.length
          ? _stepPositions[i + 1]
          : _geometryMeters;
      if (end > _alongMeters && end > begin) {
        seconds +=
            route.steps[i].durationSeconds *
            ((end - math.max(begin, _alongMeters)) / (end - begin)).clamp(0, 1);
      }
    }
    _remainingSeconds = seconds > 0
        ? seconds.round()
        : (route.durationSeconds * (1 - fraction)).round();
    var nextIndex = -1;
    for (var i = 0; i < route.steps.length; i++) {
      if (_stepPositions[i] > _alongMeters + 8) {
        nextIndex = i;
        break;
      }
    }
    _nextStep = nextIndex >= 0
        ? route.steps[nextIndex]
        : route.steps.lastOrNull;
    _distanceToStep = nextIndex >= 0
        ? math.max(0, _stepPositions[nextIndex] - _alongMeters)
        : _remainingMeters;
    // Within the routed end's accuracy circle, nearly done and slowing.
    if (_remainingMeters <= 30 &&
        toDestination <= math.max(25, drive.locationAccuracyMeters * 1.5) &&
        drive.speedKph < 15) {
      _arrivalFixes++;
      if (_arrivalFixes >= 2) _arrive();
    } else {
      _arrivalFixes = 0;
    }
    if (!arrived &&
        !transitRestrictionAhead &&
        _nextStep != null &&
        _nextStep!.maneuverType != 'arrive' &&
        drive.voiceEnabled) {
      final stage = _promptStage(_distanceToStep);
      final language = drive.navigationLanguage;
      if (stage != null && _spokenSteps.add('$nextIndex:$stage:$language')) {
        if (stage == 'turn') {
          _spokenSteps
            ..add('$nextIndex:near:$language')
            ..add('$nextIndex:far:$language');
        } else if (stage == 'near') {
          _spokenSteps.add('$nextIndex:far:$language');
        }
        _nextIndex = nextIndex;
        final session = _session;
        final step = _nextStep!;
        unawaited(
          drive.speakTurn(
            () {
              final language = drive.navigationLanguage;
              final instruction = routeStepInstruction(step, language);
              if (stage == 'turn') return instruction;
              // The distance when spoken, not when queued.
              final metres = navigationMetres(_distanceToStep, language);
              return language == 'zh'
                  ? '$metres后，$instruction'
                  : 'In $metres, $instruction';
            },
            urgent: stage != 'far',
            // Passed, rerouted, or superseded by a nearer prompt.
            stillRelevant: () =>
                session == _session &&
                identical(_route, route) &&
                !arrived &&
                !offRoute &&
                _nextIndex == nextIndex &&
                _promptStage(_distanceToStep) == stage,
          ),
        );
      }
    }
    _nextIndex = nextIndex;
    notifyListeners();
  }

  String? _promptStage(double distance) {
    final farThreshold = drive.speedKph >= 80 ? 1200.0 : 800.0;
    return distance <= 55
        ? 'turn'
        : distance <= 300
        ? 'near'
        : distance <= farThreshold
        ? 'far'
        : null;
  }

  /// Parked near a large venue (or its car park) for 30 s counts as arrived,
  /// even when the routed end point is on a road 40–120 m away.
  bool _stationaryNearEnd(GeoPoint point, DateTime now, double toDestination) {
    final previous = _stationary;
    if (drive.speedKph >= 3 ||
        previous == null ||
        distanceMeters(
              previous.point.latitude,
              previous.point.longitude,
              point.latitude,
              point.longitude,
            ) >
            15) {
      _stationary = (point: point, since: now);
      return false;
    }
    final nearEnd =
        toDestination <= 120 ||
        (_geometryMeters - _alongMeters <= 120 && toDestination <= 250);
    return nearEnd &&
        now.difference(previous.since) >= const Duration(seconds: 30);
  }

  void _arrive() {
    arrived = true;
    offRoute = false;
    _remainingMeters = 0;
    _remainingSeconds = 0;
    _distanceToStep = 0;
    drive.guidanceRunning = false;
    // The host confirms arrival against the requested GPS coordinate
    // before announcing completion and presenting the trip summary.
  }

  Future<void> _reroute(
    GeoPoint point, {
    String? closureFingerprint,
    bool transitRestriction = false,
  }) async {
    final closureTriggered = closureFingerprint != null;
    final startedAt = _clock();
    if (!_usableGps ||
        rerouting ||
        _route == null ||
        _scheduler.inFlightAt(startedAt)) {
      return;
    }
    final session = _session;
    final previous = _route!;
    final stops = remainingStops;
    rerouting = true;
    error = null;
    notifyListeners();
    final token = _scheduler.start(
      startedAt,
      point,
      closureFingerprint: closureFingerprint,
    );
    Duration? retryAfter;
    try {
      final request = reroute!(point, previous, stops);
      // Only one request at a time, even after this attempt has timed out.
      unawaited(
        request.then<void>(
          (_) => _scheduler.settled(token),
          onError: (Object _) => _scheduler.settled(token),
        ),
      );
      final replacement = await request.timeout(rerouteTimeout);
      if (session != _session ||
          !identical(_route, previous) ||
          (!offRoute && !closureTriggered) ||
          arrived) {
        return;
      }
      if (replacement.provider != 'independent' ||
          replacement.mode != previous.mode ||
          replacement.points.length < 2 ||
          replacement.blockedForDriving) {
        throw StateError('Invalid reroute');
      }
      if (transitRoadBlocks(
        replacement,
        await drive
            .transitMatchesForRoute(replacement)
            .timeout(const Duration(seconds: 5)),
        _clock(),
      ).isNotEmpty) {
        throw StateError('Reroute uses a restricted bus-only road');
      }
      if (session != _session ||
          !identical(_route, previous) ||
          (!offRoute && !closureTriggered) ||
          arrived) {
        return;
      }
      if (!_usableGps) throw StateError('GPS unavailable during rerouting');
      final current = drive.latestPosition!;
      final currentProjection = _matcher.project(
        GeoPoint(current.latitude, current.longitude),
        replacement.points,
      );
      if (currentProjection == null ||
          currentProjection.offsetMeters > acceptanceMeters(current.accuracy)) {
        throw StateError('Reroute no longer matches the current location');
      }
      _setRoute(replacement, preserveAlerts: true);
      _closureWarning = false;
      transitRestrictionAhead = false;
      error = null;
      _lastLocationRevision = -1;
      rerouting = false;
      _onLocation();
    } catch (failure) {
      if (failure is RateLimitedException) retryAfter = failure.retryAfter;
      if (session == _session &&
          identical(_route, previous) &&
          (offRoute || closureTriggered) &&
          !arrived) {
        _closureWarning = closureTriggered;
        error = transitRestriction
            ? drive.navigationLanguage == 'zh'
                  ? '前方公交专用路段禁止通行，暂时未找到可用的绕行路线。'
                  : 'Bus-only road ahead. Could not find a legal alternative yet.'
            : closureTriggered
            ? drive.navigationLanguage == 'zh'
                  ? '前方封路，暂时未找到可用的绕行路线。'
                  : 'Closure ahead. Could not find a detour yet.'
            : drive.navigationLanguage == 'zh'
            ? '暂时无法更新路线，连接恢复后重试。'
            : 'Could not update route. Retrying when connected.';
      }
    } finally {
      if (session == _session) {
        _scheduler.finish(
          _clock(),
          closure: closureTriggered,
          retryAfter: retryAfter,
        );
      }
      if (session == _session && _route != null) {
        rerouting = false;
        notifyListeners();
      }
    }
  }

  @override
  Future<void> stop() async {
    final session = ++_session;
    drive.removeListener(_onLocation);
    _route = null;
    _nextStep = null;
    rerouting = false;
    offRoute = false;
    arrived = false;
    error = null;
    _closureWarning = false;
    transitRestrictionAhead = false;
    _lastClosureCheck = null;
    _scheduler.reset();
    _distanceToStep = 0;
    _remainingMeters = 0;
    _remainingSeconds = 0;
    await drive.stop();
    if (session == _session) notifyListeners();
  }

  @override
  void dispose() {
    ++_session;
    drive.removeListener(_onLocation);
    super.dispose();
  }
}
