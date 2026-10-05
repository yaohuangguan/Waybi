import 'dart:math' as math;

import '../domain/map_provider.dart';
import '../domain/route_option.dart';

/// Camera policy in physical road distances, independent of the map SDK.
class IndependentNavigationCamera {
  DateTime? _lastAt;
  double? _zoom, _bearing;

  void reset() {
    _lastAt = null;
    _zoom = null;
    _bearing = null;
  }

  MapViewportState update({
    required GeoPoint location,
    required double heading,
    required double speedKph,
    required WaybiTravelMode mode,
    required double visibleHeight,
    required double distanceToStep,
    required RouteStepInfo? nextStep,
    required bool northUp,
    required bool tilted,
    required DateTime now,
    bool offRoute = false,
  }) {
    final speed = speedKph.isFinite ? speedKph.clamp(0.0, 160.0) : 0.0;
    final forwardMetres = switch (mode) {
      WaybiTravelMode.walk => 100.0,
      WaybiTravelMode.bicycle => (120 + speed * 4).clamp(120.0, 240.0),
      _ => (145 + speed * 2.6).clamp(145.0, 455.0),
    };
    // The location sits 64% down the unobscured map, leaving road context ahead.
    final pixelsAhead = visibleHeight.clamp(200.0, 900.0) * .64;
    final latitudeScale = math
        .cos(location.latitude * math.pi / 180)
        .abs()
        .clamp(.2, 1.0);
    final baseZoom =
        // MapLibre's world is 512 logical pixels wide at zoom zero.
        (math.log(78271.51696 * latitudeScale * pixelsAhead / forwardMetres) /
                math.ln2)
            .clamp(14.9, 17.0);
    var desired = baseZoom;
    final step = nextStep;
    final junction =
        step != null &&
        (const {
              'turn',
              'roundabout',
              'rotary',
              'roundabout turn',
              'exit roundabout',
              'exit rotary',
              'fork',
              'merge',
              'on ramp',
              'off ramp',
              'end of road',
            }.contains(step.maneuverType) ||
            (step.maneuverType == 'continue' &&
                step.maneuverModifier.isNotEmpty &&
                step.maneuverModifier != 'straight'));
    if (!offRoute &&
        step != null &&
        (junction || step.maneuverType == 'arrive') &&
        distanceToStep.isFinite) {
      final approach = mode == WaybiTravelMode.walk
          ? 100.0
          : (140 + speed * 3).clamp(180.0, 450.0);
      final fraction = (1 - distanceToStep / approach).clamp(0.0, 1.0);
      final blend = fraction * fraction * (3 - 2 * fraction);
      final closeZoom = step.maneuverType == 'arrive' ? 17.1 : 17.35;
      desired = baseZoom + (math.max(baseZoom, closeZoom) - baseZoom) * blend;
    }
    final elapsed = _lastAt == null
        ? 1.0
        : now.difference(_lastAt!).inMilliseconds / 1000;
    final dt = elapsed.clamp(.05, 2.0);
    // Widen gradually after a turn; consecutive junctions retain detail.
    _zoom = _zoom == null
        ? desired
        : _zoom! + (desired - _zoom!).clamp(-.28 * dt, .85 * dt);
    final targetHeading = heading.isFinite ? heading % 360 : (_bearing ?? 0);
    if (_bearing == null || northUp) {
      _bearing = northUp ? 0 : targetHeading;
    } else {
      final delta = (targetHeading - _bearing! + 540) % 360 - 180;
      _bearing = (_bearing! + delta.clamp(-100 * dt, 100 * dt) + 360) % 360;
    }
    _lastAt = now;
    return MapViewportState(
      center: location,
      zoom: _zoom!,
      bearing: northUp ? 0 : _bearing!,
      pitch: tilted ? 48 : 0,
    );
  }
}
