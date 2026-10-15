# Daily navigation experience — 15 October 2026

Started from main443014d (PR126). Candidate version1.0.0(40).

## Location recovery

Startup, app resume and navigation share an outstanding OS permission request. Passive resume checks do not reopen the permission sheet after a denial. Limited/granted access is accepted; permanently denied/restricted access leads to settings. Tracking checks ownership and mounted state again after awaiting access, before creating heading/location subscriptions.

Location notices retain a Retry/Open settings action until recovery or dismissal, instead of disappearing after four seconds. Ordinary informational notices retain their existing timeout. Settings recovery resumes location tracking without requiring app restart.

## Search

Search history, scope controls, errors and places share one scrollable area, keeping them reachable on compact phones with the keyboard and larger text.

A failed refresh retains results only when they belong to the same query and search scope. It does not label a previous query's places as current matches. Retry preserves nearby/all-regions scope. A place-resolution failure retries that selected place; editing the query cancels a pending selection so a late response cannot open the previous destination.

## Camera catalog

Malformed or empty HTTP200 camera catalogs cannot overwrite a validated saved catalog. In-memory and persisted fallback preserve known locations and identify the on-device copy.

Source publication date, latest attempted check and latest successful verification are distinct. A failed source fetch advances only the attempted-check timestamp. Older stale records without a known successful timestamp display Unknown; the app does not invent a verification date from the publication date.

Everyone can reload the existing public camera catalog, including free users and guests. This uses the shared public endpoint; it does not unlock the separate Plus source-sync API or initiate new upstream checks. Source checks retain the shared daily cooldown and edge caching. Manual source checks also replace this PoP's older public camera copy, preventing an immediate subsequent read from reverting the display.

On15October production retained129 validated NZTA locations, source publication2026-10-01. Direct automated fetch returned a challenge response; reader fallback returned HTTP429. These changes do not bypass the upstream restriction, claim newly verified coverage or fabricate missing cameras. [Official source](https://www.nzta.govt.nz/travelling-on-our-roads/safety-cameras/about-safety-cameras/fixed-safety-camera-locations).

## Validation and packaging

Regression cases cover concurrent permission sheets, denied/resumed access, persistent recovery controls, compact Chinese/English layouts, cached-search failures, late selections, scope-preserving retries, invalid camera responses, truthful verification dates, free catalog reloads and public-cache refresh after source checks.

Flutter analysis and215server tests passed locally. Mobile regression and CI results are recorded in the PR. No physical driving regression is claimed; the user deferred it.

The iOS compile job saves a tar archive of the unsigned app for one day. Tar preserves executable permissions and bundle paths for local signing; it contains no signing keys or user data. The archive itself cannot be installed or submitted. Device packaging still requires matching valid profiles/certificates and strict signature verification.

Apple login code remains on main. Developer membership/capability/key setup and real Apple authentication are still pending. A Personal Team device build does not validate Apple sign-in, TestFlight or App Store distribution.
