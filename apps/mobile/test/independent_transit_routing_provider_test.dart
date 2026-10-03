import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kiwi_lens_mobile/domain/map_provider.dart';
import 'package:kiwi_lens_mobile/domain/route_option.dart';
import 'package:kiwi_lens_mobile/providers/independent_transit_routing_provider.dart';

void main() {
  test(
    'independent transit uses MOTIS RAPTOR and decodes transit geometry',
    () async {
      late Uri requestUri;
      final provider = IndependentTransitRoutingProvider(
        baseUrl: 'https://motis.test',
        client: MockClient((request) async {
          requestUri = request.url;
          return http.Response(
            jsonEncode({
              'itineraries': [
                {
                  'duration': 1260,
                  'transfers': 0,
                  'startTime': '2026-10-03T01:14:00Z',
                  'endTime': '2026-10-03T01:35:00Z',
                  'legs': [
                    {
                      'mode': 'WALK',
                      'legGeometry': {
                        'points': _encodePolyline6(const [
                          GeoPoint(-36.844, 174.766),
                          GeoPoint(-36.84431, 174.76869),
                        ]),
                        'precision': 6,
                      },
                      'from': {'name': 'START'},
                      'to': {'name': 'Waitemata Train Station'},
                    },
                    {
                      'mode': 'REGIONAL_RAIL',
                      'routeShortName': 'S-C',
                      'headsign': 'Newmarket via Parnell',
                      'startTime': '2026-10-03T01:19:00Z',
                      'endTime': '2026-10-03T01:30:00Z',
                      'legGeometry': {
                        'points': _encodePolyline6(const [
                          GeoPoint(-36.84431, 174.76869),
                          GeoPoint(-36.85470, 174.77747),
                          GeoPoint(-36.86972, 174.77884),
                        ]),
                        'precision': 6,
                      },
                      'from': {'name': 'Waitemata Train Station'},
                      'to': {'name': 'Newmarket Train Station'},
                      'intermediateStops': [
                        {'name': 'Parnell Train Station'},
                      ],
                    },
                    {
                      'mode': 'WALK',
                      'legGeometry': {
                        'points': _encodePolyline6(const [
                          GeoPoint(-36.86972, 174.77884),
                          GeoPoint(-36.870, 174.778),
                        ]),
                        'precision': 6,
                      },
                      'from': {'name': 'Newmarket Train Station'},
                      'to': {'name': 'END'},
                    },
                  ],
                },
              ],
            }),
            200,
          );
        }),
      );

      final plan = await provider.route(
        origin: const GeoPoint(-36.844, 174.766),
        destination: const GeoPoint(-36.870, 174.778),
        language: 'en',
      );
      final route = plan.forMode(KiwiTravelMode.transit).single;

      expect(requestUri.path, '/api/v6/plan');
      expect(requestUri.queryParameters['algorithm'], 'RAPTOR');
      expect(requestUri.queryParameters['transitModes'], 'TRANSIT');
      expect(requestUri.queryParameters['realtimeMode'], 'REALTIME');
      expect(plan.provider, 'motis');
      expect(route.provider, 'motis');
      expect(route.points.first, const GeoPoint(-36.844, 174.766));
      expect(route.points.last, const GeoPoint(-36.870, 174.778));
      expect(route.transit, hasLength(1));
      expect(route.transit.single.lineName, 'S-C');
      expect(route.transit.single.vehicleName, 'Train');
      expect(route.transit.single.stopCount, 3);
      expect(route.description, contains('S-C'));
      provider.dispose();
    },
  );
}

String _encodePolyline6(List<GeoPoint> points) {
  final out = StringBuffer();
  var lastLat = 0;
  var lastLon = 0;
  for (final point in points) {
    final lat = (point.latitude * 1000000).round();
    final lon = (point.longitude * 1000000).round();
    _encodeValue(lat - lastLat, out);
    _encodeValue(lon - lastLon, out);
    lastLat = lat;
    lastLon = lon;
  }
  return out.toString();
}

void _encodeValue(int delta, StringBuffer out) {
  var value = delta < 0 ? ~(delta << 1) : delta << 1;
  while (value >= 0x20) {
    out.writeCharCode((0x20 | (value & 0x1f)) + 63);
    value >>= 5;
  }
  out.writeCharCode(value + 63);
}
