import 'map_provider.dart';
import 'route_option.dart';

/// An external location is either a coordinate or a query the user must resolve.
class NavigationTarget {
  const NavigationTarget({required this.label, this.coordinate});

  final String label;
  final GeoPoint? coordinate;

  static NavigationTarget parse(String value, {String? label}) {
    final text = value.trim();
    if (text.isEmpty ||
        text.length > 1000 ||
        text.contains(RegExp(r'[\x00-\x1f]'))) {
      throw const FormatException('Invalid location');
    }
    final pair = text.split(',');
    final latitude = pair.length == 2 ? double.tryParse(pair[0].trim()) : null;
    final longitude = pair.length == 2 ? double.tryParse(pair[1].trim()) : null;
    if (latitude != null && longitude != null) {
      if (!latitude.isFinite ||
          !longitude.isFinite ||
          latitude.abs() > 90 ||
          longitude.abs() > 180) {
        throw const FormatException('Invalid coordinates');
      }
      return NavigationTarget(
        label: label?.trim().isNotEmpty == true ? label!.trim() : text,
        coordinate: GeoPoint(latitude, longitude),
      );
    }
    return NavigationTarget(label: text);
  }
}

class NavigationLink {
  const NavigationLink({
    required this.destination,
    this.source,
    this.waypoints = const [],
    this.mode = WaybiTravelMode.drive,
    this.showPlaceOnly = false,
  });

  final NavigationTarget destination;
  final NavigationTarget? source;
  final List<NavigationTarget> waypoints;
  final WaybiTravelMode mode;
  final bool showPlaceOnly;

  /// Returns null for unrelated links, including sign-in callbacks.
  /// Throws for a recognized link with invalid or ambiguous location data.
  static NavigationLink? parse(String value) {
    if (value.length > 12000) throw const FormatException('Link too long');
    final uri = Uri.parse(value);
    if (uri.scheme != 'waybi' && uri.scheme != 'geo-navigation') return null;
    if (uri.hasFragment || uri.userInfo.isNotEmpty || uri.hasPort) {
      throw const FormatException('Invalid navigation link');
    }
    final action = uri.host.isNotEmpty
        ? uri.host
        : uri.path.replaceFirst(RegExp(r'^/'), '');
    if (uri.host.isNotEmpty && uri.path.isNotEmpty && uri.path != '/') {
      throw const FormatException('Invalid navigation action');
    }
    if (!(uri.scheme == 'waybi' && action == 'navigate') &&
        !(uri.scheme == 'geo-navigation' &&
            (action == 'directions' || action == 'place'))) {
      throw const FormatException('Unknown navigation action');
    }
    final parameters = uri.queryParametersAll;
    String? single(String key) {
      final values = parameters[key];
      if (values == null) return null;
      if (values.length != 1) throw FormatException('Duplicate $key');
      return values.single;
    }

    final isPlace = action == 'place';
    String? destination;
    if (isPlace) {
      final coordinate = single('coordinate');
      final address = single('address');
      if (coordinate != null && address != null) {
        throw const FormatException('Ambiguous place');
      }
      destination = coordinate ?? address;
      if (coordinate != null &&
          NavigationTarget.parse(coordinate).coordinate == null) {
        throw const FormatException('Invalid coordinates');
      }
    } else {
      destination = single('destination');
    }
    if (destination == null) throw const FormatException('Missing destination');
    final waypointValues = parameters['waypoint'] ?? const <String>[];
    if (waypointValues.length > 10 || (isPlace && waypointValues.isNotEmpty)) {
      throw const FormatException('Invalid waypoints');
    }
    final source = single('source');
    if (isPlace && source != null) {
      throw const FormatException('Invalid source');
    }
    final mode = switch (single('mode')) {
      null || 'drive' => WaybiTravelMode.drive,
      'walk' => WaybiTravelMode.walk,
      'bicycle' => WaybiTravelMode.bicycle,
      'transit' => WaybiTravelMode.transit,
      _ => throw const FormatException('Invalid travel mode'),
    };
    return NavigationLink(
      destination: NavigationTarget.parse(destination, label: single('name')),
      source: source == null ? null : NavigationTarget.parse(source),
      waypoints: List.unmodifiable(waypointValues.map(NavigationTarget.parse)),
      mode: mode,
      showPlaceOnly: isPlace,
    );
  }
}
