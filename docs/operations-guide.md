# Deployment, Maintenance & Operations Guide

This guide is intended for hardware engineers and field technicians responsible for installing, commissioning, and maintaining the Biomass IoT Monitor.

## 1. Hardware Setup & Assembly
1. **PCB Assembly:** Follow the provided hardware schematics in `/hardware/schematics.pdf` (or equivalent) to populate the custom PCB. Ensure buck converters are tuned to output exactly 5V and 3.3V before connecting the ESP32 or sensors to avoid over-voltage damage.
2. **Sensor Wiring:**
   - Connect the MQ135 and MQ2 analog outputs through the required voltage dividers before routing them to ESP32 pins 34 and 35.
   - Connect the K-Type Thermocouple to the MAX6675 amplifier module, ensuring correct polarity.
3. **Actuator Wiring:** Connect the 12V PWM/MOSFET controller for the fan and the independent Buzzer module.

## 2. Device Commissioning Workflow
When deploying a newly flashed board to the field:
1. **Power On:** Apply 12V DC power. The unprovisioned ESP32 will boot into Access Point (AP) mode.
2. **Mobile Pairing:** Use the Biomass Companion App to connect to the ESP32's AP (e.g., `Biomass-Monitor-XXXX`).
3. **Inject Credentials:** Through the app's "Local Setup" flow, inject the target facility's WiFi credentials and the Cloud API authentication token.
4. **Reboot:** The device will automatically reboot into Station Mode and connect to the facility's WiFi. Verify it appears on the Cloud dashboard.

## 3. Field Deployment Considerations
- **Environmental Protection:** The ESP32 and logic boards must be housed in an IP65-rated weatherproof enclosure. 
- **Thermal Isolation:** The electronics enclosure must be physically isolated from the biomass burning chamber to prevent thermal damage. The thermocouple wire is the only component designed to withstand chamber temperatures.
- **Gas Sensor Placement:** The MQ2 and MQ135 sensors must be exposed to the exhaust/smoke path but protected from direct rain or extreme heat.

## 4. Calibration & Maintenance
- **Pre-Heating:** MQ sensors require a 24-48 hour "burn-in" or pre-heating period when brand new to stabilize their chemical elements. 
- **Routine Calibration:** Calibrate BOTH the MQ135 and MQ2 sensors in clean air by updating their respective baseline `R0` values via the Mobile App settings once a month to prevent chemical drift.
- **Cleaning:** Inspect the fan intake and sensor mesh covers weekly for soot buildup. Use compressed air to clean them.

## 5. Over-The-Air (OTA) Updates
Field updates are pushed securely to devices without physical intervention.
1. System administrators upload a signed firmware binary (`.bin`) to the Cloud backend.
2. The backend signals the target device.
3. The device downloads the binary to its inactive OTA partition in the background (non-blocking).
4. Upon successful download and signature verification, the device reboots into the new firmware. 
5. If the new firmware crashes repeatedly, it will automatically roll back to the previous partition.

## 6. Troubleshooting & Disaster Recovery

| Symptom | Probable Cause | Resolution |
| :--- | :--- | :--- |
| **Green LED (Safe State) with low fan speed** | Normal operation. | The system is operating normally. The fan runs at 25% (PWM) to provide continuous baseline ventilation. This is NOT a fan malfunction. |
| **Yellow LED (Fault State)** | Sensor failure or disconnected wire. | Check serial logs or dashboard to identify the failed sensor. Re-seat wire connections or replace the sensor. The system will continue to ventilate at 100% until resolved. |
| **System resets continuously** | Power brownout during WiFi transmission. | Ensure the 12V power supply is rated for at least 3A. The ESP32 draws significant current spikes during WiFi transmission. |
| **Red LED (Danger) stuck on** | System is actively detecting a hazardous environment. | Verify dashboard telemetry. If temperature, MQ2 (Smoke), OR MQ135 (Air Quality) exceeds their respective thresholds, the system is operating correctly in Active Filtration mode (100% Fan). |
| **Buzzer sounding continuously** | Catastrophic chamber overheat. | The chamber temperature has exceeded the maximum safety limit. Wait for the active filtration fan to cool the chamber. **Note:** The buzzer strictly indicates thermal danger, not gas limits. |
| **Device cannot connect to WiFi** | Changed credentials or corrupted NVS. | Perform a physical Factory Reset (see below). |

**⚠️ Critical Warning - Offline Data Volatility:**
If a device has lost WiFi connectivity, it buffers telemetry in volatile RAM. **Do NOT power cycle the device** to attempt a reboot if you need to recover this data. A power loss before the WiFi connection is restored will permanently destroy all buffered offline telemetry.

### Physical Factory Reset
If a device is completely inaccessible or its NVS is corrupted (e.g., bad WiFi credentials), perform a physical wipe:
1. Press and hold the physical `RESET_CFG` button (Pin 0 / BOOT button) on the ESP32 for **10 seconds** while the device is powered on.
2. The RGB LED will flash Blue rapidly, indicating NVS has been wiped.
3. The device will reboot into AP mode, ready for Re-Commissioning (Section 2).
