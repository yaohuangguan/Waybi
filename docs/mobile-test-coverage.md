# Mobile test coverage

Scope is Waybi's first-party Flutter code, companion package and reusable map package on iOS and Android. Existing Web tests remain in CI; Web coverage expansion is outside this request.

## What the checks establish

The reviewed inventory contains 148 Dart sources: 142 executable modules and six files containing only constants, exports or abstract interfaces. Each executable module must have executed line coverage and meet its reviewed per-file baseline. A new source file, a never-executed component, a missing report, or a coverage regression fails CI. Declaration exemptions have a reviewed content hash; adding logic cannot silently inherit an exemption.

These are executable-line baselines, not a claim of 100% line, branch, function or hardware coverage. The app's large main.dart and retained legacy Google adapter still have substantial untested implementation paths; their limits remain visible in the report. Capability tests below exercise shared logic and user actions separately. Third-party Flutter/plugins and the vendored MapLibre SDK are compiled and exercised through app adapters, not counted as first-party coverage.

Run the complete mobile checks from the repository root:

```sh
(cd apps/mobile && flutter analyze && flutter test --coverage --concurrency=2)
(cd packages/waybi_friends && flutter analyze && flutter test --coverage --concurrency=2)
(cd packages/waybi_map && dart analyze && dart test --coverage=coverage && dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info --report-on=lib)
node --test scripts/check-mobile-coverage.test.mjs
pnpm mobile:coverage:check
swift test --package-path apps/mobile/ios --enable-code-coverage
```

CI retains the three LCOV reports and a source inventory as the mobile-test-coverage artifact for seven days. The policy is in tests/mobile-coverage-policy.json. New capabilities must update tests/mobile-features.json with meaningful tests; changing thresholds requires review.

## Capability inventory

Test names in this table are under apps/mobile/test unless a package or native test is named. The machine-readable manifest stores full repository paths and CI checks that all referenced test files exist.

| Capability | Automated regression evidence |
| --- | --- |
| Startup, onboarding, appearance and page navigation | `app_shell_test.dart`, `status_banner_test.dart` |
| Location access, permanent denial and concurrent requests | `location_permission_gate_test.dart`, `app_shell_test.dart` |
| Silent GPS, stream errors, stopped-trip races and stale fixes | `reliable_location_feed_test.dart`, `drive_engine_platform_test.dart`, `navigation_location_filter_test.dart` |
| Heading validation, motion and trustworthy route origin | `native_contracts_test.dart`, `navigation_forward_bearing_test.dart`, `navigation_motion_test.dart`, `route_origin_location_test.dart` |
| MapLibre interaction, follow, viewport and independent style | `independent_map_interaction_test.dart`, `independent_map_style_test.dart`, `independent_navigation_camera_test.dart`, `map_provider_test.dart` |
| Map and alert layers, persisted preferences and region capabilities | `map_layer_sheet_test.dart`, `map_layer_settings_test.dart`, `map_region_capabilities_test.dart` |
| Location, camera and destination marker visibility | `marker_catalog_test.dart`, `companion_journey_stats_test.dart` |
| Multilingual search, cache, debounce, latency and selection races | `local_multilingual_search_test.dart`, `search_recovery_test.dart`, `search_latency_test.dart`, `live_search_experience_test.dart` |
| Search result resolution and correct destination handoff | `independent_search_to_navigation_contract_test.dart`, `regional_search_adapter_test.dart` |
| Place decks, photos, data credits and independent details | `place_details_content_test.dart`, `place_photo_test.dart`, `waybi_explore_test.dart` |
| Explore categories, saved places and failed/stale responses | `component_catalog_test.dart`, `explore_search_test.dart`, `waybi_explore_test.dart` |
| Route request contract, geometry, alternatives and travel modes | `repository_contracts_test.dart`, `independent_provider_test.dart`, `driving_route_quality_test.dart`, `independent_transit_routing_provider_test.dart` |
| Fastest/shortest/camera preferences and closure detours | `route_filter_detour_test.dart`, `route_preview_preferences_test.dart`, `route_preference_test.dart` |
| Progress, reroute recovery, wrong-way guards and arrival | `route_progress_tracker_test.dart`, `independent_navigation_engine_test.dart`, `navigation_polish_test.dart` |
| Partial lane data, arrow rendering and guidance layouts | `lane_arrow_test.dart`, `navigation_lanes_test.dart`, `independent_navigation_overlay_test.dart`, `navigation_experience_test.dart` |
| Camera matching, alert lifecycle and route relevance | `camera_matcher_test.dart`, `camera_alert_lifecycle_test.dart`, `route_camera_matcher_test.dart`, `navigation_camera_alert_test.dart` |
| Road closures, reports, direction and event timelines | `road_intelligence_test.dart`, `route_road_events_test.dart`, `component_catalog_test.dart` |
| Traffic flow, source fallback and route matching | `traffic_flow_repository_test.dart`, `route_traffic_match_test.dart`, `nzta_traffic_road_event_provider_test.dart` |
| Bus/transit lane restrictions and review corridors | `transit_lanes_test.dart`, `transit_lane_map_test.dart`, `transit_review_corridor_test.dart` |
| Native GPS configuration, follow, trail and complete stop | `drive_engine_platform_test.dart`, `route_display_trail_test.dart`, `drive_hud_test.dart`, `independent_navigation_camera_test.dart` |
| Serialized speech, audio focus, iOS mixing and release | `voice_engine_test.dart`, `navigation_polish_test.dart` |
| Lockscreen status, retry, native serialization and stop | `system_navigation_test.dart`, `component_catalog_test.dart` |
| Navigation links, cold-start requests and intent validation | `external_navigation_inbox_test.dart`, `navigation_link_test.dart` |
| iOS and Android permission denial/grant and payloads | `notification_service_test.dart` |
| Arrival presentation, parking selection and walk handoff | `parking_flow_test.dart`, `navigation_experience_test.dart` |
| Journeys, saved routes, search/filter and commute controls | `journey_tracker_test.dart`, `trips_page_test.dart`, `trips_experience_test.dart` |
| Discover cards, freshness and empty/error states | `discover_page_test.dart`, `discover_memory_test.dart` |
| Sessions, profile sync, favorite places, reviews and logout | `account_features_test.dart`, `profile_actions_test.dart`, `component_catalog_test.dart` |
| Apple nonce/state/token validation and platform-specific login UI | `native_contracts_test.dart`, `apple_account_test.dart`, `apple_profile_test.dart` |
| Confirmation, keyboard, failed deletion and credential erasure | `profile_actions_test.dart`, `account_features_test.dart`, `account_brand_migration_test.dart` |
| Store gateway, purchase/restore states and unavailable billing | `app_store_billing_test.dart`, `plus_page_test.dart` |
| Saved corridors, bounded acknowledgements and encoded IDs | `account_features_test.dart`, `trips_page_test.dart` |
| Validated catalogs, saved copy, freshness and free reload | `camera_catalog_recovery_test.dart`, `camera_data_settings_test.dart`, `offline_navigation_cache_test.dart` |
| Companion backup, conflicts, durable totals and journal recovery | `friends_backup_service_test.dart`, `friends_large_journal_test.dart`, `companion_profile_test.dart` |
| Navigation rewards, idempotence and feedback | `navigation_rewards_feedback_test.dart` |
| Legacy preference/account names and isolation | `brand_migration_test.dart`, `account_brand_migration_test.dart`, `quick_location_store_test.dart` |
| Non-blocking bounded usage and unknown speed limits | `repository_contracts_test.dart` |
| Companion room, bag, journal, journeys, souvenirs and erasure | `room_widget_test.dart`, `journal_recovery_test.dart`, `packing_test.dart`, `room_life_test.dart`, `account_erasure_test.dart`, `souvenir_painter_test.dart` |
| Reusable map models, renderer capabilities, overlays and source contracts | `waybi_map_test.dart`, `place_renderer_contracts_test.dart` |
| Production Swift URL queue, duplicates, encoding and OAuth isolation | `NavigationURLQueueTests.swift` |

## Platform and hardware boundaries

- DriveEngine tests execute both iOS and Android branches: background location configuration, routed versus Just Drive streams, disabled services, GPS jumps, late callbacks and startup/stop races.
- Apple consent tests verify actual plugin-channel payloads, random nonce hashing, state and rejected credentials. Google/Apple account UI, billing and notification gateways use controlled test responses. They do not authenticate a real Apple/Google account or make purchases.
- Native Swift tests execute the URL queue used by the production bridge. iOS and Android CI still compile the application. The placeholder iOS XCTest was replaced with real queue tests.
- Real permission sheets, ActivityKit/Dynamic Island presentation, Android foreground-service delivery, developer trust, audio coexistence with YouTube Music, GPS performance, weak mobile signal and lockscreen endurance require device checks. They are not marked passed by mocks.
- Physical CBD/CMJ/ramps/airport/roundabout regression remains user-deferred. Follow docs/driving-regression-results.csv. Apple developer membership/capability/key setup and real store sandbox purchase/restore remain pending. No paid services or live road/camera requests are needed by these tests.

## Bugs exposed by the new tests

The profile deletion dialog disposed its controller while the dialog's reverse animation could still rebuild its text field. The display-name dialog had the same lifetime issue. Both now let the input widget own its controller. Deletion content scrolls above the keyboard. iOS/Android tests cover matching-email confirmation, cancellation, a failed deletion preserving the session, success clearing credentials and the closing transition.
