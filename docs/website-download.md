# App Store download guidance

The landing page directs its header and hero buttons to `#download`. Until
Waybi has a public store listing, that section shows an honest Coming soon
state with a disabled App Store button; no placeholder listing is used.

Once the listing is available, set `VITE_APP_STORE_URL` to its HTTPS
`apps.apple.com` URL with the actual `id...` path, then rebuild and deploy the
website. A valid URL changes the download section into a working store link.
The existing browser map and dashboard remain reachable at their own routes.

The footer introduces Clover and Sett using the same transparent artwork as
the Flutter app. The main Waybi bird logo stays unchanged.
