import '../domain/map_provider.dart';

class RegionalQueryAliasRule {
  const RegionalQueryAliasRule({
    required this.minLatitude,
    required this.maxLatitude,
    required this.minLongitude,
    required this.maxLongitude,
    required this.aliases,
  });

  final double minLatitude;
  final double maxLatitude;
  final double minLongitude;
  final double maxLongitude;
  final Map<String, String> aliases;

  bool contains(GeoPoint point) =>
      point.latitude >= minLatitude &&
      point.latitude <= maxLatitude &&
      point.longitude >= minLongitude &&
      point.longitude <= maxLongitude;
}

// Optional local vocabulary enrichments live outside the global search engine.
// Adding another market is a data/adapter change, not a core ranking fork.
const regionalQueryAliasRules = <RegionalQueryAliasRule>[
  RegionalQueryAliasRule(
    minLatitude: -48,
    maxLatitude: -34,
    minLongitude: 166,
    maxLongitude: 179,
    aliases: {
      '福地': 'Foodie Asian Supermarket',
      '福地超市': 'Foodie Asian Supermarket',
      '福地亚洲超市': 'Foodie Asian Supermarket',
      '太平超市': 'Tai Ping',
      '太平亚洲超市': 'Tai Ping',
    },
  ),
];

String resolveRegionalQueryAlias(String query, GeoPoint? proximity) {
  if (proximity == null || !proximity.isValid) return query;
  final key = query.replaceAll(RegExp(r'\s+'), '');
  for (final rule in regionalQueryAliasRules) {
    if (!rule.contains(proximity)) continue;
    final alias = rule.aliases[key];
    if (alias != null) return alias;
  }
  return query;
}
