# Christchurch and Wellington – bus lane corridor discovery (map-only)

**Status: pilot, not driver-safety coverage.** Auckland's AT-sourced exact lane
overlay and directed, verified navigation checks are unchanged. The Christchurch
and Wellington layer is a **centreline-based hint** to find places worth reviewing.
It must never be used by `matchTransitLanes`, `transitRoadBlocks`, ETA,
automatic lane violation warnings, or route access decisions.

## Reviewed city council evidence

| City | Road | Published source | Council rule context | What still needs review |
| --- | --- | --- | --- | --- |
| Christchurch | Cranford Street | [CCC construction notice (May 2026)](https://letstalk.ccc.govt.nz/waipapa-papanui-innes-central-community-board/cranford-street-bus-lanes-be-implemented) | Weekday southbound 7–9am, northbound 4–6pm | Exact endpoints, lane-side geometry and as-built signs |
| Christchurch | Papanui Road | [CCC 2025 cycling map](https://ccc.govt.nz/assets/Documents/Transport/Cycling/map/WEB-INF7542-Christchurch-Bike-Map-2025.pdf) | Identified as a corridor with bus lanes | Current local hours, directed spans, limits |
| Wellington | Adelaide Road | [WCC Newtown–city project, **In use**](https://www.transportprojects.org.nz/current/newtown-to-city/project-details) | Bus lanes both directions, 24/7 on the named project corridor | Exact physical extents, bus vs bus-only |
| Wellington | Kent Terrace | [WCC Newtown–city project, **In use**](https://www.transportprojects.org.nz/current/newtown-to-city/project-details) | Extended bus-only lane hours, weekdays 7–9am / 4–6pm | Exact sections and permissible vehicles |
| Wellington | Cambridge Terrace | [WCC Newtown–city project, **In use**](https://www.transportprojects.org.nz/current/newtown-to-city/project-details) | Extended bus-only lane hours, weekdays 7–9am / 4–6pm | Exact sections and permissible vehicles |

Each feature retains the council rule URL. Geometry is derived **only from
public council road centreline GIS** and is deliberately not called the bus
lane geometry:

- [CCC Road FeatureServer / StreetCentreLine](https://gis.ccc.govt.nz/server/rest/services/OpenData/Road/FeatureServer/7)
- [WCC Transportation/Roads / Road Name](https://gis.wcc.govt.nz/arcgis/rest/services/Transportation/Roads/MapServer/0)
- Data providers: Christchurch City Council and Wellington City Council. Their
  respective GIS source copyrights and terms apply. Check current licensing
  and attribution requirements prior to redistribution outside the Waybi app.

## Pipeline and product behaviour

Run `node scripts/import-regional-transit-corridors.mjs` from the repo root.
It validates road name exact matches, geography, non-empty geometries and
bounded segment counts before rewriting the single 34 KB offline mobile asset
`apps/mobile/assets/data/transit-corridors-review.json`.

The initial import found five named corridors covering **54 centreline pieces**:
50 Christchurch and four Wellington. This is **not 54 verified bus lanes**.
Each piece is tagged `precision: corridor-only` and remains separated by Dart
type from Auckland's navigable `TransitLane` dataset. The independently named
`review:` feature IDs and amber map colour indicate unknown lane boundaries.
The detail sheet displays the council's rule *context*, a prominent warning
and link to the source. No new Cloudflare endpoint, KV operation, Cron, location
upload, online geocoding or OSM-derived licence dependency is introduced.

Auckland's blue/grey line statuses still mean a published lane schedule is
known. Christchurch and Wellington's amber lines do **not** communicate that
the whole road or any precise portion of it is currently restricted.

## Promotion gate (mandatory)

Only promote a segment to actionable navigation warnings after independently
validating its official start and end intersections, permitted direction, legal
vehicle class, hours, public holiday exceptions, effective dates and physical
lane-side geometry against latest council resolutions/signs. Until then,
presentation is informational only. Never infer legality from a road name or
centreline intersection. Retain the source and review timestamp per segment.
