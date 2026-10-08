# NZ routing prototype and Cloudflare deployment

This directory prepares an optional NZ-only Valhalla service behind the existing
TypeScript Worker. No container is deployed by the main CI pipeline. Without
`WAYBI_NZ_ROUTING_URL`, the current worldwide routing path stays available.
Paid hosting was deferred on 2026-10-08 at the user's request. This remains a
local prototype and deployment preparation; do not activate it as part of a
normal main deployment.

## Local graph

```sh
docker compose -p waybi-nz-routing -f infra/nz-routing/compose.yaml up -d
docker compose -p waybi-nz-routing -f infra/nz-routing/compose.yaml logs -f
node infra/nz-routing/prepare-artifact.mjs
docker build -t waybi-nz-routing:local infra/nz-routing
docker run --rm --memory 1g --cpus .25 -p 127.0.0.1:8003:8002 waybi-nz-routing:local
```

The builder uses the official Valhalla 3.9.1 image pinned by digest, Geofabrik's
NZ OSM extract, an administrative database and timezone-boundary-builder data.
Building needs more resources than serving the finished graph. Check build
logs: the upstream timezone script can leave a zero-byte database after a
failed download. `prepare-artifact.mjs` refuses missing/invalid SQLite databases.
After correcting a failed timezone download, rebuild the graph and extract;
copying a timezone database into an already built graph is insufficient.

`artifact/` is ignored by Git and includes only the serving extract, databases,
configuration and a SHA-256 manifest. Source PBF files and build intermediates
are excluded. Keep the manifest with each image. Check `/status`, driving,
walking/cycling, languages, ramps/lanes and time-dependent restrictions before
promoting a new graph. Publish a new immutable image; retain a known-good image
for rollback. See OSM ODbL and timezone-boundary-builder attribution obligations
when distributing graph artifacts. The app's existing attribution remains.

## Cloudflare preparation

```sh
pnpm install
pnpm typecheck:nz-routing
pnpm --filter @waybi/nz-routing check
```

The dry run builds the container locally but does not deploy it. The prepared
configuration uses one `basic` instance (0.25 vCPU, 1 GiB memory, 4 GB disk), one
Valhalla serving thread, a stable instance name, an Oceania placement hint and
two-minute idle sleep. Placement is not a guarantee of an NZ/AU city.
The baked graph needs no startup download or runtime network access.

After deployment/cost approval, deploy this Worker separately. Set a randomly
generated secret as `ROUTING_TOKEN` on it and the same value as
`WAYBI_NZ_ROUTING_TOKEN` on the main Worker. Do not put it in source, build logs,
URLs or the app. Set the main Worker's `WAYBI_NZ_ROUTING_URL` only after the
authenticated `/status` and routing probes pass. The gateway refuses access
before starting a container when the key is absent/invalid. Only NZ `/route`
and `/status` are allowed; streamed route requests are limited to 64 KB and ten
locations. Existing Worker usage controls remain the client-facing gate.

Rollback: remove `WAYBI_NZ_ROUTING_URL` from the main Worker and redeploy it.
Worldwide fallback remains. Known official closures remain visibly blocked
unless an alternative is verified; an engine outage never discards exclusions
and silently treats a blocked route as a successful detour.

## Measurements and limits

Local Windows Docker sample, 2026-10-08, completed immutable NZ graph, 1 GiB /
0.25 vCPU / one thread: twelve requests across CBD–airport, CBD–Hamilton,
Christchurch–Queenstown and Hamilton–Wellington; p50 229 ms, p95 473 ms.
Three concurrent requests completed in 182–509 ms. Memory peak for this sample
was approximately 98 MiB. This is a small local sample, not Cloudflare end-to-end
latency, a load-capacity promise or phone-driving validation.

A synthetic on-ramp closure on a real NZ route produced a verified detour in
the preceding real-engine probe. This does not claim NZTA currently reports
that closure. Match the actual published geometry/direction and check every
returned candidate against both the excluded directed road and the snapshot.
Point-only reports near parallel roads remain ambiguous. Current closures are
conservatively avoided; future windows are checked at estimated arrival.

Departure-time routing is enabled to respect time-dependent access. This
Valhalla build returns one route for the tested time-dependent requests even
when alternatives are requested. Validate route-choice requirements before
making it the default. Congestion data and ETA calibration are separate work;
an owned graph does not create live traffic information.

Cloudflare pricing checked 2026-10-08: memory $0.0000025/GiB-second, active CPU
$0.000020/vCPU-second, allocated disk $0.00000007/GB-second. A basic instance
running continuously for 30 days has a gross memory+disk cost of approximately
US$7.21, before included usage, CPU, network, Worker/DO requests and taxes.
Containers require Workers Paid ($5/month; do not count it again if already
paid). Idle sleep reduces active hours; it is not a spending cap. Cloudflare
startup/placement latency still needs staging measurement before enabling NZ.

References: [Containers pricing](https://developers.cloudflare.com/containers/platform/pricing/),
[instance types](https://developers.cloudflare.com/containers/platform/limits/),
[Valhalla route API](https://github.com/valhalla/valhalla/blob/master/docs/docs/api/route/api-reference.md),
[Geofabrik NZ](https://download.geofabrik.de/australia-oceania/new-zealand.html),
[timezone boundaries](https://github.com/evansiroky/timezone-boundary-builder).
