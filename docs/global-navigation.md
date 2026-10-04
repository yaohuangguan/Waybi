# Global navigation and road intelligence

Valid worldwide coordinates can open place navigation, quick route previews,
external links and independent navigation. Reverse geocoding no longer rejects
overseas addresses or forces New Zealand formatting. The independent client
already uses global car, foot and bicycle routing graphs; server fallback now
retains the requested mode and actual maneuver metadata. Missing transit
coverage cannot silently produce a driving route.

Country configuration enables worldwide community reports and route-derived
merge/sharp-turn intelligence. Route-derived events are marked inferred and
disappear with the route. NZTA cameras and official incidents retain their NZ
provenance and coverage. The global event API includes community reports with
their source and validity, excludes reporter identity, and remains usable when
the regional official feed fails.

Six report categories have distinct, high-contrast 38-pixel symbols in both map
providers. MapLibre registers those images, uses the event type for each pin,
keeps them visible above road geometry, and includes the icon layer in hit
testing. Congestion is decoded as congestion, directional reports retain their
heading, and expired reports are excluded.

Global support does not imply complete official data in every country. The
current official speed-limit feed covers NZ. Other coordinates return an
unknown limit, never a guessed default. Route cards and the journey brief show
unavailable traffic when no observations exist, including neutral traffic bars.
Live traffic, transit and POI availability depend on the configured provider
and its regional coverage. Public routing endpoints are still prototype
infrastructure; their success is not an availability guarantee for an App Store
launch. Backend changes require deployment before they affect production.

Validation covers coordinates in Asia, Europe, North/South America, Africa and
near the date line, global event provenance/direction, mode-preserving fallback,
unknown limits, overseas reverse lookup and tapping report icons. A separate
read-only native entrypoint at `integration_test/report_map_preview.dart`
previews six synthetic events without submitting or publishing any reports.
