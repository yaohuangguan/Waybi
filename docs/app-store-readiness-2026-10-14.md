# App Store preparation and driving regression — 14 October 2026

Follow-up to [the RC1 audit](app-store-p0-audit-2026-10-14.md). This is an engineering readiness record, not approval from Apple. Physical driving has not been performed by the coding agent.

## Changes and evidence

- PR #122 merged as `7e35e9fe5cb6071003d75308fa3d6c3232ba6367`; this work started from that updated main on `fix/lane-visibility-appstore-qa`.
- Unspecified lane markings previously rendered transparent. A trusted provider recommendation was also discarded if its lane had no known arrow. The HUD now preserves physical lane order, draws neutral dashed lane boundaries for unspecified directions, retains explicit recommendations, and explains partial data in English/Chinese. It never converts an unspecified lane into a guessed straight/turn arrow. Known incompatible directions remain unhighlighted.
- A read-only production route at 14 October returned a four-lane left exit with three unspecified lanes, reproducing the reported data pattern. Other routes returned five lanes with four unspecified markings and a fork with one unspecified marking.
- Added app-owned `Runner/PrivacyInfo.xcprivacy` to the Runner resource phase. Declares UserDefaults reason `CA92.1` for the app's own Friends recovery preferences. This is the required-reason API declaration only; it does not claim that no data is collected or replace the App Privacy questionnaire, privacy policy, or each SDK's manifest.
- RC build number becomes `1.0.0 (38)`.
- Flutter analysis and 310 mobile tests passed, including screenshot-like partial lanes and all-unspecified recommended lanes at 375 × 667, raster visibility checks, GPS filtering/progress, closure handling, rerouting and existing voice lifecycle tests. These tests do not verify audio behavior of YouTube Music on a physical iPhone.

## Production read-only checks

HTTP snapshots taken 14 October around 08:55 UTC; timings and routes can change.

| Check | Observation | Meaning |
| --- | --- | --- |
| Airport Park & Ride North → 8 Whitaker Place | HTTP 200; 19,467.1 m / 1,465.6 s; one route | Known airport loop remains; road restriction/signage still needs verification |
| 8 Whitaker Place → Airport Park & Ride North | HTTP 200; 18,770 m / 1,312.1 s; one route | No active matched closure in the current snapshot; this does not exercise a closed-road detour |
| Illustrative CBD → west points from RC1 | HTTP 200; 16,330.8 m / 1,126 s; one route | API availability only; approximate points do not prove CMJ lane signage |
| Road awareness | `live`, snapshot `2026-10-14T08:50:27.223Z` | Road-event freshness is separate from camera-feed freshness |
| Camera health | 129 cameras; `stale`; source date `2026-10-01`; `reader-fallback` | Investigate feed ingestion/fallback before promising current coverage |
| Apple billing config | HTTP 200; `ready: false` | No validated purchase/restore flow yet |
| Dedicated `https://waybi.co/privacy/` | HTTP 404 | Existing subscription link goes to README privacy summary, not a complete dedicated policy |

Signed device build 38 completed with Xcode 26.3, iOS 26.2 SDK, bundle co.waybi.ios; deep/strict codesign verification passed. The app-owned privacy manifest is present in the built bundle (26 manifests total). Atlas installation succeeded. Sam was unavailable at the initial device check; physical on-screen smoke is still pending. User deferred road driving until after the fixes/device checks.

## Priorities before public submission

| Priority | Required outcome | Current state / next action |
| --- | --- | --- |
| P0 | Distribution-signed app and extension, accepted TestFlight build | Mac has only Apple Development identity. Set up Apple Distribution/profile for `co.waybi.ios` and `co.waybi.ios.navigation`, export IPA, upload and confirm processing/install. No signing keys should be pasted into chat. |
| P0 | Resolve iOS login guideline 4.8 | iOS offers Google authentication and linking but no equivalent privacy-preserving login option. User chose to retain Google. [Native Apple login, linking and revocation code](apple-sign-in.md) is implemented; Apple capability/key/profile setup and real login remain pending. Google remains available to existing users. An email/password button alongside Google does not establish the exclusive-first-party exception. |
| P0 | Complete accessible privacy policy and App Privacy disclosures | Publish a stable policy URL, link it from signed-in and signed-out profile UI and App Store Connect. Describe operator/contact, account/email/IDs, saved places/routes/reviews/Friends, precise coordinates and search requests sent to providers, retention/deletion and provider logs. Inventory all bundled SDKs and disclose actual behavior; do not copy an empty-data manifest. |
| P0 | Account deletion end to end on production-like data | Use a disposable test account; verify server deletion, session revocation and local/cloud account-scoped erasure, isolation from a second account, and billing notice. Do not test on Sam/Atlas real accounts. Local SQLite tests already pass; that is not a live D1/UI deletion result. |
| P0 | Physical navigation regression | Complete the route/condition matrix below on both phones. Record GPS recovery, prompts, background operation and music behavior with a passenger. |
| P0 | Production routing/search capacity within the intended budget | Public OSRM limits usage to 1 request/sec and no heavy use; Nominatim limits the entire application to 1 request/sec and disallows autocomplete. Per-isolate throttling is not a global limit. Confirm deployment/configuration and an appropriate endpoint/capacity arrangement before broad release; no paid resources were enabled by this work. |
| P1 | Camera freshness and claims | Diagnose the stale camera source; show freshness/coverage honestly. Never promise every camera or a camera-free route. |
| P1 | Working subscriptions or an intentional free-only release | Configure StoreKit products/server verification, test buy/cancel/restore/expired/refund with Sandbox/TestFlight. If releasing free-only, remove unfinished purchase promises/upgrade dead ends deliberately; do not silently enable billing. |
| P1 | Complete store metadata | Support URL/contact, working policy URL, screenshots of actual build, accurate description, review account/instructions, age-rating questions, content rights and regional availability. Check whether free-text reviews are public; if so validate report/filter/block/moderation features under guideline 1.2. |
| P1 | Device/performance evidence | Cold launch, denied/approximate location, permissions recovery, low-power/thermal state, battery drain, Bluetooth and phone-call interruption, large text and both languages. |

Current Xcode 26.3 meets the Xcode 26 baseline effective April 2026; inspect the final artifact's SDK and minimum deployment settings as part of export. An installed development-signed release build does not prove TestFlight or App Review readiness.

## Physical driving protocol

A passenger operates the phone and records results. Keep legal routes; do not enter a closed road to test the app. Check actual signs rather than changing map restrictions to force a desired route. Use current closures, or test injected closure scenarios in a stationary replay environment.

Record build/commit, device/iOS, start/end time, route, audio source/output, location permission/accuracy, network, observation and screenshot/timestamp for every failure. No row is passed without evidence. A route/API response is not a witnessed drive.

| Route family | Suggested exercise | Critical observation |
| --- | --- | --- |
| CBD | 8 Whitaker Place and nearby streets/tall buildings | GPS drift/recovery, correct parallel road, legal one-way turns, camera follows after pan/recenter |
| CMJ | CBD↔west and CBD↔south; choose lawful actual journeys | Successive exits, correct left-to-right lane order, no stale lane row after manoeuvre |
| Highway ramps | SH1 Mt Wellington exit toward Tai Ping; Queenstown/Hillsborough when legally open | Four/five-lane partial data, clear recommended lane, ramp vs mainline separation |
| Airport | Airport Park & Ride North↔8 Whitaker Place | Verify Verissimo/George Bolt signs and OSM restriction 14671934; observe start heading and loops |
| Multilane roundabout | An observer-selected familiar legal local roundabout | Approach lane markings, correct exit and next prompt, no left/right guess for missing data |

For every route family run/record these conditions (may be split over separate safe journeys):
1. Normal GPS/network: arrows, distances, next instruction, ETA, camera follow.
2. Tall-building/tunnel or GPS-loss segment: no false U-turn from a jump; clear degraded status and recovery.
3. Known active closure: clear alternative/detour or actionable retry; no inactive Start; no accepted route through a matched closure.
4. Closely spaced manoeuvres: lane row and voice advance together; previous exit arrows disappear.
5. Background music: YouTube Music and another source, speaker/Bluetooth; navigation ducks and releases audio, song remains playing afterward.
6. Weak/no network: existing guidance remains usable, reroute failure is visible, recovery retries are bounded.
7. Lock screen for at least five minutes during active navigation: guidance/voice continuity, Live Activity and correct state on unlock.
8. App background/foreground and phone-call interruption: no duplicated voice or permanently held audio session.

All physical rows are currently **NOT RUN** by this agent. The companion CSV provides 40 rows per device and fields for evidence. Close blocking defects and repeat affected routes before signing off.

## Official references

- [Apple review guidelines, including 4.8, 5.1 and user-generated content](https://developer.apple.com/app-store/review/guidelines/)
- [Apple account deletion guidance](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion/)
- [Apple required-reason APIs](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
- [SDK baseline effective April 2026](https://developer.apple.com/news/upcoming-requirements/?id=04282026a)
- [OSRM lane object semantics](https://project-osrm.org/docs/v5.24.0/api/#lane-object)
- [FOSSGIS public routing policy](https://routing.openstreetmap.de/about.html)
- [Nominatim policy](https://operations.osmfoundation.org/policies/nominatim/)
