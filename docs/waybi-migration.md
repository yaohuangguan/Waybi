# Waybi identity migration

The repository and primary packages become Waybi (`@waybi/*`, `waybi_mobile`,
`waybi_map`). The bird artwork remains unchanged. Clover and Sett replace the
previous cat/dog artwork; serialized marker choices stay `kiwi`, `cat`, `dog`
so existing preferences continue to select the same companion.

## Resource rollout and rollback

1. Validate the existing Worker, D1 and KV identifiers with Wrangler's standard
   authentication workflow. Capture resource metadata, binding names and the
   currently deployed version before changing names; never log credential values.
2. Create an empty `waybi-users` D1 database. Cloudflare does not support renaming
   D1 databases through its update API. Enable `WAYBI_MIGRATION_PAUSED=true` on the
   existing Worker briefly: API requests return 503 with Retry-After and scheduled
   writes stop. Export the old D1 with Wrangler into an ignored private directory,
   import it only into the verified empty new database, and compare every table's
   schema and row contents using in-memory hashes. Never print or commit SQL data.
   Keep the original database intact for rollback; remove local SQL after success.
3. Rename the existing Worker through the documented Workers API `PATCH
   /accounts/{account}/workers/workers/{id}`. Preserve its ID, secrets, deployment,
   and KV binding. Preserve secret values; switch USER_DB to the verified copy.
   Rename KV in place, preserving its namespace ID and all cached data.
4. Deploy the updated application to `waybi.nzs.workers.dev`; validate health,
   account lookup, map configuration, independent discovery and road geometry.
5. Deploy `wrangler.legacy.jsonc` as an address compatibility gateway. It forwards
   already-installed clients to Waybi without retaining credentials or data.
   Server authentication accepts both client headers and session-cookie names.
6. Build `me.samyao.waybi` (iOS) and `space.ps6.waybi` (Android) as new identities.
   Existing app installations are retained. The user can keep them during testing;
   changing bundle IDs cannot transfer another app's private local storage.

If validation fails before rollout, restore the original Worker name and database
binding and remove the pause flag. Do not delete either database or application.
After rollout, the gateway can point to a restored Waybi deployment while fixes
are prepared. Removing the compatibility gateway is a separate later operation.

Google iOS OAuth clients and any restricted Google Maps keys must authorize the
new bundle ID. App Store Connect products should use `me.samyao.waybi.plus.monthly`
and `me.samyao.waybi.plus.annual`; they have not yet been created. Apple entitlements
remain server-verified. Stripe customer/subscription data remains in the same D1.

## Waybi Map traffic and discovery

Live NZTA levels update independently of road geometry. `pnpm data:traffic-geometry`
performs a bounded maintenance query and directed road matching once, then bundles
geometry by section ID and endpoint fingerprint. Release builds should refresh
this dataset when the feed or road network changes. Unmatched sections are hidden;
stale flow is rendered unknown, never reported as flowing traffic. Publication of
street incidents does not imply complete street speed coverage.

Optional TomTom raster traffic is disabled without all of `TOMTOM_TRAFFIC_API_KEY`,
`TRAFFIC_TILES_ENABLED=true`, `TRAFFIC_TILES_MONTHLY_BUDGET` and migration 0012.
The database reserves upstream requests atomically against the explicit monthly
budget. Keys remain server-side; cached NZ tiles are reused for 60 seconds. Check
the account's actual plan before enabling: quotas are not assumed from marketing.

Independent discovery uses four bounded zoom-14 tiles from the same free basemap
as Waybi Map, with Overpass as a fallback and a 30-day previous pool for outages.
The geographically bounded, daily-cached POI pool
with balanced sights, parks, food, coffee and shopping. Photos are linked through
OSM/Wikipedia/Wikidata identities, with Commons authors and licenses retained.
Unknown photos use category artwork. Attribution is available from info controls;
the map briefly displays its initial open-data credit before collapsing it.
