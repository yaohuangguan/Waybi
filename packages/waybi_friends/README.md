# Waybi & Friends

A shared Flutter companion room used by the Waybi navigation app and the
separate Waybi's Way Home prototype.

## Experience

- Clover walks from the sofa to the window, watches outside and naps.
- Sett follows Clover, runs across the rug and settles nearby.
- Waybi packs a backpack, walks to the door and returns from a little journey.
- Character parts have their own pivots: paws, tails, wings, head and eyelids.
- Packing, souvenirs, postcards and the Journal retain the original loop.

The room uses small vector character rigs based on the existing mascots. The
original character images remain in the loading, bag and Journal views.

## Integration

Add `FriendsEntry(chinese: appLanguage == 'zh')` to the profile page, or open
`FriendsPage(language: appLanguage)` directly. The embedded page has a back
button and Journal / Bag actions. It does not add a navigation tab.

The standalone app uses `WaybisWayHomeApp` and retains its Home / Journal / Bag
navigation. Its existing `waybis_way_home_v1` save is upgraded in place. Waybi's
embedded page uses a separate `waybi_friends_v1` save within the navigation app.

## Time and lifecycle

`RoomLife` stores the start time of a routine and the departure / arrival times.
Rendering samples the current clock; no animation frame is written to storage.
Leaving and reopening the room therefore continues the same routine.

The session checks overdue journeys on load and resume. It pauses timers in the
background. Hidden pages stop their animation tickers, and reduced motion turns
off limb animation. A return postcard is presented only while the room is open,
after the arrival animation finishes.

## Verification

```sh
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
```

Tests cover older saves, reopening mid-routine, departure persistence,
concurrent return checks, background resume, small screens and the profile
entry's Journal / Back flow.
