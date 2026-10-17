import 'package:flutter_test/flutter_test.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waybi_mobile/data/route_repository.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/domain/route_reachability.dart';
import 'package:waybi_mobile/providers/independent_routing_provider.dart';

void main() {
  const auckland = GeoPoint(-36.850, 174.763);
  const sydney = GeoPoint(-33.8688, 151.2093);
  const melbourne = GeoPoint(-37.8136, 144.9631);
  const brisbane = GeoPoint(-27.4705, 153.0260);
  const tokyo = GeoPoint(35.6762, 139.6503);
  const osaka = GeoPoint(34.6937, 135.5023);

  test('NZ to AU cannot drive, walk, cycle, or reverse the sea gap', () {
    expect(isCrossTasmanSurfaceRoute([auckland, sydney]), true);
    expect(isCrossTasmanSurfaceRoute([sydney, auckland]), true);
    expect(isCrossTasmanSurfaceRoute([sydney, melbourne, auckland]), true);
    for (final mode in WaybiTravelMode.values) {
      expect(
        () => validateSurfaceRoute([auckland, sydney], mode: mode),
        throwsA(isA<NoSurfaceRouteException>()),
      );
    }
    expect(
      routeFailureMessage(const NoSurfaceRouteException(), 'zh'),
      contains('无法直接驾车抵达'),
    );
  });

  test(
    'Australian interstate, NZ domestic, and worldwide routes stay routable',
    () {
      expect(isCrossTasmanSurfaceRoute([sydney, melbourne, brisbane]), false);
      expect(
        isCrossTasmanSurfaceRoute([
          auckland,
          const GeoPoint(-41.2865, 174.7767),
        ]),
        false,
      );
      expect(isCrossTasmanSurfaceRoute([tokyo, osaka]), false);
      expect(() => validateSurfaceRoute([sydney, melbourne]), returnsNormally);
    },
  );

  test(
    'both mobile providers skip network for disconnected cross-sea routes',
    () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response('unexpected request', 500);
      });
      final independent = IndependentRoutingProvider(client: client);
      addTearDown(independent.dispose);
      await expectLater(
        independent.route(
          origin: auckland,
          destination: sydney,
          language: 'zh',
          mode: WaybiTravelMode.drive,
        ),
        throwsA(isA<NoSurfaceRouteException>()),
      );
      await expectLater(
        independent.reroute(
          origin: sydney,
          destination: auckland,
          language: 'en',
          mode: WaybiTravelMode.drive,
        ),
        throwsA(isA<NoSurfaceRouteException>()),
      );
      final repository = RouteRepository(client: client);
      await expectLater(
        repository.fetch(
          origin: const LatLng(latitude: -36.850, longitude: 174.763),
          destination: const LatLng(latitude: -33.8688, longitude: 151.2093),
          mode: WaybiTravelMode.drive,
        ),
        throwsA(isA<NoSurfaceRouteException>()),
      );
      expect(requests, 0);
    },
  );

  test('no route, network timeout and provider failure have user-friendly messages', () {
    expect(
      routeFailureMessage(StateError('No routes available'), 'zh'),
      contains('暂时没有'),
    );
    expect(
      routeFailureMessage(StateError('Route preview failed: 503'), 'en'),
      'Route service is temporarily unavailable. Please try again.',
    );
  });
}
