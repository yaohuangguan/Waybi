import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/account_repository.dart';
import '../data/quick_location_store.dart';
import '../domain/geo_math.dart';
import '../domain/map_provider.dart';
import '../domain/route_option.dart';
import '../services/notification_service.dart';
import '../widgets/trips_page.dart' show RouteWatchItem;
import 'request_generation.dart';

/// The best drive route between two points, or null when there is none.
typedef DriveRouteLookup = Future<RouteOption?> Function(
  GeoPoint origin,
  GeoPoint destination,
);

/// Shows one Route Watch notification.
typedef CommuteAlert = Future<void> Function({
  required String id,
  required String title,
  required String body,
});

/// Home and Work, their live drive times, Smart Commute (both directions)
/// and Route Watch.
///
/// Shortcuts belong to one owner: a guest's live in [QuickLocationStore]
/// without an owner, an account's are synced with the account and cached
/// under its id. Every await re-checks the account, so a sign-out mid-sync
/// can never write the previous account's shortcuts back.
class CommuteController extends ChangeNotifier {
  CommuteController({
    required this._account,
    required this._bestDriveRoute,
    required this._origin,
    required this._paused,
    required this._language,
    required bool Function() routeWatchAlertsEnabled,
    QuickLocationStore? store,
    CommuteAlert? showAlert,
    DateTime Function()? clock,
  }) : _alertsEnabled = routeWatchAlertsEnabled,
       _store = store ?? QuickLocationStore(),
       _showAlert =
           showAlert ?? WaybiNotificationService.instance.showPlusCommuteAlert,
       _clock = clock ?? DateTime.now;

  final AccountRepository _account;
  final DriveRouteLookup _bestDriveRoute;
  final GeoPoint? Function() _origin;
  final bool Function() _paused;
  final String Function() _language;
  final bool Function() _alertsEnabled;
  final QuickLocationStore _store;
  final CommuteAlert _showAlert;
  final DateTime Function() _clock;
  bool _disposed = false;

  static const labels = ['Home', 'Work'];

  /// How long a commute ETA stays fresh while the car moves less than 800 m.
  static const freshFor = Duration(minutes: 10);

  /// Route Watch alerts are fetched at most this often unless forced.
  static const alertsEvery = Duration(minutes: 2);

  String _text(String en, String zh) => _language() == 'zh' ? zh : en;

  /// Set once the page restored its settings; nothing syncs before that.
  bool ready = false;

  final Map<String, PlaceSummary> _places = {};
  final Map<String, MapProvider> _providers = {};
  final Map<String, RouteOption> _quickRoutes = {};
  final Map<String, RouteOption> _smartRoutes = {};

  /// Home and Work by label.
  Map<String, PlaceSummary> get places => Map.unmodifiable(_places);
  MapProvider? providerOf(String label) => _providers[label];

  /// Drive time from here to Home / Work.
  Map<String, RouteOption> get quickRoutes => Map.unmodifiable(_quickRoutes);

  /// Smart Commute: 'home-work' and 'work-home'.
  Map<String, RouteOption> get smartRoutes => Map.unmodifiable(_smartRoutes);

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Shortcuts

  /// Loads the shortcuts saved on this device for the current owner.
  Future<void> loadSaved() async {
    final shortcuts = await _store.load();
    for (final entry in shortcuts.entries) {
      _places[entry.key] = entry.value.place;
      _providers[entry.key] = entry.value.provider;
    }
  }

  /// The account changed: sync the signed-in account's shortcuts, or show
  /// the guest's again after sign-out, and deliver Route Watch alerts.
  void onAccountChanged() {
    if (ready && _account.signedIn && _account.profile != null) {
      unawaited(syncWithAccount());
    } else if (ready && !_account.signedIn) {
      unawaited(restoreGuest());
    }
    if (_account.profile?.isPlus == true && _account.signedIn) {
      unawaited(deliverRouteWatchAlerts());
    }
  }

  Future<void> restoreGuest() async {
    final shortcuts = await _store.load();
    if (_disposed || _account.signedIn) return;
    for (final label in labels) {
      _places.remove(label);
      _providers.remove(label);
    }
    for (final entry in shortcuts.entries) {
      _places[entry.key] = entry.value.place;
      _providers[entry.key] = entry.value.provider;
    }
    _changed();
    unawaited(refreshQuick(force: true));
  }

  static bool _samePlace(PlaceSummary? a, PlaceSummary b) =>
      a != null &&
      a.name == b.name &&
      a.address == b.address &&
      a.location.latitude == b.location.latitude &&
      a.location.longitude == b.location.longitude;

  bool _syncing = false, _syncAgain = false;

  Future<void> syncWithAccount() async {
    if (!ready || !_account.signedIn || _account.profile == null) return;
    if (_syncing) {
      // A different account may have signed in while the last sync ran.
      _syncAgain = true;
      return;
    }
    _syncing = true;
    try {
      final profile = _account.profile!;
      final userId = profile.id;
      bool current() =>
          !_disposed && _account.signedIn && _account.profile?.id == userId;
      final cachedOwner = await _store.ownerUserId();
      final cached = await _store.load(ownerUserId: userId);
      if (!current()) return;
      final remote = <String, ({PlaceSummary place, MapProvider provider})>{};
      for (final item in profile.quickLocations) {
        final label = item['label']?.toString();
        final latitude = item['latitude'];
        final longitude = item['longitude'];
        if (!labels.contains(label) || latitude is! num || longitude is! num) {
          continue;
        }
        final point = GeoPoint(latitude.toDouble(), longitude.toDouble());
        if (!point.isValid) continue;
        remote[label!] = (
          place: PlaceSummary(
            name: item['name']?.toString() ?? label,
            address: item['address']?.toString() ?? '',
            location: point,
          ),
          provider: MapProvider.independent,
        );
      }

      var changed = false;
      if (cachedOwner != null && cachedOwner != userId) {
        for (final label in labels) {
          changed = _places.remove(label) != null || changed;
          _providers.remove(label);
        }
      }

      for (final label in labels) {
        final remoteValue = remote[label];
        if (remoteValue != null) {
          // Account notifications repeat for every profile refresh; only an
          // actual Home/Work change re-saves and re-routes the commutes.
          final shownSame = _samePlace(_places[label], remoteValue.place);
          final storedSame =
              cachedOwner == userId &&
              _samePlace(cached[label]?.place, remoteValue.place);
          if (shownSame && storedSame) continue;
          _places[label] = remoteValue.place;
          _providers[label] = remoteValue.provider;
          changed = changed || !shownSame;
          if (!storedSame) {
            await _store.save(
              label,
              remoteValue.place,
              remoteValue.provider,
              ownerUserId: userId,
            );
            if (!current()) return;
          }
          continue;
        }

        final localValue = cached[label];
        if (localValue == null) continue;
        if (!_samePlace(_places[label], localValue.place)) {
          _places[label] = localValue.place;
          _providers[label] = localValue.provider;
          changed = true;
        }
        try {
          await _account.saveQuickLocation(
            label: label,
            name: localValue.place.name,
            address: localValue.place.address,
            latitude: localValue.place.location.latitude,
            longitude: localValue.place.location.longitude,
            provider: localValue.provider.name,
          );
          if (!current()) return;
          await _store.save(
            label,
            localValue.place,
            localValue.provider,
            ownerUserId: userId,
          );
          if (!current()) return;
        } catch (_) {
          // Keep local shortcuts usable offline; the next account refresh retries sync.
          if (!current()) return;
        }
      }
      if (changed) {
        _changed();
        unawaited(refreshQuick(force: true));
      }
    } finally {
      _syncing = false;
      if (_syncAgain && !_disposed) {
        _syncAgain = false;
        unawaited(syncWithAccount());
      }
    }
  }

  /// Points [label] (Home or Work) at [place], on the device and, when
  /// signed in, on the account (retried by the next sync if offline).
  Future<void> setPlace(
    String label,
    PlaceSummary place,
    MapProvider provider,
  ) async {
    _places[label] = place;
    _providers[label] = provider;
    _changed();
    unawaited(refreshQuick(force: true));
    final owner = _account.signedIn ? _account.profile?.id : null;
    await _store.save(label, place, provider, ownerUserId: owner);
    if (!_account.signedIn) return;
    try {
      await _account.saveQuickLocation(
        label: label,
        name: place.name,
        address: place.address,
        latitude: place.location.latitude,
        longitude: place.location.longitude,
        provider: provider.name,
      );
    } catch (_) {
      // The local shortcut stays usable and syncs on the next account refresh.
    }
  }

  // ---------------------------------------------------------------------
  // Commute ETAs

  final _quickGeneration = RequestGeneration();
  Future<void>? _quickPending;
  bool _quickRefreshing = false;
  DateTime? _quickRefreshedAt;
  GeoPoint? _quickOrigin;

  /// Drive times from the current location to Home and Work. Shared while
  /// one is running; reused for 10 minutes unless the car moved 800 m.
  Future<void> refreshQuick({bool force = false}) {
    if (!force && _quickPending != null) return _quickPending!;
    late final Future<void> pending;
    pending = _loadQuick(force: force).whenComplete(() {
      if (identical(_quickPending, pending)) _quickPending = null;
    });
    return _quickPending = pending;
  }

  Future<void> _loadQuick({bool force = false}) async {
    if (_disposed || !ready || _paused()) return;
    if (_quickRefreshing && !force) return;
    final origin = _origin();
    if (origin == null) return;

    final targets = {
      for (final label in labels)
        if (_places[label] != null) label: _places[label]!,
    };
    if (targets.isEmpty) {
      if (_quickRoutes.isNotEmpty) {
        _quickRoutes.clear();
        _changed();
      }
      return;
    }

    final now = _clock();
    final last = _quickOrigin;
    final moved = last == null
        ? double.infinity
        : distanceMeters(
            origin.latitude,
            origin.longitude,
            last.latitude,
            last.longitude,
          );
    final fresh =
        _quickRefreshedAt != null &&
        now.difference(_quickRefreshedAt!) < freshFor;
    if (!force && fresh && moved < 800) return;

    final token = _quickGeneration.next();
    _quickRefreshing = true;
    final results = <String, RouteOption>{};
    try {
      await Future.wait(
        targets.entries.map((entry) async {
          try {
            final route = await _bestDriveRoute(origin, entry.value.location);
            if (route != null) results[entry.key] = route;
          } catch (_) {
            // Commute ETA is a progressive enhancement. Keep shortcuts usable
            // even when routing or traffic data is temporarily unavailable.
          }
        }),
      );
      if (_disposed || token.isStale) return;
      _quickRoutes
        ..clear()
        ..addAll(results);
      _quickRefreshedAt = now;
      _quickOrigin = origin;
      _changed();
    } finally {
      if (token.isCurrent) _quickRefreshing = false;
    }
  }

  bool _smartRefreshing = false;
  DateTime? _smartRefreshedAt;

  /// Smart Commute (Plus): Home→Work and Work→Home with live traffic.
  Future<void> refreshSmart({bool force = false}) async {
    final home = _places['Home'], work = _places['Work'];
    if (_disposed ||
        _paused() ||
        _account.profile?.isPlus != true ||
        home == null ||
        work == null) {
      clearSmart();
      return;
    }
    if (_smartRefreshing) return;
    final now = _clock();
    final fresh =
        _smartRefreshedAt != null &&
        now.difference(_smartRefreshedAt!) < freshFor;
    if (!force && fresh) return;

    _smartRefreshing = true;
    final results = <String, RouteOption>{};
    Future<void> load(String label, PlaceSummary from, PlaceSummary to) async {
      try {
        final route = await _bestDriveRoute(from.location, to.location);
        if (route != null) results[label] = route;
      } catch (_) {
        // Smart Commute remains useful with the saved baseline if live routing
        // is temporarily unavailable.
      }
    }

    try {
      await Future.wait([
        load('home-work', home, work),
        load('work-home', work, home),
      ]);
      if (_disposed) return;
      _smartRoutes
        ..clear()
        ..addAll(results);
      _smartRefreshedAt = now;
      _changed();
    } finally {
      _smartRefreshing = false;
    }
  }

  void clearSmart() {
    if (_smartRoutes.isEmpty) return;
    _smartRoutes.clear();
    _changed();
  }

  // ---------------------------------------------------------------------
  // Route Watch

  bool _checkingAlerts = false;
  DateTime? _alertsCheckedAt;

  /// Shows unread Route Watch alerts (newest per watch, at most four) and
  /// marks them read. Account refreshes and resumes call this often; it
  /// asks the server at most every [alertsEvery] unless [force]d.
  Future<void> deliverRouteWatchAlerts({bool force = false}) async {
    if (_checkingAlerts ||
        !_account.signedIn ||
        _account.profile?.isPlus != true ||
        !_alertsEnabled()) {
      return;
    }
    final now = _clock();
    final last = _alertsCheckedAt;
    if (!force && last != null && now.difference(last) < alertsEvery) return;
    _alertsCheckedAt = now;
    _checkingAlerts = true;
    try {
      final alerts = await _account.routeWatchAlerts();
      if (alerts.isEmpty) return;

      final latestByWatch = <String, Map<String, dynamic>>{};
      for (final alert in alerts) {
        final watchId = alert['routeWatchId']?.toString() ?? '';
        if (watchId.isEmpty || latestByWatch.containsKey(watchId)) continue;
        latestByWatch[watchId] = alert;
      }

      final selected = latestByWatch.values.take(4).toList(growable: false);
      for (final alert in selected.reversed) {
        final id = alert['id']?.toString() ?? '';
        final label = alert['label']?.toString().trim();
        final status = alert['status']?.toString() ?? 'warning';
        final events = (alert['events'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList(growable: false);
        final first = events.isEmpty ? null : events.first;
        final road = first?['roadName']?.toString().trim();
        final impact = first?['impact']?.toString().trim();
        final routeName = label == null || label.isEmpty
            ? _text('Saved commute', '已保存通勤')
            : label;
        final title = status == 'disrupted'
            ? _text('$routeName route disrupted', '$routeName 路线出现严重影响')
            : _text('$routeName route changed', '$routeName 路线出现变化');
        final body = road != null && road.isNotEmpty
            ? _text(
                impact != null && impact.isNotEmpty
                    ? '$road · $impact'
                    : 'Road event detected on $road',
                '检测到 $road 上的道路事件',
              )
            : _text(
                '${events.length} road event${events.length == 1 ? '' : 's'} may affect this route.',
                '${events.length} 个道路事件可能影响这条路线。',
              );
        if (id.isNotEmpty) await _showAlert(id: id, title: title, body: body);
      }

      final ids = alerts
          .map((alert) => alert['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList(growable: false);
      if (ids.isNotEmpty) await _account.markRouteWatchAlertsRead(ids);
    } catch (_) {
      // Route Watch is additive; map and navigation remain usable offline.
    } finally {
      _checkingAlerts = false;
    }
  }

  /// At most 220 evenly spaced points, as the Route Watch API expects.
  static List<Map<String, double>> watchPoints(List<GeoPoint> points) {
    if (points.length < 2) return const [];
    const maxPoints = 220;
    final sampled = points.length <= maxPoints
        ? points
        : List<GeoPoint>.generate(
            maxPoints,
            (index) =>
                points[(index * (points.length - 1) / (maxPoints - 1)).round()],
            growable: false,
          );
    return sampled
        .map(
          (point) => <String, double>{
            'latitude': point.latitude,
            'longitude': point.longitude,
          },
        )
        .toList(growable: false);
  }

  /// Turns Route Watch for 'home-work' / 'work-home' on (with a fresh live
  /// route as the baseline) or off. Errors are already localized.
  Future<void> setRouteWatch(
    String label,
    RouteWatchItem? current,
    bool enabled,
  ) async {
    if (!_account.signedIn) {
      throw StateError(_text('Sign in to use Route Watch.', '请先登录后使用路线监控。'));
    }
    if (_account.profile?.isPlus != true) {
      throw StateError(
        _text('Smart Commute is a Waybi Plus feature.', '智能通勤是 Waybi Plus 功能。'),
      );
    }
    if (!enabled) {
      if (current != null) await _account.deleteRouteWatch(current.id);
      return;
    }

    final pair = switch (label) {
      'home-work' => ('Home', 'Work'),
      'work-home' => ('Work', 'Home'),
      _ => throw StateError(
        _text('This Route Watch is not available.', '这条路线监控不可用。'),
      ),
    };
    final origin = _places[pair.$1];
    final destination = _places[pair.$2];
    if (origin == null || destination == null) {
      throw StateError(
        _text(
          'Set both Home and Work before enabling Route Watch.',
          '请先同时设置“家”和“公司”，再开启路线监控。',
        ),
      );
    }

    final route = await _bestDriveRoute(origin.location, destination.location);
    if (route == null || route.points.length < 2) {
      throw StateError(
        _text(
          'A live driving route is required before Route Watch can start.',
          '需要先获取实时驾车路线，才能开启路线监控。',
        ),
      );
    }

    await _account.saveRouteWatch(
      label: label,
      originName: origin.name,
      originLatitude: origin.location.latitude,
      originLongitude: origin.location.longitude,
      destinationName: destination.name,
      latitude: destination.location.latitude,
      longitude: destination.location.longitude,
      routeProvider: route.provider,
      routePoints: watchPoints(route.points),
      durationSeconds: route.durationSeconds,
      distanceMeters: route.distanceMeters,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _quickGeneration.invalidate();
    super.dispose();
  }
}
