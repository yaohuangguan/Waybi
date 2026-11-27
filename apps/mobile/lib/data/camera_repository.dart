import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/safety_camera.dart';
import 'api_config.dart';
import 'json_file_cache.dart';

class CameraSnapshot {
  const CameraSnapshot({
    required this.cameras,
    required this.syncStatus,
    this.sourceUpdatedAt,
    this.checkedAt,
    this.lastSuccessfulAt,
    this.fromCache = false,
    this.fetchMode,
    this.syncError,
    this.changeAdded = 0,
    this.changeRemoved = 0,
  });

  final List<SafetyCamera> cameras;
  final String syncStatus;
  final DateTime? sourceUpdatedAt;
  final DateTime? checkedAt;
  final DateTime? lastSuccessfulAt;
  final bool fromCache;
  DateTime? get lastVerifiedAt =>
      lastSuccessfulAt ?? (syncStatus == 'live' ? checkedAt : null);
  final String? fetchMode;
  final String? syncError;
  final int changeAdded;
  final int changeRemoved;
}

class CameraRepository {
  CameraRepository({
    http.Client? client,
    this.baseUrl = workerBaseUrl,
    JsonFileCache? cache,
  }) : _client = client ?? http.Client(),
       _cache =
           cache ??
           JsonFileCache('camera-catalog.v1.json', legacyPrefsKey: _cacheKey);

  final http.Client _client;
  final String baseUrl;

  /// ~60 KB catalogue: a file, rewritten only when the catalogue changes.
  final JsonFileCache _cache;

  static const _cacheKey = 'waybi.cache.cameras.v1';
  CameraSnapshot? _lastValidSnapshot;

  Future<CameraSnapshot> fetchSnapshot() async {
    Object? networkError;
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/api/cameras'))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw StateError('Camera API failed: ${response.statusCode}');
      }
      final snapshot = await _decodeSnapshot(response.body);
      _lastValidSnapshot = snapshot;
      // Persistent caching is best-effort and must never turn a successful
      // live response into an offline failure.
      await _cache.write(response.body);
      return snapshot;
    } catch (error) {
      networkError = error;
    }

    final memory = _lastValidSnapshot;
    if (memory != null) return _cachedCopy(memory, networkError);
    try {
      final cached = await _cache.read();
      if (cached != null) {
        final snapshot = await _decodeSnapshot(cached);
        _lastValidSnapshot = snapshot;
        return _cachedCopy(snapshot, networkError);
      }
    } catch (_) {
      // Unit tests and unsupported platforms may not provide a preferences
      // binding. In that case surface the original network error.
    }
    throw networkError;
  }

  Future<CameraSnapshot> syncNow({required String sessionToken}) async {
    final response = await _client
        .post(
          Uri.parse('$baseUrl/api/cameras/sync'),
          headers: {
            'cookie': 'waybi_session=$sessionToken',
            'x-waybi-client': 'mobile',
          },
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        throw StateError(
          body['error']?.toString() ??
              'Camera sync failed: ${response.statusCode}',
        );
      } on FormatException {
        throw StateError('Camera sync failed: ${response.statusCode}');
      }
    }
    final snapshot = await _decodeSnapshot(response.body);
    _lastValidSnapshot = snapshot;
    await _cache.write(response.body);
    return snapshot;
  }

  Future<CameraSnapshot> _decodeSnapshot(String raw) async {
    final body = await decodeJsonOffMain(raw) as Map<String, dynamic>;
    final rows = body['cameras'];
    if (rows is! List ||
        rows.isEmpty ||
        rows.any((row) => row is! Map<String, dynamic>)) {
      throw const FormatException('Invalid camera catalog');
    }
    final cameras = rows
        .cast<Map<String, dynamic>>()
        .map(SafetyCamera.fromJson)
        .toList(growable: false);
    if (cameras.any(
          (camera) =>
              camera.id.isEmpty ||
              camera.name.isEmpty ||
              camera.type.isEmpty ||
              !camera.latitude.isFinite ||
              !camera.longitude.isFinite ||
              camera.latitude <= -48 ||
              camera.latitude >= -34 ||
              camera.longitude <= 166 ||
              camera.longitude >= 179,
        ) ||
        cameras.map((camera) => camera.id).toSet().length != cameras.length) {
      throw const FormatException('Invalid NZTA camera locations');
    }
    return CameraSnapshot(
      cameras: cameras,
      syncStatus: body['syncStatus']?.toString() ?? 'unknown',
      sourceUpdatedAt: DateTime.tryParse(
        body['sourceUpdatedAt']?.toString() ?? '',
      ),
      checkedAt: DateTime.tryParse(body['checkedAt']?.toString() ?? ''),
      lastSuccessfulAt: DateTime.tryParse(
        body['lastSuccessfulAt']?.toString() ?? '',
      ),
      fetchMode: body['fetchMode']?.toString(),
      syncError: body['syncError']?.toString(),
      changeAdded:
          (body['change'] as Map<String, dynamic>?)?['added'] as int? ?? 0,
      changeRemoved:
          (body['change'] as Map<String, dynamic>?)?['removed'] as int? ?? 0,
    );
  }

  CameraSnapshot _cachedCopy(CameraSnapshot snapshot, Object error) =>
      CameraSnapshot(
        cameras: snapshot.cameras,
        syncStatus: 'stale',
        sourceUpdatedAt: snapshot.sourceUpdatedAt,
        checkedAt: snapshot.checkedAt,
        lastSuccessfulAt: snapshot.lastVerifiedAt,
        fromCache: true,
        fetchMode: snapshot.fetchMode,
        syncError: error.toString(),
        changeAdded: snapshot.changeAdded,
        changeRemoved: snapshot.changeRemoved,
      );

  Future<List<SafetyCamera>> fetchCameras() async =>
      (await fetchSnapshot()).cameras;
}
