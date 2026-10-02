# Map providers and navigation

Settings offers Google Maps and **Kiwi Practice**, an independent experiment.
Existing `mapbox` preferences migrate to Practice. The Mapbox SDK and token requirement have been removed; old usage records remain readable.

## Kiwi Practice

- MapLibre Native (Metal on iOS, native GPU rendering on Android) owns the camera, projection, route, POIs and single location marker. Dragging never rebuilds Flutter layers. Routes and pins are batched GeoJSON sources; only changed sources are sent across the platform channel.
- OpenFreeMap supplies free OpenMapTiles vector tiles. The bundled Positron-derived style uses day/night colours that distinguish water, parks, commercial/medical/education land and road hierarchy, visible clickable POIs and clear road labels and Kiwi Lime guidance. Chinese names are preferred when present; untranslated proper names remain. Style licences are bundled in `assets/maps/LICENSES.txt` and Flutter's licence registry.
- Photon supplies independent OSM search, reverse lookup and Explore without a key. Native requests identify Kiwi Lens explicitly (the default Dart UA receives 403). Local search uses a bounded NZ metro window by default, POI/category confidence, text match and distance ranking, then falls back globally only when needed. That keeps branded searches such as `taiping` on nearby real businesses instead of same-named overseas towns. Common local intents such as `airport`, zoo, museum, university and hospital are expanded against the nearest major NZ metro. Public Photon indexes en/de/fr/local names, so arbitrary Chinese names still depend on its data coverage.
- FOSSGIS OSRM supplies **Drive, Walk and Bike** routes on separate public engines. Requests are serialized at least 1.1 seconds apart and identify Kiwi Lens. The API profile string is `driving` for all three separately built engines. Independent Transit is not fabricated from Google content; it remains unavailable until a separate public-transit routing backend is connected. Map/data credits live behind MapLibre's small native attribution control rather than a floating badge over navigation.
- Kiwi's own guidance tracks route progress, maneuvers, ETA, available lanes, unvisited stops, accuracy-aware deviation and online rerouting. Structured OSRM maneuvers are converted into human turn instructions even when the upstream step has no ready-made sentence. Voice announces the opening maneuver and staged far/near/immediate turn prompts. Failed reroutes retain the previous route; late responses cannot restart an ended session.
- Raw iOS/Android fixes pass through a navigation location filter **before** route snapping. Poor fixes are rejected, stationary startup requires two consistent fixes, implausible jumps hold the last reliable point, and the route origin is held while GPS settles. This specifically prevents a 50–100 m indoor jump from snapping the Kiwi onto a nearby motorway.
- Arrival requires proximity within 10 metres, low speed and two accurate fixes. Camera alerts and turn speech share the existing voice queue. The destination uses a chequered finish flag; NZTA spot-speed, average-speed, red-light/dual and bus-lane cameras use distinct native symbols.
- Official NZTA Traffic Conditions are exposed by the Worker as directional traffic-flow segments and refreshed every minute. Practice renders free/moderate/heavy flow as green/amber/red lines when the Traffic layer is enabled. Coverage follows NZTA's feed (especially motorway/state-highway corridors); it is not represented as Google-style coverage on every local street.
- The puck and prerasterized spreading light share one native source and projection; blur is baked once rather than repainted on every Flutter animation frame. Navigation reserves measured space above the deck, including on expansion. Manual pan/pinch pauses follow; GPS updates preserve zoom and recenter resumes follow. Navigation starts **top-down heading-up** for both Google and Practice; Practice can then use the existing perspective/zoom controls as the trip develops.

Practice has no satellite layer, guaranteed offline routing or commercial routing SLA. MapLibre GL Flutter 0.27.1 and native iOS SDK 6.28.0 are pinned. WebGL preview uses the same style; production work remains Flutter/iOS. Explore does not invent reviews, opening hours, photos or detour estimates.

The provider-neutral map contracts now live in `packages/kiwi_map` (geometry, viewport, places, traffic flow and Road Intelligence overlay contracts). The app remains an adapter around Photon/OSRM/NZTA/Google. This is the extraction seam for a standalone map library: a future B2B client can use the renderer with its own data, or attach Kiwi Lens Road Intelligence as an optional overlay rather than making the API a hard dependency of the map.

OpenFreeMap requires no access fee or API key. Public OSRM/Photon instances have shared capacity and no SLA. Keep Practice free, avoid bulk requests, and self-host services for a production navigation offering. Open-source software is free; running servers still costs resources. See [OpenFreeMap](https://openfreemap.org/quick_start/), [OSRM policy](https://routing.openstreetmap.de/about.html) and [Photon](https://github.com/komoot/photon).

## Configuration

No map token is needed. Optional `--dart-define` overrides:

| Setting | Default |
| --- | --- |
| `KIWI_PHOTON_URL` | `https://photon.komoot.io` |
| `KIWI_OSRM_CAR_URL` | `https://routing.openstreetmap.de/routed-car` |
| `KIWI_OSRM_FOOT_URL` | `https://routing.openstreetmap.de/routed-foot` |
| `KIWI_OSRM_BIKE_URL` | `https://routing.openstreetmap.de/routed-bike` |

The ignored `.dart-defines.local.json` is supported by existing launch scripts. Google platform keys remain configured separately. Google Places content is never requested or displayed in Practice; independent OSM/AT data retains its provenance.

## Google navigation

Native SDK guidance retains one native location indicator. Flutter's extra Kiwi marker and radar polygons are restricted to browsing: the SDK has no public API to replace its navigation vehicle indicator. This removes projection races during junction zoom. Native junction zoom is retained without repeated forced zoom levels. On iOS, a platform channel explicitly releases the SDK follow camera after a user gesture. The shared HUD reports top and bottom insets to the native map.

## Verification

Run `flutter analyze`, `flutter test` and Node 24 `pnpm test`. The separate `tool/practice_navigation_preview.dart` renders the real map/HUD with a labelled sample trip for visual checks; it does not simulate a real road test.

Physical iPhone/Android checks remain necessary for GPS continuity, junction zoom, network recovery, background audio/location, wake lock and arrival behavior.

Performance regression test: 120 native camera callbacks cause no map rebuilds or source uploads. GPS-only changes upload the driver source alone; manual pinch retains zoom and pauses following. The preview adds browsing, live search and theme controls for visual checks.
