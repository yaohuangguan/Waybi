# Unified account sign-in

My Waybi, the legacy profile sheet and Plus checkout now share `AccountSignIn` on Flutter. The default email flow sends a six-digit code; a successful verification signs into an existing account or creates one. Existing passwords remain usable through “Sign in with a password.” Google remains available; Apple is offered on native iOS using the existing verified Apple flow and explicit account linking. The PWA uses the same email OTP API and retains password login. Phone/SMS registration is intentionally deferred. This change does not migrate Remote Arc.

## Configure email delivery

1. Create a SendPulse account and activate its **transactional SMTP** service. This is separate from marketing campaigns. Authenticate the Waybi sending domain and wait for account approval. Create a static API key under Settings → API → API keys. See [SendPulse authentication](https://sendpulse.com/integrations/api) and [transactional API](https://sendpulse.com/integrations/api/smtp).
2. Authenticate the same sending domain in Resend if it is also used. Keep the existing `WAYBI_RESEND_API_KEY`; SendPulse is first choice and Resend is the fallback.
3. Configure these **server-side** Worker variables/secrets. Never put them in Flutter defines, Vite variables, source code or chat:

   | Name | Value |
   | --- | --- |
   | `AUTH_EMAIL_FROM` | Verified sending address, e.g. `accounts@your-domain.example`, without a display name |
   | `SENDPULSE_API_KEY` | SendPulse static Bearer API key |
   | `WAYBI_RESEND_API_KEY` | Existing Resend API key |
   | `EMAIL_OTP_SECRET` | Independent random secret, at least 32 characters; generate 32 random bytes as hex |

   Either mail provider is sufficient to enable email codes. Both credentials enable both providers. Configure through Cloudflare Worker settings or `pnpm exec wrangler secret put NAME --config wrangler.jsonc`. The latter prompts for the value without placing it in a shell command. For local development copy `.dev.vars.example` to the ignored `.dev.vars` file. `/api/auth/config` exposes readiness booleans, never provider secrets.
4. Apply the additive migration `0019_email_otp.sql` to a local database and test first: `pnpm db:migrate:local`. Production migration and deployment remain separate release actions; **this implementation has not run a production migration or sent a real email**. Confirm a database backup and follow the normal release process before deploying the Worker and mobile app.
5. Validate delivery to an inbox you control after configuration, including spam placement, resend, expiration and the Resend fallback. Native Google and Apple still need their existing platform credentials; see [Apple setup](apple-sign-in.md).

## Sending budgets and failover

[SendPulse Free](https://sendpulse.com/knowledge-base/smtp/limits) allows 50 messages/hour, 400/day and 12,000/month, with two authenticated domains. [Resend Free](https://resend.com/pricing) allows 100/day and 3,000/month. These are **provider account** allowances shared across projects and message types, not per API key or domain. The theoretical sum of the two daily allowances is 500; it is not a guaranteed combined service allowance or a way around the SendPulse hourly cap.

Waybi reserves persistent per-provider hourly and daily counters before sending. It switches to the next configured provider when its local budget is exhausted, the first provider explicitly returns HTTP 429, or SendPulse returns its documented HTTP 422 `Sending quota or bandwidth exceeded` rejection. Other 422 validation/configuration errors fail closed. See the [official SMTP OpenAPI schema](https://api.sendpulse.com/.well-known/openapi/smtp.yaml). Monthly and account-wide limits still apply upstream. Existing search quota notifications also consume the Resend account allowance. If other projects later share these accounts, use a central account-wide budget before relying on aggregate limits.

An accepted message is never sent again through the other provider. Timeout, malformed receipt and non-429 provider errors return a retryable delivery error; the server does not assume that an ambiguous attempt was unsent. No automatic retry crosses providers after an ambiguous failure. Each network request is bounded to four seconds, fitting inside the client request timeout even when both providers are tried.

## Security and compatibility

- Codes use cryptographically secure random integers, expire after 10 minutes, allow at most five verification attempts and are consumed atomically. Concurrent valid requests produce one session. A resend replaces the old challenge.
- The server enforces a 60-second cooldown, five sends/email/hour, 20 send requests/IP/hour and 60 verification requests/IP/hour. Cloudflare supplies the trusted `CF-Connecting-IP` header. Local requests without that header share an anonymous development bucket.
- Only HMAC-SHA256 values of the mailbox, client IP and code are stored in temporary authentication tables. The independent `EMAIL_OTP_SECRET` prevents offline brute-force of the six-digit code from a database dump alone. The client stores only the existing server session in secure storage or an HttpOnly cookie; no OTP or provider key is persisted on clients.
- A new user is created only after mailbox verification. Existing IDs, passwords, profile preferences, Google/Apple links, subscription entitlements and saved content are preserved. Email OTP can also recover access to an existing password account by proving mailbox ownership.
- Old clients retain the legacy password registration endpoint for compatibility; those historical password registrations do not imply verified mailbox ownership. New clients create accounts through OTP.
- `email_identities` cascades on account deletion. Expired challenges and rate limits are pruned by later successful code requests. Changing the OTP secret invalidates pending codes without affecting established sessions.

## Migration recovery

The new migration only adds tables and an index and is safe to rerun. It does not rewrite existing account rows or change old password/session formats. To roll back, redeploy the previous application and leave the extra tables in place; the old code ignores them. Disable OTP by removing `EMAIL_OTP_SECRET` before investigating a delivery issue. Do not drop tables during a rollback. No live data has been migrated by this change.

## Automated checks

Server tests run the real account handler against all migrations in an in-memory SQLite database, with strict network stubs only at provider boundaries. They cover registration, existing account recovery, cooldown, invalid/expired codes, attempt lockout, replay, concurrent consumption, origin checks, hashed storage, budget exhaustion and provider failover. Flutter widget tests exercise the shared entry, input validation, cancellation, failure recovery, policy links and password fallback; repository tests verify HTTP payloads and server-issued secure session storage. PWA tests cover the two-step flow, resend, duplicate submits, old password login and session handling. Real provider deliverability, hardware Google/Apple login and SMS are not established by these tests.
