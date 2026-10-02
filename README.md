<p align="center">
  <img src="apps/web/public/brand/kiwi-lens-lockup.svg" width="360" alt="Kiwi Lens — A clearer journey" />
</p>

<p align="center">
  <strong>A New Zealand-first navigation and road-intelligence app.</strong><br />
  Maps, routing, camera awareness, parking, commute monitoring and a cleaner pre-trip experience in one place.
</p>

<p align="center">
  <a href="https://kiwi-lens.nzs.workers.dev/">Live web app</a>
  ·
  <a href="packages/contracts/openapi.yaml">OpenAPI contract</a>
  ·
  <a href="LICENSE">Noncommercial license</a>
  ·
  <a href="#development">Development</a>
</p>

# Kiwi Lens

Kiwi Lens is a navigation companion built specifically around driving in New Zealand. It combines turn-by-turn navigation with NZTA road intelligence, safety-camera awareness, parking discovery, commute monitoring and a compact driving UI designed to keep the information that matters visible without covering the map.

The project ships as both a **Flutter mobile app** and an installable **Vite PWA**, backed by a **Cloudflare Worker**. Mobile supports both **Google Maps** and **Mapbox** as map/search/routing providers while keeping provider data boundaries explicit.

## What Kiwi Lens does

| Area | Current experience |
| --- | --- |
| Navigation | Traffic-aware driving routes, rerouting, voice guidance, lane guidance, ETA, speed and compact navigation overlays |
| Map providers | Google Maps and Mapbox on mobile, with provider-aware search, routing and content handling |
| Journey Brief | One pre-trip summary for ETA, traffic/delay, matched cameras, parking context and route rationale |
| Safety cameras | NZTA fixed-camera data, route matching, map visibility and high-confidence approach alerts |
| Trips | Home / Work shortcuts, recent destinations, route history and stable commute monitoring |
| Route Watch | Watches fixed **Home → Work** and **Work → Home** corridors against official NZTA road events |
| Parking | Nearby parking discovery, Auckland Transport data where available, drive-to-parking and walking continuation |
| Web / PWA | Search, routing, camera awareness and Cloudflare-hosted full-stack web experience |
| Cost control | Provider usage telemetry and Cost Guard aggregation for Google, Mapbox and Geoapify usage |

## Free navigation, paid intelligence

Kiwi Lens deliberately does **not** put basic navigation behind a paywall.

### Free

- Maps and place search
- Route planning and turn-by-turn navigation
- Automatic NZTA safety-camera data updates
- Camera display and navigation alerts
- Journey Brief
- Parking discovery and park-then-walk flow
- Core Trips and destination history

### Kiwi Lens Plus

Plus is for proactive road intelligence and convenience rather than access to the map itself.

- **Route Watch** — persistent Home → Work / Work → Home monitoring
- **Manual NZTA camera sync** — check for the latest camera dataset immediately instead of waiting for the automatic refresh cycle

Automatic camera refresh remains available to everyone.

The Flutter account page opens a native Plus discovery and subscription page. iOS uses StoreKit 2, with server verification, restore purchases and App Store subscription management. Planned New Zealand prices remain **NZ$4.99/month** and **NZ$39.99/year**; available products display Apple's localized prices. Purchases stay disabled until App Store products and verification credentials are configured.

Stripe Checkout and Customer Portal backend APIs are retained for a future website channel. See [billing setup](docs/billing.md) for product IDs, server secrets, migrations and validation steps.

## Journey Brief

Before starting a route, Kiwi Lens condenses the most useful decision information into one compact card:

- expected arrival time
- current traffic condition or traffic delay
- route distance
- matched safety-camera count
- nearby / selected parking context
- why the selected route is recommended

Detailed traffic, route options and parking controls remain available underneath instead of competing for attention at the top of the sheet.

## Route Watch

Route Watch monitors a **stable commute**, not a route anchored to wherever the phone happened to be when monitoring was enabled.

Once Home and Work are configured, Kiwi Lens can maintain two independent watches:

- **Home → Work**
- **Work → Home**

When a watch is created or refreshed, Kiwi Lens stores a sampled route corridor, baseline ETA/distance and route provider. Route geometry expires after **29 days** so stale geometry is not monitored indefinitely.

A Cloudflare cron evaluates active, non-expired watches every **15 minutes** against official NZTA Traffic and Travel road events. Background checks operate on the saved corridor and do not continuously upload the driver's live GPS position or repeatedly purchase fresh Google routes.

Watch states are normalized to `healthy`, `advisory`, `warning`, `disrupted` and `unknown` when route geometry needs refreshing.

Remote push delivery is a separate layer; the current implementation provides real server-side monitoring and in-app status without claiming APNs/FCM delivery that is not yet wired end-to-end.

## NZTA camera intelligence

Kiwi Lens maintains a validated snapshot of New Zealand fixed safety-camera data from the official NZTA source.

The production Worker checks for camera updates every **6 hours** and writes validated snapshots to Workers KV. A new snapshot only replaces the current one when the source date and coordinates pass validation; otherwise Kiwi Lens keeps the last known-good dataset.

During navigation, cameras are projected against the active route rather than treated as simple nearby points. The matcher also uses route geometry and road context to reduce false positives from adjacent roads.

The source data does not include every enforcement-direction or lane attribute, so Kiwi Lens should be treated as supplementary driving information, not a substitute for road signs or traffic law.

## Parking and arrival

For supported New Zealand destinations, Kiwi Lens can surface parking near the destination before navigation starts.

In Auckland, Auckland Transport Open GIS parking data is preferred where available. Published capacity is treated as **static capacity**, not live space availability.

A parking-assisted journey can be handled as:

1. drive to the selected parking location,
2. finish the driving leg,
3. continue with a walking route to the original destination.

## Architecture

```text
┌──────────────────────────────┐
│ Flutter mobile               │
│ Google Maps / Mapbox         │
│ navigation + road UI         │
└──────────────┬───────────────┘
               │ HTTPS
               ▼
┌──────────────────────────────┐
│ Cloudflare Worker            │
│ API + auth + orchestration   │
├──────────────┬───────────────┤
│ D1           │ Workers KV    │
│ accounts     │ camera cache  │
│ Route Watch  │ sync state    │
│ usage data   │               │
└──────┬───────┴───────┬───────┘
       │               │
       ▼               ▼
    NZTA / AT     Google / Geoapify
                  server-side APIs

┌──────────────────────────────┐
│ Vite PWA                     │
│ served by the same Worker    │
└──────────────────────────────┘
```

### Monorepo

```text
apps/
  mobile/      Flutter iOS / Android app
  server/      Cloudflare Worker API and scheduled jobs
  web/         Vite PWA

packages/
  core/        shared route / camera geometry logic
  contracts/   HTTP API contract

migrations/    Cloudflare D1 migrations
scripts/       data import and mobile development helpers
```

## Technology

- **Mobile:** Flutter / Dart
- **Web:** Vite / TypeScript
- **Backend:** Cloudflare Workers
- **Database:** Cloudflare D1
- **Cache / snapshots:** Workers KV
- **Maps & navigation:** Google Maps Platform, Google Navigation SDK, Mapbox
- **Road intelligence:** NZTA Traffic and Travel / fixed safety-camera source
- **Parking:** Auckland Transport Open GIS where available
- **Package management:** pnpm workspace

## Development

### Requirements

- Node.js 20+
- pnpm 12.6+
- Flutter SDK for mobile development
- Xcode for iOS builds
- Android SDK / Android Studio for Android builds
- Cloudflare Wrangler for Worker development and deployment

### Install

```bash
corepack enable
pnpm install
```

### Run the web app and Worker locally

```bash
pnpm db:migrate:local
pnpm dev
```

The web app runs at `http://localhost:5173` and proxies `/api` to the local Worker.

### Mobile

```bash
pnpm mobile:doctor
pnpm mobile:dev
```

Useful mobile commands:

```bash
pnpm mobile:devices
pnpm mobile:analyze
pnpm mobile:test
pnpm mobile:build:apk
pnpm mobile:ios
pnpm mobile:ios:install
pnpm mobile:ios:ipa
```

Provider keys/tokens for local mobile builds belong in local, uncommitted configuration. Do not commit API keys, Mapbox access tokens or unrestricted server credentials.

## Testing

```bash
pnpm test
pnpm build:web
pnpm check:worker
pnpm mobile:analyze
pnpm mobile:test
```

The test suite covers route/camera matching, NZTA parsing and snapshot safety, Route Watch evaluation, Worker APIs, map-provider rules, navigation state, parking flows and Flutter UI behavior.

## Cloudflare deployment

Production uses a **full-stack Worker**: the Worker serves the PWA assets and handles `/api/*`.

Typical deployment flow:

```bash
pnpm install
pnpm db:migrate:remote
pnpm deploy
```

Required runtime secrets and provider credentials should be configured through Cloudflare / local environment configuration rather than committed to the repository.

Current production web endpoint:

**https://kiwi-lens.nzs.workers.dev**

Scheduled jobs:

- every **15 minutes** — Route Watch road-event evaluation
- every **6 hours** — NZTA camera dataset refresh

## API

The shared API contract lives in [`packages/contracts/openapi.yaml`](packages/contracts/openapi.yaml).

Key endpoints include:

- `GET /api/health`
- `GET /api/cameras`
- `GET /api/search`
- `GET /api/parking`
- `GET /api/route`
- `GET /api/route-watches`
- `POST /api/route-watches`
- `DELETE /api/route-watches/:id`

Authenticated account, Plus and administrative endpoints are intentionally kept server-side rather than documented as public client contracts.

## Cost Guard

Kiwi Lens records aggregate provider usage so product growth can be evaluated against real API cost instead of estimates.

Current tracking includes:

- Google Routes
- Google Places search/details/photos
- Google Navigation destination units
- Mapbox navigation trips
- Geoapify autocomplete

Usage tracking is best-effort and must never interrupt search or active navigation.

## Provider boundaries

Kiwi Lens keeps provider-specific content rules explicit.

For example, changing the map renderer does not automatically relabel Google content as Mapbox content, and Mapbox-sourced content is not persisted where the current storage licence does not permit it.

This separation is intentional: map switching is a UI choice, not a licence bypass.

## Privacy

Kiwi Lens uses location on the device for navigation, route progress and road-intelligence matching.

- live GPS is not continuously stored by Route Watch
- Route Watch background checks use the saved route corridor
- route/search requests are sent only to the services required to perform those operations
- account data and Route Watch state are stored in D1
- billing records store provider transaction/customer identifiers and membership status; payment details are handled by Apple or Stripe
- validated camera snapshots are stored in Workers KV
- API keys and privileged provider credentials must not be committed to the repository

## License

Kiwi Lens is **source-available for noncommercial use** under the [PolyForm Noncommercial License 1.0.0](LICENSE).

You may study, run, modify and redistribute the code for permitted noncommercial purposes under that license. **Commercial use, commercial integration, resale, paid services based on this code, or other commercial exploitation is not permitted without a separate written commercial license from the copyright holder.**

This repository is therefore **not licensed under a permissive open-source licence such as MIT or Apache-2.0**. If you want to use Kiwi Lens commercially, contact the repository owner for separate licensing.

## Current limitations

- Browser/PWA background navigation is constrained by mobile browser GPS and audio lifecycle rules; the Flutter app is the primary path for sustained native navigation.
- NZTA camera data does not expose every enforcement direction or lane attribute.
- Parking capacity is not equivalent to live availability unless an upstream source explicitly provides live data.
- Route Watch currently provides server-side monitoring and in-app state; remote push delivery is a separate feature.
- Third-party APIs remain subject to their own quotas, licences, availability and billing.

---

<p align="center">
  <img src="apps/web/public/brand/kiwi-lens-icon.png" width="88" alt="Kiwi Lens icon" />
  <br />
  <strong>Kiwi Lens</strong><br />
  A clearer journey through New Zealand.
</p>
