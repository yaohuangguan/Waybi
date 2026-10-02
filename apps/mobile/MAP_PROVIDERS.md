# Map providers and navigation

Settings offers Google Maps and **Kiwi Practice**, an independent experiment.
Existing `mapbox` preferences migrate to Practice. The Mapbox SDK and token requirement have been removed; old usage records remain readable.

## Kiwi Practice

- Flutter Map owns the camera, projection, route and single location marker.
- OpenFreeMap supplies free OpenMapTiles vector tiles. The bundled Positron-derived style uses quiet day/night colours, clear road labels and Kiwi Lime guidance. Chinese names are preferred when present; untranslated proper names remain. Style licences are bundled in `assets/maps/LICENSES.txt` and Flutter's licence registry.
- Photon supplies independent OSM search, reverse lookup and Explore without a key.
- FOSSGIS OSRM supplies car, foot and bike routes on separate public engines. Requests are serialized at least 1.1 seconds apart and identify Kiwi Lens. The API profile string is `driving` for all three separately built engines.
- Kiwi's own guidance tracks route progress, maneuvers, ETA, available lanes, unvisited stops, accuracy-aware deviation and online rerouting. Failed reroutes retain the previous route; late responses cannot restart an ended session.
- Arrival requires proximity within 10 metres, low speed and two accurate fixes. Camera alerts and turn speech share the existing voice queue.
- The puck and animated spreading light share one map marker and one projection. Navigation reserves measured space above the deck, including on expansion. Manual pan/pinch pauses follow; GPS updates preserve zoom and recenter resumes follow.

Practice is 2D. Satellite, live traffic, guaranteed offline routing and production navigation coverage are unavailable. Vector renderer `9.0.0-beta.8` is pinned to the author's recommended Flutter Map 8 version, avoiding the experimental GPU rewrite. Explore does not invent reviews, opening hours, photos or detour estimates.

OpenFreeMap requires no access fee or API key. Public OSRM/Photon instances have shared capacity and no SLA. Keep Practice free, avoid bulk requests, and self-host services for a production navigation offering. Open-source software is free; running servers still costs resources. See [OpenFreeMap](https://openfreemap.org/quick_start/), [OSRM policy](https://routing.openstreetmap.de/about.html) and [Photon](https://github.com/komoot/photon).

## Configuration

No map token is needed. Optional `--dart-define` overrides:

| Setting | Default |
| --- | --- |
| `KIWI_VECTOR_STYLE_URL` | `https://tiles.openfreemap.org/styles/positron` |
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
