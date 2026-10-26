# Private Cloud Run routing

Deployed and probed from the owner's Windows machine and Ubuntu WSL on
2026-10-26 (Pacific/Auckland). The user explicitly authorized production and
its dedicated invoker credential. Main CI does not recreate the GCP origin.
Orion is unchanged.

## Production

The production origin is `waybi-nz-routing` in the same project/region, revision
`waybi-nz-routing-00001-5zt`, at
`https://waybi-nz-routing-ynu5h6oina-ts.a.run.app`. It uses the exact image digest
tested in staging and the same min-zero/max-one resource configuration.
Worker `waybi` version `5e93fe6d-5742-4385-af93-fb2054d596e6` serves 100% of
production traffic after successful origin, canary, and public API checks.
The previous Worker version is `d0f55f4a-3d17-4203-8a09-3699f2c72cba`.

The Flutter shipping entry point constructs
`IndependentRoutingProvider(useWaybiProxy: true)`. Initial routes and reroutes
call `https://waybi.co/api/route-options` with `provider=independent`; heading,
language, stops, and directed exclusions are forwarded. This domain is the
native app's API origin as well as the website. An already installed build
from the current `master`/`main` commit receives the new backend on its next
online route computation; this backend change does not require reinstalling.
It does not replace an in-progress or offline cached route automatically.

Every Worker-originated Valhalla attempt, including detour retries, reserves
one atomic D1 counter in the existing Cost Guard table. The deployed daily
limit is 3,000 calls, resetting at UTC midnight. Missing database access or
exhausted quota prevents an owned-engine call and retains the existing fallback
and closure validation. No database schema migration was needed.

## Staging resources

| Item | Value |
| --- | --- |
| Project | `kiwi-lens-2026-sam` |
| Region | `australia-southeast1` (Sydney) |
| Service | `waybi-nz-routing-staging` |
| Canonical audience / URL | `https://waybi-nz-routing-staging-ynu5h6oina-ts.a.run.app` |
| Revision | `waybi-nz-routing-staging-00001-7t6` |
| Runtime identity | `waybi-routing-runtime@kiwi-lens-2026-sam.iam.gserviceaccount.com` |
| Repository | `australia-southeast1-docker.pkg.dev/kiwi-lens-2026-sam/waybi-routing-staging` |
| Image digest | `sha256:17823626ab2a4db0a0b786ac5e861224d761678c2b2814889884f816cb1cb8b1` |
| Build | `6b556345-d1b1-45cb-9460-8a70bd9d4e42` |
| Stored image bytes | 383,257,090 (about 0.357 GiB) |
| Graph | Valhalla 3.9.1; immutable NZ artifact generated 2026-10-08 |

IAM authentication is required. The service policy has no anonymous invoker
binding. Anonymous probes returned HTTP 403. The runtime service account was
not granted project roles.

Serving configuration: one vCPU, 1 GiB, concurrency one, service and revision
maximum instances both one, minimum zero, request-based billing, CPU throttling
enabled, startup CPU boost disabled, port 8002. The HTTP startup probe checks
`/status`. Deployment health checking is disabled so the first authorized
request can measure startup from zero.

## Reproduce

Recover the ignored `artifact/` from an owned build using the parent README.
The graph is not checked into Git. Verify it on the Windows host:

```powershell
node infra/nz-routing/verify-artifact.mjs
```

In WSL, with `gcloud` authenticated:

```sh
export WAYBI_GCLOUD_BIN=/home/samyao/google-cloud-sdk/bin/gcloud
bash infra/nz-routing/gcp/deploy.sh             # print only
bash infra/nz-routing/gcp/deploy.sh --apply     # build and deploy private staging
```

Cloud Build uses its default machine. The build context contains only the
pinned Dockerfile, graph and build configuration. A local Docker daemon is not
required. Graph hashes are checked before upload. Deployment pins the resulting
digest. To reuse an existing build, set `WAYBI_ROUTING_IMAGE` to the full
immutable image URL in this staging repository before `deploy.sh --apply`.

On the host, use a short-lived token from the existing local login:

```powershell
$identity = wsl -d Ubuntu -- /home/samyao/google-cloud-sdk/bin/gcloud auth print-identity-token
$identity | node --experimental-strip-types infra/nz-routing/gcp/smoke.mjs `
  https://waybi-nz-routing-staging-ynu5h6oina-ts.a.run.app report.json
Remove-Variable identity
```

Tokens enter on stdin and are omitted from reports. The probe rejects public
fallback hosts. It covers twelve driving requests, walking, cycling, and a
synthetic closure checked through the existing application's detour pipeline.

## Measurements

The first authorized `/status` took 1,274 ms. Cloud Run logs confirm that the
instance started on that request and passed its startup probe after two
attempts. This is one cold start, not a cold-start percentile.

The first GeoJSON driving sample had p50 444 ms and p95 4,604 ms across twelve
requests. Logged server-side request latencies were about 71–1,041 ms; client
wall time also includes network transfer and jitter.

After selecting polyline6 for native `.run.app` requests, a second twelve
driving requests had p50 144 ms and p95 237 ms. The synthetic detour took 270 ms.
These sequential small samples do not establish peak capacity, or prove that
encoding alone explains the latency difference.

| Route | Original JSON bytes | Compact JSON bytes | Reduction |
| --- | ---: | ---: | ---: |
| Auckland–airport | 89,205 | 59,028 | 33.8% |
| Auckland–Hamilton | 202,678 | 124,905 | 38.4% |
| Christchurch–Queenstown | 647,330 | 333,078 | 48.5% |
| Hamilton–Wellington | 807,622 | 434,818 | 46.2% |

JSON sizes exclude HTTP overhead. The Worker decodes route polyline6 to its
existing longitude-first GeoJSON contract. Coordinate precision, lanes,
heading, language, stops, departure-time restrictions and closure exclusions
are retained. The separate Cloudflare gateway continues to receive GeoJSON.

All tested departure-time driving requests returned one route. Valhalla's
time-dependent routing does not promise multiple alternatives. Do not remove
time restrictions just to display three choices. Traffic feeds and ETA
accuracy remain separate from owning the road graph.

## Worker integration status

The adapter supports an IAM-private Cloud Run origin through the optional
`WAYBI_NZ_ROUTING_GCP_SERVICE_ACCOUNT` Worker secret. Web Crypto signs an
audience-bound assertion, exchanged only at Google's fixed HTTPS endpoint.
The ID token is cached until shortly before expiry; redirects are refused.
Exchange and routing share the existing four/five second fallback deadline.

The dedicated identity is
`waybi-routing-worker@kiwi-lens-2026-sam.iam.gserviceaccount.com`, with only
`roles/run.invoker` on the production service. Its credential is an encrypted
Cloudflare Worker Secret. Local temporary credential files were deleted after
successful production verification. Keys never enter the Flutter app, source,
URLs or reports. Real Google token exchange and Cloud Run invocation passed.
Workers uses `redirect: 'manual'` and rejects every non-success response,
including redirects, without forwarding credentials to another host.

Run the shipping Dart adapter against the live backend explicitly:

```sh
cd apps/mobile
flutter test tool/valhalla_backend_smoke_test.dart
```

The tool checks live geometry parsing, lane data, driving/walking/cycling,
and a synthetic closure reroute. It stays outside `test/` so routine CI does
not call production. Physical iPhone driving, GPS and audio remain separate
device validation; a passing backend probe does not establish those results.
Engine outages must retain closure blocks. Roll back with `wrangler versions
deploy d0f55f4a-3d17-4203-8a09-3699f2c72cba@100% --yes`, then remove the configured
origin from source before any subsequent main deployment if it is being retired.

## Cost and capacity

Cloud Run request-based allowances are shared by billing account: two million
requests, 180,000 vCPU-seconds and 360,000 GiB-seconds monthly, valued at Tier 1
pricing. Sydney uses Tier 2 pricing. Orion/Bananaboom and other projects share
the allowance. This work did not establish an unused monthly balance or an
exact current bill.

Plan initially for 500–1,000 daily navigation users. At three actual engine
calls per user per day, thirty days means 45,000–90,000 calls. At a planning
average of 0.3–0.6 billed seconds and one vCPU, that needs 13,500–54,000
vCPU-seconds before startup/shutdown and retries. This is a planning envelope,
not a measured user-capacity guarantee. One trip can trigger multiple calls.

At 90,000 calls, a 60–120 KB mean JSON payload is about 5–10 GiB outbound;
300 KB means about 25 GiB. Sydney outbound is not covered by Cloud Run's
North America-only free egress allowance. A small bill is possible even when
compute fits the free discount. Registry storage shares its 0.5 GiB account
allowance: this image alone fits, but other projects may have consumed it.
Cloud Build and temporary upload storage are separate.

Min zero and max one reduce idle cost and expansion; they do not impose a
zero-dollar ceiling. Ordinary alert-only budgets also do not stop billing.
The daily application cap is active. A separate billing alert is not configured
by this deployment. Do not reuse cached routes across
different closures, heading, modes or departure-time validity.

References checked 2026-10-26:
[Cloud Run pricing](https://cloud.google.com/run/pricing),
[network pricing](https://cloud.google.com/vpc/network-pricing),
[Artifact Registry pricing](https://cloud.google.com/artifact-registry/pricing),
[free features](https://docs.cloud.google.com/free/docs/free-cloud-features),
[private authentication](https://docs.cloud.google.com/run/docs/authenticating/service-to-service),
[Valhalla route API](https://valhalla.github.io/valhalla/api/route/api-reference/).
