# Waybi Map foundation

Waybi Map is the product boundary for Waybi's non-Google map experience. The
renderer, navigation UI, journey memory and Waybi-owned overlays belong to
Waybi. Open and official geographic datasets remain credited data sources.

## Current production path

- Renderer: MapLibre Native through `maplibre_gl`
- Vector basemap: OpenFreeMap / OpenMapTiles
- Search: the shipping mobile app calls Waybi Worker only; the Worker orchestrates
  LINZ/Auckland official NZ address enrichments, Geoapify/TomTom and Photon fallback
- Routing: the shipping mobile app calls Waybi Worker only with
  `provider=independent`; the Worker currently falls back to public OSRM
- NZ official data: LINZ addresses, NZTA road/camera/traffic sources where used

Public OpenFreeMap, Photon and OSRM services are prototype dependencies and
must not be treated as production-SLA infrastructure.

## Runtime basemap switch

The mobile map style can now replace every external basemap asset at build
time:

- `WAYBI_MAP_VECTOR_SOURCE`
- `WAYBI_MAP_NATURAL_EARTH_TILES`
- `WAYBI_MAP_SPRITE_URL`
- `WAYBI_MAP_GLYPHS_URL`

The intended first self-hosted source is a New Zealand PMTiles/vector archive
served from a Waybi-controlled origin such as `maps.waybi.co`. The existing
OpenMapTiles-compatible style remains the transition schema so the switch can
ship without rewriting the renderer at the same time.

Example:

```text
WAYBI_MAP_VECTOR_SOURCE=pmtiles://https://maps.waybi.co/nz.pmtiles
WAYBI_MAP_NATURAL_EARTH_TILES=https://maps.waybi.co/natural-earth/{z}/{x}/{y}.png
WAYBI_MAP_SPRITE_URL=https://maps.waybi.co/sprites/waybi
WAYBI_MAP_GLYPHS_URL=https://maps.waybi.co/fonts/{fontstack}/{range}.pbf
```

## Rollout order

1. Keep the current OpenFreeMap source as the fallback while the Waybi-hosted
   NZ archive is built and validated.
2. Serve NZ tiles, glyphs, sprites and Natural Earth assets from a Waybi-owned
   origin.
3. Validate a no-Google/no-OpenFreeMap drive in Auckland: map load, search for
   `42 Verissimo Drive`, route preview, active navigation and rerouting.
4. Replace the Worker's public-OSRM fallback with a Waybi-hosted NZ regional
   routing graph. The mobile app already routes through the Waybi API boundary.
5. Replace the Worker's Photon fallback with Waybi-hosted search/indexing as
   traffic justifies it. The shipping mobile app already has no Photon runtime dependency.
6. Migrate from the transitional OpenMapTiles-compatible schema to a
   Waybi-owned schema only when doing so provides a real product or licensing
   benefit. Do not block the navigation product on a schema rewrite.

## Attribution

Waybi shows `Map data © OpenStreetMap contributors` during the app splash and
keeps full map data credits in Settings → Map data & licences. The map style
also retains machine-readable source attribution.

The custom five-second OpenStreetMap badge in the map canvas has been removed.
MapLibre 0.27.1 still renders its native attribution ornament because that
version does not expose a supported Flutter toggle to disable it. Do not hide
it with transparent colours or off-screen margins. Add a small supported native
option/fork, or upgrade once a supported ornament toggle is available.

## Discover product boundary

The old nearby-POI Explore entry is no longer the primary product surface.
Discover is journey-led:

- places Waybi remembers from completed trips
- roads/areas not yet travelled
- scenic, coastal, sunset and weekend journey suggestions
- rediscovery prompts based on real trip history
- companion-aware suggestions and memories

Generic restaurant/shopping rankings, reviews and photo-heavy POI discovery are
not the core Waybi value proposition.
