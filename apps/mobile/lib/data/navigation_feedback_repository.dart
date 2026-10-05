import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';

/// A vote is saved before uploading. Random receipt IDs make retries
/// idempotent without sending a destination, account or location trace.
class NavigationFeedbackRepository {
  NavigationFeedbackRepository({http.Client? client})
    : _client = client ?? http.Client();
  final http.Client _client;
  static const saveKey = 'waybi.navigation_feedback.v1';
  Future<void> _writes = Future<void>.value();
  bool _flushing = false;

  Map<String, dynamic> _read(SharedPreferences prefs) {
    try {
      return Map<String, dynamic>.from(
        jsonDecode(prefs.getString(saveKey) ?? '{}') as Map,
      );
    } catch (_) {
      return {};
    }
  }

  Future<int?> voteFor(String tripId) async {
    await _writes.catchError((Object _) {});
    final prefs = await SharedPreferences.getInstance();
    final value = _read(prefs)[tripId];
    return value is Map ? value['vote'] as int? : null;
  }

  Future<void> vote(String tripId, int vote) async {
    if (vote != 1 && vote != -1) throw ArgumentError.value(vote);
    final write = _writes.catchError((Object _) {}).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final votes = _read(prefs);
      if (votes.containsKey(tripId)) return;
      final random = Random.secure();
      final id = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      votes[tripId] = {'id': id, 'vote': vote, 'sent': false};
      await prefs.setString(saveKey, jsonEncode(votes));
    });
    _writes = write;
    await write;
    await flush();
  }

  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = _read(prefs).entries
          .where((e) => e.value is Map && e.value['sent'] != true)
          .toList();
      for (final entry in pending) {
        final value = entry.value as Map;
        final response = await _client
            .post(
              Uri.parse('$workerBaseUrl/api/navigation-feedback'),
              headers: const {
                'content-type': 'application/json',
                'x-waybi-client': 'mobile',
              },
              body: jsonEncode({'id': value['id'], 'vote': value['vote']}),
            )
            .timeout(const Duration(seconds: 4));
        if (response.statusCode != 202) break;
        final write = _writes.catchError((Object _) {}).then((_) async {
          final current = _read(prefs);
          if (current[entry.key] is Map) current[entry.key]['sent'] = true;
          await prefs.setString(saveKey, jsonEncode(current));
        });
        _writes = write;
        await write;
      }
    } catch (_) {
      /* Keep the local vote for the next trip. */
    } finally {
      _flushing = false;
    }
  }

  void dispose() => _client.close();
}
