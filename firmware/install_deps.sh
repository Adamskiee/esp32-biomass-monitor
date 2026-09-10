#!/bin/bash
set -e
# Install core and library dependencies for the firmware

# Install ESP32 Core
arduino-cli core update-index --additional-urls https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
arduino-cli core install esp32:esp32@3.0.4 --additional-urls https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json

# Install required libraries
arduino-cli lib install "Adafruit PM25 AQI Sensor@2.0.0" "DHT sensor library@1.4.7" "Adafruit Unified Sensor" "MAX6675 library@1.1.2" "ArduinoJson" "Async TCP" "ESP Async WebServer"
