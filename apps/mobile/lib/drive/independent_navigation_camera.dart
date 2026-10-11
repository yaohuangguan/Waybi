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
    double zoomFor(double metres) =>
        // MapLibre's world is 512 logical pixels wide at zoom zero.
        (math.log(78271.51696 * latitudeScale * pixelsAhead / metres) /
                math.ln2)
            .clamp(14.9, 18.2);
    final baseZoom = zoomFor(forwardMetres).clamp(14.9, 17.0);
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
        distanceToStep.isFinite &&
        distanceToStep >= 0) {
      // Frame the actual junction with space beyond it, instead of reaching a
      // fixed zoom only when the vehicle is already at the turn. Slow city
      // approaches show the last 55–65 m; motorway exits retain more context.
      final minimumAhead = switch (mode) {
        WaybiTravelMode.walk => 40.0,
        WaybiTravelMode.bicycle => 50.0,
        _ => (45 + speed * .4).clamp(55.0, 90.0),
      };
      final junctionAhead = math.max(minimumAhead, distanceToStep * 1.2 + 18);
      desired = math.max(
        baseZoom,
        zoomFor(math.min(forwardMetres, junctionAhead)),
      );
    }
    final elapsed = _lastAt == null
        ? 1.0
        : now.difference(_lastAt!).inMilliseconds / 1000;
    final dt = elapsed.clamp(.05, 2.0);
    // Widen gradually after a turn; consecutive junctions retain detail.
    _zoom = _zoom == null
        ? desired
        : _zoom! + (desired - _zoom!).clamp(-.28 * dt, 1.15 * dt);
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
