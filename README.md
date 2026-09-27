# Biomass IoT Project

![Build Status](https://img.shields.io/badge/build-passing-brightgreen)
![License](https://img.shields.io/badge/license-MIT-blue)

![Hero Diagram Placeholder](docs/assets/hero-diagram.png "System Block Diagram")

## Project Overview & Business Context
The Biomass Monitor & Filtration System is an ESP32-based environmental monitor designed to mitigate emissions from the open burning of biodegradable waste (leaves, grass, branches). Open burning poses significant health and environmental risks. This system intelligently monitors smoke, combustible gases, and chamber temperatures, automatically triggering active filtration systems when safety thresholds are exceeded. 

By deploying these devices, we ensure environmental compliance at scale, reduce harmful particulate matter release, and provide real-time telemetry to stakeholders via our mobile companion app.

## Quick Start

### Hardware Requirements
- ESP32 Development Board
- MQ135 Air Quality Sensor
- MQ2 Smoke/Gas Sensor
- K-Type Thermocouple (for chamber temp)
- PWM/MOSFET-controlled Filtration Fan

### Firmware Flashing
This project uses an Arduino CLI `sketch.yaml` file for strict dependency version pinning. 

1. **Install Dependencies:**
   - **Linux/macOS:** Run `./firmware/install_deps.sh`
   - **Windows:** Run `.\firmware\install_deps.bat`
   
   *Note: This is mandatory to symlink the `BiomassConfig` library.*

2. **Build and Flash:**
   Use the Arduino IDE or CLI to build and flash the main sketch located in `firmware/src`.

### Mobile App
The mobile app enables dashboard integration and remote threshold configuration. 
Please refer to the [Mobile Application Guide](docs/mobile-app.md) for build and deployment instructions.

## Directory Structure
- `/firmware` - ESP32 C++ firmware, hardware control loops, and configuration.
- `/hardware` - Schematics, Bill of Materials (BOM), and PCB designs.
- `/mobileapp` - Flutter-based mobile dashboard for remote monitoring.
- `/docs` - System architecture, API references, operations, and developer guides.

## Documentation
For complete details on the system, please refer to our documentation:
- [System Architecture](docs/architecture.md) (Hardware/Software logic, Edge/Cloud, Security, OTA)
- [Operations Guide](docs/operations-guide.md) (Field Commissioning, Maintenance, Troubleshooting)
- [Mobile Application](docs/mobile-app.md)
- [Developer Onboarding & Contributing](CONTRIBUTING.md)
- [API Reference](docs/api.md)
