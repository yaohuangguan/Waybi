# Time-aware alternatives and road-condition recommendations

The NZ Cloud Run engine retains `date_time: { type: 0 }`, access restrictions,
origin heading, waypoints and directed road exclusions. Valhalla cannot return
native alternatives for time-dependent routes. An explicit two-point driving
alternatives request therefore evaluates the default costing and two moderate
`use_distance` profiles (0.25 and 0.5), then removes duplicate geometry and keeps
up to three real routes. It never removes time restrictions to obtain a count.
Walking/cycling, single-route requests, via-point routes and the final local-road
closure-rescue strategy do not make these optional requests. All calls share
the existing deadline; every actual engine attempt reserves daily quota.
An optional failure or exhausted quota preserves the usable primary result.

The routing API reads the shared NZTA traffic and regional official-event
snapshots. It does not fetch upstream feeds once per phone or route. Traffic
contributes only when the source timestamp is valid and less than ten minutes
old, and only where directed, road-matched geometry overlaps the route within
25 metres and 45 degrees. Known road names/highway aliases must also agree.
Endpoint chords, unknown levels, stale traffic, opposite carriageways and
nearby streets do not count. Overlapping feed records cannot multiply coverage.
Active official roadworks, incidents and hazards may contribute advisory risk;
they do not become fake closures. Existing closure and bus-only-road checks
remain hard navigation restrictions, including after detour discovery.

NZTA's traffic-conditions feed publishes **levels**, not measured speeds or
route delay seconds. `conditions.rankingPenalty` is a qualitative ranking
weight: heavy traffic 120 points/km, moderate 30 points/km, incidents/hazards
120 points each and roadworks 30 points each, capped at 1800. It is not a
measured delay and must never be presented as added travel minutes. The
assessment expires within five minutes or sooner when a source expires.
The API leaves `trafficDelaySeconds` null and the precise traffic-ETA
`trafficAvailable` flag false for these routes.

Flutter's recommendation uses estimated duration plus this current risk
weight, with a 15% / 120-point guardrail, maneuver costs and 8 points per extra
kilometre among comparable driving options. Closed/restricted options cannot
displace a legal one. Cameras are informational and do not affect the default.
Fastest/shortest filters retain their independent meanings; the UI explicitly
says travel time is estimated. The recommendation is the best-scoring known
candidate, not a guarantee of the globally fastest route or Google-equivalent
coverage. Unknown roads are never labelled clear. Source age, coverage length,
known congestion and incident/roadwork counts remain visible in the evidence.

The initial production graph remains Valhalla 3.9.1 / NZ 2026-10-08. No new paid
data provider is enabled. Precise whole-route traffic-adjusted ETAs require
speed/travel-time coverage and its own provider configuration and budget.

References: [Valhalla route API](https://valhalla.github.io/valhalla/api/route/api-reference/),
[NZTA traffic and travel data](https://www.nzta.govt.nz/about-us/our-data-and-official-information/use-our-data).
