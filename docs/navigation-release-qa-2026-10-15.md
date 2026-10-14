# Waybi navigation release QA — 15 October 2026

This work deliberately excludes Apple Developer membership, TestFlight, signing or production deployment. All fixes are staged in a separate branch.

## Routing adapter

Waybi now supports a managed or licensed OSRM-compatible service, with server-side configuration only:

- WAYBI_OSRM_URL: HTTPS OSRM route API root; the service must support /route/v1/driving, /route/v1/walking, /route/v1/cycling as used by Waybi. Optional local HTTP is restricted to loopback for development.
- WAYBI_OSRM_TOKEN: optional bearer token, sent only to the configured managed endpoint. Store as a Worker secret, never in Flutter defines or git.
- WAYBI_DISABLE_PUBLIC_ROUTING=true: operational emergency stop for public OSRM and public closure-detour fallbacks. This does not disable a configured owned NZ Valhalla engine or a configured managed OSRM route for normal requests.
- WAYBI_NZ_ROUTING_URL and WAYBI_NZ_ROUTING_TOKEN: existing owned NZ Valhalla backend, still preferred when configured and in geographical scope.

Do not enable the public-routing cutoff on production until the managed route API has been provisioned and checked against turn-by-turn maneuvers, NZ driving restrictions, bicycle/walk profiles, directions, TLS and authentication. The managed OSRM adapter does not support directed closure exclusions: NZ Valhalla remains the preferred engine for verified closure rerouting. Public fallback remains explicitly a prototype dependency until replaced.

Requests within one Worker instance coalesce and cache identical upstream results for three seconds. These optimizations do NOT enforce FOSSGIS's global 1 request/second per-application limit, because Cloudflare may run many Worker instances. Production launch needs owned routing capacity or explicitly licensed commercial routing.

The legacy /api/route now uses the same configurable routing adapter. The legacy /api/search aliases to the existing /api/suggest search stack instead of sending prohibited typeahead requests to public Nominatim. The separate /api/reverse endpoint still uses public Nominatim and requires a verified provider/terms/volume solution before scaling; it is NOT fixed by the search migration.

## Airport and CMJ sign verification

- Read-only production route test as of 14 October: Airport Park & Ride North OSM-area centroid (174.7907113,-36.9910531) -> 8 Whitaker Place (174.76697662198927,-36.8567216115252): 19,467m / 1,466s; only one returned route.
- OSM restriction relation 14671934 (no_straight_on) blocks the short transition to the northbound carriageway. A single alternative and an apparent left/reversal are not evidence that the legal restriction is incorrect.
- Airport official Park & Ride North entrance is on Verissimo Drive, not necessarily the OSM area centroid. Verify **actual exit position**, turn signage and road access; do not special-case hard-coded coordinates or remove a legal restriction to shorten ETA.
- CMJ interchange lane recommendations and spoken guidance require ground-truth signage or passenger-recorded observations; map simulation alone is insufficient.
- Verify overlapping Queenstown Rd / SH20 / Hillsborough closure notices from current official NZTA feed before accepting a proposed detour.

## Locked-screen / audio / GPS regression

Code audit on main:
- Independent Drive mode uses AppleSettings with bestForNavigation, automotive activity (fitness when cycling/walking), pauseLocationUpdatesAutomatically:false, allowBackgroundLocationUpdates:true, showBackgroundLocationIndicator:true.
- ReliableLocationFeed never synthesizes GPS coordinates; an expired fix triggers bounded recovery and a visible issue, with late-callback generation guards after stop.
- VoiceEngine queues spoken guidance, discards irrelevant instructions and releases temporary iOS audio session after completion or cancellation.
- Info.plist already declares background location and audio.

Existing Flutter tests cover stream recovery after timeout, permission errors, stale callbacks after stopping, speech queue/mute and interruption recovery. Passing tests do not establish a real iOS background/GPS/YouTube Music/Bluetooth outcome.

Physical acceptance matrix (requires an unlocked, physically available iPhone and a passenger/tester, not operation while driving):

1. Start an independent route with While Using location authorization. Lock the screen for 5 minutes. Verify actual location movement/route progress, spoken warnings and background location indicator; unlock and verify correct position and no route reset.
2. Play music through speaker and Bluetooth, allow multiple turn/camera announcements; verify volume duck/mix and music recovery, then stop navigation and verify session release.
3. Tunnel/weak-GPS case: verify lost-fix notice, no invented travel or spurious repeated rerouting, recovery on fresh OS location without requiring restart.
4. Switch away, background and foreground Waybi, pan map and tap recenter. Verify route remains active, microphone/other app audio works and camera alerts do not multiply.
5. Log redacted evidence: device/OS/build, route, background minutes, audio output, last real position age, permission state and pass/fail with timestamps. Do not store precise personal trip histories publicly.

## Release gates

- Server adapter tests + full server tests + TypeScript check.
- Flutter targeted location and voice tests.
- Owned/licensed service provisioned and production canary comparison. No new paid service or production API credentials provisioned in this branch.
- Airport exit and CMJ signs legally verified, not merely inferred.
- True device locking/Bluetooth/on-road scenarios witnessed safely.

No production deployment, no modifications to Apple Developer, and no automatic App Store submission.
