# Mobile application

## What does the app control?

The Flutter app displays readings and actuator states reported by the ESP32.
The firmware decides when safety rules activate the pump and sprinkler. The app
can request manual sprinkler operation and update supported safety thresholds.
Pump Status and saved-limit labels use values confirmed by the device.

## How do I run it?

Install the Flutter SDK, then run from `mobileapp/`:

```bash
flutter pub get
flutter run
```

Enter the ESP32's current local IP address and log in with the credentials
configured in `firmware/main/Secrets.h`. The app checks those credentials
against the device before opening the app. Open the admin-only **Control** tab
and use **Emergency Control & Local Alerts** directly. Its safety panel polls
`GET /api/state` every two seconds while the app is active. Its sprinkler switch
sends `POST /api/control`, then refreshes from device state. A safety override
returns `409` and the switch returns to the reported state.

Without an ESP32, use the [local simulator](esp32-simulator.md) to exercise
the same app flows with repeatable readings and alerts. A physical phone needs
the simulator started with `--host 0.0.0.0` and the computer's Wi-Fi IPv4
address in the app. The simulator guide shows the exact command and a browser
check for connection problems.

The pump card combines a read-only Pump Status indicator and the manual
sprinkler switch. Both follow `pump_on`; unavailable or malformed pump telemetry
displays UNAVAILABLE and disables manual control. The switch also locks while
offline, saving limits, or under chamber protection. The indicator reports the
commanded relay output, so it does not confirm that the pump ran or water flowed.
Update the device and app together because older responses omit that field.

The main telemetry view shows no live readings while the ESP32 is disconnected.
It stores history and alerts locally in `biomass_iot.db` only from successful
responses. The alert screen first reads the newest 20 alerts, then
loads another batch when you scroll near the end. Severity filters run in the
local database before each batch is read, so a long history does not delay the
screen opening. The displayed total covers the full filtered snapshot; alerts
created after it opened appear after a refresh. On phones, the end of the list
stays above the floating navigation bar so the final alert and load state are
fully visible. The app keeps one saved device IP; it does not keep a node list
or save credentials. After an ESP32 restart, the MQ-135 and MQ-2 cards show a
five-minute warm-up countdown. Their readings and MQ-2 gas alerts become active
when it reaches zero. MQ sensor values are voltages; the app does not calculate
a certified air quality index or carbon monoxide concentration from them.

The app records a warning when a DHT22, thermocouple, MQ135, MQ2, or PMS5003
sensor reports unavailable data. It records one warning for a continuing fault
and an info alert when that same sensor starts reporting valid data again.
These alerts report sensor availability; they do not change sprinkler control
or confirm that a sensor is physically disconnected.

The Sensor Logs tab contains every recorded sensor value: chamber and ambient
temperature, MQ-135 and MQ-2 voltage, and PM1.0, PM2.5, and PM10 mass
concentrations in µg/m³. `--` means the device has not provided that reading.
Its session analytics show peak and average values for each metric. The
current-session CSV export retains particulate fields as `PM1.0(ug/m3)`,
`PM2.5(ug/m3)`, and `PM10(ug/m3)`. Configured particulate limits generate
alerts and history entries; only chamber protection automatically runs the pump.

The Home dashboard groups live and historical trends by unit so readings remain
readable: ambient and chamber temperatures, MQ2 and MQ135 voltages, and PM1.0,
PM2.5, and PM10 concentrations. Each chart uses the same Live, 1H, and 24H
timeframe control. A missing reading appears as a gap, so the app does not
misrepresent unavailable sensor data as zero.

The sensor data log reads the full local history in pages of 10 records, newest
first. Live updates are off by default so records do not move between pages
while they are being reviewed. Use Refresh to create a newer snapshot, or turn
on Live updates to refresh the first page as telemetry arrives. When new data
arrives while an older page is open, the app keeps that page stable and shows a
New records available action that returns to the refreshed first page. Session
analytics and CSV exports continue to use the current in-memory session.

## How do I configure sensor limits on Control?

Under **Emergency Control & Local Alerts**, the Temperature, Gas, Particulate
Matter, and Humidity groups provide nine numeric fields for eight readings.
Each row shows its current reading, confirmed saved limit, and status. Chamber
temperature says **Alerts + automatic sprinkler**; every other reading says
**Alerts only**. Pump status and manual control share the card above the groups.

1. Drag a slider or type the limits selected for your operation. Configuration
   ranges validate device settings; they are not exposure standards. New optional
   limits start unset, with **Not configured** displayed until saved.
2. Enter both humidity boundaries for the first configuration, with minimum
   strictly below maximum. Later edits validate against the latest saved
   opposite boundary. Limits already configured cannot be cleared.
3. Select **Apply Thresholds**. Only changed fields are sent together. Inputs
   lock during the request, and the device-confirmed values replace the draft
   and saved labels after success. Failed writes or missing confirmation keep
   the typed values so you can retry.

Each upper limit pairs a slider with exact numeric entry. Humidity uses one
two-handle range slider and separate minimum/maximum inputs. Dragging uses
0.5 °C, 0.1 V, 1 µg/m³, and 1% steps; typing retains finer precision.
Particulate sliders initially span 1–500 µg/m³ and expand for larger typed or
saved values, up to 65535. Their displayed range stays stable while dragging.
These slider ranges do not restrict the API's accepted configuration ranges.
An unset slider position does not configure a limit until you interact with it.

Polling refreshes readings and saved labels while preserving edited text,
including while scrolling or using the keyboard. For example, if you type a
humidity minimum of 35% while another client changes the saved maximum to 34%,
Apply rejects the invalid pair. Offline readings are marked stale and controls
lock until reconnecting; the draft remains available.

New MQ-2 limits must be 0.1 to 4.8 V because readings above 4.8 V are sensor
faults. A saved legacy limit of 5 V remains visible and does not block editing
other limits. Missing firmware fields are individually disabled with **Firmware
update required**; an explicit null field remains editable. See the
[API reference](api.md) for all configuration ranges.

**Sensor fault** takes priority over a row's alert or unconfigured status.
During the 300-second MQ warm-up, MQ rows instead show a countdown. A retained
`catastrophic_latch` keeps chamber protection visible and manual control locked
even when the chamber reading is faulty. Environmental alerts leave manual
control available. The device rejects a manual command with 409 if chamber
protection takes ownership after the most recent poll.

Control and background telemetry share ordered observations and persistent
activation keys, so an ongoing condition creates one history entry across
polls and app restarts. Recovery permits a later activation to create another
entry. DHT22 faults and PMS5003 faults are grouped by physical sensor. Muting app
sound changes neither history nor firmware protection.

Limits apply immediately in device memory. Flash writes occur at most once
every 60 seconds, so power loss before persistence can lose a recent change.
App history requires the app to be running and connected; there are no push
notifications or device-side history. The standalone dashboard route remains
available for compatibility and hosts the same controls.

## How do filtration attempts work?

The **Attempts** segment records local snapshots while the app remains open,
authenticated, and connected to the ESP32. Start one attempt as **Without
filtration** and another as **With filtration**, then stop each one. A lost
connection marks the active attempt interrupted while preserving its readings.
App upgrades retain saved attempts and readings from the earlier local database
schema.

Saved attempts appear in separate **Without filtration** and **With filtration**
groups. Select one attempt from each group to enable **Compare attempts**.
Deleting a saved attempt requires confirmation; deleting a selected attempt
clears that selection and disables comparison until another is chosen.
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
