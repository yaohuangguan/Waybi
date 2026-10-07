# Waybi capability audit and roadmap — 2026-10-08

## Production baseline

Audited main through `1681d2b` (PR #86). “NZ owned, global available” is the strategy; **NZ independence is not yet complete**.

| Area | Main before this release | This release |
| --- | --- | --- |
| NZ basemap | Waybi-hosted PMTiles on R2; native MapLibre | Default Waybi Map; less Flutter/platform work during gestures |
| Overseas maps | OpenFreeMap fallback by requested map area | Preserved |
| Map assets | Glyphs, sprites and Natural Earth still use external defaults | Preserved; ownership remains roadmap work |
| Search | LINZ/Auckland official address enrichment + Geoapify/TomTom/Photon | Whole-response shared cache and request coalescing; faster provider scheduling; preserve slower valid partial suggestions; instant cached suggestions |
| NZ addresses | Generic interpolation can fill missing house numbers using nearby published addresses | Exact candidates win; derived candidates cannot seed another interpolation; distance/house-number gaps bounded; ordinary address UI |
| Routing | Independent path still uses public OSRM; no owned NZ production graph | Preserved; closure matching and alternative selection are additional product logic, not a new route engine |
| Navigation | Waybi progress/reroute, heading-up camera, speed/turn zoom, bilingual voice | Preserved and regression tested |
| Road events | NZTA + global community reports, with weak visibility | Shared cron snapshots; NZTA + NSW adapter selected by request area; default-on event layer; real published segments only; route preview closure warnings |
| Official Australian coverage | None | NSW only, via Transport for NSW; other states are not claimed |
| Cameras | NZTA fixed cameras, route matching, timed strip + deck | Preserved; NZ only |
| Discover | History-driven prototype | New trip CTA, actual revisit history, meaningful direction exploration, nearby events with source/freshness |
| Friends | Persistent three-character room, random long trips, illustrated souvenirs, confirmed-navigation arrival rewards | Preserved; marketing now reflects these capabilities |
| External destinations | Waybi links and iPhone Shortcuts | Preserved; Google Calendar controls its own app picker, inclusion is not guaranteed |
| Feedback / Plus | Arrival thumbs-up/down; collapsible Plus card | Preserved |
| Backend | JavaScript `.mjs` runtime and tests | All server runtime/tests TypeScript, generated Worker runtime/binding types, typecheck + dry-run + regression CI |
| Website | New homepage, old three feature guides | Four matching guide cards, refreshed bilingual navigation/road/Route Watch guides, new Friends guide |

The TypeScript migration retains explicit legacy JSON compatibility boundaries. It is **not yet a repository-wide strict-mode conversion**. Deployment remains Cloudflare Workers, KV and D1. TypeScript improves checks and maintenance; upstream network requests dominate the search latency investigated here.

## What the Symonds Street report revealed

The published NZTA record for the southbound Symonds Street SH1 on-ramp was active at approximately 21:20 NZDT on 6 October. The app needed better visibility and whole-route checking, rather than a hardcoded workaround for one address or ramp. Ramp direction names describe the joined motorway, so they must not suppress warnings using the curved ramp's local bearing.

Published data can be late, absent or point-only. The map must preserve those limits. Whole-route closure matching does not prove road topology, nor does a blank event list prove a route is open. The current independent route provider cannot guarantee a detour around a new official closure. This is the main remaining navigation gap.

NZTA/NSW feeds are fetched once into shared backend snapshots on the three-minute schedule, rather than once per phone. Cold or stale requests use the shared KV snapshot and coalesce overlapping refreshes within an isolate. Five-minute freshness and 15-minute maximum stale retention bound outages. KV is eventually consistent, so this is not a promise of exactly one upstream request globally. Failed refreshes also receive a retry backoff. Search cache is scoped to query, language and approximate request location, contains no account/history data, and uses hashed cache URLs.

## Priorities and acceptance gates

### P0 — navigation reliability and measurement

1. On-device release profiling: sustained pan/pinch frame timings, GPS follow, junction approaches, motorway speed changes, battery/thermal behaviour. A native simulator compile and a gesture regression test do not establish a real-device FPS result.
2. Search p50/p95/p99, cache-hit rate, upstream timeout/error count and per-provider spend. Compare cold and warm prefixes, dense city POIs and overseas queries. Same-key coalescing reduces duplicate work; it does not prove capacity under unique-query load.
3. Closure-aware routing: require a validated engine/provider exclusion path, safe off-ramp alternatives, directed road matching and route recomputation after events change. Test single-point ramp closures, parallel carriageways, whole-road geometry, expired incidents and overnight windows.
4. NZ road-event quality: deduplicate reports against official events, improve source geometry, add first-party freshness/error monitoring. Expand AU by validated state adapters, starting with QLD/VIC; add coverage to the registry rather than scatter country conditionals.

### P1 — complete the controlled NZ stack

1. Host licensed glyphs/sprites/background assets on R2 and verify attribution. Test NZ with commercial providers, OpenFreeMap, public Photon and public OSRM disabled before calling independence complete.
2. Build a versioned NZ address/POI index from LINZ, OSM and validated local datasets. Test prefix completion, Chinese/English names, missing-number cases, locality ambiguity and exact-address preference. Atomic index rollout, rollback and freshness reporting are required.
3. Compare **OSRM and Valhalla on the same NZ OSM extract** before choosing production routing. OSRM is the lowest parser migration cost. Valhalla offers runtime costing, multiple modes and exclusion options; directed closure application still needs our matching/integration. Compare route quality, turns/lanes, walking/cycling, exclusions, memory, build time and warm/cold p95 on public Auckland/Hamilton and CBD/airport-area routes.
4. Choose Cloud Run versus a small VM using graph memory, startup time and warm latency. Region-local private engine endpoints sit behind the existing Worker gateway. Rebuild graphs in scheduled jobs and publish immutable versioned artifacts.

### P2 — differences users can feel

1. Discover destinations ranked using real distance, revisit history, opening data where available, road conditions and actual scenic metadata. Do not label arbitrary low-cost roads “scenic”.
2. More companion scenes, character-specific interactions and verified landmark collections. Country-themed illustrated keepsakes exist; landmark-specific artwork and location matching need their own curated catalogue.
3. AU owned infrastructure only when usage justifies it. China remains a lower-priority provider/network/coordinate-system validation effort; current worldwide fallbacks do not imply guaranteed availability in every network or address dataset.

## Language and hosting decision

Keep API gateway, authentication, D1, subscriptions, camera snapshots, traffic orchestration and global fallback in **TypeScript Workers**. Do not migrate the whole backend to Go for hoped-for I/O improvements.

An independently indexed NZ search service can later use Go when memory/CPU profiling, deployment boundaries or index design justify it. Go is a possible implementation choice for our business layer, not a replacement for OSRM/Valhalla algorithms. Pelias is another search candidate, with autocomplete/forward/reverse APIs; assess its operational footprint and data-import fit against a smaller NZ-only index before adopting it. Cloud Run Jobs are candidates for ingestion/index and graph rebuilds, not an already deployed capability.

References: [Workers TypeScript](https://developers.cloudflare.com/workers/languages/typescript/), [OSRM](https://github.com/Project-OSRM/osrm-backend), [Valhalla route API](https://github.com/valhalla/valhalla/blob/master/docs/docs/api/route/api-reference.md), [Pelias](https://github.com/pelias/documentation), [Cloud Run minimum instances](https://docs.cloud.google.com/run/docs/configuring/min-instances), [NZTA data](https://www.nzta.govt.nz/about-us/our-data-and-official-information/use-our-data), [TfNSW hazards](https://opendata.transport.nsw.gov.au/data/dataset/live-traffic-hazards), [OSM attribution](https://osmfoundation.org/wiki/Licence/Attribution_Guidelines).

## PR #78

PR #78 remains open and was not merged as a whole. Later main improvements superseded most of its search goals. Optional HERE is another candidate provider, not a requirement to find a missing address. This release keeps precision safeguards internally and honours the product decision to display a nearby derived address normally. Do not merge the old conflicting PR solely to recover its older provider path.
