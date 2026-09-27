# Mobile Application Guide

## 1. Architecture & Tech Stack
The Biomass IoT Mobile Application serves as the primary user interface for field operators and stakeholders to monitor the system, configure safety thresholds, and receive alerts.

- **Framework:** Flutter (Dart) for cross-platform support (iOS & Android).
- **State Management:** Provider/Riverpod.
- **Networking:** `http` package for REST API communication.
- **Security:** Token-based API authentication for cloud interactions; direct HTTP for local edge provisioning.

## 2. Build & Deployment
To build the application locally, ensure you have the Flutter SDK installed.

### Local Development
1. Navigate to the mobile app directory:
   ```bash
   cd mobileapp
   ```
2. Fetch dependencies:
   ```bash
   flutter pub get
   ```
3. Run the app on an emulator or connected device:
   ```bash
   flutter run
   ```

### Production Build
- **Android:** `flutter build apk --release` (or `appbundle` for Play Store).
- **iOS:** `flutter build ipa` (requires Xcode and an Apple Developer account).

## 3. UI/UX Workflows

### Device Commissioning (Local Provisioning)
When deploying a fresh ESP32 board in the field:
1. The ESP32 boots in Access Point (AP) mode.
2. The user connects their mobile device to the ESP32's WiFi network (e.g., `Biomass-Monitor-XXXX`).
3. Inside the app, navigate to **"Add Device"** -> **"Local Setup"**.
4. The app communicates directly with the ESP32 via its local IP (usually `192.168.4.1`) to securely inject the facility's target WiFi credentials and backend API tokens.
5. The ESP32 restarts in Station mode, and the app connects back to the facility network to verify the device is online.

### Dashboard & Telemetry
The main dashboard displays real-time data from the selected device:
- **Status Indicator:** Shows the current system state (Safe, Danger, Fault) matching the physical LED on the device.
- **Overheat Alarm (Buzzer):** A critical, distinct visual alert (e.g., flashing banner) appears if the independent thermal overheat alarm is triggered, decoupled from standard gas danger warnings.
- **Sensor Readings:** Live feeds of Chamber Temperature, MQ2 (Smoke), and MQ135 (Air Quality).
- **Fan Status:** Current duty cycle of the PWM Filtration Fan.
- **Offline / Sync Status:** Indicates if the device is currently buffering data locally due to a WiFi drop. **⚠️ Warning:** Do NOT instruct field operators to power-cycle a disconnected device to 'fix' its connection. Buffered telemetry is stored in volatile RAM and will be permanently destroyed upon power loss.

### Remote Configuration & Calibration
Administrators and field technicians can adjust dynamic safety thresholds and calibration data remotely:
1. Navigate to **"Device Settings"**.
2. **Safety Thresholds:** Modify `safe_chamber_limit`, `safe_mq2_limit`, or `safe_mq135_limit` to adjust when the Danger state triggers.
3. **Sensor Calibration:** Modify `mq135_r0` and `mq2_r0` during routine monthly maintenance to recalibrate the sensors in clean air.
4. Changes are sent via the Cloud backend (or locally via HTTP) to the ESP32, which saves them to NVS (subject to the 60-second hardware rate limit).
