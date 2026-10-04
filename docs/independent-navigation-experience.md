# Independent navigation camera and GPS recovery

The independent renderer uses confirmed OS locations from the same navigation
engine that calculates route progress. Camera movement never counts as a GPS fix.

`IndependentNavigationCamera` frames the map in road distances. The location is
anchored 64% down the unobscured map. City driving shows a few hundred metres
ahead; motorway driving progressively widens that distance. Walking and cycling
use shorter distances. Heading follows the road course, while north-up and the
perspective controls remain available. Manual gestures pause following; recenter
resets the camera policy and resumes it.

The approach to a turn, fork, ramp or roundabout gradually increases detail to
at most zoom 16.9. Straight instructions and outdated off-route maneuvers do not
trigger junction zoom. After a turn, widening is limited to 0.28 zoom levels per
second, so close consecutive junctions do not cause repeated camera jumps.
Native camera transitions use linear interpolation for continuous movement.

Road distance calculations use MapLibre's 512-pixel world at zoom zero, rather
than copying zoom numbers from a different SDK. See the
[native coordinate-system documentation](https://maplibre.org/maplibre-native/docs/book/design/coordinate-system.html).

`ReliableLocationFeed` owns the platform location stream and a bounded one-shot
request. A real, confirmed browse fix under 10 seconds old can transfer into
navigation; stale or inaccurate cached observations cannot bypass filtering.
The startup request supplies a second stationary OS observation. A watchdog
recovers missing initial fixes and stale fixes, reconnects quiet/failed streams,
and throttles attempts to once every six seconds. One-shot requests have a native
five-second time limit. Generation checks discard late callbacks after stopping.
Returning to the foreground requests recovery immediately.

When the OS omits speed/course or reports zero while coordinates move, a motion
estimator requires consecutive precise observations with a consistent course.
It supplies motion metadata before drift filtering, and resets after poor
accuracy, an outage or inconsistent jumps. This keeps heading-up navigation
rotating through a turn without treating stationary jitter as driving.
Small displacements accumulate across frequent callbacks. Confirmed estimates
last at most two seconds without further movement, so stopping cannot leave a
moving speed indefinitely. Optional debug-only metadata logging is enabled with
`WAYBI_NAVIGATION_DIAGNOSTICS=true`; it does not log coordinates.

The existing accuracy, impossible-jump and arrival checks remain in force.
Permissions, disabled services, unstable readings and stale readings have
separate messages. A timeout preserves an actionable permission/service error.
Route requests made before GPS is ready retain the selected destination and
travel mode, then resume automatically when a reliable observation arrives.

## Validation

Unit coverage includes moving camera trajectories, crossing north without a
full rotation, approach/exit zoom, straight/off-route instructions, recenter,
missing initial GPS, stream failure, stalled requests, permission causes, late
callbacks and transfer of fresh versus stale observations. Existing routing,
arrival and turn-guidance regression tests also run.

For an independent-map simulator build without a saved user preference:

```sh
flutter build ios --simulator --debug --dart-define=WAYBI_DEFAULT_MAP_PROVIDER=independent
```

The optional default does not override a saved map selection. Production builds
without it retain the existing default. The camera is an implementation tuned
for Waybi; it does not use Google's internal camera algorithm.

A physical-device road check should cover city and motorway speeds, a roundabout,
consecutive turns, manual pan/recenter, a brief GPS outage, and returning from the
background. Simulator success does not establish real-world GPS reception.
