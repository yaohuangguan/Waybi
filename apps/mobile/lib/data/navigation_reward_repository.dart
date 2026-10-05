import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:waybi_friends/waybi_friends.dart';

import '../domain/map_provider.dart';
import '../drive/journey_tracker.dart';
import 'api_config.dart';

class NavigationRewardRepository {
  NavigationRewardRepository({http.Client? client, GameController? controller})
    : _client = client ?? http.Client(),
      controller = controller ?? GameController.embedded;
  final http.Client _client;
  final GameController controller;

  Future<String?> countryAt(GeoPoint point) async {
    if (!point.isValid) return null;
    try {
      final uri = Uri.parse('$workerBaseUrl/api/reverse').replace(
        queryParameters: {'at': '${point.longitude},${point.latitude}'},
      );
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final code = (body['countryCode'] as String?)?.toUpperCase();
      return code != null && RegExp(r'^[A-Z]{2}$').hasMatch(code) ? code : null;
    } catch (_) {
      return null;
    }
  }

  Future<JourneyMemory?> complete(
    JourneySummary summary, {
    Future<String?>? country,
  }) async {
    if (!summary.arrived) return null;
    final code = await (country ?? Future<String?>.value(null));
    return controller.rememberArrival(
      tripId: '${summary.startedAt.microsecondsSinceEpoch}',
      destinationName: summary.destination,
      countryCode: code,
    );
  }

  void dispose() => _client.close();
}
