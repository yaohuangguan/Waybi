# Mainland China: Amap search and routing

OpenStreetMap is too sparse in mainland China for search. Near Shijiazhuang a
search for "盛世春天" found exactly one OSM match, a compound in Luohe 494 km
away, and the app planned a 564 km drive to it. Inside mainland China the
Worker therefore uses the Amap (高德, AutoNavi) Web Service API for search,
reverse geocoding and routing. The base map (OpenFreeMap/OSM) and device GPS
stay WGS-84; only the server talks to Amap.

## What changes in mainland China

Mainland China is a simplified boundary polygon
(`apps/server/src/china_geo.ts`, mirrored in
`apps/mobile/lib/domain/china_region.dart`). Hong Kong, Macau, Taiwan, Penghu,
Kinmen and Matsu are outside it and keep the existing global stack.

| Request | Mainland China behaviour |
| --- | --- |
| `/api/suggest` with `near` in China | Amap input tips (city from a cached reverse geocode, GCJ-02 location bias); around search (50 km) and keyword search only while fewer than 3 places were found; OSM only as a deduplicated fallback |
| `/api/search` with `near` in China | Amap around + keyword search, same fallback |
| `/api/reverse` in China | Amap regeo label, Nominatim fallback |
| `/api/route-options`, `/api/route` with every point in China | Amap driving v5 (`show_fields=cost,navi,tmcs,polyline`, alternatives, up to 16 stops), Amap walking and bicycling for single-leg trips |

- Amap coordinates are GCJ-02. Requests convert WGS-84 → GCJ-02 with the
  standard transform; responses convert back with an iterative inverse that
  round-trips to under a millimetre.
- Search results carry `provider: "amap"`, `attribution: "高德地图 / AutoNavi"`
  and `distanceMeters`, ranked by relevance and proximity, so a nearby
  exact-name compound beats a distant namesake.
- Routes keep the normalised route-option shape the app already consumes:
  OSRM-style steps (Amap `navi.action`/`assistant_action` mapped to `turn`,
  `fork`, `on ramp`, `off ramp`, `merge`, `roundabout`, `arrive`, ... with
  `left`/`slight right`/`uturn` modifiers), `along` distances, waypoint
  `arrive`/`depart` steps, alternatives, and traffic intervals plus live
  `conditions` from `tmcs`. Requested as Waybi routing they stay
  `provider: "independent"` (so the app's navigation engine accepts them) with
  `routingEngine: "amap"`.
- The app never queries photon.komoot.io or public OSRM directly in mainland
  China, shows distance on every result, warns when the nearest named match is
  more than 50 km away ("最近的匹配在 494 公里外"), and opens full search
  instead of auto-selecting such a match on Enter. Amap attribution is shown
  with results, the place card, the route preview and in Data credits.

Not covered by Amap here, so the current engines answer: public transport in
China (the app's transit itineraries come from a separate client-side
provider and show "not available" there), walking or cycling with stops, more
than 16 stops, and any trip that leaves the mainland. Amap's web API has no
heading parameter, so reroutes do not pass the travel direction, and it
publishes no lane data, so lane prompts are absent on Amap routes.

## Setup: `AMAP_WEB_KEY`

1. Sign in to the [Amap open platform](https://console.amap.com/) and complete
   developer verification (个人认证 or 企业认证).
2. Console → 应用管理 → 我的应用 → 创建新应用, then 添加 Key and choose the
   service platform **「Web服务」**. Do not use a JS API, Android or iOS key; the
   Worker calls the REST endpoints under `restapi.amap.com`.
3. Leave the IP allowlist empty (Cloudflare Worker egress addresses change), or
   use a digital signature if you add one later.
4. Store the key as a Worker secret, never in `wrangler.jsonc` or the app:

   ```sh
   pnpm exec wrangler secret put AMAP_WEB_KEY
   ```

5. Deploy. Without the secret, or once a daily budget is spent, mainland
   China simply keeps the existing OSM search and routing.

Check it with a search near Shijiazhuang; the first result must be the local
compound and `provider` must be `amap`:

```sh
curl 'https://waybi.co/api/suggest?q=%E7%9B%9B%E4%B8%96%E6%98%A5%E5%A4%A9&near=114.51,38.04&provider=independent&lang=zh'
```

## Budgets and limits

Every Amap call reserves one unit in D1 (`api_usage_daily`, provider
`__waybi_quotas`, sku `amap:<api>`, UTC days) before it is sent, exactly like
the Google budgets. Each client (pseudonymous IP fingerprint) may use at most
`client_share` of each API's daily ceiling. A D1 failure fails closed. Usage is
also recorded for Cost Guard (`/api/admin/costs`) as provider `amap`.

Amap's free quota for a certified personal developer is monthly and pooled:
基础搜索服务 (input tips, keyword and around search) 5,000 calls/month and
基础LBS服务 (route planning, geocoding, reverse geocoding) 150,000/month. The
defaults stay under both pools in a 31-day month:

| API | Daily default | Pool |
| --- | ---: | --- |
| `inputtips` | 90 | search |
| `place_text` | 30 | search |
| `place_around` | 30 | search |
| `regeo` | 1,000 | LBS |
| `driving` | 2,500 | LBS |
| `walking` | 400 | LBS |
| `bicycling` | 400 | LBS |
| `client_share` | 0.5 | per-client fraction |

Override any of them with the `WAYBI_AMAP_DAILY_BUDGET` Worker variable, a JSON
object such as `{"inputtips":300,"driving":6000,"client_share":0.25}`, after
confirming the account's real quota in the Amap console (控制台 → 流量分析 →
配额管理). The search pool is small: about 150 searches a day across all
users of the free tier. Search results are cached for five minutes per query
and area, and the city lookup for a ~5 km cell is cached for a day.

Requests are also covered by the existing per-client rate limits
(`RATE_LIMIT_SEARCH` for suggest/search/reverse, `RATE_LIMIT_ROUTING` for
routes). Search and reverse geocoding time out after 5 s, walking/cycling
after 6 s and driving after 8 s.

## Errors and logging

Amap answers most errors with HTTP 200, `status: "0"` and an `infocode`. Those,
HTTP errors, timeouts and invalid JSON all fall back to the existing stack.
Key errors (100xx such as 10001 `INVALID_USER_KEY`, 10009
`USERKEY_PLAT_NOMATCH` for a non-Web-service key) pause all Amap calls in that
Worker isolate for 10 minutes; quota errors (10003, 10044, 10045, 1001x/1002x
concurrency limits) pause only that API. Each failure logs one structured
`amap_request_failed` line with the API, reason and infocode. Logs never
contain the key, request URL, query or coordinates.

## Terms and licensing caveats

- The free quota is for non-commercial use by certified developers. Waybi
  sells Waybi Plus, so the Amap pricing page indicates that commercial use
  needs the 技术服务许可 (technical service licence; the published 基础版 price
  is ¥50,000 per year). Confirm with AutoNavi before relying on Amap in
  production.
- Amap content must carry its attribution ("高德地图 / AutoNavi") where it is
  shown; Waybi does this for results, place cards, route previews and Data
  credits.
- Amap results are shown on a non-Amap base map after GCJ-02 → WGS-84
  conversion. Check the current Amap service agreement for any restriction on
  displaying its data over third-party maps or storing it; Waybi caches search
  results for at most five minutes and city lookups for a day.
- Calls come from Cloudflare outside mainland China. Amap tracks overseas
  callers separately (infocode 10045, `USER_ABROAD_DAILY_QUERY_OVER_LIMIT`);
  watch for it in the logs.
- Searches and routes in mainland China send the query, nearby position,
  origin, destination and stops to AutoNavi; the privacy policy says so.

## Verification

- `apps/server/tests/china_geo.test.ts`: boundary pairs (Shenzhen/Hong Kong,
  Zhuhai/Macau, Xiamen/Kinmen, Fujian/Matsu), reference GCJ-02 values, the
  iterative inverse, and parity with the Dart polygon.
- `apps/server/tests/amap_search.test.ts`: the 盛世春天 case (local compound
  first, converted coordinates, distances), status "0" handling and back-off,
  budget exhaustion, HK/Macau/Taiwan staying on the existing stack, reverse
  geocoding.
- `apps/server/tests/amap_routing.test.ts`: driving normalisation (maneuvers,
  steps, waypoints, traffic intervals, alternatives, restrictions, tolls),
  walking/cycling, fallbacks and the app contract fixture.
- `apps/mobile/test/china_amap_test.dart`: no Photon/OSRM calls in China,
  route parsing, far-match warnings and attribution.
