# Contributing Guide

Welcome to the Biomass IoT Project! We appreciate your contributions to the firmware, hardware designs, and mobile app.

## 1. Development Workflow
To ensure consistency across environments, we enforce strict dependency versioning.

### Local Setup (Firmware)
You **must** run the provided setup script before opening the project in the Arduino IDE or compiling via CLI. This script symlinks the internal `BiomassConfig` library and installs the exact versions of external dependencies required by `sketch.yaml`.

- **Linux/macOS:** `./firmware/install_deps.sh`
- **Windows:** `.\firmware\install_deps.bat`

## 2. AI Agents & Pull Request Conventions
This project utilizes AI agents (like Claude or Gemini) to assist with coding and reviews. Therefore, strict conventions must be followed by both human and AI contributors.

### Pull Request Rules (from `AGENTS.md`)
1. **Title:** Must use Conventional Commits format (e.g., `feat:`, `fix:`, `chore:`). The entire title must be strictly under 72 characters. If introducing a breaking change, append an `!` (e.g., `feat!:`).
2. **Description:** Must directly expand on the exact change mentioned in the title.
3. **Unrelated Changes:** Do NOT mix unrelated changes into one PR.
4. **Context & Verification:** Include linked issue numbers if applicable. If you cannot verify the code yourself on real hardware, explicitly state that it is unverified and provide a proposed manual testing plan.
5. **Breaking Changes:** If the title contains an `!`, the description MUST include a footer starting with `BREAKING CHANGE:` followed by an explanation.

## 3. Testing

- **Firmware Unit Tests:** Run `./firmware/tests/run_native_tests.sh` on Linux or macOS with `g++` installed. These tests cover host-compatible safety and actuator logic without introducing a second embedded toolchain.
- **Firmware Compile:** Run `arduino-cli compile --fqbn esp32:esp32:esp32 --warnings all --library firmware/shared/BiomassConfig firmware/main/main.ino` to compile the production sketch.
- **Hardware-in-the-Loop (HIL):** Final verification of sensor reading logic must be done on physical ESP32 hardware using serial output. Provide serial output logs in your PR if applicable.
- **Mobile App:** Run `flutter test` in the `/mobileapp` directory to execute unit and widget tests before submitting UI changes.

## 4. Code Style & Debugging
- **C++ (Firmware):** Follow standard Arduino C++ conventions. Do not use blocking delays (`delay()`) inside FreeRTOS tasks. Always use non-blocking `vTaskDelay()` or hardware timers.
- **FreeRTOS Debugging:** If the ESP32 crashes with a `Guru Meditation Error`, use the ESP32 Exception Decoder tool to interpret the backtrace from the serial logs. Ensure all FreeRTOS Mutexes (`xSemaphoreTake`) are released (`xSemaphoreGive`) properly to prevent deadlocks.
- **Dart (Mobile App):** Follow the standard `flutter analyze` linter rules.
