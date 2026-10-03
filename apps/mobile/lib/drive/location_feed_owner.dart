import 'dart:async';

/// Geolocator caches its first position stream's platform settings. Release the
/// old stream completely before navigation subscribes with background settings.
class LocationFeedOwner {
  StreamSubscription<dynamic>? subscription;

  Future<void> release() async {
    final previous = subscription;
    subscription = null;
    await previous?.cancel();
    // The broadcast stream's onCancel resets the platform singleton next tick.
    await Future<void>.delayed(Duration.zero);
  }
}
