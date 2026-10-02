import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;

import '../data/api_config.dart';
import '../domain/geo_math.dart';
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
  IndependentSearchProvider({
    http.Client? client,
    this.requestSpacing = const Duration(milliseconds: 750),
  }) : _client = client ?? http.Client();
  final http.Client _client;
  static const _base = String.fromEnvironment(
    'KIWI_PHOTON_URL',
    defaultValue: 'https://photon.komoot.io',
  );

  final Duration requestSpacing;
  final _cache = <String, (DateTime, List<PlaceSummary>)>{};
  final _pending = <String, Future<List<PlaceSummary>>>{};
  static Future<void>? _queue;
  static DateTime? _lastRequest;

  Future<List<PlaceSummary>> _load(
    String path,
    Map<String, String> parameters,
  ) {
    final uri = Uri.parse('$_base/$path').replace(queryParameters: parameters);
    final key = uri.toString();
    final cached = _cache[key];
    if (cached != null &&
        DateTime.now().difference(cached.$1) < const Duration(minutes: 5)) {
      return Future.value(cached.$2);
    }
    return _pending.putIfAbsent(key, () async {
      try {
        final result = await _fetch(path, parameters);
        if (_cache.length >= 64) _cache.remove(_cache.keys.first);
        _cache[key] = (DateTime.now(), result);
        return result;
      } finally {
        _pending.remove(key);
      }
    });
  }

  Future<List<PlaceSummary>> _fetch(
    String path,
    Map<String, String> parameters,
  ) async {
    // Be a named, conservative public API client. Photon rejects Dart's
    // anonymous default UA with 403; identifying the app is required on iOS.
    final previous = _queue;
    final completed = Completer<void>();
    _queue = completed.future;
    late http.Response response;
    try {
      if (previous != null) await previous;
      final last = _lastRequest;
      if (last != null && requestSpacing > Duration.zero) {
        final gap = requestSpacing - DateTime.now().difference(last);
        if (gap > Duration.zero) await Future<void>.delayed(gap);
      }
      _lastRequest = DateTime.now();
      response = await _client
          .get(
            Uri.parse('$_base/$path').replace(queryParameters: parameters),
            headers: {
              'Accept': 'application/json',
              if (!kIsWeb)
                'User-Agent':
                    'KiwiLens/1.0 (+https://kiwi-lens.nzs.workers.dev)',
            },
          )
          .timeout(const Duration(seconds: 12));
    } finally {
      if (identical(_queue, completed.future)) _queue = null;
      completed.complete();
    }
    if (response.statusCode != 200) {
      throw StateError(
        'OpenStreetMap search unavailable: ${response.statusCode}',
      );
    }
    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
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

  static const _genericSearchWords = {
    'asian',
    'supermarket',
    'market',
    'store',
    'shop',
    'restaurant',
    'cafe',
    'café',
  };

  String? _coreBrandQuery(String query) {
    final words = query
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    if (words.length < 2) return null;
    final core = words
        .where((word) => !_genericSearchWords.contains(word.toLowerCase()))
        .join(' ')
        .trim();
    return core.runes.length >= 2 && core != query.trim() ? core : null;
  }

  String _compactSearchText(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  bool _nameMatchesCore(PlaceSummary place, String core) {
    final name = _compactSearchText(place.name);
    final wanted = _compactSearchText(core);
    return wanted.isNotEmpty &&
        (name.contains(wanted) || wanted.contains(name));
  }

  Map<String, String> _photonParameters(String query, GeoPoint? proximity) => {
    'q': query,
    'limit': '8',
    'lang': 'en',
    if (proximity != null) 'lat': proximity.latitude.toStringAsFixed(3),
    if (proximity != null) 'lon': proximity.longitude.toStringAsFixed(3),
  };

  @override
  Future<List<PlaceCandidate>> search(
    String query, {
    GeoPoint? proximity,
    required String language,
  }) async {
    final trimmed = query.trim();
    if (trimmed.runes.length < 2) return [];
    // The public Photon index only provides en/de/fr/local names. Translate
    // category intents and NZ city aliases; preserve other names and addresses.
    const aliases = {
      '咖啡': 'cafe',
      '咖啡店': 'cafe',
      '餐厅': 'restaurant',
      '餐馆': 'restaurant',
      '公园': 'park',
      '超市': 'supermarket',
      '加油站': 'petrol station',
      '医院': 'hospital',
      '停车场': 'parking',
      '奥克兰': 'Auckland',
      '惠灵顿': 'Wellington',
      '基督城': 'Christchurch',
      '皇后镇': 'Queenstown',
    };
    final primaryQuery = aliases[trimmed] ?? trimmed;
    var results = await _load(
      'api/',
      _photonParameters(primaryQuery, proximity),
    );

    // Photon can over-weight generic category words. For a branded query such
    // as "taiping asian supermarket", retry the brand portion only when the
    // first response does not contain a matching place name.
    final coreQuery = _coreBrandQuery(trimmed);
    if (coreQuery != null &&
        !results.any((place) => _nameMatchesCore(place, coreQuery))) {
      final fallback = await _load(
        'api/',
        _photonParameters(coreQuery, proximity),
      );
      final merged = <String, PlaceSummary>{};
      for (final place in [...fallback, ...results]) {
        final ref = place.reference;
        final key = ref == null
            ? '${place.name}|${place.location.latitude}|${place.location.longitude}'
            : '${ref.provider}:${ref.id}';
        merged.putIfAbsent(key, () => place);
      }
      results = merged.values.toList(growable: false)
        ..sort((a, b) {
          final aMatch = _nameMatchesCore(a, coreQuery);
          final bMatch = _nameMatchesCore(b, coreQuery);
          if (aMatch != bMatch) return aMatch ? -1 : 1;
          if (proximity == null) return 0;
          final aDistance = distanceMeters(
            proximity.latitude,
            proximity.longitude,
            a.location.latitude,
            a.location.longitude,
          );
          final bDistance = distanceMeters(
            proximity.latitude,
            proximity.longitude,
            b.location.latitude,
            b.location.longitude,
          );
          return aDistance.compareTo(bDistance);
        });
    }

    return results
        .take(8)
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
