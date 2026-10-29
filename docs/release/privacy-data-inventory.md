# App Privacy preparation — not submitted answers

The public policy lives at `/privacy/` and `/zh/privacy/`; public contact is
`support@waybi.co`. The private forwarding destination is operational configuration
and is not embedded in the published pages. Confirm the legal operator/copyright
name with the owner before the final App Store record.

This inventory is a worksheet for the final build. It is not a declaration of
“no data collected” and does not decide SDK behaviour from the app manifest alone.

| Data flow | Actual use and storage | Disclosure work |
| --- | --- | --- |
| Email, account ID and optional display name | D1 accounts, authentication and sync | Contact info / identifiers; linked to account; app functionality |
| Google/Apple identity | Provider ID and verified identity; configured Apple refresh credentials are encrypted server-side | Verify provider disclosures and final Apple capability/configuration |
| Precise location | On-device position/guidance; search/route origins/destinations/nearby requests leave the device | Separate transient request processing from retained data under Apple's collection definition; review upstream SDK/provider behaviour |
| Saved Home/Work, destinations and routes | Account-linked saved coordinates, recent locations and completed-route history | Location and user content linked to the account; app functionality |
| Friends journal / travel totals | Local journal with supported cloud account backup/sync | User content / identifiers as applicable; map actual final backup fields |
| Notes and place reviews | Saved in the account profile | User content linked to the account; do not describe these as anonymous |
| Community road reports / navigation feedback | Event coordinates, type/time and submitted feedback | Review report visibility, retention and diagnostics; avoid private details |
| API quota/usage counters and errors | Usage accounting, reliability and provider/hosting logs | Review applicable usage/diagnostic categories and account linkage; not an advertising consent claim |
| Purchases if enabled | Apple transaction/product IDs and server-verified entitlement; Stripe backend remains separately configured | Purchase history if used; Waybi does not receive full Apple card details |
| Support messages | User email and volunteered attachments; planned Cloudflare forwarding to a Google-hosted support inbox | Customer support / user content; real support operation must be verified |

Cloudflare hosts the API/data/caches; Google Cloud hosts the NZ route engine.
Google Places UI Kit and independently sourced map/search/route providers process
the requests needed by their selected features. The final SDK inventory includes
Google Maps/Navigation and sign-in components even when the default map is Waybi
Map. Review actual initialization/telemetry and final bundled privacy manifests.

Runner currently declares UserDefaults reason `CA92.1`. This does not replace
App Privacy labels, an accessible privacy policy, or third-party SDK declarations.
No new tracking-consent promise or zero-collection claim is made by this work.

The active-account deletion API has been tested with a temporary production
account and revoked both sessions. Physical signed-build deletion, Apple
revocation, backups/provider logs and support records need their own checks;
do not claim every recovery copy disappears immediately.

Owner decisions still needed: legal operator name; initial regions; monetization;
actual final SDK data practices; exact retention of support/hosting backups.

Official guidance: [App Privacy details](https://developer.apple.com/app-store/app-privacy-details/),
[Apple privacy review rules](https://developer.apple.com/app-store/review/guidelines/#privacy),
[NZ collection transparency](https://www.privacy.org.nz/responsibilities/collecting/).
