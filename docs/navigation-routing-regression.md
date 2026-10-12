# Navigation regression notes (12 October 2026)

The app ranks legal driving alternatives by ETA plus a bounded reversal penalty.
A smoother default must be within both 15% and 120 seconds of the fastest ETA.
Necessary U-turns remain available. Walking and cycling are unaffected by the
reversal penalty. Both previews and driving reroutes use the same policy.
Initial direction constraints require a moving, accurate, recent GPS fix; a
stationary compass or manually chosen origin supplies no heading constraint.
OSRM uses a 60 degree origin bearing tolerance, matching Valhalla's default.
These rules contain no country or location exceptions; regression tests cover
New Zealand and Australian origin coordinates.

## Airport Park & Ride North → 8 Whitaker Place

A live Waybi request and its independent OSRM source both returned one route,
approximately 19.47 km / 1466 seconds, exiting Verissimo Drive left and reversing
on George Bolt Memorial Drive. The normal alternatives request returned no
right-turn alternative, so changing the app's ranking cannot repair this example.

The current OpenStreetMap graph contains
[restriction relation 14671934](https://www.openstreetmap.org/relation/14671934):
`no_straight_on` from way 590894181 via node 5640734791 to way 605685491.
This blocks the connection through the divided junction needed to reach the
northbound carriageway. A directed local graph walk ignoring restrictions can
reach that carriageway in about 126 metres, but that path crosses this restriction.

This relation needs verification against the current signed road layout before
any map-data correction and routing graph rebuild. The app must continue to
respect it until then. Do not special-case the airport or silently strip turn
restrictions. Test mocks demonstrate alternative selection, not a claim that the
live airport route has been repaired or that every NZ/AU route is correct.

[Airport's parking information](https://www.aucklandairport.co.nz/airport-parking/park-and-ride)
locates Park & Ride North at 42 Verissimo Drive. Route sampling used the OSM
parking-area centroid (-36.9910531, 174.7907113), not a recorded driver GPS trace.

## Device checks

Automated tests cover lane raster continuity and empty unknown lanes, temporary
map browsing and GPS follow recovery, and iOS audio-session release after speech,
errors, cancellation and late callbacks. CI compiles iOS and Android. Actual
YouTube Music/Bluetooth/AirPlay coexistence still needs a device listening check;
unit tests cannot assert another app's playback state.
