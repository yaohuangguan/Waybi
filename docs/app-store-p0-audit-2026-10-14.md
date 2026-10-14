# Waybi iOS App Store P0 release audit — 14 October 2026

This document records **verified observations** separately from release gates. Public endpoint checks are snapshots, not safety certification. Never change road restrictions to make a route appear shorter without verifying road signs.

## Account deletion

- [x] In-app Profile > Delete account flow includes irreversible-action confirmation and a warning about Apple subscription cancellation.
- [x] Authenticated `POST /api/auth/delete` requires the current account email and the exact confirmation `DELETE`.
- [x] Cloud user record deletion cascades to sessions, profiles, route history, reviews, quick/saved places, Route Watch records/alerts, companion stats, cloud Friends saves, Google links, subscriptions, API keys and API usage. Login attempts and user-scoped community report usage quotas are removed separately because they are not related by a foreign key. Any surviving 2-hour KV road reports are purged before D1 deletion; new road reports retain no user identity.
- [x] Account-scoped Friends local journals, backup, pending restore and sync snapshot are erased after a confirmed server deletion; unrelated users' journals remain.
- [x] D1-compatible SQLite integration tests exercise authorization, confirmation, cascade and account isolation. No production users were deleted.
- [ ] Release validation with a disposable App Store reviewer test account and production-like D1 database.
- [ ] Confirm third-party Stripe billing/customer retention and active subscriptions cancellation UX; account deletion cannot by itself cancel Apple auto-renewal.
- [ ] Privacy policy and App Store Connect disclosures must describe retention and cloud/local data deletion accurately.

## Route data and highway junctions

- **Production read-only validation:** Airport Park & Ride North (OSM area centroid `174.7907113,-36.9910531`) to Auckland Council's exact 8 Whitaker Place coordinates (`174.76697662198927,-36.8567216115252`) returned one independent driving option, ~19.467 km and ~1466 seconds.
- This reproduces the known route in `docs/navigation-routing-regression.md`. The relevant OSM `no_straight_on` restriction relation `14671934` still needs on-road signage confirmation; do NOT strip the restriction or hardcode a right turn.
- An **illustrative** CBD (`174.7655,-36.8460`) to west (`174.6309,-36.8734`) pair returned one option ~16.331 km/1126 seconds. These approximate points cannot establish CMJ lane-sign accuracy.
- [ ] Photograph/independently verify Verissimo Drive / George Bolt Memorial Drive road signs and actual legal turns.
- [ ] Record real CMJ north/west/south manoeuvres, lane indications, and spoken commands with a second observer.
- [ ] Verify Queenstown Rd, SH20 and Hillsborough overlapping closure detours against **current** NZTA feed, not only prior October 13 regression snapshot.
- [ ] Validate route alternatives and ETA in representative Auckland CBD/highway/airport/roundabout routes without route-provider outage.

## iOS / real device / TestFlight

- Device discovery on 14 October found two paired iPhones: Sam (iPhone 16 Pro Max) and Atlas (iPhone 17).
- Xcode 26.3 and Flutter 3.47.5 are present. Mac's signing keychain initially showed a single **Apple Development** identity; an Apple Distribution identity and App Store provisioning are **not yet verified**.
- The normal Remote Arc shell omitted `/usr/local/bin`, making installed CocoaPods 1.17.0 appear missing; use `PATH=/usr/local/bin:$PATH` and `LANG=en_US.UTF-8` when building. Do not reinstall tooling prematurely.
- The iOS Xcode `project.pbxproj` had local uncommitted changes before this audit and must not be reset or bundled into this PR without review.
- [x] Xcode archive built `Waybi 1.0.0 (37)` successfully with Flutter 3.47.5 + Xcode 26.3. The archive was development-signed (embedded entitlement `get-task-allow=true`).
- [ ] App Store IPA export failed: `No signing certificate "iOS Distribution" found`, and provisioning profiles missing for both `Runner.app` and `WaybiNavigation.appex`. A successful archive and Flutter process exit **do not** prove distributable IPA or TestFlight upload.
- [x] Replaced 1x1 placeholder LaunchImage with existing Waybi icon at 1x/2x/3x and updated center-pinned LaunchScreen storyboard. XML parse and `ibtool` compilation passed; rebuilt release artifact still requires confirmation.
- [x] Inspected archive: 25 third-party privacy manifests bundled; **no conclusion** yet on app-owned privacy manifest/required-reason API compliance.
- [ ] Obtain official Apple Distribution signing and matching App Store profiles for app + extension (and Apple Developer/App Store Connect permissions), export validated IPA and upload/accept TestFlight build.
- [x] After fixing launch artwork, `flutter build ios --release --build-name=1.0.0 --build-number=37` completed and produced `build/ios/iphoneos/Runner.app` (~82.3 MB); `codesign --verify --deep --strict` passed for this **development-signed** build.
- [x] Paired-device direct install of the development-signed Release build succeeded on both Sam iPhone 16 Pro Max and Atlas iPhone 17. This is **NOT** TestFlight.
- [x] Atlas app process launched successfully via `xcrun devicectl`; process list showed both `Runner` and `WaybiNavigation.appex` immediately after launch.
- [ ] Sam app launch was denied while the device was locked (`FBSOpenApplicationErrorDomain: Locked`); retry manually after unlocking. Not evidence of an app crash.
- [ ] App UI/map/search/navigation smoke tests on unlocked physical devices; process launch alone proves no screen functionality.
- [ ] App Store export remains blocked by missing Apple Distribution certificate + app and widget provisioning profiles.
- [ ] Upload via an authorized App Store Connect account; TestFlight processing and tester invitation / installation.
- [ ] True physical driving test: active routing -> lock screen -> 5+ minutes -> unlock; background notification / voice direction and UI state continuity.
- [ ] Bluetooth, audio during spoken directions, AirPlay / music ducking and restoration; interruption from a phone call and app background/foreground.
- [ ] GPS loss/recovery (CBD canyon, tunnel / network gap), reroute, manual pan-and-recenter, thermal and battery metrics on both devices.
- [ ] Never conduct UI interactions or view logs while driving; passenger/helper handles the app.
- Automated Flutter analysis and 307 mobile tests passed after account deletion edits; server TypeScript validation and 208 server tests passed; the Friends account-erasure regression passed. This does not establish driving or App Store review readiness.

## Providers, public API and compliance

| Component | Actual/current condition | P0 action |
| --- | --- | --- |
| NZ map tiles | Waybi-hosted PMTiles / R2 regional tiles, OSM/OpenMapTiles/Positron attribution | Verify visible attribution on app map and map-data sheet; confirm all imagery and tile licensing |
| Global fallback tiles | OpenFreeMap/external glyph/sprite providers | Audit global fallback reliability, attribution and third-party terms |
| Turn-by-turn fallback | `routing.openstreetmap.de` used by independent route fallback (code inspection); FOSSGIS public server policy states ~1 request/sec and no production SLA | **Cannot assert scalable public launch readiness.** Move production routing to a licensed or owned endpoint or secure explicit capacity/terms |
| Legacy search/reverse | `nominatim.openstreetmap.org` in Worker legacy search and reverse endpoints | OSMF public server policy limits **the whole app** to 1 request/second; no systematic autocomplete. Remove reliance or bound globally with an alternate provider |
| Geoapify / HERE / TomTom and other search providers | Optional external providers; configurations depend on secrets | Verify valid contracts, attribution and budget/quotas in production, without printing secrets |
| Auckland transit lanes | AT Open GIS transit lanes with source/CC BY attribution in app | Verify current dataset license, schedule freshness, geography and signage |
| NZTA road centreline | Current NZTA **National Road Centreline** usage terms prohibit commercial navigation and derivative navigation | Do not import that restricted dataset into production turn-by-turn routing; audit other NZTA feeds by dataset, not as one blanket licence |
| Road incidents / cameras | Public health endpoint 14 Oct: HTTP 200, 129 cameras, syncStatus `stale`, sourceUpdatedAt `2026-10-01`, `reader-fallback` | Treat camera freshness as a validation gate; do not label this snapshot live/complete |

Other verified observations: production `/api/health`, a route-options request and a typical street suggestion request responded HTTP 200; one earlier exact-address suggestion temporarily returned HTTP 502 and then succeeded on retry. Monitor intermittent upstream errors and fail gracefully.

## Release gate

**NO-GO for App Store public submission** while any of these persist:
1. Unverified airport legal turn restriction / critical navigational misleading guidance.
2. Public routing provider relied upon at scale without adequate permission/capacity/fallback.
3. Real iOS Archive / TestFlight distribution not proven.
4. No in-app account deletion live end-to-end, including data and local storage handling.
5. Real driving-background/GPS/audio scenarios not witnessed and documented.

References:
- Apple account deletion: https://developer.apple.com/support/offering-account-deletion-in-your-app/
- FOSSGIS public OSRM: https://routing.openstreetmap.de/about.html
- OSMF Nominatim policy: https://operations.osmfoundation.org/policies/nominatim/
- NZTA NRC restriction: https://www.nzta.govt.nz/about-us/our-data-and-official-information/open-data/national-road-centreline-data-request
