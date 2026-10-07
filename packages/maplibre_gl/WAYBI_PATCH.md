This directory vendors `maplibre_gl` 0.27.1 from
https://github.com/maplibre/flutter-maplibre-gl under its original BSD licence.

Waybi adds one native option, `attributionButtonEnabled` (default `true`).
The Dart option is forwarded through the existing option sinks to iOS
`MLNMapView.attributionButton.isHidden` and Android `UiSettings.setAttributionEnabled`.
Web keeps the upstream attribution control.

Waybi presents legible map credits when the native map first becomes ready,
allows them to collapse after five seconds or interaction, and provides full
data licences in Settings. No transparent tint or offscreen margin is used.

Upstream PMTiles, renderer, camera and source implementations remain unchanged.
Rebase this small patch on the next upstream update rather than upgrading the
map SDK as part of an unrelated product change.
