# Map providers and navigation

Tasman retains Google native Navigation SDK guidance and adds Mapbox Maps with
Directions API routes and Tasman's own GPS guidance engine. Users select the
map in Settings. Each provider feeds the same navigation HUD and camera alerts.

## Mapbox flow

- Browse, tap a POI, long-press a coordinate, search NZ places or open Explore.
- Preview driving, walking and cycling routes; optional modes may be unavailable.
- Fit the whole preview/active route, start guidance, pan freely and recenter.
- Follow continuous route progress, upcoming maneuvers, per-step ETA and available
  lane recommendations. GPS accuracy and off-route status are visible.
- After at least three accurate off-route fixes over three seconds, request a
  replacement for the active mode, retaining unvisited stops. Requests are
  limited to one at a time with a 15-second cooldown. Failed requests retain the
  previous route; late responses cannot restart an ended session.
- Search for an extra stop during navigation and route through that stop.
- Arrive only near the destination at low speed over two location fixes.
- Enter Drive Mode without a destination for speed, NZ limits and camera alerts.
- Keep the display awake while driving. Android uses a foreground location
  notification; iOS requests automotive background location updates.

Camera matching uses route distance and direction, a narrow road corridor and
road names across the full step. Free Drive uses direction-aware nearby matches.
The existing 800/300-metre alerts and passed-camera lifecycle remain shared.
Camera speech interrupts turn guidance; the latest turn waits until the alert
finishes. Mute/End stop pending speech. Reroutes retain spoken-camera memory.

Mapbox Standard rendering follows the user's top-down follow preference. Route,
camera, Explore and selection annotations update independently; unchanged
groups are not deleted and recreated on every compass/GPS update.

## NZ search and provider boundaries

Mapbox Search Box's documented coverage excludes New Zealand. Tasman therefore
uses Worker requests with `provider=geoapify` for Mapbox search and Explore.
The Worker explicitly bypasses Google Places for these requests, even when a
Google key is configured, and labels results with their actual source.
Geoapify/OSM attribution is displayed in search and Explore.

Deploy the updated Worker with its existing `GEOAPIFY_API_KEY` secret before
using these flows on a device. An old backend's Google results are rejected on
Mapbox; a missing independent-search key reports an unavailable service.
Google searches/Explore continue to use their existing provider.

Mapbox map taps use the feature's actual POI coordinates. Reverse address
enrichment uses Mapbox Geocoding v6, including Chinese. Mapbox-derived content
remains session-scoped under the existing storage policy. Google Places content
cannot be displayed on Mapbox, or Mapbox content on Google. Independent
Geoapify/OSM/AT data may be displayed on either map.

## Configure and build

Provide a public Mapbox token at build time. Never embed a private `sk.` token.

```bash
cd apps/mobile
flutter run --dart-define=MAPBOX_ACCESS_TOKEN=YOUR_PUBLIC_TOKEN
flutter build apk --dart-define=MAPBOX_ACCESS_TOKEN=YOUR_PUBLIC_TOKEN
```

For development, create the ignored `apps/mobile/.dart-defines.local.json`:

```json
{"MAPBOX_ACCESS_TOKEN":"pk..."}
```

The repository's `pnpm mobile:dev`/`mobile:run` and iOS build/install launchers
automatically include this file when present. Direct Flutter commands need:

```bash
flutter run --dart-define-from-file=.dart-defines.local.json
flutter build apk --debug --dart-define-from-file=.dart-defines.local.json
```

Release CI must supply the public token explicitly. Without it, Mapbox cannot
be selected and a saved Mapbox selection falls back to Google. Google platform
keys remain configured separately. Android API 24+ and iOS 16+ are required.

## Capabilities and release verification

This is **Maps SDK + Directions API + Tasman GPS guidance**, not the native
Mapbox Navigation SDK. It does not provide native road snapping, offline route
calculation, voice assets or guaranteed background behavior. Lane information
appears only when returned by Directions. NZ routing uses `driving`; live Mapbox
traffic coverage is not assumed. Explore does not invent ratings, photos,
opening hours or along-route detour times.

Verification includes Flutter analysis, unit/widget tests, all Worker/shared
tests, Worker bundle validation, an Android debug build and successful live
Auckland Directions/Chinese reverse-geocoding requests. Simulated tests cover
progress across route crossings, jitter/backward travel, poor GPS, ETA,
sustained deviation, stop-preserving reroutes, failures, late responses, arrival,
voice priority/mute, independent-source searches and a 375×667 dark HUD.

Before calling this App Store/Play Store ready, run on physical Android and
iPhone devices with production credentials:

1. Search/Explore in English and Chinese; choose a POI or long-pressed coordinate,
   preview alternatives, start, pan, recenter and view the whole route.
2. Drive past same-road and adjacent-road cameras, cross the 800/300-metre
   thresholds, confirm speech priority, mute and the passed-camera lifecycle.
3. Deviate, lose network, regain network and add stops; confirm old geometry
   stays usable and unvisited stops survive rerouting.
4. Test destination-free Drive, lock screen, background/resume, calls/audio
   interruption, location permission removal and End. Verify background service,
   speech and display wake lock stop when driving ends.
5. Approach/drive past/stop at the destination and check single arrival speech.
6. Switch providers in browsing and verify Google native navigation still works.

No physical device was connected in this workspace. Native iOS build/signing and
actual GPS/background/audio/performance behavior remain unverified here.

## Code boundaries

- `domain/map_provider.dart`, `domain/route_option.dart`: neutral places,
  geometry, maneuver/lanes and source policy.
- `providers/mapbox_map_renderer.dart`: map events, annotation groups, follow
  camera and route fitting.
- `providers/mapbox_routing_provider.dart`: online route preview and rerouting.
- `drive/route_progress_tracker.dart`: GPS continuity and accuracy-aware progress.
- `providers/mapbox_navigation_engine.dart`: maneuver/ETA, deviation and arrival.
- `drive/drive_engine.dart`: location, NZ road intelligence, limits and alerts.
- `drive/voice_engine.dart`: speech priority and cancellation.
- `widgets/navigation_overlay.dart`: shared navigation HUD.
- `apps/server/src/compatible_places.mjs`: independent NZ Explore endpoint.
