// Explicit live check; kept outside test/ so normal CI does not call production.
// flutter test tool/valhalla_backend_smoke_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/road_event.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/domain/route_road_events.dart';
import 'package:waybi_mobile/providers/independent_routing_provider.dart';

class _LiveHttpOverrides extends HttpOverrides {}

void main() {
  test(
    'shipping Flutter adapter reads live Valhalla routes, lanes and detours',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final provider = IndependentRoutingProvider(
          useWaybiProxy: true,
          client: IOClient(HttpClient()),
        );
        addTearDown(provider.dispose);
        const origin = GeoPoint(-36.8485, 174.7633);
        const destination = GeoPoint(-37.787, 175.2793);
        final plan = await provider.route(
          origin: origin,
          destination: destination,
          language: 'zh',
          mode: WaybiTravelMode.drive,
        );
        final base = plan.options.first;
        expect(base.provider, 'independent');
        expect(base.points.length, greaterThan(2));
        expect(base.points.every((point) => point.isValid), isTrue);
        expect(base.points.first.latitude, closeTo(origin.latitude, .005));
        expect(base.points.first.longitude, closeTo(origin.longitude, .005));
        expect(base.steps.any((step) => step.lanes.isNotEmpty), isTrue);
        expect(base.steps.any((step) => step.instruction.isNotEmpty), isTrue);
        expect(base.blockedForDriving, isFalse);
        // Alternatives and current closures can change the chosen corridor.
        // Check explicit engine provenance instead of an old distance hash.
        expect(base.routingEngine, 'valhalla');

        final ramp = base.steps.firstWhere(
          (step) => step.maneuverType == 'on ramp',
          orElse: () => base.steps[2],
        );
        final exclusions = closureExclusions(base, [
          RoadEvent(
            id: 'flutter-smoke-synthetic',
            type: RoadEventType.roadClosure,
            location: ramp.location,
            roadName: 'Synthetic validation only',
            source: const RoadEventSource(
              provider: 'Synthetic validation only',
              country: 'NZ',
              sourceId: 'flutter-smoke',
            ),
          ),
        ]);
        expect(exclusions, isNotEmpty);
        final detour = await provider.reroute(
          origin: origin,
          destination: destination,
          mode: WaybiTravelMode.drive,
          language: 'zh',
          avoid: exclusions,
        );
        expect(detour.provider, 'independent');
        expect(detour.blockedForDriving, isFalse);
        expect(detour.points, isNot(equals(base.points)));
        expect(detour.waypoints, [origin, destination]);
        stdout.writeln(
          'Flutter live drive: ${base.distanceMeters} m, '
          '${base.steps.length} steps; detour: ${detour.distanceMeters} m.',
        );

        for (final mode in [WaybiTravelMode.walk, WaybiTravelMode.bicycle]) {
          final result = await provider.route(
            origin: origin,
            destination: const GeoPoint(-36.852, 174.774),
            language: 'zh',
            mode: mode,
          );
          final route = result.options.single;
          expect(route.mode, mode);
          expect(route.points.length, greaterThan(2));
          expect(route.steps.length, greaterThan(1));
          stdout.writeln(
            'Flutter live ${mode.name}: ${route.distanceMeters} m, '
            '${route.steps.length} steps.',
          );
        }
      }, _LiveHttpOverrides());
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
