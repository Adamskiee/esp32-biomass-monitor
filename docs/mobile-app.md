# Mobile application

## What does the app control?

The Flutter app displays readings and actuator states reported by the ESP32.
The firmware decides when safety rules activate the fan and sprinkler. The app
can request manual sprinkler operation and update two safety thresholds, but a
request does not become the displayed state until the ESP32 reports it.

## How do I run it?

Install the Flutter SDK, then run from `mobileapp/`:

```bash
flutter pub get
flutter run
```

Enter the ESP32's current local IP address and log in with the credentials
configured in `firmware/main/Secrets.h`. The app checks those credentials
against the device before opening the dashboard. The safety dashboard polls
`GET /api/state` every two seconds while the app is active. Its sprinkler switch
sends `POST /api/control`, then refreshes from device state. A safety override
returns `409` and the switch returns to the reported state.

Without an ESP32, use the [local simulator](esp32-simulator.md) to exercise
the same app flows with repeatable readings and alerts. A physical phone needs
the simulator started with `--host 0.0.0.0` and the computer's Wi-Fi IPv4
address in the app. The simulator guide shows the exact command and a browser
check for connection problems.

The dashboard also shows a read-only Pump Status indicator. It can briefly
differ from Sprinkler Status while the controller opens the valve before
starting the pump or stops the pump before closing the valve. The indicator
reports the commanded relay output, so it does not confirm that the pump ran or
that water flowed.

The main telemetry view shows no live readings while the ESP32 is disconnected.
It stores history, alerts, and audit logs locally in `biomass_iot.db` only from
successful responses. The app keeps one saved device IP; it does not keep a
node list or save credentials. MQ sensor values are voltages; the app does not
calculate a certified air quality index or carbon monoxide concentration from
them.

The safety dashboard sends threshold changes to `POST /api/thresholds`. The
firmware also accepts `/api/settings` for older clients, with the same
validation. See [the API reference](api.md) for ranges and examples.

## How do filtration attempts work?

The **Attempts** segment records local snapshots while the app remains open,
authenticated, and connected to the ESP32. Start one attempt as **Without
filtration** and another as **With filtration**, then stop each one. A lost
connection marks the active attempt interrupted while preserving its readings.

Select one saved attempt from each scenario and choose **Compare attempts**.
The app shows average, minimum, maximum, and elapsed-time series for MQ-2,
MQ-135, DHT-22 temperature and humidity, and PM1.0, PM2.5, and PM10. A
percentage is `(with filtration average - without filtration average) / without
filtration average`. Missing data and zero baselines are shown as unavailable.
The comparison describes observations and never gives a success verdict.

## How do I check the app?

```bash
flutter analyze
flutter test
```

## How do I profile tab transitions?

Debug builds include extra checks and are not performance evidence. Connect
the affected Android device, then run from `mobileapp/`:

```bash
flutter run --profile
```

Open Flutter DevTools from the run output and record frame timings in its
Performance view while repeatedly switching among all five tabs. Confirm the
fade-and-scale effect remains visible and live telemetry keeps updating on the
active tab with an ESP32 or the local simulator connected. Compare UI and raster
frame times with the device's frame budget, for example 16.7 ms at 60 Hz.
Isolated first-use shader warm-up can occur, but recurring transition-related
jank or frame-budget spikes are not expected.

## How do I publish an Android release?

Android requires every update for `com.biomo.biomassmonitor` to use the same
signing key. Create the key outside the repository and keep an offline backup;
losing it prevents future APKs from updating installations of the first release.

```bash
keytool -genkeypair -keystore ~/biomass-release.jks -alias biomass-release \
  -keyalg RSA -keysize 2048 -validity 10000
base64 -w 0 ~/biomass-release.jks
```

Add the encoded output and the passwords to these GitHub repository secrets:
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD`,
and `ANDROID_KEY_ALIAS`. Keep the keystore and its passwords out of the
repository. The release workflow reconstructs them only on its runner.

Publish a three-part numeric version tag after the normal checks pass:

```bash
git tag v1.2.3
git push origin v1.2.3
```

The workflow creates or updates the matching GitHub Release. It includes the
firmware binary and `biomo-biomassmonitor-v1.2.3.apk`; a hardware archive is
included only when matching hardware files exist. A manual workflow run must
target a valid tag in the same `vMAJOR.MINOR.PATCH` format.

## How do I inspect and update an APK?

Download the APK from the GitHub Release page. Android Build Tools can check
the signature and the package metadata before installation:

```bash
apksigner verify biomo-biomassmonitor-v1.2.3.apk
aapt2 dump badging biomo-biomassmonitor-v1.2.3.apk
```

The output must identify `com.biomo.biomassmonitor`. Install later releases
over the earlier APK on a device to confirm the retained signing key permits an
update. APK distribution uses manual installation and does not provide Google
Play or in-app updates.

## What can prevent a release from working?

Missing signing secrets, an invalid tag, failed Flutter analysis or tests, and
missing firmware or APK artifacts stop publication. The workflow verifies the
APK signature, application ID, version name, and version code before upload.

The app needs local network access to the device. This firmware connects to a
configured Wi-Fi network; it does not implement access point provisioning,
cloud telemetry, or over-the-air updates. Basic authentication travels over
plain HTTP, so use it only on a trusted local network.
The Android and iOS app configurations allow local HTTP access because the
device currently has no HTTPS endpoint.
Biometric re-entry works only while the app process still holds a previously
validated device session. After an app restart, enter the device credentials
again; they are not saved to local preferences.
