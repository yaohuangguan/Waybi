# iOS map performance investigation

Release profiling on an iPhone 16 Pro Max running iOS 26.6 traced high-zoom work
to MapLibre's cross-tile symbol index and symbol validation on the main thread.
Flutter raster work and PMTiles loading were small in those CPU samples. A public
z14 Auckland CBD tile contained 3,428 POI features; overzooming leaves many
candidates outside the small visible area.

The opt-in native probe moves the camera over the same public CBD area, after a
warmup, at zooms 16, 18 and 19. It also isolates POI names and all symbol layers.
These are programmatic pan measurements, not a guarantee of touch FPS or driving
performance. Encoding times include native render-tree work and are converted
from the SDK's internal seconds to milliseconds.

The 6.28 baseline recorded approximately 135 ms median intervals at zoom 18/19.
Upgrading to 6.31 alone still produced 65/51 ms median intervals at zoom 18/19.
With POI names disabled for diagnosis, zoom 18 reached approximately 16.7 ms.
That diagnostic is not the shipping solution: the app retains POI names.

The change uses expanded-viewport label predicates before symbol layout, keeps
the original category/rank predicates, and refreshes coverage as the camera
leaves its margin or changes scale. Geometry, POI circles, selected places,
reports, traffic, navigation routes and the location marker remain intact.
POI name density grows more gradually between zooms 15 and 18; selectable dots
retain the original density. No SDK memory guards are disabled.

The final signed release on Sam retained visible POI names in every normal
phase and recorded the following results after warmup:

| Zoom | Frames | Median interval | p95 interval | Visible POI names | Intervals over 33.4 ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| 16 | 487 | 16.67 ms | 18.40 ms | 65 | 3 |
| 18 | 501 | 16.66 ms | 16.98 ms | 22 | 0 |
| 19 | 471 | 16.67 ms | 17.81 ms | 7 | 1 |

Each phase sampled approximately eight seconds of native camera animation.
These results show the high-zoom label bottleneck was substantially reduced in
this CBD scenario. Loading new tiles, long finger gestures crossing coverage
boundaries, navigation camera updates and other devices need broader field
testing; this measurement does not establish a universal 60 FPS guarantee.
The probe temporarily keeps the screen awake, restores its previous idle-timer
setting and camera when finished, and runs only with the explicit environment
variable. The private on-device journal check also confirmed four memories in
both the primary save and its backup, with no pending import left over.

To repeat, launch a development-signed release with the environment variable
`WAYBI_MAP_PERFORMANCE_PROBE` set to a run label. Keep the phone unlocked and
foregrounded until `Documents/waybi-map-performance.json` is written. Copy that
artifact through device tooling, check its run label, and compare warmed runs.
Do not compare simulator timings with physical-device timings.
