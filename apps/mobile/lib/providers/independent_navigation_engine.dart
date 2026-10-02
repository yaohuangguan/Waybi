import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../domain/geo_math.dart';
import '../domain/map_provider.dart';
import '../domain/route_option.dart';
import '../drive/drive_engine.dart';
import '../drive/navigation_language.dart';
import '../drive/route_camera_matcher.dart';
import '../drive/route_progress_tracker.dart';
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
  }) : _clock = clock ?? DateTime.now;
  final DriveEngine drive;
  final IndependentReroute? reroute;
  final DateTime Function() _clock;
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
  int _session = 0;
  int _lastLocationRevision = -1;
  int _offRouteFixes = 0;
  int _arrivalFixes = 0;
  DateTime? _offRouteSince;
  DateTime? _lastReroute;
  bool rerouting = false;
  bool offRoute = false;
  bool arrived = false;
  String? error;

  RouteOption? get route => _route;
  RouteStepInfo? get nextStep => _nextStep;
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
    _geometryMeters = RouteProgressTracker.geometryLength(route.points);
    final scale = route.distanceMeters > 0
        ? _geometryMeters / route.distanceMeters
        : 1.0;
    _stepPositions = [
      for (final step in route.steps)
        step.alongRouteMeters != null
            ? step.alongRouteMeters! * scale
            : _matcher.project(step.location, route.points)?.alongMeters ?? 0,
    ];
    _stops = [
      for (final point
          in route.waypoints
              .skip(1)
              .take(math.max(0, route.waypoints.length - 2)))
        (point, _matcher.project(point, route.points)?.alongMeters ?? 0),
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
    offRoute = false;
    arrived = false;
    drive.setRoute(route, preserveAlerts: preserveAlerts);
  }

  @override
  Future<void> start(RouteOption route) async {
    if (route.provider != 'independent' || route.points.length < 2) {
      throw StateError(
        'Independent navigation requires a valid Independent route',
      );
    }
    ++_session;
    drive.removeListener(_onLocation);
    _lastLocationRevision = -1;
    _lastReroute = null;
    rerouting = false;
    error = null;
    _setRoute(route);
    try {
      await drive.startLocal();
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
    final location = drive.snappedLocation;
    if (route == null ||
        !drive.active ||
        location == null ||
        _lastLocationRevision == drive.locationRevision ||
        arrived) {
      return;
    }
    _lastLocationRevision = drive.locationRevision;
    final point = GeoPoint(location.latitude, location.longitude);
    final progress = drive.routeProgress;
    if (progress == null) return;
    final now = _clock();
    offRoute =
        progress.offsetMeters >
        math.max(35, drive.locationAccuracyMeters * 1.5);
    if (offRoute) {
      _offRouteSince ??= now;
      _offRouteFixes++;
      if (_offRouteFixes >= 3 &&
          now.difference(_offRouteSince!).inSeconds >= 3 &&
          !rerouting &&
          reroute != null &&
          (_lastReroute == null ||
              now.difference(_lastReroute!).inSeconds >= 15)) {
        unawaited(_reroute(point));
      }
      notifyListeners();
      return;
    }
    _offRouteFixes = 0;
    _offRouteSince = null;
    error = null;
    _alongMeters = progress.alongMeters;
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
    final destination = route.points.last;
    final toDestination = distanceMeters(
      point.latitude,
      point.longitude,
      destination.latitude,
      destination.longitude,
    );
    if (_remainingMeters <= 15 && toDestination <= 10 && drive.speedKph < 15) {
      _arrivalFixes++;
      if (_arrivalFixes >= 2) {
        arrived = true;
        _remainingMeters = 0;
        _remainingSeconds = 0;
        _distanceToStep = 0;
        drive.guidanceRunning = false;
        // The host confirms arrival against the requested GPS coordinate
        // before announcing completion and presenting the trip summary.
      }
    } else {
      _arrivalFixes = 0;
    }
    if (!arrived &&
        _nextStep != null &&
        _nextStep!.maneuverType != 'arrive' &&
        drive.voiceEnabled) {
      final farThreshold = drive.speedKph >= 80 ? 1200.0 : 800.0;
      final stage = _distanceToStep <= 55
          ? 'turn'
          : _distanceToStep <= 300
          ? 'near'
          : _distanceToStep <= farThreshold
          ? 'far'
          : null;
      if (stage != null &&
          _spokenSteps.add('$nextIndex:$stage:${drive.navigationLanguage}')) {
        if (stage == 'turn') {
          _spokenSteps
            ..add('$nextIndex:near:${drive.navigationLanguage}')
            ..add('$nextIndex:far:${drive.navigationLanguage}');
        } else if (stage == 'near') {
          _spokenSteps.add('$nextIndex:far:${drive.navigationLanguage}');
        }
        final instruction = routeStepInstruction(
          _nextStep,
          drive.navigationLanguage,
        );
        final message = stage == 'turn'
            ? instruction
            : drive.navigationLanguage == 'zh'
            ? '${navigationMetres(_distanceToStep, drive.navigationLanguage)}后，$instruction'
            : 'In ${navigationMetres(_distanceToStep, drive.navigationLanguage)}, $instruction';
        unawaited(drive.speakMessage(message));
      }
    }
    notifyListeners();
  }

  Future<void> _reroute(GeoPoint point) async {
    final session = _session;
    final previous = _route!;
    final stops = remainingStops;
    rerouting = true;
    _lastReroute = _clock();
    error = null;
    notifyListeners();
    try {
      final replacement = await reroute!(point, previous, stops);
      if (session != _session || _route == null) return;
      if (replacement.provider != 'independent' ||
          replacement.mode != previous.mode ||
          replacement.points.length < 2) {
        throw StateError('Invalid reroute');
      }
      _setRoute(replacement, preserveAlerts: true);
      _lastLocationRevision = -1;
    } catch (_) {
      if (session == _session && _route != null) {
        error = 'Could not update route. Retrying when connected.';
      }
    } finally {
      if (session == _session && _route != null) {
        rerouting = false;
        notifyListeners();
      }
    }
  }

  @override
  Future<void> stop() async {
    ++_session;
    drive.removeListener(_onLocation);
    _route = null;
    _nextStep = null;
    rerouting = false;
    offRoute = false;
    arrived = false;
    error = null;
    _distanceToStep = 0;
    _remainingMeters = 0;
    _remainingSeconds = 0;
    await drive.stop();
    notifyListeners();
  }

  @override
  void dispose() {
    ++_session;
    drive.removeListener(_onLocation);
    super.dispose();
  }
}
