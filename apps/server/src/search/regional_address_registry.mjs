import { parseStreetQuery } from './numbered_street_query.mjs';
import { aucklandCouncilAddressProvider } from './regional/auckland_council.mjs';

// Regional providers are optional enrichments. The global search path remains
// authoritative and fully functional when no regional adapter applies.
const providers = [aucklandCouncilAddressProvider];

export function regionalAddressProviders() {
  return [...providers];
}

export async function searchRegionalAddressEnrichments(
  query,
  near,
  fetcher = fetch
) {
  const parsed = parseStreetQuery(query);
  if (!parsed || !near) return [];
  const eligible = providers.filter((provider) =>
    provider.supports({ query, near, parsed })
  );
  if (!eligible.length) return [];
  const settled = await Promise.allSettled(
    eligible.map((provider) => provider.search({ query, near, parsed, fetcher }))
  );
  return settled.flatMap((result) =>
    result.status === 'fulfilled' && Array.isArray(result.value)
      ? result.value
      : []
  );
}
