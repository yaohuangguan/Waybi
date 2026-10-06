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

  if (!parsed.number && eligible.length > 1) {
    // Street-name typeahead is latency-sensitive and does not require one
    // exact house authority to win. Query overlapping official adapters in
    // parallel and return the first useful street result.
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

  // Numbered addresses preserve provider priority so the broadest official
  // address authority gets first chance at an exact coordinate.
  for (const provider of eligible) {
    try {
      const results = await provider.search({ query, near, parsed, fetcher });
      if (Array.isArray(results) && results.length) return results;
    } catch {
      // A regional adapter is enrichment only. Failure must never break the
      // worldwide Geoapify/TomTom/Photon path.
    }
  }
  return [];
}
