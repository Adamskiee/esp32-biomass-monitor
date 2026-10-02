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

The dashboard also shows a read-only Pump Status indicator. It can briefly
differ from Sprinkler Status while the controller opens the valve before
starting the pump or stops the pump before closing the valve. The indicator
reports the commanded relay output, so it does not confirm that the pump ran or
that water flowed.

The main telemetry view shows no live readings while the ESP32 is disconnected.
It stores history only from successful responses and creates gas alerts from
firmware triggers. MQ sensor values are voltages; the app does not calculate a
certified air quality index or carbon monoxide concentration from them.

The safety dashboard sends threshold changes to `POST /api/thresholds`. The
firmware also accepts `/api/settings` for older clients, with the same
validation. See [the API reference](api.md) for ranges and examples.

## How do I check the app?

```bash
flutter analyze
flutter test
```

The app needs local network access to the device. This firmware connects to a
configured Wi-Fi network; it does not implement access point provisioning,
cloud telemetry, or over-the-air updates. Basic authentication travels over
plain HTTP, so use it only on a trusted local network.
The Android and iOS app configurations allow local HTTP access because the
device currently has no HTTPS endpoint.
Biometric re-entry works only while the app process still holds a previously
validated device session. After an app restart, enter the device credentials
again; they are not saved to local preferences.
