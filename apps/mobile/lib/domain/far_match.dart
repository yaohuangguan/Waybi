import 'geo_math.dart';
import 'map_provider.dart';

/// A named place (a POI, a residential compound, a street address) this far
/// from the driver is probably a namesake, not the place they meant: in
/// Shijiazhuang the only OpenStreetMap "盛世春天" is 494 km away in Luohe.
const farMatchThresholdMeters = 50000.0;

const _geographicCategories = {
  'country',
  'state',
  'province',
  'county',
  'district',
  'city',
  'town',
  'village',
  'suburb',
  'quarter',
  'locality',
  'municipality',
  'neighbourhood',
  'administrative_area_level_1',
  'administrative_area_level_2',
};

/// Cities and regions are legitimate far destinations; never warn for them.
bool isGeographicCategory(String category) =>
    _geographicCategories.contains(category.trim().toLowerCase());

double _metres(GeoPoint from, GeoPoint to) =>
    distanceMeters(from.latitude, from.longitude, to.latitude, to.longitude);

/// Distance to the nearest named (non-geographic) result when even that one
/// is more than [farMatchThresholdMeters] away; otherwise null. A city or
/// region ranked first means the person searched for a place name, so there
/// is nothing to warn about.
double? farMatchDistance(Iterable<PlaceCandidate> results, GeoPoint? from) {
  if (from == null || !from.isValid) return null;
  double? nearest;
  var first = true;
  for (final result in results) {
    final location = result.location;
    if (location == null || !location.isValid) continue;
    final geographic = isGeographicCategory(result.category);
    if (first && geographic) return null;
    first = false;
    if (geographic || result.kind == PlaceKind.coordinate) continue;
    final metres = _metres(from, location);
    if (nearest == null || metres < nearest) nearest = metres;
  }
  return nearest != null && nearest > farMatchThresholdMeters ? nearest : null;
}

/// Straight-line distance to a selected destination when it is a named place
/// more than [farMatchThresholdMeters] from [from]; otherwise null.
double? farDestinationDistance(PlaceSummary place, GeoPoint? from) {
  if (from == null || !from.isValid || !place.location.isValid) return null;
  if (place.kind == PlaceKind.coordinate ||
      isGeographicCategory(place.category)) {
    return null;
  }
  final metres = _metres(from, place.location);
  return metres > farMatchThresholdMeters ? metres : null;
}

String _kilometres(double metres) => (metres / 1000).round().toString();

/// "Nearest match is 494 km away" / "最近的匹配在 494 公里外".
String farMatchTitle(double metres, String language) => language == 'zh'
    ? '最近的匹配在 ${_kilometres(metres)} 公里外'
    : 'Nearest match is ${_kilometres(metres)} km away';

String farMatchDetail(String language) => language == 'zh'
    ? '附近可能没有这个地点。请核对名称，或加上城市名再搜索。'
    : 'This place may not exist nearby. Check the name, or add a city.';

/// "This place is 494 km away" / "该地点在 494 公里外".
String farDestinationTitle(double metres, String language) => language == 'zh'
    ? '该地点在 ${_kilometres(metres)} 公里外'
    : 'This place is ${_kilometres(metres)} km away';

String farDestinationDetail(String language) => language == 'zh'
    ? '出发前请确认这是你要去的地方。'
    : 'Check that this is the place you meant before you go.';
