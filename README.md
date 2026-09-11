# Biomass IoT Project

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
