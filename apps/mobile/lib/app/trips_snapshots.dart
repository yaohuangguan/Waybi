import 'package:shared_preferences/shared_preferences.dart';

import '../data/account_repository.dart';
import '../domain/map_provider.dart';
import '../widgets/trips_page.dart';
import 'commute_controller.dart';
import 'journey_store.dart';

/// What the Trips and Discover pages show: Home and Work with their drive
/// times, recent places, the account's trip history and lifetime totals
/// (or the guest's), Route Watch and Smart Commute.
class TripsSnapshots {
  TripsSnapshots({
    required this._account,
    required this._commute,
    required this._journeys,
    required this._recent,
    required this._active,
    required this._language,
  });

  final AccountRepository _account;
  final CommuteController _commute;
  final JourneyStore _journeys;

  /// Recent destinations, newest first.
  final List<TripDestination> Function() _recent;

  /// False once the page is gone: refreshes in flight stop.
  final bool Function() _active;
  final String Function() _language;

  static const _guestPrefix = 'waybi.companion.guest.v1.';

  Future<TripsSnapshot> read({
    Map<String, RouteWatchItem> routeWatches = const {},
  }) async {
    final profile = _account.profile;
    final quickPlaces = <String, TripDestination>{
      for (final label in CommuteController.labels)
        if (_commute.places[label] case final place?)
          label: TripDestination(
            name: place.name,
            address: place.address,
            location: place.location,
          ),
    };
    final history = <TripHistoryItem>[];
    for (final record in profile?.routes ?? const <Map<String, dynamic>>[]) {
      final latitude = record['latitude'];
      final longitude = record['longitude'];
      final distance = record['distanceMeters'];
      final duration = record['durationSeconds'];
      if (latitude is! num ||
          longitude is! num ||
          distance is! num ||
          duration is! num) {
        continue;
      }
      final startedAt = record['startedAt'];
      history.add(
        TripHistoryItem(
          destination: TripDestination(
            name:
                record['destinationName']?.toString() ??
                (_language() == 'zh' ? '最近行程' : 'Recent trip'),
            location: GeoPoint(latitude.toDouble(), longitude.toDouble()),
          ),
          mode: record['mode']?.toString() ?? 'drive',
          distanceMeters: distance.toInt(),
          durationSeconds: duration.toInt(),
          createdAt: startedAt is num
              ? DateTime.fromMillisecondsSinceEpoch(startedAt.toInt())
              : DateTime.tryParse(
                  (record['createdAt'] ?? startedAt)?.toString() ?? '',
                ),
        ),
      );
    }
    final prefs = await SharedPreferences.getInstance();
    final totals = profile?.companionTotals;
    return TripsSnapshot(
      lifetimeDistanceMeters: totals?.distanceMeters,
      lifetimeTripCount: totals?.tripCount,
      lifetimeDurationSeconds: totals?.durationSeconds,
      guestDistanceMeters: prefs.getInt('${_guestPrefix}distance') ?? 0,
      guestTripCount: prefs.getInt('${_guestPrefix}trips') ?? 0,
      guestDurationSeconds: prefs.getInt('${_guestPrefix}duration') ?? 0,
      quickPlaces: quickPlaces,
      quickRoutes: _commute.quickRoutes,
      recent: _recent(),
      history: history,
      routeWatches: routeWatches,
      smartCommuteRoutes: _commute.smartRoutes,
      signedIn: _account.signedIn,
      isPlus: profile?.isPlus == true,
    );
  }

  /// The cached snapshot first, then again after each refresh (the
  /// account, journeys waiting to sync, drive times, Route Watch). A
  /// sign-out midway stops the account's refreshes.
  Stream<TripsSnapshot> progressive() {
    final session = _account.sessionToken;
    bool current() => _active() && _account.sessionToken == session;
    final watches = <String, RouteWatchItem>{};
    return loadTripsInStages(
      readSnapshot: () => read(
        routeWatches: _account.sessionToken == session
            ? Map.of(watches)
            : const {},
      ),
      refreshers: [
        if (_account.signedIn)
          (publish) async {
            try {
              await _account.refresh();
            } catch (_) {
              // Keep the cached profile.
            }
            publish();
            if (!current()) return;
            await _journeys.syncGuestCompanionJourneys();
            publish();
            if (!current()) return;
            await _journeys.syncPendingAccountJourneys();
          },
        (_) => _commute.refreshQuick(),
        if (_account.signedIn && _account.profile?.isPlus == true)
          (publish) async {
            for (final item in await _account.routeWatches()) {
              if (!current()) return;
              final watch = RouteWatchItem.fromJson(item);
              if (watch.id.isNotEmpty && watch.label.isNotEmpty) {
                watches[watch.label] = watch;
              }
            }
            publish();
            if (watches.isNotEmpty) {
              await _commute.refreshSmart();
            } else {
              _commute.clearSmart();
            }
          },
      ],
    );
  }

  /// The snapshot after every refresh.
  Future<TripsSnapshot> load() => progressive().last;
}
