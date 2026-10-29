# Waybi Cloudflare account move

On 30 October 2026 (Pacific/Auckland), Waybi's runtime moved from account
`cdc04de9bc4c6a41b5003758e505a0d1` (7199) to
`6b1d0dd4e6f7f30df92753cd1e2ee12d` (moviegoer24).

The target resources are recorded in `wrangler.jsonc`. USER_DB was copied with
31 application tables and 259 rows verified by per-table hashes, including
sessions and the Google search budget. Twelve KV entries were copied and
verified. Both R2 objects in `waybi-map` were verified by SHA-256; the NZ archive
is 447,323,313 bytes. All six existing Worker secrets moved directly between
Cloudflare Workers without printing their values or storing them on local disk.

The `waybi.co` zone is active in the target account. Nameservers are
`ivan.ns.cloudflare.com` and `malavika.ns.cloudflare.com`. The main and www
hosts use Worker routes. Existing DNS records from the zone import conflicted
with Worker Custom Domains; the route configuration serves the production
application without requiring their removal. `maps.waybi.co` points to the
target R2 bucket with the original CORS policy and TLS minimum 1.2.

The new Worker runs the original four cron schedules. The former Worker's
schedules are disabled and it forwards historical API URLs to `waybi.co`.
The old D1 and R2 data remain intact for recovery. Do not restore old-account
write traffic after the new database has accepted production writes without
first reconciling those writes.

The runtime move does not change the private GCP Valhalla project, Google
search's 9,990-per-month protection, or Flutter's API domain. Apple sign-in
still reports `ready:false`; Developer membership and server credentials are
separate setup work.

## Remaining account administration

Wrangler OAuth can administer Workers, D1, KV and R2. It does not grant DNS
record read/write, zone-settings or Page Rules administration. The complete
source-to-target DNS/rules comparison requires separate zone authorization;
an active imported zone alone does not prove all records and rules were copied.
Do not claim that comparison is complete until it has been verified.

GitHub's Worker and D1 deployment secrets must authorize the target account
before the next CI release. `scripts/check-cloudflare-account.mjs` checks both
destinations and stops before publishing if the credentials still belong to the
old account. Local manual deployment uses the Mac's moviegoer24 Wrangler login,
or the explicitly selected `moviegoer24` profile on Windows. Windows' default
profile remains 7199 by the owner's request.
