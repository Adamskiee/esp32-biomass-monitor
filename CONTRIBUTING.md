# Contributing to Biomass Monitor

Thank you for your interest in contributing to the ESP32 Biomass Monitor project!

## Getting Started

### 1. Firmware (ESP32)
We use `arduino-cli` for compilation.
1. Install [arduino-cli](https://arduino.github.io/arduino-cli/latest/installation/).
2. Run `./firmware/install_deps.sh` (or `.ps1` on Windows) to install required libraries and the `esp32:esp32` board core.
3. Code is located in `firmware/main/main.ino`.

### 2. Mobile App (Flutter)
1. Install [Flutter SDK](https://docs.flutter.dev/get-started/install).
2. Navigate to `mobileapp/` and run `flutter pub get`.
3. Start coding!

## Code Style & Linting

### Firmware
CI enforces formatting and static analysis. Before submitting, run:
```bash
# Format all firmware code (requires clang-format-14)
find firmware \( -iname '*.h' -o -iname '*.cpp' -o -iname '*.ino' \) -print0 | xargs -0 -r clang-format-14 -i

# Run static analysis (requires cppcheck)
find firmware \( -iname '*.cpp' -o -iname '*.h' \) -print0 | xargs -0 -r cppcheck --enable=warning,style,performance,portability --library=firmware/cppcheck.cfg --error-exitcode=1 -I firmware/main
```

### Mobile App
```bash
cd mobileapp
flutter analyze
flutter test
```

## Submitting a Pull Request
1. Branch off `main` for your work.
2. Ensure you have tested your code locally.
3. Open a Pull Request using the provided PR template.
4. Ensure the CI pipeline passes.
