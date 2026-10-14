# Production D1 migration gate

Every deployment through the root deploy command must run `pnpm db:migrate:remote` successfully before `pnpm deploy`. Wrangler reconciles pending migrations. Do not decide this only from files changed in the newest push: a failed earlier migration can otherwise be skipped on a later code-only or documentation-only push.

The Apple identity release (PR124, main 52c0730) exposed this failure mode on 14 October 2026. Its migration0017 was not applied because the GitHub Actions credential could not access the configured D1 service (Cloudflare7403). The Worker deploy correctly stopped. The root deploy command reconciles pending migrations for both CLI and CI releases. The existing production release remained active; the new Apple endpoint was not live.

## Credential recovery

- The deployment credential in repository secret `CLOUDFLARE_API_TOKEN` must retain its existing Worker/KV/routes permissions and have **Account → D1 → Edit** for the actual deployment account specified in wrangler.jsonc.
- Check the account before changing permissions. An unrelated Mac OAuth login cannot administer the project's original account.
- Prefer editing the correctly identified deployment token to add the needed scoped permission. If replacing a token, update the GitHub repository secret through secure input, never chat/logs/source/mobile defines.
- Do not skip the migration gate, point production at a new empty database, or deploy code requiring an absent table.
- After authorization is fixed, rerun the failed deployment (or deploy latest main). Confirm pending migrations including0017 completed, then confirm Worker deployment and read-only health/auth config requests.
- Validate new Apple flows only after separate Sign in with Apple capability/key/profile configuration. A ready:false response is expected until that setup.

A disposable production API check on the still-active release passed registration, profile write/read, second login, deletion, both sessions invalidation and old-password rejection. The test account was deleted and its temporary credential file removed. That verifies existing backend account deletion, not the unpublished Apple integration or physical in-app deletion UI.

Reference: [Cloudflare D1 API token setup](https://developers.cloudflare.com/d1/tutorials/import-to-d1-with-rest-api/).
