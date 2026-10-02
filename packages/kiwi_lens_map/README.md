# Kiwi Lens Map

Reusable map and road-intelligence abstraction extracted from Kiwi Lens.

`kiwi_lens_map` is the shared product boundary for the consumer app and future
B2B integrations. The public models and layer contracts are renderer-neutral;
Kiwi Lens currently uses MapLibre through an app adapter.

## Defaults

A standalone `KiwiLensMapStack` includes the Kiwi Lens safety-camera source by
default. Camera positions come from the Kiwi Lens public camera endpoint and are
clipped to the requested viewport.

Traffic and Road Intelligence are separate replaceable layers:

- **Safety cameras** — enabled by default.
- **Traffic** — attach Kiwi Lens/NZTA traffic or a customer traffic source.
- **Road Intelligence** — attach Kiwi Lens Road Intelligence API or a private
  incident/operations source.

The host can replace every source. The map does not require Kiwi Lens account,
subscription or UI state.

## Package boundary

`kiwi_lens_map` owns:

- coordinates, bounds and viewport state
- places and provider references
- renderer-neutral controller capabilities
- generic async layer/source contracts
- safety-camera models and default Kiwi Lens camera source
- live traffic-flow models and source interface
- Road Intelligence feature models and source interface
- `KiwiLensMapStack`, the composition root for the whole map stack

Kiwi Lens app adapters currently own:

- MapLibre rendering and visual style
- Photon place search
- OSRM routing
- GPS filtering / navigation lifecycle
- NZTA traffic ingestion
- API keys, billing and B2B Road Intelligence transport

The intended dependency direction is:

```
Kiwi Lens App / B2B Host
   │
   ├── renderer adapter
   ├── search/routing adapters
   ├── optional traffic source
   └── optional Road Intelligence source
                    │
                    ▼
              kiwi_lens_map
          (stable map contracts)
```

## Example

```dart
final map = KiwiLensMapStack(
  // safety cameras are already present by default
  traffic: myTrafficSource,
  roadIntelligence: myKiwiRoadIntelligenceSource,
);
```

A B2B customer may use only the map + cameras, add live traffic, buy the Road
Intelligence overlay, or replace any layer with their own implementation.

## Extraction path

- **0.1** — shared geometry, places, traffic and Road Intelligence models
- **0.2** — generic layer/renderer contracts, default camera source and B2B
  composition root
- next — move the current MapLibre renderer/style into a standalone Flutter
  adapter package
- later — stabilize and publish the adapter independently from the Kiwi Lens app

The migration stays incremental so improvements to GPS, search, traffic and
navigation continue shipping in Kiwi Lens while the reusable map package grows
underneath it.
