# TestFlight package and review notes

Draft only. Apple account-dependent setup, build upload, tester invitation and
review submission have not been performed by this work.

## Ready-to-copy What to Test

English:

Please test Waybi on familiar New Zealand journeys. Focus on accurate address
selection, available route alternatives, rerouting, Trips loading, voice and
lock-screen navigation. Check Bluetooth/music interruption and recovery, weak
network behaviour, and account sync. Follow actual road signs; have a passenger
record issues or stop safely. Send the build number, device/iOS version,
reproduction steps and a redacted screenshot to support@waybi.co or use
TestFlight feedback. Please omit private home/work locations where possible.

简体中文：

请在熟悉的新西兰路线测试 Waybi，重点看地址选择、可用备选路线、偏航重算、
行程页加载、语音和锁屏导航，以及蓝牙音乐、电话打断、弱网恢复和账号同步。
始终遵守实际道路标志，由乘客记录或安全停车后反馈。请通过 TestFlight 或
support@waybi.co 提供 build、设备/系统、复现步骤和已遮住隐私的截图。

## Review walkthrough

1. Open Waybi. Basic map/search/navigation can be explored without registration.
2. Allow location if testing current-position guidance; manual destination search
   remains relevant when location is denied.
3. Search a public Auckland place, confirm its location, select an available route
   and start navigation only for an appropriate real or controlled test.
4. Open Trips to inspect recent/saved information. Account sync requires an account.
5. Open Me → Privacy policy / Terms of use / Help & support. These links are also
   available while signed out.
6. A disposable signed-in account can be deleted from Me → Delete account using
   its email confirmation. Do not give reviewers a personal daily-use account.

Before submitting, fill the App Store Connect contact fields with the owner's
confirmed information and create a dedicated reviewer account if reviewers need
protected features. No credentials belong in this document or source control.

Apple sign-in and StoreKit products are pending owner account setup. Do not claim
they are ready in review notes. The existing backend has a production-first,
transaction-not-found-only Sandbox lookup for TestFlight; real Sandbox purchase
and restoration are still unverified until keys/products are configured.

## Screenshot plan

Capture the actual final candidate: map/search, route choices, active navigation,
Trips, and Waybi & Friends. Use public example places rather than private Home
or Work. Prepare English and Simplified Chinese views. The project currently
supports iPhone and iPad; either validate/capture iPad or make an explicit device
support decision before submission. Screenshots are pending, not fabricated.

## Deferred until the developer account is ready

- Verify paid team, identifiers and agreements; do not infer activation from payment.
- Enable Apple sign-in and store credentials securely on the server.
- Create/verify distribution signing for App and navigation extension.
- Confirm next build number, archive/export, upload and check processing.
- Run the physical-device test matrix with the distribution build.
- Set up internal and external groups and submit the first external Beta Review.

See [App Store localizations](https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations/)
for English (Australia) / Simplified Chinese, and
[external TestFlight testing](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/).
