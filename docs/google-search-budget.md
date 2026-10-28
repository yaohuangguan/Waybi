# Google search with a free-source fallback

The Flutter search action opens Google's official **Places UI Kit** search list
inside a restricted native WebView. The UI Kit is compatible with non-Google
maps. Ordinary Places API results remain incompatible with Waybi Map.
Typing suggestions still use independent providers. Each explicit Google search
first reserves one unit from a shared, atomic D1 counter; no reservation is
refunded after a timeout or cancellation.

## Limits and alerts

- UI Kit Query: **9,990 reservations per calendar month**, with a 10-query margin
  below its 10,000 monthly free allowance. Periods use America/Los_Angeles time.
- The Google project also caps UI Kit Query at 9,990 per day. Advanced Query and
  Autocomplete Session are disabled with daily quotas of zero.
- A missing database, missing credentials, failed reservation, exhausted budget,
  empty result or Google failure returns the current query to free search.
- The last reservation creates one monthly alert. Mail goes only to
  `moviegoer24@gmail.com` from the verified `alerts@waybi.co` sender.
- An outbox lease, stable Resend idempotency key and bounded retries protect
  against duplicate messages. The existing five-minute cron retries delivery.

The counter covers this integration's reservations. Google free allowances are
shared at billing-account level; do not add another consumer of this SKU without
including its usage in the budget. Cloud billing alerts do not enforce this cap.

## Credentials and content

`WAYBI_GOOGLE_PLACES_UI_KEY` is a browser key restricted to `waybi.co` referrers
and the UI Kit/Maps JavaScript APIs. `WAYBI_RESEND_API_KEY` is a sending-only key
restricted to the verified Waybi domain. CI sends both directly from GitHub
secrets to Worker secrets through stdin, without temporary credential files.

Google names, addresses, photos and reviews remain in the attributed official
component. The native bridge accepts only a selected place ID, coordinates and
the user's own query. Google coordinates remain in the navigation session;
Google selections are not written to recents, favorites or shortcut storage.
Home/Work can be saved when a separately retrieved, non-approximate free address
matches the query within 75 metres. Otherwise the app asks the user to confirm
the location on Waybi Map. Journey records retain actual movement or Valhalla's
independently calculated route geometry.

## Independent search and progressive trips

Qualified addresses retain suburb/city/postcode constraints throughout merging,
enrichment and interpolation. LINZ uses the indexed full-road-name field.
Council queries apply suburb and postcode constraints before record limits.
Street results use a real address point from one locality instead of averaging
unrelated streets with the same name.

Trips renders the cached snapshot first. Account history, upload sync, commute
routes and Plus watches publish independently as they become available. Optional
failures keep existing content, and a stale or cancelled refresh cannot replace
the current snapshot. Concurrent commute refreshes share their pending request.

## Official references

- [UI Kit pricing](https://developers.google.com/maps/billing-and-pricing/pricing)
- [Maps service terms, section 15](https://cloud.google.com/maps-platform/terms/maps-service-terms)
- [Official search component and attribution](https://developers.google.com/maps/documentation/javascript/places-ui-kit/place-search)

## Verification

Server tests use real SQLite for simultaneous final-slot reservations, Pacific
period boundaries, fail-closed behavior and email retry/idempotency. Flutter
tests exercise the native bridge, Google-first handoff, free-source recovery and
independent trip section updates while another request remains pending. Native
iOS and Android compilation run in PR CI. Real SDK rendering must also be
checked on the production origin because the browser key rejects preview hosts.
