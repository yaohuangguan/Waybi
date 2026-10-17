import 'dart:async';

import 'country_profile.dart';
import 'map_provider.dart';
import 'route_option.dart';

/// A route cannot be served by Waybi's surface-navigation engines.
class NoSurfaceRouteException implements Exception {
  const NoSurfaceRouteException();
  String localized(String language) => language == 'zh'
      ? '新西兰和澳大利亚之间无法直接驾车抵达。你仍可以查看目的地，抵达当地后再规划路线。'
      : 'There is no drivable route between New Zealand and Australia. You can still explore the destination and plan a local route after arriving.';
  @override
  String toString() => localized('en');
}

/// Check only the disconnected NZ/Australia road networks.
/// Do not block international land crossings or Australian interstate routes.
bool isCrossTasmanSurfaceRoute(List<GeoPoint> points) {
  for (var i = 1; i < points.length; i++) {
    final previous = CountryProfiles.at(points[i - 1])?.code;
    final next = CountryProfiles.at(points[i])?.code;
    if ((previous == 'NZ' && next == 'AU') ||
        (previous == 'AU' && next == 'NZ')) {
      return true;
    }
  }
  return false;
}

void validateSurfaceRoute(List<GeoPoint> points, {WaybiTravelMode? mode}) {
  // Transit planning does not include flights, and none of Waybi's providers
  // supports an NZ-AU sea crossing for any of these travel modes.
  if (isCrossTasmanSurfaceRoute(points)) {
    throw const NoSurfaceRouteException();
  }
}

String routeFailureMessage(Object error, String language) {
  if (error is NoSurfaceRouteException) return error.localized(language);
  if (error is TimeoutException) {
    return language == 'zh'
        ? '路线查询超时，请检查网络后重试。'
        : 'Route lookup timed out. Check your connection and try again.';
  }
  final message = error.toString().toLowerCase();
  if (message.contains('no route') ||
      message.contains('could not find a route') ||
      message.contains('no independent routes')) {
    return language == 'zh'
        ? '暂时没有可用的路线，请检查起点、终点或换一种出行方式。'
        : 'No route is available. Check the start and destination or try another travel mode.';
  }
  return language == 'zh'
      ? '路线服务暂时不可用，请稍后重试。'
      : 'Route service is temporarily unavailable. Please try again.';
}
