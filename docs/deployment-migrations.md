# Production D1 migration gate

Every root `pnpm deploy` reconciles pending D1 migrations before building or publishing. Wrangler applies only pending migrations. Do not decide this from files changed in the newest push: a failed earlier migration could otherwise be skipped by a later code-only or documentation-only push.

## Separate credentials

GitHub Actions supplies both repository secrets to the deployment job:

- `CLOUDFLARE_API_TOKEN`: the existing Worker publishing credential, with the required Worker/KV/routes access.
- `CLOUDFLARE_D1_API_TOKEN`: D1 migration credential with **Account → D1 → Edit** for account cdc04de9bc4c6a41b5003758e505a0d1, the deployment account in wrangler.jsonc.

The migration launcher overrides `CLOUDFLARE_API_TOKEN` only inside its migration child process and removes the extra D1 variable from that child. It does not change the parent environment; subsequent Worker publishing continues using the original credential. Migration failure stops the deployment chain.

When the separate D1 token is absent, the launcher retains the existing API token or local Wrangler OAuth. This preserves single-token installations and authorized local CLI deployments. No token value belongs in source, logs, chat or mobile configuration.

## Recovery evidence

The Apple identity release (PR124, main52c0730) exposed the need for this gate on 14 October 2026. GitHub's publishing token could not access D1 (Cloudflare7403), so migration0017 and Worker publishing stopped. PR125 made the root deployment command reconcile migrations on every release.

The project's existing Windows7199 Wrangler OAuth subsequently applied0017 to the existing waybi-users database and deployed main879325a successfully. Health and Apple-config requests returned HTTP200. A disposable production account passed registration, profile read/write, login, deletion, both-session revocation and old-password rejection; the test account and temporary credential file were removed. This verifies the backend API, not physical in-app deletion or Apple authentication.

The user then added the separate D1 repository secret. This integration makes the workflow use it while retaining the Worker publishing credential. Verify the first main deployment completes both migration reconciliation and publishing; a successful PR test alone does not verify production credentials.

## Operational checks

- Check the configured account before editing permissions. An unrelated Mac OAuth cannot administer the project's original account.
- Do not skip the migration gate, point production at an empty replacement database, or publish code requiring an absent table.
- After a credential repair, deploy latest main and confirm migration reconciliation, Worker version and read-only health/auth configuration.
- Apple config remains `ready:false` until the separate Developer membership, capability/key and provisioning setup. Test real Apple flows only after that setup.

Reference: [Cloudflare D1 API token permissions](https://developers.cloudflare.com/d1/tutorials/import-to-d1-with-rest-api/).
