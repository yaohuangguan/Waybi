import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;

import '../data/api_config.dart';
import '../domain/geo_math.dart';
import '../domain/map_provider.dart';
import 'regional_query_aliases.dart';
import 'provider_contracts.dart';

class WorkerSearchProvider implements CachedSearchProvider, ExploreProvider {
  WorkerSearchProvider({http.Client? client, this.mapCompatible = false})
    : _client = client ?? http.Client();

  final bool mapCompatible;

  final http.Client _client;
  final _searchCache = <String, (DateTime, List<PlaceCandidate>)>{};
  final _searchPending = <String, Future<List<PlaceCandidate>>>{};

  String _searchKey(String query, GeoPoint? proximity, String language) => [
    query.trim().toLowerCase(),
    language,
    mapCompatible ? 'map-compatible' : 'global',
    if (proximity != null)
      '${proximity.latitude.toStringAsFixed(2)},${proximity.longitude.toStringAsFixed(2)}',
  ].join('|');

  @override
  List<PlaceCandidate> cachedSuggestions(
    String query, {
    GeoPoint? proximity,
    required String language,
  }) {
    final normalized = query.trim().toLowerCase();
    if (normalized.runes.length < 2) return const [];
    final exact = _searchCache[_searchKey(query, proximity, language)];
    if (exact != null &&
        DateTime.now().difference(exact.$1) < const Duration(minutes: 5)) {
      return exact.$2;
    }
    final suffix = _searchKey('', proximity, language);
    final seen = <String>{};
    final matches = <PlaceCandidate>[];
    for (final entry in _searchCache.entries.toList().reversed) {
      if (!entry.key.endsWith(suffix) ||
          DateTime.now().difference(entry.value.$1) >=
              const Duration(minutes: 5)) {
        continue;
      }
      for (final candidate in entry.value.$2) {
        if (!candidate.name.toLowerCase().startsWith(normalized) &&
            !candidate.address.toLowerCase().startsWith(normalized)) {
          continue;
        }
        final identity =
            '${candidate.reference}:${candidate.name}:${candidate.location}';
        if (seen.add(identity)) matches.add(candidate);
      }
    }
    return matches.take(12).toList(growable: false);
  }

  @override
  Future<List<PlaceCandidate>> search(
    String query, {
    GeoPoint? proximity,
    required String language,
  }) {
    final key = _searchKey(query, proximity, language);
    final cached = _searchCache[key];
    if (cached != null &&
        DateTime.now().difference(cached.$1) < const Duration(minutes: 5)) {
      return Future.value(cached.$2);
    }
    return _searchPending.putIfAbsent(key, () async {
      try {
        final results = await _searchNetwork(
          query,
          proximity: proximity,
          language: language,
        );
        if (_searchCache.length >= 48) {
          _searchCache.remove(_searchCache.keys.first);
        }
        if (results.isNotEmpty) _searchCache[key] = (DateTime.now(), results);
        return results;
      } finally {
        _searchPending.remove(key);
      }
    });
  }

  Future<List<PlaceCandidate>> _searchNetwork(
    String query, {
    GeoPoint? proximity,
    required String language,
  }) async {
    final uri = Uri.parse('$workerBaseUrl/api/suggest').replace(
      queryParameters: {
        'q': query,
        'lang': language,
        if (mapCompatible) 'provider': 'independent',
        if (proximity != null)
          'near':
              '${proximity.longitude.toStringAsFixed(2)},${proximity.latitude.toStringAsFixed(2)}',
      },
    );
    final fallbackUri = Uri.parse('$workerBaseUrl/api/search').replace(
      queryParameters: {
        'q': query,
        'lang': language,
        if (mapCompatible) 'provider': 'independent',
        if (proximity != null)
          'near':
              '${proximity.longitude.toStringAsFixed(3)},${proximity.latitude.toStringAsFixed(3)}',
      },
    );
    var response = await _client.get(uri).timeout(const Duration(seconds: 4));
    var data = response.statusCode == 200
        ? jsonDecode(response.body) as List<dynamic>
        : const <dynamic>[];
    if (response.statusCode == 502 ||
        response.statusCode == 503 ||
        data.isEmpty) {
      response = await _client
          .get(fallbackUri)
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        data = jsonDecode(response.body) as List<dynamic>;
      }
    }
    if (response.statusCode != 200) {
      throw StateError('Search unavailable: ${response.statusCode}');
    }
    final results = data
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final sourceProvider = item['provider']?.toString() ?? 'geoapify';
          final sourceId =
              item['id']?.toString() ?? item['label']?.toString() ?? '';
          if (mapCompatible &&
              !const ProviderPolicy(MapProvider.independent)
                  .canDisplay(ProviderReference(sourceProvider, sourceId))) {
            return null;
          }
          final latitude = item['latitude'];
          final longitude = item['longitude'];
          if (latitude is! num || longitude is! num) return null;
          final label = item['label']?.toString() ?? '';
          final name = item['name']?.toString().trim() ?? '';
          final address = item['address']?.toString().trim() ?? '';
          final displayName = name.isEmpty ? label : name;
          final isAddress =
              item['isPoi'] == false || RegExp(r'^\d+\s').hasMatch(displayName);
          return PlaceCandidate(
            name: displayName,
            category: item['resultType']?.toString() ?? '',
            address: address.isEmpty ? label : address,
            kind: isAddress ? PlaceKind.address : PlaceKind.poi,
            location: GeoPoint(latitude.toDouble(), longitude.toDouble()),
            reference: ProviderReference(
              sourceProvider,
              sourceId.isEmpty ? label : sourceId,
            ),
          );
        })
        .whereType<PlaceCandidate>()
        .toList();
    final deduped = <PlaceCandidate>[];
    final seen = <String>{};
    for (final result in results) {
      final key = result.reference == null
          ? '${result.name.toLowerCase()}|${result.location}'
          : '${result.reference!.provider}:${result.reference!.id}';
      if (seen.add(key)) deduped.add(result);
    }
    return List.unmodifiable(deduped);
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
    implements
        ExpandedSearchProvider,
        CachedSearchProvider,
        PlaceProvider,
        ExploreProvider {
  IndependentSearchProvider({
    http.Client? client,
    this.requestSpacing = const Duration(milliseconds: 750),
    this.useWorkerSuggestions = false,
    this.workerOnly = false,
  }) : _client = client ?? http.Client() {
    if (useWorkerSuggestions) {
      _fastSearch = WorkerSearchProvider(client: _client, mapCompatible: true);
    }
  }
  final http.Client _client;
  static const _base = String.fromEnvironment(
    'KIWI_PHOTON_URL',
    defaultValue: 'https://photon.komoot.io',
  );

  final Duration requestSpacing;
  final bool useWorkerSuggestions;
  final bool workerOnly;
  WorkerSearchProvider? _fastSearch;
  @override
  List<PlaceCandidate> cachedSuggestions(
    String query, {
    GeoPoint? proximity,
    required String language,
  }) =>
      _fastSearch?.cachedSuggestions(
        query,
        proximity: proximity,
        language: language,
      ) ??
      const [];
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
              if (!kIsWeb) 'User-Agent': 'Waybi/1.0 (+https://waybi.co)',
            },
          )
          .timeout(const Duration(seconds: 4));
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
            props['postcode']?.toString() ?? '',
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
            kind:
                props['osm_key'] != 'shop' &&
                    props['osm_key'] != 'amenity' &&
                    props['housenumber']?.toString().isNotEmpty == true
                ? PlaceKind.address
                : PlaceKind.poi,
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

  String _compactSearchText(String value) => value.toLowerCase().replaceAll(
    RegExp(r'[^\p{L}\p{N}]+', unicode: true),
    '',
  );

  static final _streetAddressPattern = RegExp(
    r'^\d+[A-Za-z]?(?:\s*/\s*\d+[A-Za-z]?)?\s+.+\s+(?:road|rd|street|st|drive|dr|avenue|ave|lane|ln|place|pl|crescent|cres|terrace|tce|court|ct|close|cl|parade|pde|highway|hwy|way)\.?$',
    caseSensitive: false,
  );

  Future<List<PlaceSummary>> _globalAddressSupplement(
    String query,
    GeoPoint? proximity,
    String language,
  ) async {
    if (!_streetAddressPattern.hasMatch(query.trim())) return const [];
    try {
      final params = {
        'q': query.trim(),
        'lang': language,
        if (proximity != null)
          'near':
              '${proximity.longitude.toStringAsFixed(3)},${proximity.latitude.toStringAsFixed(3)}',
      };
      final headers = {
        'Accept': 'application/json',
        if (!kIsWeb) 'User-Agent': 'Waybi/1.0 (+https://waybi.co)',
      };
      var response = await _client
          .get(
            Uri.parse('$workerBaseUrl/api/suggest')
                .replace(queryParameters: {...params, 'provider': 'geoapify'}),
            headers: headers,
          )
          .timeout(const Duration(seconds: 9));
      var decoded = response.statusCode == 200
          ? jsonDecode(response.body) as List<dynamic>
          : const <dynamic>[];
      if (response.statusCode == 502 ||
          response.statusCode == 503 ||
          decoded.isEmpty) {
        response = await _client
            .get(
              Uri.parse('$workerBaseUrl/api/search')
                  .replace(queryParameters: params),
              headers: headers,
            )
            .timeout(const Duration(seconds: 9));
        decoded = response.statusCode == 200
            ? jsonDecode(response.body) as List<dynamic>
            : const <dynamic>[];
      }
      if (response.statusCode != 200) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((item) {
            final latitude = item['latitude'];
            final longitude = item['longitude'];
            if (latitude is! num || longitude is! num) return null;
            final provider = item['provider']?.toString() ?? 'osm';
            if (provider != 'osm' &&
                provider != 'geoapify' &&
                provider != 'tomtom' &&
                !provider.startsWith('derived:') &&
                !provider.startsWith('regional:')) {
              return null;
            }
            final name = item['name']?.toString().trim() ?? '';
            final address = item['address']?.toString().trim() ?? '';
            return PlaceSummary(
              name: name.isEmpty ? address : name,
              category: item['resultType']?.toString() ?? '',
              address: address,
              location: GeoPoint(latitude.toDouble(), longitude.toDouble()),
              kind: PlaceKind.address,
              reference: ProviderReference(
                provider,
                item['id']?.toString() ?? address,
              ),
            );
          })
          .whereType<PlaceSummary>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  bool _nameMatchesCore(PlaceSummary place, String core) {
    final name = _compactSearchText(place.name);
    final wanted = _compactSearchText(core);
    return wanted.isNotEmpty &&
        name.isNotEmpty &&
        (name.contains(wanted) || wanted.contains(name));
  }

  static const _localizedCategoryIntents = {
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

  String? _localizedIntentQuery(String query) =>
      _localizedCategoryIntents[query.toLowerCase().trim()];

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
    'province',
    'county',
    'district',
    'city',
    'town',
    'village',
    'suburb',
    'quarter',
    'locality',
  };

  bool _isCategoryIntent(String query) {
    final normalized = query.toLowerCase().trim().replaceAll(' ', '_');
    return _poiCategories.contains(normalized) ||
        _genericSearchWords.contains(query.toLowerCase().trim()) ||
        _localizedCategoryIntents.containsKey(query.toLowerCase().trim());
  }

  bool _strongNameMatch(PlaceSummary place, String query) {
    String words(String value) => value
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
        .trim();
    final name = words(place.name);
    final wanted = words(query);
    return wanted.isNotEmpty && name == wanted;
  }

  String _localBbox(GeoPoint center) {
    // Roughly metro-scale everywhere on Earth. Longitude expands towards the
    // poles so the local-first behavior is geographic, not country-specific.
    const latRadius = .65;
    final lonRadius =
        (latRadius /
                math.cos(center.latitude * math.pi / 180).abs().clamp(.2, 1))
            .clamp(.65, 3.25);
    return [
      (center.longitude - lonRadius).clamp(-180, 180).toStringAsFixed(4),
      (center.latitude - latRadius).clamp(-90, 90).toStringAsFixed(4),
      (center.longitude + lonRadius).clamp(-180, 180).toStringAsFixed(4),
      (center.latitude + latRadius).clamp(-90, 90).toStringAsFixed(4),
    ].join(',');
  }

  bool _automaticGlobalCandidate(
    PlaceSummary place,
    String query,
    GeoPoint proximity,
  ) {
    final metres = distanceMeters(
      proximity.latitude,
      proximity.longitude,
      place.location.latitude,
      place.location.longitude,
    );
    if (metres <= 250000) return true;

    final wanted = _compactSearchText(query);
    final name = _compactSearchText(place.name);
    final address = _compactSearchText(place.address);
    final exactOrContained =
        wanted.isNotEmpty &&
        (name == wanted ||
            name.contains(wanted) ||
            wanted.contains(name) ||
            address.contains(wanted));
    if (!exactOrContained) return false;

    // Named cities/regions and explicit street addresses should work globally
    // without a mode switch. For ambiguous non-Latin POI names, keep remote
    // namesakes behind the explicit "Search further" action.
    if (_administrativeCategories.contains(place.category)) return true;
    if (_streetAddressPattern.hasMatch(query.trim())) return true;
    final containsCjk = RegExp(r'[\u3400-\u9fff\uf900-\ufaff]').hasMatch(query);
    return !containsCjk;
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
    if (_administrativeCategories.contains(category) && name != wanted) {
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
    'limit': localBias ? '16' : '10',
    'lang': 'en',
    if (proximity != null) 'lat': proximity.latitude.toStringAsFixed(3),
    if (proximity != null) 'lon': proximity.longitude.toStringAsFixed(3),
    if (proximity != null) 'location_bias_scale': '0.1',
    if (localBias && proximity != null && proximity.isValid)
      'bbox': _localBbox(proximity),
  };

  @override
  Future<List<PlaceCandidate>> search(
    String query, {
    GeoPoint? proximity,
    required String language,
  }) => _search(query, proximity: proximity, language: language);

  @override
  Future<List<PlaceCandidate>> searchFurther(
    String query, {
    GeoPoint? proximity,
    required String language,
  }) =>
      _search(query, proximity: proximity, language: language, expanded: true);

  Future<List<PlaceCandidate>> _search(
    String query, {
    GeoPoint? proximity,
    required String language,
    bool expanded = false,
  }) async {
    final trimmed = query.trim();
    if (trimmed.runes.length < 2) return [];
    // Photon is global. Normalize language/category intent, then apply optional
    // regional vocabulary adapters without changing the core search algorithm.
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
    };
    final plainQuery = resolveRegionalQueryAlias(
      aliases[trimmed] ?? trimmed,
      proximity,
    );
    final intentQuery = _localizedIntentQuery(trimmed);
    final coreQuery = _coreBrandQuery(plainQuery);
    final primaryQuery = intentQuery ?? plainQuery;
    final localFirst = !expanded && proximity != null && proximity.isValid;

    // Normal search is powered by Waybi's global search endpoint first. It is
    // substantially faster than serial public-Photon lookups and keeps search
    // quality identical regardless of which map renderer is selected. Photon
    // remains the open-data fallback if Waybi search is slow or unavailable.
    final fastSearch = _fastSearch;
    if (fastSearch != null && (!expanded || workerOnly)) {
      try {
        // The Worker owns the provider deadline. A second, shorter timeout
        // here used to discard its valid response and start a serial Photon
        // fallback, which cannot resolve many partial numbered addresses.
        final fast = await fastSearch.search(
          trimmed,
          proximity: proximity,
          language: language,
        );
        if (fast.isNotEmpty || workerOnly) {
          return fast.take(12).toList(growable: false);
        }
      } catch (_) {
        if (workerOnly) {
          throw StateError('Waybi Search is temporarily unavailable');
        }
        // Development/direct mode may still fall through to Photon.
      }
    }

    if (workerOnly) {
      throw StateError('Waybi Search is temporarily unavailable');
    }

    var results = await _load(
      'api/',
      _photonParameters(primaryQuery, proximity, localBias: !expanded),
    );
    final addressSupplement = await _globalAddressSupplement(
      trimmed,
      proximity,
      language,
    );
    if (addressSupplement.isNotEmpty) {
      final merged = <String, PlaceSummary>{};
      for (final place in [...addressSupplement, ...results]) {
        final ref = place.reference;
        final key = ref == null
            ? '${place.name}|${place.location.latitude}|${place.location.longitude}'
            : '${ref.provider}:${ref.id}';
        merged.putIfAbsent(key, () => place);
      }
      results = merged.values.toList(growable: false);
    }

    // Normal search is local-first everywhere, never NZ-first. If the local
    // metro box has no strong semantic match, fetch a global pass. Safe exact
    // destinations/cities can surface automatically; ambiguous remote CJK POI
    // names stay behind the explicit "Search further" action.
    if (localFirst &&
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
      for (final place in results) {
        final ref = place.reference;
        final key = ref == null
            ? '${place.name}|${place.location.latitude}|${place.location.longitude}'
            : '${ref.provider}:${ref.id}';
        merged.putIfAbsent(key, () => place);
      }
      for (final place in global.where(
        (place) => _automaticGlobalCandidate(place, plainQuery, proximity),
      )) {
        final ref = place.reference;
        final key = ref == null
            ? '${place.name}|${place.location.latitude}|${place.location.longitude}'
            : '${ref.provider}:${ref.id}';
        merged.putIfAbsent(key, () => place);
      }
      results = merged.values.toList(growable: false);
    }

    // Photon can over-weight generic category words. Branded searches retry
    // the brand portion. Localized category intents are normalized before the first request;
    // proximity then picks the relevant nearby instance anywhere in the world.
    final fallbacks = <String>[
      if (intentQuery != null && plainQuery != primaryQuery && results.isEmpty)
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
          _photonParameters(fallbackQuery, proximity, localBias: !expanded),
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
        final geographic =
            (_administrativeCategories.contains(b.category) &&
                    _strongNameMatch(b, plainQuery)
                ? 1
                : 0) -
            (_administrativeCategories.contains(a.category) &&
                    _strongNameMatch(a, plainQuery)
                ? 1
                : 0);
        if (geographic != 0) return geographic;
        // Keep explicitly named destinations and brand intent, then rank
        // equally relevant addresses/places by actual distance without a cap.
        if (proximity != null && intentQuery == null) {
          bool matches(PlaceSummary p) => coreQuery != null
              ? _nameMatchesCore(p, coreQuery)
              : _isCategoryIntent(plainQuery)
              ? _poiCategories.contains(p.category)
              : _nameMatchesCore(p, plainQuery) ||
                    _compactSearchText(plainQuery).isNotEmpty &&
                        _compactSearchText(p.address)
                            .contains(_compactSearchText(plainQuery));
          final exactName =
              (_strongNameMatch(b, plainQuery) ? 1 : 0) -
              (_strongNameMatch(a, plainQuery) ? 1 : 0);
          // For exact destinations/POIs the name should beat proximity. For a
          // numbered street address, equivalent house/street matches should
          // instead be disambiguated by distance/locality.
          if (exactName != 0 && !_streetAddressPattern.hasMatch(plainQuery)) {
            return exactName;
          }
          final relevance = (matches(b) ? 1 : 0) - (matches(a) ? 1 : 0);
          if (relevance != 0) return relevance;
          double metres(PlaceSummary p) => distanceMeters(
            proximity.latitude,
            proximity.longitude,
            p.location.latitude,
            p.location.longitude,
          );
          final nearby = metres(a).compareTo(metres(b));
          if (nearby != 0) return nearby;
        }
        final aRank = _resultRank(
          a,
          query: plainQuery,
          proximity: proximity,
          preferredName: intentQuery,
          coreName: coreQuery,
        );
        final bRank = _resultRank(
          b,
          query: plainQuery,
          proximity: proximity,
          preferredName: intentQuery,
          coreName: coreQuery,
        );
        return aRank.compareTo(bRank);
      });

    return results
        .take(12)
        .map(
          (p) => PlaceCandidate(
            name: p.name,
            address: p.address,
            category: p.category,
            kind: p.kind,
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
  }) async {
    if (workerOnly) {
      try {
        final uri = Uri.parse('$workerBaseUrl/api/reverse').replace(
          queryParameters: {
            'at': '${point.longitude},${point.latitude}',
            'lang': language,
          },
        );
        final response = await _client
            .get(uri)
            .timeout(const Duration(seconds: 4));
        if (response.statusCode != 200) return null;
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is! Map<String, dynamic>) return null;
        final label = data['label']?.toString().trim() ?? '';
        if (label.isEmpty) return null;
        return PlaceSummary(
          name: preferredName.trim().isEmpty ? label : preferredName.trim(),
          address: label,
          kind: PlaceKind.address,
          location: point,
          reference: ProviderReference(
            'osm',
            'reverse:${point.latitude},${point.longitude}',
          ),
        );
      } catch (_) {
        return null;
      }
    }
    return (await _load('reverse', {
      'lat': '${point.latitude}',
      'lon': '${point.longitude}',
      'limit': '1',
      'lang': 'en',
    })).firstOrNull;
  }

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
