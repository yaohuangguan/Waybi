# TestFlight uploads from GitHub Actions

`.github/workflows/ios-testflight.yml` builds Waybi for iOS on a GitHub-hosted Mac
and uploads it to App Store Connect, so no local Mac is needed. Signing uses an
App Store Connect API key and Xcode's automatic, cloud-managed signing for team
`U94L2UMT25`. No certificates or provisioning profiles are stored in the repo or
in secrets.

| Trigger | What it does |
| --- | --- |
| **Actions → iOS TestFlight → Run workflow** | Signed archive, then upload to TestFlight (or untick *upload* to only keep a signed IPA artifact for 7 days) |
| Pull request that edits the workflow | Unsigned archive only, as a dry run. No secrets are used |

## One-time setup

1. **Create an API key.** In App Store Connect, open *Users and Access →
   Integrations → App Store Connect API → Team Keys* and generate a key with the
   **Admin** role. Admin is required because xcodebuild has to create
   cloud-managed certificates and register App IDs. Download `AuthKey_<KEYID>.p8`.
   Apple lets you download it only once. Note the **Key ID** and the
   **Issuer ID** shown above the key list.
2. **Add the repository secrets** (PowerShell, from the folder that holds the `.p8`):

   ```powershell
   gh secret set ASC_KEY_ID -R yaohuangguan/Waybi --body "<KEYID>"
   gh secret set ASC_ISSUER_ID -R yaohuangguan/Waybi --body "<ISSUER-UUID>"
   Get-Content .\AuthKey_<KEYID>.p8 -Raw | gh secret set ASC_KEY_P8_BASE64 -R yaohuangguan/Waybi
   ```

   `ASC_KEY_P8_BASE64` accepts either the raw `.p8` text, as above, or its base64.
   Keep the `.p8` file out of the repo, and delete or vault it once it is uploaded.
3. **Register the identifiers.** Run the workflow once with *upload* unticked.
   That signed build registers `co.waybi.ios`, with Sign in with Apple, and
   `co.waybi.ios.navigation` in the developer portal if they do not exist yet.
4. **Create the app record.** In App Store Connect, go to *Apps → + → New App*:
   iOS, bundle ID `co.waybi.ios`, SKU of your choice. An upload fails until this
   record exists.

## Each TestFlight build

```powershell
gh workflow run ios-testflight.yml -R yaohuangguan/Waybi -f build_number=50
```

You can also start it from the Actions tab. If `build_number` is empty, the
workflow uses the `+N` from `apps/mobile/pubspec.yaml` (`1.0.0+49` → version
`1.0.0`, build `49`). Every upload of the same version needs a higher build
number than the last one, so bump pubspec or pass a number. Processing usually
takes 5–30 minutes before the build appears in TestFlight. Internal testers can
use it right away. External groups need Beta App Review: see
[testflight-review-notes.md](testflight-review-notes.md).

## Public testing (Beta App Review)

```powershell
gh workflow run testflight-beta-review.yml -R yaohuangguan/Waybi -f build_number=50
```

`.github/workflows/testflight-beta-review.yml` runs `scripts/asc-beta-review.mjs`
with the same API key. It waits until the build has processed, then:

- answers export compliance as exempt (standard HTTPS and OS-provided encryption only);
- fills TestFlight Test Information (beta description, `support@waybi.co`
  feedback, privacy policy) and the Beta App Review notes (no demo account needed);
- sets bilingual What to Test for the build;
- creates or reuses the external group **Public testers** with a public link and adds the build;
- submits the build to Beta App Review and prints the public link in the run summary.

Every step is idempotent, so re-running for the same build is safe. Tick
*dry_run* to only read App Store Connect. Beta App Review needs a contact
name, phone and email. The script keeps whatever App Store Connect already has
(TestFlight → Test Information → Beta App Review Information). If those are
empty, fill them there once or add the optional secrets
`ASC_REVIEW_CONTACT_FIRST_NAME`, `ASC_REVIEW_CONTACT_LAST_NAME`,
`ASC_REVIEW_CONTACT_PHONE` and `ASC_REVIEW_CONTACT_EMAIL`. Contact details never
go in the repo. Apple usually reviews within 24–48 hours. The public link
works for testers once the build is approved, and later builds of the same
version usually skip full review.

## Optional secret

`WAYBI_DART_DEFINES_JSON` is a JSON object passed as `--dart-define-from-file`
(for example `{"KIWI_PHOTON_URL":"https://…"}`). Without it the app uses its
built-in defaults, which is what local `pnpm mobile:ios:ipa` builds do when no
`.dart-defines.local.json` exists.

## Notes and troubleshooting

- **Export compliance.** `Info.plist` has no `ITSAppUsesNonExemptEncryption`
  key, so App Store Connect asks the encryption question for every build. If the
  answer is "standard HTTPS only / exempt", the owner can add
  `<key>ITSAppUsesNonExemptEncryption</key><false/>` to skip the prompt.
- **"No Accounts" / "No profiles for 'co.waybi.ios'".** The key is not Admin,
  or the Apple Developer Program agreements in App Store Connect still need
  accepting.
- **"The bundle version must be higher".** Pass a larger `build_number`.
- **Failed runs.** They upload `xcodebuild-logs`. The repo is public, so
  workflow artifacts, including the optional IPA, can be downloaded by any
  signed-in GitHub user while they are retained (7 days). They contain no keys.
- Pin `runs-on` to a specific `macos-NN` image if a new Xcode on `macos-latest`
  ever breaks the build.
