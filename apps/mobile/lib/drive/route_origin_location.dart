import '../domain/map_provider.dart';
import 'navigation_location_filter.dart';

/// Route previews can use a fresh, precise OS fix before stationary puck
/// confirmation. Camera gestures never supply or invalidate this location.
class RouteOriginLocation {
  RouteOriginLocation({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  NavigationLocationFix? _firstFix, _confirmed;

  void update(NavigationLocationFix fix, {required bool confirmed}) {
    if (confirmed) {
      _confirmed = fix;
    } else if (_confirmed == null && _usable(fix, 25, 10)) {
      _firstFix = fix;
    }
  }

  GeoPoint? get point {
    final confirmed = _confirmed;
    if (confirmed != null) {
      return _usable(confirmed, 35, 30) ? confirmed.point : null;
    }
    final first = _firstFix;
    return first != null && _usable(first, 25, 10) ? first.point : null;
  }

  bool _usable(NavigationLocationFix fix, double accuracy, int seconds) {
    final age = _clock().difference(fix.timestamp);
    return fix.point.isValid &&
        fix.accuracyMeters.isFinite &&
        fix.accuracyMeters > 0 &&
        fix.accuracyMeters <= accuracy &&
        age >= const Duration(seconds: -5) &&
        age <= Duration(seconds: seconds);
  }
}
