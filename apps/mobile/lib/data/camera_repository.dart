import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/safety_camera.dart';
import 'api_config.dart';

class CameraSnapshot {
  const CameraSnapshot({
    required this.cameras,
    required this.syncStatus,
    this.sourceUpdatedAt,
    this.checkedAt,
    this.fetchMode,
    this.syncError,
    this.changeAdded = 0,
    this.changeRemoved = 0,
  });

  final List<SafetyCamera> cameras;
  final String syncStatus;
  final DateTime? sourceUpdatedAt;
  final DateTime? checkedAt;
  final String? fetchMode;
  final String? syncError;
  final int changeAdded;
  final int changeRemoved;
}

class CameraRepository {
  CameraRepository({http.Client? client, this.baseUrl = workerBaseUrl})
    : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  static const _cacheKey = 'kiwi.cache.cameras.v1';

  Future<CameraSnapshot> fetchSnapshot() async {
    Object? networkError;
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/api/cameras'))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw StateError('Camera API failed: ${response.statusCode}');
      }
      final snapshot = _decodeSnapshot(response.body);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_cacheKey, response.body);
      } catch (_) {
        // Persistent caching is best-effort and must never turn a successful
        // live response into an offline failure.
      }
      return snapshot;
    } catch (error) {
      networkError = error;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKey);
      if (cached != null) {
        final snapshot = _decodeSnapshot(cached);
        return CameraSnapshot(
          cameras: snapshot.cameras,
          syncStatus: 'stale',
          sourceUpdatedAt: snapshot.sourceUpdatedAt,
          checkedAt: snapshot.checkedAt,
          fetchMode: snapshot.fetchMode,
          syncError: networkError.toString(),
          changeAdded: snapshot.changeAdded,
          changeRemoved: snapshot.changeRemoved,
        );
      }
    } catch (_) {
      // Unit tests and unsupported platforms may not provide a preferences
      // binding. In that case surface the original network error.
    }
    throw networkError;
  }

  Future<CameraSnapshot> syncNow() async {
    final response = await _client
        .post(Uri.parse('$baseUrl/api/cameras/sync'))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw StateError('Camera sync failed: ${response.statusCode}');
    }
    final snapshot = _decodeSnapshot(response.body);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, response.body);
    } catch (_) {}
    return snapshot;
  }

  CameraSnapshot _decodeSnapshot(String raw) {
    final body = jsonDecode(raw) as Map<String, dynamic>;
    final cameras = (body['cameras'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SafetyCamera.fromJson)
        .toList(growable: false);
    return CameraSnapshot(
      cameras: cameras,
      syncStatus: body['syncStatus']?.toString() ?? 'unknown',
      sourceUpdatedAt: DateTime.tryParse(
        body['sourceUpdatedAt']?.toString() ?? '',
      ),
      checkedAt: DateTime.tryParse(body['checkedAt']?.toString() ?? ''),
      fetchMode: body['fetchMode']?.toString(),
      syncError: body['syncError']?.toString(),
      changeAdded:
          (body['change'] as Map<String, dynamic>?)?['added'] as int? ?? 0,
      changeRemoved:
          (body['change'] as Map<String, dynamic>?)?['removed'] as int? ?? 0,
    );
  }

  Future<List<SafetyCamera>> fetchCameras() async =>
      (await fetchSnapshot()).cameras;
}
