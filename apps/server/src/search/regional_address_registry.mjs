import { parseNumberedStreetQuery, parseStreetQuery } from './numbered_street_query.mjs';
import { linzNzAddressProvider } from './regional/linz_nz_addresses.mjs';
import { aucklandCouncilAddressProvider } from './regional/auckland_council.mjs';

// Regional providers are optional enrichments. The global search path remains
// authoritative and fully functional when no regional adapter applies.
//
// Providers are ordered from the broadest/most authoritative dataset to local
// supplements. For New Zealand, LINZ is the national address authority, so a
// successful LINZ match should not wait for (or be diluted by) a city layer.
const providers = [linzNzAddressProvider, aucklandCouncilAddressProvider];

export function regionalAddressProviders() {
  return [...providers];
}

export async function searchRegionalAddressEnrichments(
  query,
  near,
  fetcher = fetch
) {
  const parsed = parseNumberedStreetQuery(query) || parseStreetQuery(query);
  if (!parsed || !near) return [];

  const eligible = providers.filter((provider) =>
    provider.supports({ query, near, parsed })
  );
  if (!eligible.length) return [];

  if (eligible.length > 1) {
    // Search typeahead must not inherit the latency of the slowest official
    // service. Run overlapping regional adapters concurrently and return the
    // first useful result. This is especially important in NZ where the LINZ
    // ArcGIS service can occasionally be much slower than Auckland Council.
    //
    // Both sources remain official enrichment; the global search stack still
    // merges/ranks the returned candidates and can interpolate a missing house
    // number from neighbouring official addresses.
    return new Promise((resolve) => {
      let remaining = eligible.length;
      let settled = false;
      for (const provider of eligible) {
        Promise.resolve(provider.search({ query, near, parsed, fetcher }))
          .then((results) => {
            if (!settled && Array.isArray(results) && results.length) {
              settled = true;
              resolve(results);
            }
          })
          .catch(() => {})
          .finally(() => {
            remaining -= 1;
            if (!settled && remaining === 0) resolve([]);
          });
      }
    });
  }

  try {
    const results = await eligible[0].search({ query, near, parsed, fetcher });
    return Array.isArray(results) ? results : [];
  } catch {
    // Regional data is enrichment only. Failure must never break the
    // worldwide Geoapify/TomTom/Photon path.
    return [];
  }
}
