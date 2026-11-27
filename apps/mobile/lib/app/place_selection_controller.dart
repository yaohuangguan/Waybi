import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/http_guard.dart' show RateLimitedException;
import '../data/place_details_repository.dart';
import '../domain/geo_math.dart';
import '../domain/map_provider.dart';
import '../domain/route_option.dart';
import '../domain/route_reachability.dart';
import '../widgets/friendly_error.dart';
import 'request_generation.dart';

/// The best drive route for a place card's ETA; throws when there is none.
typedef PlaceRouteLookup = Future<RouteOption> Function(
  GeoPoint origin,
  GeoPoint destination,
);

/// A reverse-geocoded name and address near a point.
typedef ReverseLookup = Future<PlaceSummary?> Function(
  GeoPoint point,
  String preferredName,
);

/// The place card: which place is selected, its details and its drive ETA.
///
/// Every load carries a generation token, so a late answer for a previous
/// place (or a closed card) never changes the card. A failed ETA is cached
/// and retried with backoff instead of on every GPS fix.
class PlaceSelectionController extends ChangeNotifier {
  PlaceSelectionController({
    required this._fetchDetails,
    required this._reverse,
    required this._route,
    required this._language,
    required bool Function() quickRouteSuppressed,
    DateTime Function()? clock,
  }) : _suppressed = quickRouteSuppressed,
       _clock = clock ?? DateTime.now;

  final Future<PlaceDetails> Function(PlaceSummary place) _fetchDetails;
  final ReverseLookup _reverse;
  final PlaceRouteLookup _route;
  final String Function() _language;
  final bool Function() _suppressed;
  final DateTime Function() _clock;
  bool _disposed = false;

  String _text(String en, String zh) => _language() == 'zh' ? zh : en;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  SelectedPlace? _selected;
  SelectedPlace? get selected => _selected;

  PlaceDetails? details;
  bool detailsLoading = false;
  String? detailsError;

  RouteOption? quickRoute;
  bool quickRouteLoading = false;
  String? quickRouteIssue;

  final _detailsGeneration = RequestGeneration();
  final _routeGeneration = RequestGeneration();

  /// Cache key of a place: its provider id, else its rounded coordinate.
  static String routeKey(PlaceSummary place) {
    final reference = place.reference;
    if (reference != null) return '${reference.provider}:${reference.id}';
    return '${place.location.latitude.toStringAsFixed(5)},${place.location.longitude.toStringAsFixed(5)}';
  }

  /// Selects [place]: resets its ETA, loads (or uses [seedDetails]) its
  /// details and, for a map tap without an address, looks the address up.
  void select(
    PlaceSummary place,
    SelectionSource source, {
    required MapProvider originMap,
    PlaceDetails? seedDetails,
  }) {
    _selected = SelectedPlace(place, source, originMap: originMap);
    _resetQuickRoute();
    if (seedDetails == null) {
      unawaited(loadDetails(place));
    } else {
      _detailsGeneration.invalidate();
      details = seedDetails;
      detailsLoading = false;
      detailsError = null;
    }
    _changed();
    if ((source == SelectionSource.map ||
            source == SelectionSource.longPress) &&
        place.address.isEmpty) {
      unawaited(_enrich(place, source, originMap));
    }
  }

  /// Points the card at [value] without reloading anything (a car park or
  /// the original destination of a parking leg).
  void replace(SelectedPlace value) {
    _selected = value;
    _changed();
  }

  /// No place: the card closes and every load in flight is dropped.
  void clear() {
    _selected = null;
    _detailsGeneration.invalidate();
    details = null;
    detailsLoading = false;
    detailsError = null;
    _resetQuickRoute();
    _changed();
  }

  void _resetQuickRoute() {
    _routeGeneration.invalidate();
    quickRoute = null;
    quickRouteIssue = null;
    quickRouteLoading = false;
    _loadingKey = null;
  }

  /// Drops an ETA in flight (a preview took over the card).
  void cancelQuickRoute() => _routeGeneration.invalidate();

  Future<void> loadDetails(PlaceSummary place) async {
    final token = _detailsGeneration.next();
    details = null;
    detailsLoading = true;
    detailsError = null;
    _changed();
    try {
      final loaded = await _fetchDetails(place);
      if (_disposed || token.isStale) return;
      details = loaded;
      detailsLoading = false;
      _changed();
    } catch (error) {
      if (_disposed || token.isStale) return;
      detailsLoading = false;
      detailsError = friendlyErrorMessage(
        error,
        _language(),
        fallback: _text(
          'Place details are unavailable right now.',
          '暂时无法加载地点详情。',
        ),
      );
      _changed();
    }
  }

  void retryDetails() {
    final place = _selected?.place;
    if (place != null) unawaited(loadDetails(place));
  }

  Future<void> _enrich(
    PlaceSummary original,
    SelectionSource source,
    MapProvider originMap,
  ) async {
    try {
      final coordinate =
          original.kind == PlaceKind.coordinate &&
          source != SelectionSource.longPress;
      final resolved = await _reverse(
        original.location,
        coordinate ? '' : original.name,
      );
      if (_disposed ||
          resolved == null ||
          !identical(_selected?.place, original)) {
        return;
      }
      _selected = SelectedPlace(
        PlaceSummary(
          name: coordinate ? resolved.name : original.name,
          location: original.location,
          address: resolved.address,
          category: original.category.isEmpty
              ? resolved.category
              : original.category,
          kind: coordinate ? resolved.kind : original.kind,
          reference: source == SelectionSource.longPress
              ? null
              : resolved.reference,
        ),
        source,
        originMap: originMap,
      );
      _changed();
    } catch (_) {
      // A map feature remains selectable if reverse lookup is unavailable.
    }
  }

  // ---------------------------------------------------------------------
  // Drive ETA

  final Map<String, ({RouteOption route, DateTime at, GeoPoint origin})>
  _cache = {};

  /// A failed ETA is retried with backoff (15 s doubling to 5 min, or the
  /// server's Retry-After), not on every GPS fix.
  final Map<String, ({DateTime retryAt, int failures, String message})>
  _failures = {};
  String? _loadingKey;

  static Duration backoff(int failures, Object error) {
    final base = Duration(
      seconds: (15 * math.pow(2, (failures - 1).clamp(0, 5))).round().clamp(
        15,
        300,
      ),
    );
    if (error is RateLimitedException && error.retryAfter > base) {
      return error.retryAfter;
    }
    return base;
  }

  bool _isSelected(String key) {
    final place = _selected?.place;
    return place != null && routeKey(place) == key;
  }

  /// The drive ETA from [origin] to the selected place, reused for five
  /// minutes while the origin moves less than 300 m.
  Future<void> loadQuickRoute(GeoPoint? origin) async {
    final place = _selected?.place;
    if (_disposed || place == null || origin == null || _suppressed()) return;
    if (!place.location.isValid) return;
    final key = routeKey(place);
    if (isCrossTasmanSurfaceRoute([origin, place.location])) {
      _routeGeneration.invalidate();
      quickRoute = null;
      quickRouteLoading = false;
      _loadingKey = null;
      quickRouteIssue = const NoSurfaceRouteException().localized(_language());
      _changed();
      return;
    }
    final cached = _cache[key];
    final fresh =
        cached != null &&
        _clock().difference(cached.at) < const Duration(minutes: 5) &&
        distanceMeters(
              origin.latitude,
              origin.longitude,
              cached.origin.latitude,
              cached.origin.longitude,
            ) <
            300;
    if (fresh) {
      if (!identical(quickRoute, cached.route) ||
          quickRouteIssue != null ||
          quickRouteLoading) {
        quickRoute = cached.route;
        quickRouteIssue = null;
        quickRouteLoading = false;
        _loadingKey = null;
        _changed();
      }
      return;
    }
    final failure = _failures[key];
    if (failure != null && _clock().isBefore(failure.retryAt)) {
      if (quickRouteIssue != failure.message || quickRouteLoading) {
        quickRoute = null;
        quickRouteIssue = failure.message;
        quickRouteLoading = false;
        _loadingKey = null;
        _changed();
      }
      return;
    }
    if (quickRouteLoading && _loadingKey == key) return;

    final token = _routeGeneration.next();
    // Keep a previous failure visible until the retry answers; clearing it
    // first makes the card flash on every attempt.
    quickRoute = null;
    quickRouteLoading = true;
    _loadingKey = key;
    _changed();
    // Only this request, for the place still selected, may change the card.
    bool current() =>
        !_disposed && token.isCurrent && !_suppressed() && _isSelected(key);
    try {
      final route = await _route(origin, place.location);
      _failures.remove(key);
      if (_cache.length >= 20 && !_cache.containsKey(key)) {
        final oldest = _cache.entries
            .reduce((a, b) => a.value.at.isBefore(b.value.at) ? a : b)
            .key;
        _cache.remove(oldest);
      }
      _cache[key] = (route: route, at: _clock(), origin: origin);
      if (!current()) return;
      quickRoute = route;
      quickRouteIssue = null;
      quickRouteLoading = false;
      _loadingKey = null;
      _changed();
    } catch (error) {
      final failures = (_failures[key]?.failures ?? 0) + 1;
      final message = routeFailureMessage(error, _language());
      _failures[key] = (
        retryAt: _clock().add(backoff(failures, error)),
        failures: failures,
        message: message,
      );
      if (_failures.length > 20) _failures.remove(_failures.keys.first);
      if (!current()) return;
      quickRoute = null;
      quickRouteIssue = message;
      quickRouteLoading = false;
      _loadingKey = null;
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _detailsGeneration.invalidate();
    _routeGeneration.invalidate();
    super.dispose();
  }
}
