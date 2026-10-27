# Mobile application

## What does the app control?

EcoBurn is the Flutter app for readings and actuator states reported by the ESP32.
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

Pages show available content immediately when opened. A data section with no
available content shows skeleton shapes only if its request is still pending
after 200 milliseconds. When the request finishes, the shapes disappear and the
result fades in over 150 milliseconds, without a minimum loading time. Fast
requests skip the skeleton and fade. Background refreshes keep existing content
visible. Skeletons shimmer in light and dark themes; the system's reduced-motion
setting disables shimmer and the fade.

The main telemetry view shows no live readings while the ESP32 is disconnected.
The app stores history and alerts locally in `biomass_iot.db` only from successful
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
temperature, humidity, MQ-135 and MQ-2 voltage, and PM1.0, PM2.5, and PM10 mass
concentrations in µg/m³. `--` means the device has not provided that reading.
The page opens directly to the recorded readings. The current-session CSV export
retains particulate fields as `PM1.0(ug/m3)`, `PM2.5(ug/m3)`, and `PM10(ug/m3)`.
Configured particulate limits generate alerts and history entries; only chamber
protection automatically runs the pump.

The Home dashboard groups live and historical trends by unit so readings remain
readable: ambient and chamber temperatures, humidity, MQ2 and MQ135 voltages,
and PM1.0, PM2.5, and PM10 concentrations. The shared timeframe control offers
Live, 1H, 24H, and All time. Each chart section shows a peak and average for
each sensor, calculated over the same period as the chart.

Live uses the latest 60 readings held in memory. The 1H and 24H options use all
saved readings within the selected period; All time uses the entire saved
history through the time it was loaded. Pull down to refresh a historical view.
Historical charts show up to 60 averaged points to keep large histories readable.
Their statistics use the original readings, so averaging chart points cannot
hide a peak or give a small group of readings too much weight. For example,
a peak outside the latest 60 readings still appears in the All time summary.

Missing readings are excluded from each sensor's peak and average. A sensor
without valid readings shows No data in its summary. A missing chart reading
appears as a gap, so the app does not misrepresent unavailable sensor data as
zero. A sensor with no valid readings in the selected timeframe is omitted from
its chart and legend. If every sensor in a chart is unavailable, the chart shows
a no-data message. This also handles
hardware startup and sensor faults, when the ESP32 can report null readings.

The sensor data log reads the full local history in pages of 10 records, newest
first. Live updates are off by default so records do not move between pages
while they are being reviewed. Use Refresh to create a newer snapshot, or turn
on Live updates to refresh the first page as telemetry arrives. When new data
arrives while an older page is open, the app keeps that page stable and shows a
New records available action that returns to the refreshed first page. CSV
exports continue to use the current in-memory session; the chart timeframe does
not change their scope.

To export those session readings on Android, tap the export icon beside
**Sensor Data Log**, then **GENERATE & SHARE CSV**. The export sheet scrolls
on smaller screens and with larger text. Android opens its share chooser with
`Biomass_Telemetry_Export.csv` attached, so the receiving app gets a CSV file.
The file includes the latest 60 session readings, rather than the full paginated
log. If there are no readings or sharing fails, the app displays a message.

## How do icons stay consistent across pages?

UI icons come from `AppIcons` in `mobileapp/lib/app/app_icons.dart` so the same
action or sensor uses the same Cupertino symbol on every page. Reuse an existing
semantic name when adding UI, or add a name there for a new concept.

Icons accompany section headings, chart groups, analytics cards, sensor threshold
rows, settings controls, and alert filters. Sensor symbols match their dashboard
cards so readers can recognize the same measurement across pages. `IconLabel` in
`mobileapp/lib/core/widgets/icon_label.dart` pairs an icon with wrapping text;
keep visible labels so icons are not the only way to identify a control.

Icons use outlines by default. Home, Alerts, and Settings use filled variants
when selected in both desktop and mobile navigation. Critical, warning, and
informational alert indicators also use filled symbols to emphasize status.
Monitor and Control keep the same symbol when selected and use color to indicate
selection. Navigation and standalone content icons use 24 logical pixels;
heading, label, and button icons use 20. Severity filter icons use 16, and sensor
cards use 20 in compact layouts or 24 otherwise. Branding and large status
illustrations retain sizes suited to their context.

Alert filters pair matching icon and label colors: neutral gray for All, blue for
Info, orange for Warning, and red for Critical. The selected filter adds a subtle
matching background tint, stronger border, and bolder label so selection remains
visible without relying on color alone. Light mode uses darker severity shades
to keep the labels readable.

Uncolored icons inherit Flutter's light or dark theme foreground so they stay
readable against the page background. Keep that default when adjusting global
icon sizing. Settings uses the theme's `onSurfaceVariant` foreground for all
icons, including dialog headings and chevrons, with 20-pixel sizing and matching
label spacing.

## How do I configure sensor limits on Control?

Under **Emergency Control & Local Alerts**, the Temperature, Gas, Particulate
Matter, and Humidity groups list eight sensor readings. Each sensor starts
collapsed; its slider, numeric input, and Default button appear only when opened.
Only the open sensor shows its current reading and editable limit. Closed
sensors show their names and any status badges. Normal readings have no badge;
alerts, faults, and setup states remain visible.
Humidity shares one reading and status across its minimum and maximum controls.
Chamber temperature says **Alerts + automatic sprinkler**; groups containing only
alerting sensors show **Alerts only** once. Pump status and manual control
share the card above the groups.

1. Tap a sensor row to open its slider and numeric input. Opening another
   sensor closes the previous one. Only the open sensor can be edited, which
   prevents accidental slider changes while browsing the list.
   Configuration ranges validate device settings; they are not exposure standards. Current
   firmware provides defaults for every limit and fills previously unset fields
   at startup while preserving saved values. See the [default table](api.md#post-apithresholds).
2. Keep humidity minimum strictly below maximum. Either boundary can be edited;
   validation uses the latest saved opposite boundary. Limits already configured
   cannot be cleared.
3. Select **Apply Thresholds**. Only changed fields are sent together. Inputs
   lock during the request, and the device-confirmed values replace the draft
   after success. Failed writes or missing confirmation keep the typed values
   so you can retry. A successful save closes the open sensor.

**Default** restores the project setting for that sensor as a draft. Humidity
has one **Default** button that restores both bounds to 30% and 60%, avoiding
an invalid range when the existing bounds differ. Select **Apply Thresholds**
to save restored defaults. These values match the [firmware defaults](api.md#post-apithresholds).
Default is unavailable while controls are locked or the sensor setting is
unsupported by the firmware.

Each upper limit pairs a slider with exact numeric entry. Tap its row again
to close it. Closing a sensor preserves its draft, including when another
sensor opens. Humidity opens both bounds together. Controls are unavailable
during saving or disconnection, and **Apply Thresholds** saves all edited sensors.
On narrow screens or with larger text, the input moves below the slider to
keep both usable.
Humidity uses one two-handle range slider and separate minimum/maximum inputs.
Dragging uses 0.5 °C, 0.1 V, 1 µg/m³, and 1% steps; typing retains finer precision.
Particulate sliders initially span 1–500 µg/m³ and expand for larger typed or
saved values, up to 65535. Their displayed range stays stable while dragging.
These slider ranges do not restrict the API's accepted configuration ranges.
On earlier firmware, an unset slider position does not configure a limit until
you interact with it. Such fields display **Not configured** until saved;
configure both humidity boundaries together if both are unset.

Polling refreshes readings and unedited limits while preserving edited text,
including while scrolling or using the keyboard. For example, if you type a
humidity minimum of 35% while another client changes the saved maximum to 34%,
Apply rejects the invalid pair, reopens Humidity, and shows the error. Other
validation errors also reopen the first invalid sensor and identify it in the
message. Offline readings are marked stale and controls
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

## Why did login fail?

Login checks credentials with one `GET /api/state` request and a three-second
timeout. The screen distinguishes invalid credentials (`401`), a busy device
(`503`), a timeout, network errors, and other HTTP responses. If waiting and
retrying works, capture the first failure before changing the timeout or adding
retries, so the original cause remains visible.

Run the app with `flutter run` from `mobileapp/` and look for `Device login:`
in the console. For an already running app, use `flutter logs` with the phone
connected and selected. For example:

```text
Device login: timeout exception=TimeoutException elapsed_ms=3002
Device login: http_error status=503 elapsed_ms=24
Device login: success status=200 elapsed_ms=18
```

Logs include the outcome, HTTP status or exception type, and elapsed time.
They omit credentials, authorization headers, response bodies, and raw exception
messages. A timeout only establishes that the request missed the deadline;
it does not identify whether Wi-Fi, the phone, or the ESP32 caused the delay.

## How do I check the app?

```bash
flutter analyze
flutter test
```

## Where are the EcoBurn branding assets?

`mobileapp/assets/branding/ecoburn-logo.png` is the supplied logo used on the
login screen. `ecoburn-icon.png` is the symbol-only launcher artwork, with a
dark green background and padding to keep the symbol readable at small sizes.
Android and iOS launcher images are checked in so normal builds need no image
generation dependencies. After replacing the launcher artwork, install
ImageMagick and run from `mobileapp/`:

```bash
bash tool/generate_launcher_icons.sh
```

The Android application ID is `com.biomo.ecoburn`. Android treats it as a
separate app from the earlier `com.biomo.biomassmonitor` package, so the old
installation's preferences, history, and attempts do not transfer automatically.
The Dart package name and iOS bundle identifier retain their existing values.

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

Android requires every update for `com.biomo.ecoburn` to use the same
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

Set the built-in version in `mobileapp/pubspec.yaml` before tagging. The
three-part version must exactly match the release tag; the `+BUILD` suffix can
remain a local build counter because GitHub Actions supplies the release build
number.

```yaml
version: 1.2.3+1
```

Publish the matching three-part numeric version tag after the normal checks
pass:

```bash
git tag v1.2.3
git push origin v1.2.3
```

The workflow creates or updates the matching GitHub Release. It includes the
firmware binary and `ecoburn-v1.2.3.apk`; a hardware archive is
included only when matching hardware files exist. A manual workflow run must
target a valid tag in the same `vMAJOR.MINOR.PATCH` format.

## How do I inspect and update an APK?

Download the APK from the GitHub Release page. Android Build Tools can check
the signature and the package metadata before installation:

```bash
apksigner verify ecoburn-v1.2.3.apk
aapt2 dump badging ecoburn-v1.2.3.apk
```

The output must identify `com.biomo.ecoburn`. Install later EcoBurn releases
over the first EcoBurn APK on a device to confirm the retained signing key
permits an update. The previous `com.biomo.biomassmonitor` APK cannot update to
EcoBurn because Android treats the new application ID as a separate app. APK
distribution uses manual installation and does not provide Google Play or
in-app updates.

## What can prevent a release from working?

Missing signing secrets, an invalid tag, a tag that does not match the built-in
app version, failed Flutter analysis or tests, and missing firmware or APK
artifacts stop publication. The workflow verifies the APK signature,
application ID, version name, and version code before upload.

The app needs local network access to the device. This firmware connects to a
configured Wi-Fi network; it does not implement access point provisioning,
cloud telemetry, or over-the-air updates. Basic authentication travels over
plain HTTP, so use it only on a trusted local network.
The Android and iOS app configurations allow local HTTP access because the
device currently has no HTTPS endpoint.
Biometric re-entry works only while the app process still holds a previously
validated device session. After an app restart, enter the device credentials
again; they are not saved to local preferences.
