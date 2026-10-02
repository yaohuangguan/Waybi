import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/api_config.dart';
import '../domain/map_provider.dart';
import 'provider_contracts.dart';

class WorkerSearchProvider implements SearchProvider, ExploreProvider {
  WorkerSearchProvider({http.Client? client, this.mapCompatible = false})
    : _client = client ?? http.Client();

  final bool mapCompatible;

  final http.Client _client;

  @override
  Future<List<PlaceCandidate>> search(
    String query, {
    GeoPoint? proximity,
    required String language,
  }) async {
    final uri = Uri.parse('$workerBaseUrl/api/suggest').replace(
      queryParameters: {
        'q': query,
        'lang': language,
        if (mapCompatible) 'provider': 'geoapify',
        if (proximity != null)
          'near': '${proximity.longitude},${proximity.latitude}',
      },
    );
    var response = await _client.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode == 503 && !mapCompatible) {
      response = await _client
          .get(
            Uri.parse('$workerBaseUrl/api/search')
                .replace(queryParameters: {'q': query, 'lang': language}),
          )
          .timeout(const Duration(seconds: 12));
    }
    if (response.statusCode != 200) {
      throw StateError('Search unavailable: ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as List<dynamic>;
    final results = data
        .whereType<Map<String, dynamic>>()
        .map((item) {
          if (mapCompatible && item['provider'] != 'geoapify') return null;
          final latitude = item['latitude'];
          final longitude = item['longitude'];
          if (latitude is! num || longitude is! num) return null;
          final label = item['label']?.toString() ?? '';
          final name = item['name']?.toString().trim() ?? '';
          final address = item['address']?.toString().trim() ?? '';
          final displayName = name.isEmpty ? label : name;
          final isAddress = RegExp(r'^\d+\s').hasMatch(displayName);
          return PlaceCandidate(
            name: displayName,
            address: address.isEmpty ? label : address,
            kind: isAddress ? PlaceKind.address : PlaceKind.poi,
            location: GeoPoint(latitude.toDouble(), longitude.toDouble()),
            reference: ProviderReference(
              item['provider']?.toString() ?? 'geoapify',
              item['id']?.toString() ?? label,
            ),
          );
        })
        .whereType<PlaceCandidate>()
        .toList();
    return List.unmodifiable(results);
  }

  void dispose() => _client.close();

  @override
  Future<List<PlaceSummary>> nearby(
    String category, {
    required GeoPoint center,
    required String language,
  }) async {
    final results = await search(
      category,
      proximity: center,
      language: language,
    );
    return results
        .where((result) => result.location != null)
        .map((result) => result.toPlace(result.location!))
        .toList(growable: false);
  }
}

/// Keyless OSM search. Every candidate carries coordinates and provenance.
class IndependentSearchProvider
    implements SearchProvider, PlaceProvider, ExploreProvider {
  IndependentSearchProvider({http.Client? client})
    : _client = client ?? http.Client();
  final http.Client _client;
  static const _base = String.fromEnvironment(
    'KIWI_PHOTON_URL',
    defaultValue: 'https://photon.komoot.io',
  );

  Future<List<PlaceSummary>> _load(
    String path,
    Map<String, String> parameters,
  ) async {
    final response = await _client
        .get(Uri.parse('$_base/$path').replace(queryParameters: parameters))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw StateError('OpenStreetMap search unavailable');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['features'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map((feature) {
          final props = feature['properties'] as Map<String, dynamic>? ?? {};
          final coordinates =
              (feature['geometry'] as Map<String, dynamic>?)?['coordinates']
                  as List<dynamic>? ??
              [];
          if (coordinates.length < 2 ||
              coordinates[0] is! num ||
              coordinates[1] is! num) {
            return null;
          }
          final location = GeoPoint(
            (coordinates[1] as num).toDouble(),
            (coordinates[0] as num).toDouble(),
          );
          if (!location.isValid) return null;
          final street = [
            props['housenumber'],
            props['street'],
          ].whereType<String>().join(' ');
          final name =
              props['name']?.toString() ??
              (street.isNotEmpty ? street : 'Selected location');
          return PlaceSummary(
            name: name,
            location: location,
            address: [
              street,
              props['city'],
              props['state'],
              props['country'],
            ].whereType<String>().where((v) => v.isNotEmpty).join(', '),
            category: props['osm_value']?.toString() ?? '',
            reference: ProviderReference(
              'osm',
              '${props['osm_type'] ?? ''}:${props['osm_id'] ?? ''}',
            ),
          );
        })
        .whereType<PlaceSummary>()
        .toList(growable: false);
  }

  @override
  Future<List<PlaceCandidate>> search(
    String query, {
    GeoPoint? proximity,
    required String language,
  }) async {
    if (query.trim().length < 3) return [];
    final results = await _load('api/', {
      'q': query,
      'limit': '8',
      'lang': 'en',
      if (proximity != null) 'lat': '${proximity.latitude}',
      if (proximity != null) 'lon': '${proximity.longitude}',
    });
    return results
        .map(
          (p) => PlaceCandidate(
            name: p.name,
            address: p.address,
            category: p.category,
            location: p.location,
            reference: p.reference,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<PlaceSummary> resolve(
    ProviderReference reference, {
    required String language,
  }) => Future.error(
    StateError('OSM search candidates already include coordinates'),
  );

  Future<PlaceSummary?> reverseNear(
    GeoPoint point, {
    required String language,
    String preferredName = '',
  }) async => (await _load('reverse', {
    'lat': '${point.latitude}',
    'lon': '${point.longitude}',
    'limit': '1',
    'lang': 'en',
  })).firstOrNull;

  @override
  Future<List<PlaceSummary>> nearby(
    String category, {
    required GeoPoint center,
    required String language,
  }) async => (await search(
    category,
    proximity: center,
    language: language,
  )).map((p) => p.toPlace(p.location!)).toList(growable: false);

  void dispose() => _client.close();
}
