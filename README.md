# Biomass IoT Project

The project monitors a biomass burning chamber and controls its filtration,
alarm, and sprinkler hardware. The ESP32 firmware is developed and uploaded
with Arduino IDE. Arduino CLI provides the same dependency installation and
compile checks for continuous integration.

## Dependencies

This project uses an Arduino CLI `sketch.yaml` file for strict dependency version pinning. 

To build locally with Arduino CLI or the Arduino IDE, you **must** first run the provided script to install dependencies and symlink the shared configuration library (`BiomassConfig`) into your local sketchbook.

**On Linux/macOS:**
```bash
./firmware/install_deps.sh
```

**On Windows:**
Double-click `firmware\install_deps.bat` or run it from the command prompt:
```cmd
.\firmware\install_deps.bat
```

**⚠️ Important Notes:**
- **Arduino IDE Users:** Running `install_deps.sh` is mandatory even if you manually install the third-party libraries, as it symlinks the internal `BiomassConfig` library required by both the main firmware and the test sketches.
- **Multiple Clones/Branches:** The `install_deps.sh` script creates a global symlink in your `~/Arduino/libraries/` folder pointing to this specific directory. If you clone this repository multiple times or rename the directory, you must re-run `install_deps.sh` in the active repository so the IDE compiles against the correct configuration.

## Arduino IDE workflow

1. Run the dependency installer for your operating system.
2. Open `firmware/main/main.ino` in Arduino IDE.
3. Select the ESP32 board and port.
4. Compile and upload the sketch.
5. Open Serial Monitor at 115200 baud to confirm the device IP and sensor readings.

The mobile app uses the selected node's IP address. Configure that address in
the app after reading it from Serial Monitor or your router. The firmware does
not advertise an `esp32.local` mDNS hostname.

## Verification

Compile the production firmware with the same ESP32 core used by continuous
integration:

```bash
arduino-cli compile \
  --fqbn esp32:esp32:esp32 \
  --warnings all \
  --library firmware/shared/BiomassConfig \
  firmware/main/main.ino
```

Run the optional native safety tests on Linux or macOS when `g++` is available:

```bash
./firmware/tests/run_native_tests.sh
```

These tests exercise control logic without replacing Arduino IDE or compiling
the hardware-dependent API server for the host computer.
