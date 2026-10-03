import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../domain/geo_math.dart';
import '../domain/map_provider.dart';
import '../domain/route_option.dart';

/// Provider-neutral public-transport routing for the independent map stack.
///
/// The endpoint speaks the MOTIS v6 API, so production can point this at a
/// self-hosted MOTIS instance without changing mobile routing or MapLibre
/// rendering. Transitous is only the development/default endpoint.
class IndependentTransitRoutingProvider {
  IndependentTransitRoutingProvider({
    http.Client? client,
    this.baseUrl = const String.fromEnvironment(
      'KIWI_MOTIS_URL',
      defaultValue: 'https://api.transitous.org',
    ),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  Future<RoutePlan> route({
    required GeoPoint origin,
    required GeoPoint destination,
    required String language,
  }) async {
    if (!origin.isValid || !destination.isValid) {
      throw ArgumentError('Transit routing requires valid coordinates');
    }

    final uri = Uri.parse('$baseUrl/api/v6/plan').replace(
      queryParameters: {
        'fromPlace': '${origin.latitude},${origin.longitude}',
        'toPlace': '${destination.latitude},${destination.longitude}',
        'transitModes': 'TRANSIT',
        'directModes': '',
        'preTransitModes': 'WALK',
        'postTransitModes': 'WALK',
        'language': language == 'zh' ? 'zh' : 'en',
        'algorithm': 'RAPTOR',
        'realtimeMode': 'REALTIME',
      },
    );

    final response = await _client
        .get(
          uri,
          headers: {
            'Accept': 'application/json',
            if (!kIsWeb)
              'User-Agent':
                  'KiwiLens/1.0 (+https://github.com/yaohuangguan/kiwi-lens)',
          },
        )
        .timeout(const Duration(seconds: 18));
    if (response.statusCode != 200) {
      throw StateError(
        'Independent transit unavailable: ${response.statusCode}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final itineraries = (body['itineraries'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_routeFromItinerary)
        .where((route) => route.points.length >= 2 && route.transit.isNotEmpty)
        .take(3)
        .toList(growable: false);
    if (itineraries.isEmpty) {
      throw StateError('No public-transport route available');
    }

    return RoutePlan(
      options: itineraries,
      trafficAvailable: false,
      provider: 'motis',
      stopsApplied: 0,
    );
  }

  RouteOption _routeFromItinerary(Map<String, dynamic> itinerary) {
    final legs = (itinerary['legs'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final points = <GeoPoint>[];
    final transitLegs = <TransitLeg>[];
    final lineNames = <String>[];

    for (final leg in legs) {
      final geometry = leg['legGeometry'] as Map<String, dynamic>?;
      final encoded = geometry?['points'] as String? ?? '';
      final precision = (geometry?['precision'] as num?)?.round() ?? 6;
      for (final point in _decodePolyline(encoded, precision: precision)) {
        if (points.isEmpty || points.last != point) points.add(point);
      }

      final mode = leg['mode']?.toString() ?? '';
      if (_isTransitMode(mode)) {
        final shortName = leg['routeShortName']?.toString().trim() ?? '';
        final longName = leg['routeLongName']?.toString().trim() ?? '';
        final line = shortName.isNotEmpty ? shortName : longName;
        if (line.isNotEmpty && !lineNames.contains(line)) lineNames.add(line);
        final intermediate =
            (leg['intermediateStops'] as List<dynamic>? ?? const []).length;
        transitLegs.add(
          TransitLeg(
            lineName: line.isNotEmpty ? line : _vehicleLabel(mode),
            headsign: leg['headsign']?.toString() ?? '',
            vehicleType: mode,
            vehicleName: _vehicleLabel(mode),
            departureStop: _placeName(leg['from']),
            arrivalStop: _placeName(leg['to']),
            stopCount: intermediate + 2,
            departureTime: leg['startTime']?.toString(),
            arrivalTime: leg['endTime']?.toString(),
            agencies: const [],
          ),
        );
      }
    }

    var metres = 0.0;
    for (var index = 1; index < points.length; index++) {
      metres += distanceMeters(
        points[index - 1].latitude,
        points[index - 1].longitude,
        points[index].latitude,
        points[index].longitude,
      );
    }

    final transfers = (itinerary['transfers'] as num?)?.round() ?? 0;
    final duration = (itinerary['duration'] as num?)?.round() ?? 0;
    final transferLabel = transfers == 0
        ? 'direct'
        : '$transfers transfer${transfers == 1 ? '' : 's'}';
    return RouteOption(
      id: 'independent-transit-${_stableId(itinerary)}',
      mode: KiwiTravelMode.transit,
      durationSeconds: duration,
      staticDurationSeconds: duration,
      distanceMeters: metres.round(),
      points: List.unmodifiable(points),
      provider: 'motis',
      traffic: const TrafficSummary(normal: 0, slow: 0, trafficJam: 0),
      trafficIntervals: const [],
      transit: List.unmodifiable(transitLegs),
      description: lineNames.isEmpty
          ? 'Public transport'
          : '${lineNames.join(' · ')} · $transferLabel',
      labels: const ['RAPTOR'],
    );
  }

  bool _isTransitMode(String mode) =>
      !const {'WALK', 'BIKE', 'CAR', 'HGV', 'RENTAL'}.contains(mode);

  String _vehicleLabel(String mode) => switch (mode) {
    'BUS' || 'COACH' => 'Bus',
    'FERRY' => 'Ferry',
    'REGIONAL_RAIL' ||
    'REGIONAL_FAST_RAIL' ||
    'SUBURBAN' ||
    'RAIL' ||
    'SUBWAY' => 'Train',
    'TRAM' => 'Tram',
    _ =>
      mode
          .toLowerCase()
          .split('_')
          .map(
            (part) => part.isEmpty
                ? ''
                : '${part[0].toUpperCase()}${part.substring(1)}',
          )
          .join(' '),
  };

  String _placeName(dynamic value) {
    if (value is! Map<String, dynamic>) return '';
    return value['name']?.toString() ?? '';
  }

  String _stableId(Map<String, dynamic> itinerary) {
    final start = itinerary['startTime']?.toString() ?? '';
    final end = itinerary['endTime']?.toString() ?? '';
    final legs = (itinerary['legs'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((leg) => '${leg['mode']}:${leg['routeId'] ?? ''}')
        .join('|');
    return '${start.hashCode.abs()}-${end.hashCode.abs()}-${legs.hashCode.abs()}';
  }

  List<GeoPoint> _decodePolyline(String encoded, {required int precision}) {
    if (encoded.isEmpty) return const [];
    final factor = _pow10(precision);
    final result = <GeoPoint>[];
    var index = 0;
    var latitude = 0;
    var longitude = 0;
    while (index < encoded.length) {
      final latDelta = _decodeValue(encoded, index);
      index = latDelta.nextIndex;
      latitude += latDelta.value;
      if (index >= encoded.length) break;
      final lonDelta = _decodeValue(encoded, index);
      index = lonDelta.nextIndex;
      longitude += lonDelta.value;
      result.add(GeoPoint(latitude / factor, longitude / factor));
    }
    return result;
  }

  ({int value, int nextIndex}) _decodeValue(String encoded, int startIndex) {
    var index = startIndex;
    var result = 0;
    var shift = 0;
    int byte;
    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20 && index < encoded.length);
    final value = (result & 1) != 0 ? ~(result >> 1) : result >> 1;
    return (value: value, nextIndex: index);
  }

  double _pow10(int exponent) {
    var value = 1.0;
    for (var i = 0; i < exponent; i++) {
      value *= 10;
    }
    return value;
  }

  void dispose() => _client.close();
}
