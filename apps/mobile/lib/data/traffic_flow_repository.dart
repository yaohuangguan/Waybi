import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/traffic_flow.dart';
import 'api_config.dart';

class TrafficFlowRepository {
  TrafficFlowRepository({http.Client? client, this.baseUrl = workerBaseUrl})
    : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  Future<TrafficFlowSnapshot> load() async {
    final response = await _client
        .get(Uri.parse('$baseUrl/api/traffic-flow'))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('Traffic flow unavailable: ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final segments = (body['segments'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(TrafficFlowSegment.fromJson)
        .where((segment) => segment.start.isValid && segment.end.isValid)
        .toList(growable: false);
    if (segments.isEmpty) {
      throw StateError('Traffic flow response contained no usable segments');
    }
    return TrafficFlowSnapshot(
      segments: segments,
      syncStatus: body['syncStatus']?.toString() ?? 'unknown',
      sourceUpdatedAt: DateTime.tryParse(
        body['sourceUpdatedAt']?.toString() ?? '',
      ),
      checkedAt: DateTime.tryParse(body['checkedAt']?.toString() ?? ''),
    );
  }

  void dispose() => _client.close();
}
