# Road Intelligence v1 preview

Base URL: `https://waybi.co/api/v1/road-intelligence`.
The API exposes official NZ road events and safety cameras with attribution, source freshness and data-use conditions. It excludes Google content, personal journeys and private community reports.

Apply D1 migration `0011_road_intelligence_api.sql` before deployment. Tests use Node 24 SQLite against the actual migration and statements.

| Endpoint | Authorization | Purpose |
| --- | --- | --- |
| `GET /capabilities` | Public | Features, quotas and source permissions |
| `GET /openapi.json` | Public | OpenAPI 3.1 contract |
| `GET /keys` | Existing signed-in account session | Metadata; never the secret |
| `POST /keys` | Account session | `{ "name": "Fleet evaluation" }`; secret returned once |
| `DELETE /keys/{id}` | Owning account session | Revoke a key |
| `GET /events` | `Authorization: Bearer klri_...` | Area/nearby query |
| `POST /corridor` | API key | Events ordered along a route |

At most five active keys/account; expiry 90 days, preview:read scope. Only a SHA-256 hash and display prefix are stored.

```bash
curl "$BASE/events?near=174.7633,-36.8485&radiusMeters=1500&limit=50" -H "Authorization: Bearer $ROAD_API_KEY"
curl "$BASE/corridor?types=safetyCamera,roadworks" -H "Authorization: Bearer $ROAD_API_KEY" -H 'Content-Type: application/json' -d '{"coordinates":[[174.7633,-36.8485],[174.7700,-36.8600]],"bufferMeters":180}'
```

Alternatively use `bbox=west,south,east,north`, bounded to NZ and at most 2 degrees wide/high. Nearby radii: 50–10,000 metres. Corridors: 2–250 `[longitude, latitude]` points, buffers 25–500 metres, body at most 24 KB. `types`, `limit` (1–100) and `cursor` apply to both endpoints. Cursors are offsets in the current refreshed snapshot, not a frozen dataset.

Responses include `requestId`, `generatedAt`, `events`, `sources`, `dataUse`, `total` and `nextCursor`. Check source `stale` and `status`; failed refreshes retain the last successful retrieval time. Future/expired events are omitted. Camera confidence is null rather than an invented score.

Quotas: 1,000 authenticated attempts/day and 60/minute, atomically counted in D1. Invalid queries and rejected minute-limit attempts count toward the daily budget. Successful responses include `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`; 429 includes `Retry-After`. Counters older than seven days are cleaned up. Submitted route coordinates are processed in memory and never stored or logged by the API.

This is a **free evaluation API**, not a licence to sell NZTA data. Responses set `commercialRedistribution: false`. Paid B2B requires appropriate source permissions and a production data/hosting agreement; NZTA terms distinguish value-added functionality from charging for raw travel data. See [traffic API terms](https://www.nzta.govt.nz/about-us/our-data-and-official-information/use-our-data/terms-of-use) and [website data terms](https://www.nzta.govt.nz/about-us/about-this-site).
