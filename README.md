# Biomass IoT Project

![Build Status](https://img.shields.io/badge/build-passing-brightgreen)
![License](https://img.shields.io/badge/license-MIT-blue)

![Hero Diagram Placeholder](docs/assets/hero-diagram.png "System Block Diagram")

## What problem does this system solve?

The Biomass Monitor and Filtration System is an ESP32-based environmental
monitor for controlled disposal of biodegradable waste. It monitors smoke,
combustible gases, and chamber temperature. The fan runs continuously while
firmware safety rules control alarms and a water sprinkler.

The companion Flutter app provides live telemetry, authenticated manual
sprinkler control, threshold configuration, and active danger alerts.

## What hardware is required?

- ESP32 development board
- MQ135 air-quality sensor
- MQ2 smoke and gas sensor
- K-type thermocouple
- Filtration fan and driver
- Water sprinkler solenoid and relay
- Status LEDs and buzzer

## How do I build and upload the firmware?

The normal firmware workflow uses Arduino IDE. The setup scripts install the
required dependencies and link the shared `BiomassConfig` library into the
Arduino sketchbook.

1. Install dependencies:

   - Linux or macOS: `./firmware/install_deps.sh`
   - Windows: `firmware\install_deps.bat`

2. Open `firmware/main/main.ino` in Arduino IDE.
3. Select the ESP32 board and serial port.
4. Compile and upload the sketch.
5. Open Serial Monitor at 115200 baud to find the device IP and confirm sensor
   readings.

The mobile app connects to one ESP32 IP address entered on the login screen.
The firmware does not advertise an `esp32.local` mDNS hostname.

To try the app without an ESP32, run the local API simulator. See the
[ESP32 simulator guide](docs/esp32-simulator.md) for setup and scenarios.

## How do I verify a change?

Arduino CLI provides the same production compile check used by continuous
integration:

```bash
arduino-cli compile \
  --fqbn esp32:esp32:esp32 \
  --warnings all \
  --library firmware/shared/BiomassConfig \
  firmware/main/main.ino
```

Run the native safety tests on Linux or macOS when `g++` is available:

```bash
./firmware/tests/run_native_tests.sh
```

The native tests exercise control logic without replacing Arduino IDE or
compiling hardware-dependent networking code for the host computer.

Run the Flutter checks from `mobileapp/`:

```bash
flutter analyze
flutter test
```

## Where is each component?

- `firmware/`: ESP32 firmware, hardware tests, and shared configuration
- `hardware/`: schematics, bill of materials, and physical design files
- `mobileapp/`: Flutter monitoring and control app
- `simulator/`: local API simulator for app development and demonstrations
- `docs/`: architecture, API, operations, and developer documentation

## Where can I learn more?

- [System Architecture](docs/architecture.md)
- [Operations Guide](docs/operations-guide.md)
- [Mobile Application](docs/mobile-app.md)
- [Developer Onboarding and Contributing](CONTRIBUTING.md)
- [API Reference](docs/api.md)
