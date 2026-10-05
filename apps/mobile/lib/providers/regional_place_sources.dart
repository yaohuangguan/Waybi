class RegionalPlaceSourceCredit {
  const RegionalPlaceSourceCredit({
    required this.provider,
    required this.label,
    required this.url,
  });

  final String provider;
  final String label;
  final String url;
}

// Attribution belongs to the same adapter namespace as regional search data.
// Core UI consumes provider IDs generically; new markets only add registry data.
const regionalPlaceSourceCredits = <RegionalPlaceSourceCredit>[
  RegionalPlaceSourceCredit(
    provider: 'regional:auckland-council',
    label: 'Auckland Council Open Data',
    url: 'https://www.aucklandcouncil.govt.nz/',
  ),
];

List<RegionalPlaceSourceCredit> regionalCreditsForProviders(
  Iterable<String> providers,
) {
  final wanted = providers.toSet();
  return regionalPlaceSourceCredits
      .where((credit) => wanted.contains(credit.provider))
      .toList(growable: false);
}
