# Woosmap Geofencing → Back-office (REST) — Flutter Sample

This sample starts the Woosmap Geofencing `passiveTracking` profile from **Dart**,
and forwards every geofence **region event** (enter/exit) to a customer back-office
via a native **REST call** — the iOS side in **Swift**, the Android side in **Kotlin**.


## How it works

```
┌─────────────┐    startTracking('passiveTracking')   ┌──────────────────────┐
│  Dart (UI)  │ ───────────────────────────────────►  │ Woosmap Geofencing    │
│ main.dart   │                                        │ SDK (native)          │
│ service.dart│                                        └──────────┬───────────┘
└─────────────┘                                                   │ region event
                                                                  ▼
                              iOS: NotificationCenter      Android: Broadcast
                              .didEventPOIRegion            com.woosmap.action.
                                                            GEOFENCE_TRIGGERED
                                        │                          │
                                        ▼                          ▼
                          GeofencingEventsReceiver.swift   GeofencingEventsReceiver.kt
                                        │                          │
                                        └────────► HTTP POST ◄──────┘
                                                     │
                                                     ▼
                                          Customer back-office REST API
```

The Dart layer only starts/stops tracking. Region events are captured and POSTed
**natively**, so they still fire when the app is backgrounded or terminated.

## Project layout

```
woosmap_geofencing_rest_sample/
├── pubspec.yaml
├── lib/
│   ├── main.dart                    # Sample UI + location permission request
│   └── geofencing_service.dart      # init() + startTracking('passiveTracking')
├── ios/Runner/
│   ├── AppDelegate.swift            # wires up the receiver at launch
│   └── GeofencingEventsReceiver.swift  # observes region events → REST POST
└── android/
    ├── build.gradle                 # adds JitPack repo
    └── app/
        ├── build.gradle             # adds Woosmap SDK dependencies
        └── src/main/
            ├── AndroidManifest.xml  # permissions + MainApplication
            └── kotlin/.../
                ├── MainActivity.kt
                ├── MainApplication.kt          # registers the receiver
                └── GeofencingEventsReceiver.kt # broadcast → REST POST
```

## Configure before running

1. **Back-office endpoint & auth** — set `backOfficeURL` / `apiKey` (Swift) and
   `BACK_OFFICE_URL` / `API_KEY` (Kotlin). For production, store the key in
   Keychain (iOS) / EncryptedSharedPreferences or BuildConfig (Android) rather
   than as a hardcoded constant.

2. **Woosmap API key** — set your Woosmap private key wherever your app
   initializes the SDK (per the Flutter plugin Setup guide).

3. **iOS permissions** — already set in `ios/Runner/Info.plist`
   (`NSLocationWhenInUseUsageDescription`,
   `NSLocationAlwaysAndWhenInUseUsageDescription`, and `UIBackgroundModes` →
   `location`). Reword the two usage-description strings to match your app —
   they are the text shown in the iOS permission dialogs.

4. **Android** — background location (`ACCESS_BACKGROUND_LOCATION`) must be
   granted by the user from system settings (Android 10+ shows it separately).

## Run on iOS

The full iOS Xcode project is committed (`Runner.xcodeproj`, `Podfile` pinned to
iOS 15.0, `Info.plist` with the location permissions). No `flutter create`
regeneration is needed — just fetch dependencies and run.

1. **Fetch dependencies:**

   ```bash
   flutter pub get
   cd ios && pod install && cd ..
   ```

   If `pod install` crashes with
   `Unicode Normalization not appropriate for ASCII-8BIT`, your shell locale is
   not UTF-8 — prefix the command:

   ```bash
   LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 pod install
   ```

2. **Set a development team** — open `ios/Runner.xcworkspace`, then
   Runner target → *Signing & Capabilities*, and select your Apple Developer
   team (required to run on a physical device).

3. **Run on a device:**

   ```bash
   flutter devices          # find your device id
   flutter run -d <device-id>
   ```

> **Use a real device, not the Simulator.** This is a geofencing /
> `passiveTracking` sample: the iOS Simulator cannot deliver real region events
> or background location, and `passiveTracking` requires *Always* location
> authorization. A physical iPhone is needed to see events fire.

## Event payload

The JSON body sent to the back-office follows the Woosmap connector event spec:

| Field         | Always | POI only |
| ------------- | :----: | :------: |
| date          |   •    |          |
| eventName     |   •    |          |
| id            |   •    |          |
| latitude      |   •    |          |
| longitude     |   •    |          |
| radius        |   •    |          |
| didEnter      |   •    |          |
| origin (iOS)  |   •    |          |
| spentTime (Android) | • |          |
| idStore       |        |    •     |
| name          |        |    •     |
| city          |        |    •     |
| zipCode       |        |    •     |
| distance      |        |    •     |
| countryCode   |        |    •     |
| address       |        |    •     |
| tags          |        |    •     |
| types         |        |    •     |

POI fields are only populated when the region originates from a POI; they are
omitted for custom regions.

## Notes / production hardening

- **Retry / offline queue**: geofence events can fire with no connectivity.
  Consider persisting failed POSTs and retrying (e.g. WorkManager on Android,
  a background URLSession or local queue on iOS).
- **iOS region slots**: `passiveTracking` uses all 20 `CLRegion` slots. Use
  `protectedRegionSlot` (up to 3) if another plugin also needs geofencing.
- Verify the `geofencing_flutter_plugin` and SDK versions against the latest
  published releases before shipping.
