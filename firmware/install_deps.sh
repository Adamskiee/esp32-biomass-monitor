#!/bin/bash
set -e
# Install core and library dependencies for the firmware

if ! command -v arduino-cli &> /dev/null; then
    echo "Error: arduino-cli is not installed or not in PATH."
    exit 1
fi

if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is not installed or not in PATH."
    exit 1
fi

# Install ESP32 Core
arduino-cli core update-index --additional-urls https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
arduino-cli core install esp32:esp32@3.0.4 --additional-urls https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json

# Install required libraries
arduino-cli lib install "Adafruit PM25 AQI Sensor@2.0.0" "DHT sensor library@1.4.7" "Adafruit Unified Sensor" "MAX6675 library@1.1.2" "ArduinoJson" "Async TCP" "ESP Async WebServer"

# Setup Secrets.h if it does not exist
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
if [ ! -f "$SCRIPT_DIR/main/Secrets.h" ] && [ -f "$SCRIPT_DIR/main/Secrets.h.example" ]; then
    cp "$SCRIPT_DIR/main/Secrets.h.example" "$SCRIPT_DIR/main/Secrets.h"
    echo "Created Secrets.h from example"
fi

# Symlink the shared BiomassConfig library to the Arduino sketchbook
SOURCE_DIR="$SCRIPT_DIR/shared/BiomassConfig"

if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source library directory not found at $SOURCE_DIR"
    exit 1
fi

# Parse sketchbook dir using Python to avoid brittle grep/sed
SKETCHBOOK_DIR=$(arduino-cli config dump --format json 2>/dev/null | python3 -c "import sys, json; print((json.load(sys.stdin).get('directories') or {}).get('user', ''))" 2>/dev/null || true)

if [ -z "$SKETCHBOOK_DIR" ]; then
    if [ "$(uname -s)" = "Darwin" ]; then
        SKETCHBOOK_DIR="$HOME/Documents/Arduino"
    else
        SKETCHBOOK_DIR="$HOME/Arduino"
    fi
    echo "Could not parse sketchbook from config. Using default: $SKETCHBOOK_DIR"
fi

DEST="$SKETCHBOOK_DIR/libraries/BiomassConfig"

echo "Symlinking BiomassConfig to $DEST..."
mkdir -p "$SKETCHBOOK_DIR/libraries"

# If destination exists and is a real directory (not a symlink), remove it safely
if [ -d "$DEST" ] && [ ! -L "$DEST" ]; then
    echo "Removing existing non-symlink library directory..."
    rm -rf "$DEST"
fi

ln -sfn "$SOURCE_DIR" "$DEST"
echo "Done."
