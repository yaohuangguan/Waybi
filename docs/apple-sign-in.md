# Sign in with Apple for Waybi iOS

Google and email/password sign-in remain. The native iOS profile adds an Apple button and an explicit **Link Apple account** action for an already signed-in Waybi account. Apple authorization codes and nonce-bound identity tokens go to the Worker; a local Apple credential alone never establishes a Waybi session.

## Implementation

- Native SDK obtains Apple credentials with a cryptographically random nonce and state. The Worker verifies Apple's RS256 signature against the fixed Apple JWKS endpoint, issuer, configured bundle audience, expiry, issue time and SHA-256 nonce. It exchanges the single-use authorization code using a short-lived ES256 client secret, then verifies that the exchanged ID token represents the same identity/nonce.
- D1 migration 0017 stores Apple's stable subject and an AES-GCM encrypted refresh credential. The encryption key and Apple private key are Worker-only secrets. No refresh credential is returned in profile responses.
- Existing subjects sign in to their linked account, including private-relay users. An email match never silently merges accounts. An existing Waybi session can explicitly link Apple even when Hide My Email differs from the account email. Unique subject/user constraints and transactional creation protect concurrent links.
- Confirmed account deletion revokes Apple's refresh authorization before deleting the account and its cascading identity record. An Apple outage keeps the account and returns a retryable failure instead of claiming deletion succeeded.
- The existing 15-minute cron checks up to five oldest identities per run, each no more frequently than daily. An explicit Apple `invalid_grant` revokes Waybi sessions and marks the identity withdrawn; transient outages do not log users out. This bounded queue needs capacity monitoring as accounts grow.
- Apple login is iOS-only in this release. No new Android/web Apple OAuth service or redirect is enabled.
- Missing configuration returns `ready:false` / HTTP 503. The app checks it before opening Apple's consent sheet and offers the existing sign-in methods. This is a configuration gate, not a validated App Store-ready Apple login.

## Verified development checks

Server typecheck and 212 server tests passed. Flutter analysis and 313 full mobile tests passed; three additional profile UI checks passed for iOS/Android provider visibility and explicit linking. Candidate build 39 compiled for iOS without signing. Neither Apple portal setup nor real Apple authentication is verified.

## Apple Developer configuration (pending)

The user asked the agent to configure this, but currently cannot complete Apple login/2FA or share the portal. No portal changes, private key creation or Worker secret writes have been performed.

1. Log in to [Apple Developer identifiers](https://developer.apple.com/account/resources/identifiers/list), choose the correct paid team, and enable **Sign in with Apple** for `co.waybi.ios` as the primary App ID. A Service ID is unnecessary for this native-only flow.
2. Under [Keys](https://developer.apple.com/account/resources/authkeys/list), register a key specifically enabled for Sign in with Apple and associate that primary App ID. Download its .p8 once and save it in a secure Mac location outside the repository. This is separate from the In-App Purchase key.
3. Configure the Worker-only values below. Public client ID defaults to `co.waybi.ios`; do not include the Team ID in it.

| Value | Purpose |
| --- | --- |
| APPLE_AUTH_CLIENT_ID | Native bundle audience, co.waybi.ios |
| APPLE_AUTH_TEAM_ID | Apple Developer Team ID |
| APPLE_AUTH_KEY_ID | Sign in with Apple key identifier |
| APPLE_AUTH_PRIVATE_KEY | Contents of the Sign in with Apple .p8 private key |
| APPLE_AUTH_TOKEN_KEY | Independent cryptographically random 32-byte AES key, encoded as 64 hex characters |

Use Wrangler secret input or a secure bulk secrets file; never paste secrets in chat, logs, commits or mobile dart-defines. Generate the token key locally with a cryptographically secure RNG and back it up securely. Replacing it requires re-encrypting existing refresh credentials before removing the old key, otherwise login/revocation can fail.

4. Apply migration 0017 to the intended D1 database before deploying the Worker. The main CI migration gate handles this for the production merge when configured.
5. Refresh Xcode provisioning profiles after enabling Apple sign-in. Runner.entitlements and the optional Navigation.entitlements both declare `com.apple.developer.applesignin = [Default]`; the navigation widget does not need this entitlement. The currently installed development profile was inspected and lacks this capability.
6. Build a new signed device artifact after the capability/profile update. Build 38 contains the lane fix and predates Apple login. Build 39 identifies the Apple-login candidate; an unsigned compilation is not an installable/TestFlight artifact.
7. Confirm `GET /api/auth/apple/config` is ready, then test on a signed iPhone using the checklist below. Separately configure Apple Distribution profiles for Runner and WaybiNavigation, export and upload TestFlight.

The coding agent can complete the portal/secret steps when a logged-in, writable portal is available and the keys are supplied through secure local storage. Apple passwords, verification codes and keys should not be sent in chat.

## Acceptance checks before submission

- New Apple user, Share My Email and Hide My Email; a second login with the same subject; cancellation without losing an existing session.
- Existing Google/email account explicitly links Apple, then signs in with either method. Verified email collision requires explicit linking; another user's linked Apple identity is rejected.
- Client/backend errors never save an unverified session, and Google/email still work.
- Wrong issuer/audience/nonce/signature, expired identity and reused authorization code are rejected.
- Delete a disposable Apple account: Apple authorization revoked, D1 identity/account/sessions erased, account-scoped local data removed, second user's data preserved. Check retry behavior during an Apple outage.
- Withdraw authorization in Apple settings; verify scheduled session invalidation and fresh authorization recovery.
- TestFlight login after Distribution signing/profile changes. These real Apple/device checks remain pending until configuration is completed.

## References

- [Apple authentication overview](https://developer.apple.com/documentation/signinwithapple/authenticating-users-with-sign-in-with-apple)
- [Apple token validation](https://developer.apple.com/documentation/signinwithapplerestapi/generate-and-validate-tokens)
- [Apple revocation and account deletion](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple)
- [Flutter plugin setup](https://pub.dev/packages/sign_in_with_apple)
