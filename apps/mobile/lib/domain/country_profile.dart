import 'map_provider.dart';

class CountryProfile {
  const CountryProfile({
    required this.code,
    required this.locale,
    required this.distanceUnit,
    required this.speedUnit,
    required this.drivingSide,
    required this.roadIntelligenceAvailable,
    this.region,
  });

  final String code;
  final String locale;
  final String distanceUnit;
  final String speedUnit;
  final String drivingSide;
  final bool roadIntelligenceAvailable;
  final String? region;
}

abstract final class CountryProfiles {
  static const nz = CountryProfile(
    code: 'NZ',
    locale: 'en-NZ',
    distanceUnit: 'km',
    speedUnit: 'km/h',
    drivingSide: 'left',
    roadIntelligenceAvailable: true,
  );

  /// Community reports and route intelligence are available worldwide.
  static const au = CountryProfile(
    code: 'AU',
    locale: 'en-AU',
    distanceUnit: 'km',
    speedUnit: 'km/h',
    drivingSide: 'left',
    roadIntelligenceAvailable: true,
  );

  static const global = CountryProfile(
    code: 'GLOBAL',
    locale: 'en',
    distanceUnit: 'km',
    speedUnit: 'km/h',
    drivingSide: 'unknown',
    roadIntelligenceAvailable: true,
  );

  static CountryProfile? at(GeoPoint point) {
    if (!point.isValid) return null;
    if (point.latitude >= -48 &&
        point.latitude <= -34 &&
        point.longitude >= 166 &&
        point.longitude <= 179) {
      return nz;
    }
    if (point.latitude >= -44 &&
        point.latitude <= -10 &&
        point.longitude >= 112 &&
        point.longitude <= 154) {
      return au;
    }
    return global;
  }
}
