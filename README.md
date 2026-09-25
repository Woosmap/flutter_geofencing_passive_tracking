
# Woosmap Geofencing → Back-office (REST) — Flutter Sample

This sample starts the Woosmap Geofencing `passiveTracking` profile from **Dart**,
and forwards every geofence **region event** (enter/exit) to a customer back-office
via a **REST call made in Dart** — including when the app has been terminated.

It requires `geofencing_flutter_plugin` **1.10.0-dev.2** or later, which added
`registerBackgroundRegionCallback()`. No native code is involved: earlier
revisions of this sample carried a Swift observer and a Kotlin `BroadcastReceiver`
for the same job, and both have been removed.

## How it works

```
┌─────────────┐    startTracking('passiveTracking')   ┌───────────────────────┐
│  Dart (UI)  │ ───────────────────────────────────►  │ Woosmap Geofencing    │
│ main.dart   │                                       │ SDK (native)          │
│ service.dart│  registerBackgroundRegionCallback()   └───────────┬───────────┘
└─────────────┘ ───────────────────────────────────►              │ region event
                                                                  ▼
                                                   ┌──────────────────────────┐
                                                   │ Plugin starts a headless │
                                                   │ Flutter engine if needed │
                                                   └────────────┬─────────────┘
                                                                ▼
                                             onWoosmapRegionEvent(Region region)
                                             (background isolate, no widgets)
                                                                │
                                                                ▼ HTTP POST
                                                  Customer back-office REST API
```

The callback is woken by the OS even after the app has been killed: Android
plugs a region listener from a `ContentProvider` as soon as the process is
created, and iOS relaunches the app in the background for the region event.

`registerBackgroundRegionCallback()` is persisted natively, so it survives a
restart — the sample calls `hasBackgroundRegionCallback()` before registering
again. `stopTracking()` removes it, since tracking is what produces the events.

> The callback fires only when the region **stream** cannot deliver the event.
> This sample never calls `getWatchRegionStream()`, so every event goes through
> `onWoosmapRegionEvent` — foreground included, and never twice. Add a stream
> listener only if you want in-app UI for the events; while it is listening, the
> background callback stays idle.

## Project layout

```
woosmap_geofencing_rest_sample/
├── pubspec.yaml
├── lib/
│   ├── main.dart                     # Sample UI + location permission request
│   ├── geofencing_service.dart       # init(), startTracking, callback registration
│   └── geofence_event_forwarder.dart # background callback → REST POST
├── ios/Runner/
│   └── AppDelegate.swift             # plain Flutter registrant, nothing Woosmap-specific
└── android/
    ├── build.gradle                  # adds JitPack repo
    └── app/
        ├── build.gradle              # compileSdk 36 / minSdk 26
        └── src/main/
            ├── AndroidManifest.xml   # permissions
            └── kotlin/.../MainActivity.kt
```

## Configure before running

1. **Back-office endpoint & auth** — set `kBackOfficeUrl` / `kBackOfficeApiKey`
   in `lib/geofence_event_forwarder.dart`. For production, inject the token at
   runtime (`String.fromEnvironment`, or secure storage read from the callback)
   rather than hardcoding it.

2. **Woosmap API key** — replace the `kWoosmapPrivateApiKey` placeholder in
   `lib/geofencing_service.dart` with your Woosmap private key. It is passed to
   the plugin via `WoosmapGeofencingOptions(privateKeyWoosmapAPI: ...)` during
   `initialize()`. For production, inject it at runtime (secure storage or a
   build-time environment variable) rather than hardcoding it.

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

> **Testing on the Simulator.** A physical iPhone is still the right place to
> validate real-world behaviour (motion, Wi-Fi/cell positioning, battery), but
> the Simulator *can* drive enter/exit events — including a relaunch of a
> terminated app — by injecting coordinates:
>
> ```bash
> xcrun simctl privacy booted grant location-always com.woosmap.woosmapGeofencingRestSample
> xcrun simctl location booted set 48.856710,2.354800
> ```
>
> Move to a coordinate inside a POI region, wait for the SDK to settle, then
> `xcrun simctl terminate booted <bundle-id>` and move away: iOS relaunches the
> app in the background and `onWoosmapRegionEvent` receives the exit event.
> Leave 30s or so at each position — the SDK fetches POIs for the new area and
> re-arms its regions on a location update, and killing the app before that has
> happened leaves nothing monitored to trigger on.

<img width="400" alt="How App looks" src="https://github.com/user-attachments/assets/d0609081-9c2c-4bd6-847f-0971c46adcbc" />


## Run on Android

The Android project is committed with the settings the Woosmap SDK needs:

- `android/settings.gradle` — AGP 8.11.1 / Kotlin 2.2.20 (Gradle wrapper 8.14).
- `android/gradle.properties` — `android.useAndroidX=true` and
  `android.enableJetifier=true` (the SDK's dependency graph is AndroidX).
- `android/app/build.gradle` — `compileSdk = 36` and `minSdk = 26`, both
  required by `geofencing_flutter_plugin`. The app declares no SDK dependency
  of its own: `geofencing_flutter_plugin` pulls
  `com.github.Woosmap:geofencing-core-android-sdk` and
  `com.webgeoservices.woosmapgeofencing:woosmap-mobile-sdk` from JitPack
  transitively.

1. **Run it:**

   ```bash
   flutter pub get
   flutter devices          # find your device / emulator id
   flutter run -d <device-id>
   ```

   The first build downloads Gradle and the Woosmap SDK from JitPack, so it
   takes a few minutes; later builds are fast.

2. **Grant background location.** `ACCESS_FINE_LOCATION`,
   `ACCESS_COARSE_LOCATION`, and `ACCESS_BACKGROUND_LOCATION` are declared in
   `android/app/src/main/AndroidManifest.xml`, but on Android 10+ the user must
   grant *Allow all the time* from system settings — it is not offered in the
   in-app prompt.

> An emulator is fine for launching the UI, but real geofence transitions need
> either a physical device or the emulator's *Extended controls → Location* to
> inject coordinates.

<img width="300" alt="How App looks" src="https://github.com/user-attachments/assets/a992159e-7983-41af-8575-8402b9fb87fe" />

## Event payload

The JSON body sent to the back-office is built by `regionEventPayload()` from
the `Region` handed to the callback. The same fields are sent on both platforms:

| Field                 | Type   | Notes                                    |
| --------------------- | ------ | ---------------------------------------- |
| date                  | int    | epoch milliseconds                       |
| eventName             | string | `woos_geofence_entered_event` / `..._exited_event` |
| id                    | string | region identifier — the store id for a POI region |
| latitude              | double |                                          |
| longitude             | double |                                          |
| radius                | double | metres                                   |
| didEnter              | bool   |                                          |
| spentTime             | int    | seconds, on exit events                  |
| fromPositionDetection | bool   |                                          |

### POI enrichment

When the region is a POI region, `PoiResolver` (`lib/poi_resolver.dart`) looks
the store up from `Region.identifier` and merges these keys into the same
payload: `idStore`, `name`, `city`, `zipCode`, `countryCode`, `address`, `tags`,
`types`, `distance`. They are omitted for a custom region, and a failed lookup
only costs the extra fields — the event is still forwarded.

Two sources, tried in order:

| Source | Platform | Cost |
| ------ | -------- | ---- |
| Plugin `getPois()` — SDK's local database | iOS only | ~12 ms, no network |
| Store API `GET /stores/{id}/` over `dart:io` | both | ~460 ms, one HTTPS call |

The local path needs plugins inside the headless engine, which only iOS
supports — `AppDelegate` wires it up with
`GeofencingFlutterPlugin.setPluginRegistrantCallback`. The Android background
engine registers no plugins and has no Activity, so it always takes the Store
API path. The API key travels in the `X-Api-Key` header rather than the query
string, so it stays out of server logs.

## Notes / production hardening

- **Keep the callback self-contained.** It runs in a background isolate that
  shares no memory with the UI isolate, and on Android that isolate has no
  plugins registered — only `dart:*` code is safe there. iOS can expose plugins
  to it via `GeofencingFlutterPlugin.setPluginRegistrantCallback` from
  `AppDelegate`, as this sample does for the local POI lookup, but anything
  relying on that needs a `dart:*` fallback for Android — see how `PoiResolver`
  drops to the Store API.
- **Retry / offline queue**: geofence events can fire with no connectivity, and
  the isolate is given only a short window to finish, so a failed POST is lost.
  Consider persisting failures and retrying on the next event or app launch.
- **iOS region slots**: `passiveTracking` uses all 20 `CLRegion` slots. Use
  `protectedRegionSlot` (up to 3) if another plugin also needs geofencing.
- Verify the `geofencing_flutter_plugin` and SDK versions against the latest
  published releases before shipping.
