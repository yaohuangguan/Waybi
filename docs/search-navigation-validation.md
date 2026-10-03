# Search and navigation validation

The independent Flutter search keeps Unicode letters and numbers when matching
names. Nearby search uses the person's GPS position rather than a previously
panned map center; explicit wider search remains available in the search screen.
An empty local Chinese query does not silently become an overseas namesake.
Exact city searches and destinations elsewhere in NZ continue to work.

Local Chinese trading-name aliases only affect queries originating in NZ and
never contain fabricated coordinates. Foodie's own site confirms its Chinese
name and Westgate location: https://myfoodie.co.nz/home. The public Photon result
for Foodie Asian Supermarket was checked against OSM node 12157396838 at
174.6048637, -36.8114218, Northside Drive. Tai Ping's local stores are listed at
https://www.taiping.co.nz/.

Photon supports a bounded query and location bias:
https://github.com/komoot/photon/blob/master/docs/api-v1.md. Wider results are
opt-in for local POI searches; no Nominatim autocomplete requests are added.

Navigation ignores stale/future/duplicate and poor-quality location samples.
A route origin is a visual anchor, never an observation that can advance a turn
or confirm arrival. A stale anchor can recover after three consistent precise
fixes; accepted fixes keep their original timestamps. The navigation GPS feed
continues in the background and exposes a waiting state if reliable fixes stop.
Closely spaced turns get a short following-maneuver cue in the top card.

Live Activities are distinct from the iOS background location indicator. The
native bridge reports authorization and actual activity state, preserves pending
start requests across scene activation, retries a missing surface in the
foreground, and ends it when navigation ends. User-dismissed activities are not
automatically recreated. The widget uses fresh GPS confidence and staleness,
and has compact/minimal/expanded Dynamic Island and Lock Screen presentations.
Apple's integration requirements:
https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities.

`apps/mobile/tool/live_activity_probe.dart` is a simulator-only entrypoint for
testing the production native bridge and widget. It is not the shipping app
entrypoint. Use it to check start, periodic updates, GPS waiting, and stop, then
build the real app from `lib/main.dart` for physical devices.
