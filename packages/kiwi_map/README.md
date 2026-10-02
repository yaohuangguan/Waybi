# kiwi_map

Reusable map contracts extracted from Kiwi Lens.

The package is intentionally provider-neutral. Kiwi Lens currently renders the map with MapLibre, but app concerns such as accounts, subscriptions, Google Navigation, NZTA authentication and HTTP clients stay outside this package.

## Boundary

`kiwi_map` owns map-facing value objects:

- coordinates and viewport state
- places and provider references
- live traffic-flow segments
- road-intelligence overlay features and source contracts

The Kiwi Lens app owns adapters that translate Photon, OSRM, NZTA, Google and the Kiwi Lens Road Intelligence API into these contracts.

This lets the renderer move into this package incrementally without changing its public data model. A future B2B consumer can render the same map and optionally attach a `RoadIntelligenceLayerSource` backed by the Kiwi Lens Road Intelligence API.

The Road Intelligence API is an optional overlay, not a hard dependency of the map. That separation matters for customers that want only the renderer, only their own overlays, or the full Kiwi Lens road-intelligence stack.
