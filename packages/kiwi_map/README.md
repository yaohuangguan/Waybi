# kiwi_map

Reusable, provider-neutral map SDK core extracted from Kiwi Lens.

The package is intentionally **not** tied to Google Maps, MapLibre, NZTA, a
particular HTTP client, authentication scheme, or Kiwi Lens account state.

Kiwi Lens currently uses MapLibre for the Practice renderer. The app owns the
MapLibre adapter and the Photon / OSRM / NZTA adapters; `kiwi_map` owns the
stable contracts those adapters speak.

## Why this exists

Kiwi Lens should be able to evolve in three directions without rewriting the
map:

1. keep shipping the consumer navigation app;
2. publish the map stack as a reusable Flutter/Dart library;
3. offer B2B customers optional Road Intelligence overlays on top of that map.

Those are separate products. A customer should be able to use the base map
without buying Road Intelligence, or bring their own renderer / traffic source
while still consuming Kiwi Lens intelligence.

## Package boundary

`kiwi_map` owns:

- coordinates, bounds and viewport state
- places and provider references
- renderer-neutral controller capabilities
- generic async layer/source contracts
- live traffic-flow models and source interface
- Road Intelligence feature models and source interface
- `KiwiMapStack`, a composition root for optional overlays

Kiwi Lens app adapters own:

- MapLibre rendering and visual style
- Photon place search
- OSRM routing
- GPS filtering / navigation lifecycle
- NZTA traffic ingestion
- API keys, billing, quotas and HTTP clients

This dependency direction is intentional:

```
Kiwi Lens App
   │
   ├── MapLibre adapter ───────┐
   ├── Photon / OSRM adapters  │
   └── NZTA / Road API adapters│
                              ▼
                         kiwi_map
                     (pure SDK contracts)
```

## B2B Road Intelligence

Road Intelligence is an **optional overlay**, not a hard dependency of the map.

A B2B integration can provide a `RoadIntelligenceLayerSource` backed by:

- Kiwi Lens Road Intelligence API
- the customer's own incident feed
- a private fleet/road-operations source

and compose it with a traffic source:

```dart
final stack = KiwiMapStack(
  traffic: myTrafficSource,
  roadIntelligence: myKiwiRoadIntelligenceSource,
);
```

Transport and credentials remain outside the map core. That prevents an SDK
consumer from inheriting Kiwi Lens authentication, subscription, or backend
assumptions.

## Extraction path

The current extraction is deliberately incremental:

- **0.1** — shared geometry, places, traffic and Road Intelligence models
- **0.2** — generic layer + renderer contracts and B2B composition root
- next — move the MapLibre renderer behind a standalone adapter package
- later — publish the adapter as a separate Flutter package once the public API
  is stable

The app continues using the same contracts during the extraction, so turning
this into a standalone library does not require a rewrite or a risky big-bang
migration.
