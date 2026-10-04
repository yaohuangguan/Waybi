# Waybi Plus billing

Flutter is the primary product. The iOS subscription flow uses Apple's StoreKit 2 through `in_app_purchase`. Stripe backend APIs are retained for a future website channel; the iOS app does not open Stripe Checkout or link to website purchases. This change adds no website purchase UI, keeping the website's App Store acquisition direction.

The code is ready for configuration. App Store Connect products and merchant credentials have not been provisioned. Both providers report `ready: false` until their required server configuration exists; the UI shows planned prices and disables payment.

## Apple setup

Create the Waybi application with bundle ID `co.waybi.ios`. Create one auto-renewable subscription group containing two products at the same service level:

| Product ID | Duration | Planned New Zealand price |
| --- | --- | --- |
| `co.waybi.ios.plus.monthly` | 1 month | NZ$4.99 |
| `co.waybi.ios.plus.annual` | 1 year | NZ$39.99 |

Set each product's localization, availability, price and review information in App Store Connect. Complete the applicable paid-app agreements and merchant details there. Live native prices come from StoreKit, including the current storefront currency; the application does not charge its fallback display prices.

Generate an **In-App Purchase** key in App Store Connect → Users and Access → Integrations → In-App Purchase. Configure these as Cloudflare Worker secrets; do not commit keys, put them in Flutter dart-defines, or send them in chat:

| Secret | Value |
| --- | --- |
| `APPLE_IAP_ISSUER_ID` | Key issuer ID |
| `APPLE_IAP_KEY_ID` | Key ID |
| `APPLE_IAP_PRIVATE_KEY` | Entire downloaded `.p8` PEM, preserving newlines |

Optional Worker variables `APPLE_IAP_PRODUCT_MONTHLY` and `APPLE_IAP_PRODUCT_ANNUAL` override product IDs. `APPLE_IAP_ENVIRONMENT=Sandbox` pins a test deployment to Apple's sandbox. The default uses production first and retries sandbox only for Apple's `4040010` transaction-not-found response, supporting TestFlight and App Review. Authentication, network and server failures do not trigger fallback.

The app signs in to a Waybi account before purchasing and supplies its UUID as StoreKit's `appAccountToken`. The server accepts only a transaction ID, queries authenticated Apple API endpoints and validates the app, product, environment and matching account. It obtains the latest subscription status before storing access. Client receipts, client expiration dates and a successful payment-sheet dismissal never grant Plus. An original subscription cannot be moved to another Waybi account. Restore requires the original Waybi account and Apple account.

Only server-verified transactions are finished in StoreKit. Failed verification leaves transactions retryable. The listener is owned by the app root so leaving the Plus page does not drop pending purchases; account restoration retries queued transactions. Restore waits for verification before reporting completion. Valid expired history can be finished without enabling Plus.

Known subscriptions are refreshed on account fetch and by the existing 15-minute scheduled Worker. Cancellation retains access until expiration; expiry and revocation remove Apple access while preserving another active Stripe subscription or manual entitlement. There is currently no Apple Server Notifications receiver; do not configure an unsigned notification endpoint. Refresh requests use fixed Apple HTTPS hosts and authenticated responses, rather than decoding untrusted client JWS payloads.

## Stripe setup (website channel)

Create a Waybi Plus product with recurring NZD prices of 499 cents/month and 3999 cents/year. Configure Worker secrets:

| Secret | Value |
| --- | --- |
| `STRIPE_SECRET_KEY` | Server secret for the chosen test/live mode |
| `STRIPE_PRICE_MONTHLY` | Monthly recurring price ID |
| `STRIPE_PRICE_ANNUAL` | Annual recurring price ID |
| `STRIPE_WEBHOOK_SECRET` | Endpoint signing secret |

Enable the Customer Portal for payment method updates and cancellation. Optionally set `STRIPE_PORTAL_CONFIGURATION` to its configuration ID. Register `/api/billing/webhook` on the public Worker origin for:

- `checkout.session.completed`
- `checkout.session.async_payment_succeeded`
- `customer.subscription.created`, `customer.subscription.updated`, `customer.subscription.deleted`
- `invoice.paid`, `invoice.payment_failed`

Match the webhook endpoint's API version to the pinned Stripe SDK's default API version. Use consistent test/live keys, prices and webhook secrets. Hosted Checkout and Portal sessions are tied to the authenticated Waybi user. The server chooses prices, validates webhook signatures against the raw body, deduplicates fulfilled events and fetches current subscription state to handle delayed events. A success URL alone does not grant access. Existing manual or paid Plus accounts cannot start a second checkout.

The authenticated backend exposes `GET /api/billing/status`, `POST /api/billing/checkout` (`plan`, `language`), `POST /api/billing/confirm` (`sessionId`) and `POST /api/billing/portal`. Public prices are at `GET /api/billing/plans`. Browser mutations require the same origin and `x-waybi-client: web`. Checkout/Portal return URLs currently target `/subscribe`; build that separate website flow before enabling public Stripe purchases. These APIs are deliberately not exposed as a purchasing option inside the iOS app.

## Deploy and validate

Run `pnpm db:migrate:remote` before `pnpm deploy`. Migrations `0009_stripe_billing.sql` and `0010_apple_billing.sql` add provider records without replacing existing user accounts or manual Plus entitlements.

Automated validation:

```sh
pnpm test
pnpm build:web
pnpm check:worker
cd apps/mobile
flutter analyze
flutter test
```

`flutter run -d web-server --target tool/plus_preview.dart` renders the actual Flutter Plus and Trips widgets with clearly labeled sample data for visual checks. It cannot process purchases. Test doubles exercise delayed/rejected server verification, canceled purchases, expired restores, ownership checks, renewal/refund state and preservation of other entitlements; these checks are not a real Apple or Stripe payment test.

After products and secrets are configured, validate on a signed iPhone/TestFlight build with Apple's sandbox: localized products, a new monthly/yearly purchase, cancellation, restoration after app restart, a different Waybi account's rejection, expiration/refund, subscription management and account synchronization. Test Stripe separately with test Checkout and signed webhook retries before enabling live mode.

Before App Store submission, set the application's privacy-policy URL and subscription metadata in App Store Connect. The current native page links Apple's standard EULA and the repository's published privacy/data description; update the latter to the final public privacy-policy URL when available. This change does not submit the application or configure merchant accounts.

References: [Flutter in_app_purchase](https://pub.dev/packages/in_app_purchase), [Apple App Store Server API](https://developer.apple.com/documentation/appstoreserverapi), [Apple In-App Purchase key setup](https://github.com/apple/app-store-server-library-node#obtaining-an-in-app-purchase-key-from-app-store-connect), [Stripe webhooks](https://docs.stripe.com/webhooks).
