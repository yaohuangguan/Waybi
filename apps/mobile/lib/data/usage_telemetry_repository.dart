import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';

class UsageTelemetryRepository {
  UsageTelemetryRepository({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<void> record(String event, {int units = 1}) async {
    try {
      await _client
          .post(
            Uri.parse('$workerBaseUrl/api/telemetry/usage'),
            headers: const {
              'content-type': 'application/json',
              'x-waybi-client': 'mobile',
            },
            body: jsonEncode({'event': event, 'units': units.clamp(1, 25)}),
          )
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      // Telemetry is best-effort and must never interrupt a journey.
    }
  }

  void dispose() => _client.close();
}
