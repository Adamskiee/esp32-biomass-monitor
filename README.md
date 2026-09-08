# Biomass IoT Project

## Dependencies

This project uses an Arduino CLI `sketch.yaml` file for strict dependency version pinning. 

To build locally with Arduino CLI, first install the pinned dependencies:
```bash
arduino-cli core update-index --additional-urls https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
arduino-cli core install esp32:esp32@2.0.11 --additional-urls https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
arduino-cli lib install "Adafruit PM25 AQI Sensor@2.0.0" "DHT sensor library@1.4.7"
```

If using the Arduino IDE, please refer to the versions pinned in `firmware/sketch.yaml` and install them via the Library Manager.
