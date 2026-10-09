# Auckland bus and special vehicle lane awareness

This release adds official Auckland Transport GIS lane geometry and operating
hours to Waybi navigation. It does not infer which physical lane a phone occupies,
claim a complete enforcement-camera inventory or provide NZ-wide coverage.

## Data and refresh budget

Source: [AT Transit Lanes FeatureServer](https://services2.arcgis.com/JkPEgZJGxhSjYOo0/arcgis/rest/services/OpenData_TransitLanes/FeatureServer/0).
AT describes a weekly update cycle. The bundled 9 October snapshot contains
361 lane features; 271 have parsable published schedules and 90 retain unknown
hours. Missing road names are retained without inventing a street name.

Licence: © Auckland Transport, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
Waybi normalizes schedules and coordinates. Attribution is also in Settings.
The GIS last-edit time is separate from Waybi's check time.

The existing daily cron checks the existing KV namespace, fetching metadata
and geometry only when its shared snapshot is at least seven days old. A failed
refresh retains the prior snapshot and waits seven days before trying again.
Visitors never trigger ingestion or KV writes. This adds about 30 cron KV reads,
4–5 KV writes and 8–10 source requests per month. The public endpoint has a
shared 24-hour edge cache. Each device includes an offline seed and checks the
endpoint at most once per seven days, with a persisted cooldown for failures.
GPS updates make no lane-data requests. No D1 migration, new paid resource,
container, R2 bucket or additional cron schedule is required. These are the
incremental budgets for this feature, not a guarantee that all Waybi traffic
will remain below account-wide free limits at arbitrary user counts.

Rebuild both bundled copies with `node --experimental-strip-types scripts/import-transit-lanes.mjs`.

## Rules and navigation

Schedules use Pacific/Auckland, including daylight saving and overnight
windows. Monday–Friday is not interpreted as excluding public holidays.
Unknown or provisional hours remain unknown and prompt the driver to check
signs. Outside known operating hours the lane does not produce an active warning.

Route matching requires a directed parallel overlap, rather than proximity
to a camera or a crossing road. Published start/end attributes supply the
direction; missing direction produces an advisory to check signs. Geometry
matching runs once per route on a background isolate. Live fixes scan only
the overlaps, avoiding full-city geometry work in the map gesture/render loop.

The shared bilingual HUD shows type, distance, operating days and hours;
speech uses the same schedule and a completion-aware queue. Turn guidance
finishes before the reminder. Expired, passed, muted or rerouted reminders
are discarded; unsuccessful speech does not consume an alert. The same road,
type and schedule is not repeated for ten minutes across adjacent segments.
A nearby camera gets the upper strip; the lane reminder remains in the deck.

Ordinary roads with a bus lane remain navigable. `BusOnly` in the GIS describes
a lane and is never automatically promoted to a whole-road prohibition.
Whole-road rules need an independently verified official source, recorded in
`apps/server/data/transit-road-access.json`. The initial catalogue covers both
directions of Grafton Bridge, whose AT guide explicitly restricts ordinary cars
Monday–Friday 07:00–19:00 including public holidays. It is deliberately not a
claim that all Auckland bus-only roads have been catalogued.

Independent route options filter verified restricted-road alternatives during
the predicted traversal. When no legal returned alternative exists the route
is explicitly blocked; the App refuses to start it. The App also checks bundled
rules before navigation and replacement routes. Changes becoming active during
a trip can trigger recalculation. Current public routing cannot accept arbitrary
Waybi road exclusions; this release selects verified legal returned alternatives
and never claims to have generated a detour when none was found. Google SDK
automatic routing remains under Google's control.

## Map layer

The default **Waybi Map (Independent/MapLibre)** now renders the official
Auckland bus, T2/T3 and special vehicle lane geometry as **thin dashed traces**.
A separate **Bus & transit lanes / 公交与专用车道** switch under Map layers is on by
default and is persisted independently of the bus-lane *camera* category.
Blue traces indicate published hours that are currently operating; grey means
outside the published hours; amber means the schedule is not confirmed.
Tap a trace for type, operating days/hours, status and AT attribution.
The overlay comes from the same weekly/offline snapshot as navigation alerts:
no extra GPS-based requests, Cron jobs, Workers or KV writes are needed.
It does not establish legal lane occupancy or replace road signs.
Google's native map mode does not currently render this Waybi-owned overlay.

## Validation

Replay Symonds Street northbound from Alfred Street towards Waterloo Quadrant:
the published 24/7 bus lane must warn while leaving the ordinary road usable.
Check Grafton Bridge during and outside restricted hours, Friday/Saturday,
NZST/NZDT, opposite direction, perpendicular and nearby parallel roads, unknown
hours, queued speech becoming irrelevant and offline refresh cooldowns.
Actual signage and road testing remain necessary; GPS cannot confirm lane
occupancy or authorize entry at an exact 50-metre boundary.
