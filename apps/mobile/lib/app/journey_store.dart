import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../data/account_repository.dart';
import '../drive/journey_tracker.dart';

/// Finished-trip bookkeeping that must survive going offline: signed-in
/// trips wait in an idempotent outbox until the account confirms them, and
/// guest totals are imported once on sign-in.
class JourneyStore {
  JourneyStore(this._account);

  final AccountRepository _account;
  Future<void>? _pendingRouteFlush;

  static const guestPrefix = 'waybi.companion.guest.v1.';

  static String newJourneyId() =>
      'wb_${DateTime.now().microsecondsSinceEpoch}_${math.Random.secure().nextInt(0x7fffffff).toRadixString(16)}';

  Future<void> queueAccountJourney({
    required String destinationName,
    required double latitude,
    required double longitude,
    required String mode,
    required int distanceMeters,
    required int durationSeconds,
  }) async {
    final userId = _account.profile?.id;
    if (userId == null || userId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final journeyId = newJourneyId();
    final key = 'waybi.companion.outbox.v1.$userId.$journeyId';
    // Persist before network I/O: offline trips survive app restarts.
    await prefs.setString(
      key,
      jsonEncode({
        'journeyId': journeyId,
        'destinationName': destinationName,
        'latitude': latitude,
        'longitude': longitude,
        'mode': mode,
        'distanceMeters': distanceMeters,
        'durationSeconds': durationSeconds,
      }),
    );
    unawaited(syncPendingAccountJourneys().catchError((Object _) {}));
  }

  Future<void> syncPendingAccountJourneys() {
    final active = _pendingRouteFlush;
    if (active != null) return active;
    final future = _flushPendingAccountJourneys();
    _pendingRouteFlush = future;
    return future.whenComplete(() => _pendingRouteFlush = null);
  }

  Future<void> _flushPendingAccountJourneys() async {
    final userId = _account.profile?.id;
    if (userId == null ||
        userId.isEmpty ||
        !_account.signedIn ||
        _account.profile?.companionTotals == null) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'waybi.companion.outbox.v1.$userId.';
    final keys = prefs.getKeys().where((key) => key.startsWith(prefix)).toList()
      ..sort();
    for (final key in keys) {
      if (_account.profile?.id != userId || !_account.signedIn) break;
      final raw = prefs.getString(key);
      if (raw == null) continue;
      try {
        final route = jsonDecode(raw) as Map<String, dynamic>;
        await _account.recordRoute(
          journeyId: route['journeyId'] as String,
          destinationName: route['destinationName'] as String,
          latitude: (route['latitude'] as num).toDouble(),
          longitude: (route['longitude'] as num).toDouble(),
          mode: route['mode'] as String,
          distanceMeters: (route['distanceMeters'] as num).toInt(),
          durationSeconds: (route['durationSeconds'] as num).toInt(),
        );
        await prefs.remove(key); // Only after the backend confirms success.
      } catch (_) {
        // Keep the exact same idempotent payload for the next reconnect.
        break;
      }
    }
  }

  Future<void> syncGuestCompanionJourneys() async {
    if (!_account.signedIn || _account.profile?.companionTotals == null) return;
    final prefs = await SharedPreferences.getInstance();
    const prefix = 'waybi.companion.guest.v1.';
    final trips = prefs.getInt('${prefix}trips') ?? 0;
    if (trips <= 0) return;
    var importId = prefs.getString('${prefix}import_id');
    if (importId == null) {
      importId = newJourneyId();
      await prefs.setString('${prefix}import_id', importId);
    }
    try {
      await _account.importGuestJourneys(
        importId: importId,
        distanceMeters: prefs.getInt('${prefix}distance') ?? 0,
        tripCount: trips,
        durationSeconds: prefs.getInt('${prefix}duration') ?? 0,
      );
      // The import ID ensures a retry after a crash cannot double count.
      await prefs.remove('${prefix}distance');
      await prefs.remove('${prefix}duration');
      await prefs.remove('${prefix}trips');
      await prefs.remove('${prefix}import_id');
    } catch (_) {
      // Preserve local totals and import ID until a later successful sync.
    }
  }

  Future<void> recordGuestJourney(JourneySummary summary) async {
    final prefs = await SharedPreferences.getInstance();
    const prefix = 'waybi.companion.guest.v1.';
    await prefs.setInt(
      '${prefix}distance',
      (prefs.getInt('${prefix}distance') ?? 0) + summary.distanceMeters.round(),
    );
    await prefs.setInt(
      '${prefix}duration',
      (prefs.getInt('${prefix}duration') ?? 0) +
          summary.elapsed.inSeconds.clamp(0, 86400),
    );
    await prefs.setInt(
      '${prefix}trips',
      (prefs.getInt('${prefix}trips') ?? 0) + 1,
    );
  }
}
