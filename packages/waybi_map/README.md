# Waybi Map

Reusable map and road-intelligence abstraction extracted from Waybi.

`waybi_map` is the shared product boundary for the consumer app and future
B2B integrations. The public models and layer contracts are renderer-neutral;
Waybi currently uses MapLibre through an app adapter.

## Defaults

A standalone `WaybiMapStack` includes the Waybi safety-camera source by
default. Camera positions come from the Waybi public camera endpoint and are
clipped to the requested viewport.

Traffic and Road Intelligence are separate replaceable layers:

- **Safety cameras** — enabled by default.
- **Traffic** — attach Waybi/NZTA traffic or a customer traffic source.
- **Road Intelligence** — attach Waybi Road Intelligence API or a private
  incident/operations source.

The host can replace every source. The map does not require Waybi account,
subscription or UI state.

## Package boundary

`waybi_map` owns:

- coordinates, bounds and viewport state
- places and provider references
- renderer-neutral controller capabilities
- generic async layer/source contracts
- safety-camera models and default Waybi camera source
- live traffic-flow models and source interface
- Road Intelligence feature models and source interface
- `WaybiMapStack`, the composition root for the whole map stack

Waybi app adapters currently own:

- MapLibre rendering and visual style
- Waybi Search client contracts (shipping traffic goes through the Waybi Worker;
  Photon remains a server/dev fallback)
- Waybi Routing client contracts (shipping traffic goes through the Waybi Worker;
  OSRM remains a server/dev fallback)
- GPS filtering / navigation lifecycle
- NZTA traffic ingestion
- API keys, billing and B2B Road Intelligence transport

The intended dependency direction is:

```
Waybi App / B2B Host
   │
   ├── renderer adapter
   ├── search/routing adapters
   ├── optional traffic source
   └── optional Road Intelligence source
                    │
                    ▼
              waybi_map
          (stable map contracts)
```

## Example

```dart
final map = WaybiMapStack(
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
- later — stabilize and publish the adapter independently from the Waybi app

The migration stays incremental so improvements to GPS, search, traffic and
navigation continue shipping in Waybi while the reusable map package grows
underneath it.
