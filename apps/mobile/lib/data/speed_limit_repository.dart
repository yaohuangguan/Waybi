import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'http_guard.dart';

class SpeedLimitInfo {
  const SpeedLimitInfo({required this.speedLimitKph, this.zoneName});

  final int? speedLimitKph;
  final String? zoneName;
}

class SpeedLimitRepository {
  SpeedLimitRepository({
    http.Client? client,
    this.baseUrl = workerBaseUrl,
    this.timeout = const Duration(seconds: 5),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  /// A stalled lookup must never freeze the displayed limit.
  final Duration timeout;

  /// Throws [RateLimitedException] on HTTP 429 so the caller can back off.
  Future<SpeedLimitInfo> fetch({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.parse('$baseUrl/api/speed-limit?at=$longitude,$latitude');
    final response = await abortableGet(_client, uri, timeout: timeout);
    final body = decodeJsonResponse(
      response,
      unavailable: 'Speed limit API failed: ${response.statusCode}',
    );
    if (body is! Map<String, dynamic>) {
      throw ApiException('Speed limit API returned an invalid response');
    }
    return SpeedLimitInfo(
      speedLimitKph: (body['speedLimitKph'] as num?)?.round(),
      zoneName: body['zoneName'] as String?,
    );
  }
}
