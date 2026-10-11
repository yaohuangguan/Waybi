import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/transit_lane.dart';
import 'api_config.dart';

class TransitLaneSnapshot {
  TransitLaneSnapshot(Map<String, dynamic> json)
    : lanes = (json['lanes'] as List)
          .whereType<Map<String, dynamic>>()
          .map(TransitLane.fromJson)
          .toList(),
      checkedAt = DateTime.parse(json['checkedAt'] as String),
      sourceUpdatedAt = DateTime.tryParse(
        json['sourceUpdatedAt']?.toString() ?? '',
      ),
      source = json['source'] as String,
      syncStatus = json['syncStatus'] as String? ?? 'seed';
  final List<TransitLane> lanes;
  final DateTime checkedAt;
  final DateTime? sourceUpdatedAt;
  final String source, syncStatus;
}

/// One shared city snapshot. No GPS upload, per-location request or navigation
/// polling. Bundled data works immediately; each device checks at most weekly.
class TransitLaneRepository {
  TransitLaneRepository({
    http.Client? client,
    this.baseUrl = workerBaseUrl,
    DateTime Function()? clock,
    Future<String> Function()? seedLoader,
  }) : _client = client ?? http.Client(),
       _clock = clock ?? DateTime.now,
       _seedLoader =
           seedLoader ??
           (() => rootBundle.loadString('assets/data/transit-lanes.json'));
  final http.Client _client;
  final String baseUrl;
  final DateTime Function() _clock;
  final Future<String> Function() _seedLoader;
  Future<TransitLaneSnapshot>? _local;
  Future<TransitLaneSnapshot>? _refresh;
  static const _cache = 'waybi.transit_lanes.v1',
      _attempt = 'waybi.transit_lanes.last_attempt';

  Future<TransitLaneSnapshot> loadLocal() => _local ??= _loadLocal();
  Future<TransitLaneSnapshot> _loadLocal() async {
    final seed = TransitLaneSnapshot(
      jsonDecode(await _seedLoader()) as Map<String, dynamic>,
    );
    try {
      final prefs = await SharedPreferences.getInstance(),
          raw = prefs.getString(_cache);
      if (raw != null) {
        final cached = TransitLaneSnapshot(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        if (cached.lanes.length >= 200 &&
            cached.checkedAt.isAfter(seed.checkedAt)) {
          return cached;
        }
      }
    } catch (_) {
      /* Retain the bundled snapshot. */
    }
    return seed;
  }

  Future<TransitLaneSnapshot> refresh() {
    final pending = _refresh;
    if (pending != null) return pending;
    final job = _refreshSnapshot();
    _refresh = job;
    return job.whenComplete(() => _refresh = null);
  }

  Future<TransitLaneSnapshot> _refreshSnapshot() async {
    final previous = await loadLocal(), now = _clock();
    if (now.difference(previous.checkedAt) < const Duration(days: 7)) {
      return previous;
    }
    final prefs = await SharedPreferences.getInstance();
    final last = DateTime.tryParse(prefs.getString(_attempt) ?? '');
    if (last != null && now.difference(last) < const Duration(days: 7)) {
      return previous;
    }
    // Persist the attempt first, including failures; relaunches cannot hammer
    // the free Worker while connectivity or the upstream snapshot is stale.
    await prefs.setString(_attempt, now.toIso8601String());
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/api/transit-lanes'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return previous;
      final json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (json['schemaVersion'] != 1) return previous;
      final next = TransitLaneSnapshot(json);
      if (next.lanes.length < 200 ||
          next.checkedAt.isBefore(previous.checkedAt)) {
        return previous;
      }
      await prefs.setString(_cache, response.body);
      _local = Future.value(next);
      return next;
    } catch (_) {
      return previous;
    }
  }
}
