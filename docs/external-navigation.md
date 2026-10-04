# External navigation on iOS

Waybi accepts a destination from another app, then opens its existing place / route preview. Guidance begins only after the user taps Start. If a trip is active, Waybi asks before ending it. Name and address queries use the current map provider's search and require the user to choose a result.

## App links

```
waybi://navigate?destination=Westfield%20Newmarket%2C%20Auckland
waybi://navigate?destination=-36.8697,174.7762&name=Westfield%20Newmarket
waybi://navigate?destination=-36.8697,174.7762&mode=walk
```

Build links with `Uri` / `URLComponents` rather than string interpolation. Destination is a place name, address, or `latitude,longitude`. Optional `mode`: `drive`, `walk`, `bicycle`, `transit`. Optional `source` and repeated `waypoint` parameters preserve explicit origins and the order of intermediate stops (up to 10). `name` labels a coordinate destination. Invalid coordinates, duplicate destination parameters and unknown actions are rejected.

The existing Google sign-in scheme remains registered. Navigation URL handling claims only `waybi` and `geo-navigation` and forwards unrelated callbacks to Flutter's plugin delegates. Flutter's automatic deep-link routing remains disabled; a native inbox handles URLs received before splash, preferences or onboarding are ready, and later URLs while the app is running. Requests arriving during a new navigation transition wait until it finishes. A newer request supersedes an unresolved older one. If GPS is still becoming ready, the destination stays selected and route preview starts after the first reliable fix; selecting another destination or starting a trip cancels this pending preview.

## Shortcuts / Siri / share-sheet fallback

`Navigate with Waybi` is an iOS 16+ App Intent with a **Destination** text parameter. It accepts an address, place name or coordinate pair, brings Waybi to the foreground and sends the same destination request. iOS 26 uses `supportedModes`; earlier versions use `openAppWhenRun`.

In Apple's Shortcuts app, create a shortcut that accepts **Text** from the share sheet, add **Navigate with Waybi**, and bind its Destination to **Shortcut Input**. When an app offers a text share sheet, select that shortcut. For a Calendar event, use the event's venue address / location, not its event title; a shortcut can also obtain the Location field using Calendar actions and pass it to Waybi. Apps that expose neither their location as text nor a share action require copying the address into the shortcut. This is an Apple Shortcuts action, not a Waybi Share Extension.

Google Calendar's own **Open with** list is controlled by Google Calendar. No public third-party registration API was found for this picker. The custom scheme, Shortcuts action, and Apple's default-navigation capability do **not** promise inclusion in Google's list. No private API or scheme impersonation is used.

## Apple's system default navigation

The Runner target declares `com.apple.developer.navigation-app = true`, registers `geo-navigation`, and retains background location. Supported incoming forms:

```
geo-navigation://directions?destination=Westfield%20Newmarket
geo-navigation:///directions?source=-36.8,174.7&destination=-36.9,174.8&waypoint=Queen%20Street
geo-navigation://place?coordinate=-36.8697,174.7762
geo-navigation:///place?address=Westfield%20Newmarket
```

`place` opens a place without automatically requesting routes. System URLs do not supply Apple place IDs or transportation preferences. Explicit source/waypoint names are each resolved through user selection, rather than silently discarded.

Apple currently exposes the default-navigation setting in the **EU on iOS/iPadOS 18.4+** and **Japan on iOS/iPadOS 26.2+**, not New Zealand. On an eligible device with a correctly signed build, select Waybi in Settings → Apps → Default Apps → Navigation. Simulator compilation is not a substitute for testing eligible-region settings and distribution signing; the Apple Developer App ID / provisioning profile must include the capability when making the release. No developer-portal or distribution settings were changed in this implementation.

Official documentation:

- [Preparing your app to be the default navigation app](https://developer.apple.com/documentation/mapkit/preparing-your-app-to-be-the-default-navigation-app)
- [Default Navigation entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.navigation-app)
- [App Intent foreground modes](https://developer.apple.com/documentation/appintents/appintent/supportedmodes)

## Verification

Parser tests cover Calendar addresses, coordinates, Unicode, system place/directions forms, explicit source / ordered stops, malformed inputs, and OAuth passthrough. Inbox tests cover cold start, newer warm requests, arrival during startup handoff, and platforms without this iOS bridge. Native simulator checks use `xcrun simctl openurl` after termination and while running. Also verify on a real device: run the Shortcuts action, open an address from your chosen source app, and confirm that a current trip is kept if the switch prompt is cancelled.
