This directory vendors `maplibre_gl` 0.27.1 from
https://github.com/maplibre/flutter-maplibre-gl under its original BSD licence.

Waybi adds one native option, `attributionButtonEnabled` (default `true`).
The Dart option is forwarded through the existing option sinks to iOS
`MLNMapView.attributionButton.isHidden` and Android `UiSettings.setAttributionEnabled`.
Web keeps the upstream attribution control.

Waybi presents legible map credits when the native map first becomes ready,
allows them to collapse after five seconds or interaction, and provides full
data licences in Settings. No transparent tint or offscreen margin is used.

The iOS SDK is pinned to 6.31.0 in both Swift Package Manager and CocoaPods.
Waybi styles limit vector label candidates to an expanded viewport at street
zoom. This runs entirely in the native wrapper, preserves each original filter,
and keeps intersecting roads, POI hit targets and all navigation overlays.
Coverage is reused while the visible viewport remains inside its margin; zooming
out restores the original predicates. PMTiles and renderer internals, including
symbol memory guards, remain upstream implementations.

An opt-in device probe (`WAYBI_MAP_PERFORMANCE_PROBE` launch environment variable)
records native frame timings for reproducible pan comparisons. It never runs on
normal launches and writes results only to the app's Documents directory. SDK
rendering statistics use seconds internally; the probe converts them to ms.
