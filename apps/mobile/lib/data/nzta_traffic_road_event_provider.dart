import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/country_profile.dart';
import '../domain/map_provider.dart';
import '../domain/road_event.dart';
import '../domain/road_intelligence.dart';
import 'api_config.dart';
import 'json_file_cache.dart';

/// The feed combines regional official events and worldwide Waybi reports.
///
/// Scheduled events that start within [scheduledWindow] are kept, with their
/// `validFrom`/`validUntil`, so routing can avoid a closure that begins
/// before the car reaches it. Consumers that show or announce events as
/// active must check [RoadEvent.isCurrent]. Both the older server (current
/// events only) and the newer one (`scheduledWindowHours`) are accepted.
class NztaTrafficRoadEventProvider implements RoadEventProvider {
  NztaTrafficRoadEventProvider({
    http.Client? client,
    this.baseUrl = workerBaseUrl,
    JsonFileCache Function(String key)? cache,
  }) : _client = client ?? http.Client(),
       _cacheFor =
           cache ?? ((key) => JsonFileCache('$key.json', legacyPrefsKey: key));
  final JsonFileCache Function(String key) _cacheFor;
  final _caches = <String, JsonFileCache>{};
  final _cachedEvents = <String, (int, DateTime)>{};

  final http.Client _client;
  final String baseUrl;
  String lastSyncStatus = 'not_loaded';
  DateTime? lastCheckedAt;
  GeoPoint? regionCenter;
  List<String> officialCoverage = const [];
  static const scheduledWindow = Duration(hours: 12);

  @override
  bool supports(CountryProfile country) => country.roadIntelligenceAvailable;

  static const _cacheKey = 'waybi.cache.road_events.v1';

  @override
  Future<List<RoadEvent>> load() async {
    final cacheKey = _regionalCacheKey;
    lastSyncStatus = 'unavailable';
    officialCoverage = const [];
    lastCheckedAt = null;
    Object? networkError;
    try {
      final response = await _client
          .get(
            Uri.parse('$baseUrl/api/road-events').replace(
              queryParameters: {
                if (regionCenter != null)
                  'near':
                      '${regionCenter!.longitude},${regionCenter!.latitude}',
              },
            ),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw StateError('Road events API failed: ${response.statusCode}');
      }
      final events = _decode(response.body, stale: false);
      // Polled every 5 minutes while driving: rewrite the offline copy only
      // when the events changed, or to refresh its age before it expires.
      final signature = _eventsSignature(response.body);
      final previous = _cachedEvents[cacheKey];
      final now = DateTime.now();
      if (previous == null ||
          previous.$1 != signature ||
          now.difference(previous.$2) > const Duration(minutes: 10)) {
        final cache = _caches[cacheKey] ??= _cacheFor(cacheKey);
        if (await cache.write(response.body)) {
          _cachedEvents[cacheKey] = (signature, now);
        }
      }
      return events;
    } catch (error) {
      networkError = error;
    }

    try {
      final cache = _caches[cacheKey] ??= _cacheFor(cacheKey);
      final cached = await cache.read();
      if (cached != null) return _decode(cached, stale: true);
    } catch (_) {
      // Fall through to the original network failure.
    }
    throw networkError;
  }

  List<RoadEvent> _decode(String raw, {required bool stale}) {
    final body = jsonDecode(raw) as Map<String, dynamic>;
    lastSyncStatus = stale
        ? 'stale'
        : body['syncStatus']?.toString() ?? 'unknown';
    lastCheckedAt = DateTime.tryParse(body['checkedAt']?.toString() ?? '');
    officialCoverage =
        (body['officialCoverage'] as List<dynamic>?)
            ?.whereType<String>()
            .toList() ??
        const ['NZ'];
    final retrievedAt =
        DateTime.tryParse(body['retrievedAt']?.toString() ?? '') ??
        lastCheckedAt;
    final expiredSnapshot =
        stale &&
        (retrievedAt == null ||
            DateTime.now().difference(retrievedAt) >
                const Duration(minutes: 15));
    if (expiredSnapshot) lastSyncStatus = 'unavailable';
    final serverWindow = body['scheduledWindowHours'];
    final window = serverWindow is num && serverWindow >= 0
        ? Duration(
            minutes: (serverWindow * 60)
                .clamp(0, scheduledWindow.inMinutes)
                .round(),
          )
        : scheduledWindow;
    final now = DateTime.now();
    return (body['events'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_fromJson)
        .whereType<RoadEvent>()
        .where(
          (event) =>
              event.isCurrentOrUpcoming(now, window: window) &&
              (!expiredSnapshot || event.metadata['userReported'] == true),
        )
        .toList(growable: false);
  }

  static int _eventsSignature(String raw) {
    final body = jsonDecode(raw);
    return body is Map ? jsonEncode(body['events']).hashCode : raw.hashCode;
  }

  String get _regionalCacheKey => regionCenter == null
      ? _cacheKey
      : '$_cacheKey.${CountryProfiles.at(regionCenter!)?.code ?? 'GLOBAL'}';

  RoadEvent? _fromJson(Map<String, dynamic> json) {
    final location = json['location'];
    final source = json['source'];
    if (location is! Map<String, dynamic> || source is! Map<String, dynamic>) {
      return null;
    }
    final latitude = (location['latitude'] as num?)?.toDouble();
    final longitude = (location['longitude'] as num?)?.toDouble();
    if (latitude == null ||
        longitude == null ||
        !GeoPoint(latitude, longitude).isValid) {
      return null;
    }

    final geometry = (json['geometry'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((point) {
          final lat = (point['latitude'] as num?)?.toDouble();
          final lon = (point['longitude'] as num?)?.toDouble();
          return lat == null || lon == null ? null : GeoPoint(lat, lon);
        })
        .whereType<GeoPoint>()
        .toList(growable: false);

    return RoadEvent(
      id: json['id']?.toString() ?? '',
      type: _eventType(json['type']?.toString()),
      location: GeoPoint(latitude, longitude),
      geometry: geometry,
      source: RoadEventSource(
        provider: source['provider']?.toString() ?? 'NZTA Traffic and Travel',
        country: source['country']?.toString() ?? 'GLOBAL',
        sourceId: source['sourceId']?.toString() ?? '',
        region: source['region']?.toString(),
        updatedAt: DateTime.tryParse(source['updatedAt']?.toString() ?? ''),
      ),
      severity: _severity(json['severity']?.toString()),
      observation: _observation(json['observation']?.toString()),
      roadName: json['roadName']?.toString(),
      headingDegrees: (json['headingDegrees'] as num?)?.toDouble(),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1,
      validFrom: DateTime.tryParse(json['validFrom']?.toString() ?? ''),
      validUntil: DateTime.tryParse(json['validUntil']?.toString() ?? ''),
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
    );
  }

  RoadEventType _eventType(String? value) => switch (value) {
    'roadClosure' => RoadEventType.roadClosure,
    'roadworks' => RoadEventType.roadworks,
    'flooding' => RoadEventType.flooding,
    'slip' => RoadEventType.slip,
    'congestion' => RoadEventType.congestion,
    _ => RoadEventType.incident,
  };

  RoadEventObservation _observation(String? value) => switch (value) {
    'observed' => RoadEventObservation.observed,
    'forecast' => RoadEventObservation.forecast,
    'inferred' => RoadEventObservation.inferred,
    _ => RoadEventObservation.official,
  };

  RoadEventSeverity _severity(String? value) => switch (value) {
    'critical' => RoadEventSeverity.critical,
    'warning' => RoadEventSeverity.warning,
    'advisory' => RoadEventSeverity.advisory,
    _ => RoadEventSeverity.information,
  };
}
