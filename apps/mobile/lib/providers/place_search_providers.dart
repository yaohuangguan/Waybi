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
                'User-Agent': 'Waybi/1.0 (+https://waybi.nzs.workers.dev)',
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
          ].whereType<String>().where((v) => v.trim().isNotEmpty).join(' ');
          final name =
              props['name']?.toString() ??
              (street.isNotEmpty ? street : 'Selected location');
          final addressParts = <String>[
            street,
            props['district']?.toString() ?? '',
            props['locality']?.toString() ?? '',
            props['city']?.toString() ?? '',
            props['state']?.toString() ?? '',
            props['country']?.toString() ?? '',
          ];
          final seenAddressParts = <String>{};
          final address = addressParts
              .where((v) => v.trim().isNotEmpty)
              .where((v) => seenAddressParts.add(v.trim().toLowerCase()))
              .join(', ');
          return PlaceSummary(
            name: name,
            location: location,
            address: address,
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

  static const _regionalSearchAnchors = <(String, GeoPoint)>[
    ('Auckland', GeoPoint(-36.8485, 174.7633)),
    ('Hamilton', GeoPoint(-37.7870, 175.2793)),
    ('Tauranga', GeoPoint(-37.6878, 176.1651)),
    ('Wellington', GeoPoint(-41.2866, 174.7756)),
    ('Christchurch', GeoPoint(-43.5321, 172.6362)),
    ('Dunedin', GeoPoint(-45.8788, 170.5028)),
    ('Queenstown', GeoPoint(-45.0312, 168.6626)),
  ];

  static const _regionalIntents = {
    'airport': 'Airport',
    'international airport': 'Airport',
    '机场': 'Airport',
    'zoo': 'Zoo',
    '动物园': 'Zoo',
    'museum': 'Museum',
    '博物馆': 'Museum',
    'stadium': 'Stadium',
    '体育场': 'Stadium',
    'university': 'University',
    '大学': 'University',
    'hospital': 'Hospital',
    '医院': 'Hospital',
    'ferry terminal': 'Ferry Terminal',
    '渡轮': 'Ferry Terminal',
  };

  String? _regionalIntentQuery(String query, GeoPoint? proximity) {
    if (proximity == null) return null;
    final intent = _regionalIntents[query.toLowerCase().trim()];
    if (intent == null) return null;
    (String, GeoPoint)? nearest;
    var nearestMeters = double.infinity;
    for (final region in _regionalSearchAnchors) {
      final metres = distanceMeters(
        proximity.latitude,
        proximity.longitude,
        region.$2.latitude,
        region.$2.longitude,
      );
      if (metres < nearestMeters) {
        nearest = region;
        nearestMeters = metres;
      }
    }
    // Use city intent expansion only when the map/search origin is genuinely
    // in that metro area. Outside those regions Photon keeps its normal ranking.
    if (nearest == null || nearestMeters > 160000) return null;
    return '${nearest.$1} $intent';
  }

  static const _poiCategories = {
    'supermarket',
    'convenience',
    'mall',
    'restaurant',
    'cafe',
    'fast_food',
    'hotel',
    'motel',
    'hospital',
    'pharmacy',
    'fuel',
    'museum',
    'attraction',
    'zoo',
    'stadium',
    'university',
    'school',
    'parking',
    'aerodrome',
    'terminal',
    'station',
  };

  static const _administrativeCategories = {
    'country',
    'state',
    'county',
    'district',
    'city',
    'town',
    'village',
    'suburb',
    'quarter',
    'locality',
  };

  bool _queryNamesAnotherRegion(String query) {
    final lower = query.toLowerCase();
    if (lower.contains('new zealand') || RegExp(r'\bnz\b').hasMatch(lower)) {
      return true;
    }
    return _regionalSearchAnchors.any(
      (region) => lower.contains(region.$1.toLowerCase()),
    );
  }

  bool _shouldBoundLocally(String query, GeoPoint? proximity) =>
      proximity != null &&
      proximity.latitude > -48 &&
      proximity.latitude < -34 &&
      proximity.longitude > 166 &&
      proximity.longitude < 179 &&
      !_queryNamesAnotherRegion(query);

  bool _isCategoryIntent(String query) {
    final normalized = query.toLowerCase().trim().replaceAll(' ', '_');
    return _poiCategories.contains(normalized) ||
        _genericSearchWords.contains(query.toLowerCase().trim()) ||
        _regionalIntents.containsKey(query.toLowerCase().trim());
  }

  bool _strongNameMatch(PlaceSummary place, String query) {
    final name = _compactSearchText(place.name);
    final wanted = _compactSearchText(query);
    return wanted.isNotEmpty && name == wanted;
  }

  String _localBbox(GeoPoint center) {
    const latRadius = .40;
    const lonRadius = .58;
    return [
      (center.longitude - lonRadius).toStringAsFixed(4),
      (center.latitude - latRadius).toStringAsFixed(4),
      (center.longitude + lonRadius).toStringAsFixed(4),
      (center.latitude + latRadius).toStringAsFixed(4),
    ].join(',');
  }

  double _resultRank(
    PlaceSummary place, {
    required String query,
    required GeoPoint? proximity,
    String? preferredName,
    String? coreName,
  }) {
    var rank = 0.0;
    final name = _compactSearchText(place.name);
    final wanted = _compactSearchText(query);
    if (wanted.isNotEmpty) {
      if (name == wanted) {
        rank -= 100000;
      } else if (name.startsWith(wanted)) {
        rank -= 45000;
      } else if (name.contains(wanted) || wanted.contains(name)) {
        rank -= 30000;
      }
    }
    if (preferredName != null) {
      final preferred = _compactSearchText(preferredName);
      if (name == preferred) {
        rank -= 100000;
      } else if (name.contains(preferred) || preferred.contains(name)) {
        rank -= 50000;
      }
    }
    if (coreName != null && _nameMatchesCore(place, coreName)) {
      rank -= 25000;
    }
    final category = place.category.toLowerCase();
    if (_poiCategories.contains(category)) rank -= 9000;
    if (_administrativeCategories.contains(category) &&
        !_queryNamesAnotherRegion(query) &&
        name != wanted) {
      rank += 12000;
    }
    if (preferredName?.toLowerCase().contains('airport') == true) {
      if (category == 'aerodrome') rank -= 12000;
      if (category.contains('terminal')) rank -= 6000;
    }
    if (proximity != null) {
      // Proximity is a tie-breaker, not the whole relevance model. Raw metres
      // made a famous exact destination 150 km away lose to an unrelated local
      // name. Cap and scale it so semantic/type confidence remains dominant.
      rank +=
          distanceMeters(
            proximity.latitude,
            proximity.longitude,
            place.location.latitude,
            place.location.longitude,
          ).clamp(0, 200000) *
          .12;
    }
    return rank;
  }

  Map<String, String> _photonParameters(
    String query,
    GeoPoint? proximity, {
    bool localBias = true,
  }) => {
    'q': query,
    'limit': localBias ? '16' : '8',
    'lang': 'en',
    if (proximity != null) 'lat': proximity.latitude.toStringAsFixed(3),
    if (proximity != null) 'lon': proximity.longitude.toStringAsFixed(3),
    if (localBias && _shouldBoundLocally(query, proximity))
      'bbox': _localBbox(proximity!),
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
    final plainQuery = aliases[trimmed] ?? trimmed;
    final regionalQuery = _regionalIntentQuery(trimmed, proximity);
    final coreQuery = _coreBrandQuery(trimmed);
    final primaryQuery = regionalQuery ?? plainQuery;
    final bounded = _shouldBoundLocally(primaryQuery, proximity);
    var results = await _load(
      'api/',
      _photonParameters(primaryQuery, proximity),
    );

    // A bounded local query keeps short brands local, but must not make long
    // distance destination search impossible. When the local box has no strong
    // name match (for example searching a city elsewhere in NZ), merge a global
    // response and let semantic relevance outrank proximity.
    if (bounded &&
        (results.isEmpty ||
            (coreQuery == null &&
                !_isCategoryIntent(plainQuery) &&
                !results.any(
                  (place) => _strongNameMatch(place, plainQuery),
                )))) {
      final global = await _load(
        'api/',
        _photonParameters(primaryQuery, proximity, localBias: false),
      );
      final merged = <String, PlaceSummary>{};
      for (final place in [...results, ...global]) {
        final ref = place.reference;
        final key = ref == null
            ? '${place.name}|${place.location.latitude}|${place.location.longitude}'
            : '${ref.provider}:${ref.id}';
        merged.putIfAbsent(key, () => place);
      }
      results = merged.values.toList(growable: false);
    }

    // Photon can over-weight generic category words. Branded searches retry
    // the brand portion. Common local intents are expanded before the first
    // request so "airport" near Auckland is both smarter and faster.
    final fallbacks = <String>[
      if (regionalQuery != null &&
          plainQuery != primaryQuery &&
          results.isEmpty)
        plainQuery,
      if (coreQuery != null &&
          coreQuery != primaryQuery &&
          !results.any((place) => _nameMatchesCore(place, coreQuery)))
        coreQuery,
    ];
    if (fallbacks.isNotEmpty) {
      final merged = <String, PlaceSummary>{};
      for (final fallbackQuery in fallbacks) {
        final fallback = await _load(
          'api/',
          _photonParameters(fallbackQuery, proximity),
        );
        for (final place in fallback) {
          final ref = place.reference;
          final key = ref == null
              ? '${place.name}|${place.location.latitude}|${place.location.longitude}'
              : '${ref.provider}:${ref.id}';
          merged.putIfAbsent(key, () => place);
        }
      }
      for (final place in results) {
        final ref = place.reference;
        final key = ref == null
            ? '${place.name}|${place.location.latitude}|${place.location.longitude}'
            : '${ref.provider}:${ref.id}';
        merged.putIfAbsent(key, () => place);
      }
      results = merged.values.toList(growable: false);
    }

    results = results.toList(growable: false)
      ..sort((a, b) {
        final aRank = _resultRank(
          a,
          query: trimmed,
          proximity: proximity,
          preferredName: regionalQuery,
          coreName: coreQuery,
        );
        final bRank = _resultRank(
          b,
          query: trimmed,
          proximity: proximity,
          preferredName: regionalQuery,
          coreName: coreQuery,
        );
        return aRank.compareTo(bRank);
      });

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
