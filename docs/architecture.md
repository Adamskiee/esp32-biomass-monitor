# System Architecture

## 1. Hardware Architecture
The core of the Biomass IoT Monitor is the ESP32 microcontroller, chosen for its built-in WiFi, dual-core processing, and robust FreeRTOS support. 

### Sensors (Inputs)
- **MQ135 (Air Quality):** Analog voltage input (Pin 34). Operates on 5V logic (requires voltage divider for ESP32 3.3V ADC).
- **MQ2 (Smoke & Combustible Gas):** Analog voltage input (Pin 35). Operates on 5V logic (requires voltage divider).
- **Internal Temperature:** Board-level thermal monitoring.
- **Thermocouple:** K-Type thermocouple via MAX6675 amplifier. SPI Interface (SCK: Pin 18, CS: Pin 5, SO: Pin 19).

### Actuators (Outputs)
- **Filtration Fan:** 12V DC Fan driven by a MOSFET/PWM controller (Control Pin: 25). This allows variable speed control for baseline vs. active filtration.
- **Status LED (RGB):** Visual system state indicator (R: Pin 2, G: Pin 4, B: Pin 16).
- **Buzzer:** Audible overheat alarm (Pin 17). Operates independently based on thermal logic.

### Power Requirements
- **Input Power:** 12V DC Supply.
- **ESP32 & Logic:** Stepped down to 5V (for MQ sensors/fan controller) and 3.3V (for ESP32 and MAX6675) via buck converters.

## 2. Software Architecture
The firmware utilizes FreeRTOS to manage concurrent tasks efficiently.

- **Control Loop:** Hardware sensors are polled every `POLL_INTERVAL_MS`. 
- **State Management:** Hardware readings are safely cached into global state variables, protected by a FreeRTOS mutex (`stateMutex`). This non-blocking architecture allows the API server to rapidly serve data to the visualization dashboard without delaying the hardware control loop.

## 3. Safety Logic & State Recovery
The system evaluates sensor data continuously against safety thresholds.

### Danger State (Active Filtration)
Triggered when ANY of the following are true:
1. Chamber Temperature > `safe_chamber_limit`
2. MQ2 Voltage > `safe_mq2_limit`
3. MQ135 Voltage > `safe_mq135_limit`
- **Action:** Filtration Fan ON at 100% duty cycle (PWM), LED RED.

### Hardware Fault State (Fail-Safe)
Triggered on sensor failure (e.g., MQ2 voltage < 0.1V, or `NaN` temperature readings).
- **Action:** Filtration Fan ON at 100% duty cycle (PWM), LED YELLOW.

### Safe State
Triggered when no Danger or Fault conditions are met.
- **Action:** Filtration Fan ON at 25% duty cycle (PWM) for continuous baseline ventilation, LED GREEN.

### State Priority & Overlap
If conditions for multiple states are met simultaneously (e.g., a high MQ2 reading triggers Danger, but a melted thermocouple triggers a Fault), **Hardware Fault State takes absolute precedence**. If any critical sensor fails, the system state is considered unreliable, and the system defaults to Fault State (LED YELLOW) to alert operators, while maintaining fail-safe 100% filtration.

### Overheat Alarm (Buzzer)
The buzzer operates on a strict, independent rule focused entirely on catastrophic overheating.
- **Action:** Buzzer sounds ONLY if the Chamber Temperature is a valid number (not `NaN`) AND strictly exceeds the `safe_chamber_limit`. It does not trigger for gas thresholds or sensor disconnects.

### Power-Loss State Recovery
If the ESP32 suffers a power loss or brownout during a Danger state, upon reboot, the system will initialize in a Fail-Safe mode (Filtration Fan 100%) until the first successful sensor polling cycle completes.

## 4. Data Persistence
Dynamic safety limits (e.g., `safe_chamber_limit`, `safe_mq2_limit`) can be updated remotely. To prevent flash memory wear, changes are saved to the ESP32's Non-Volatile Storage (NVS) with a hard rate limit (maximum once per 60 seconds).

## 5. Network Resilience & Offline Behavior
The monitor operates in potentially unstable field environments.
- **Offline Data Buffering:** Telemetry data is buffered in an in-memory (RAM/PSRAM) ring buffer when WiFi connectivity is lost, preventing internal flash memory wear-out.
- **Architectural Trade-off (Volatility Risk):** Because this buffer is stored in RAM, all buffered offline telemetry data will be permanently lost if the system experiences a power loss or brownout before the WiFi connection is restored and the data is synced.
- **Reconnection Synchronization:** Once connectivity is restored, the buffered historical data is transmitted to the backend asynchronously.

## 6. Security, Connectivity & Edge/Cloud Boundary
- **Edge/Cloud Boundary:** The system operates in a hybrid model. It can function purely at the Edge (Local Station mode) or transmit telemetry to a central Cloud backend for fleet-wide monitoring.
- **WiFi Provisioning:** A new unconfigured device starts in Access Point (AP) mode. Field operators connect to this AP via the Mobile App to securely inject local WiFi credentials, after which the device reboots into Station mode.
- **Data Encryption (In-Transit):** All communication between the ESP32 and the Cloud backend is encrypted using HTTPS/TLS 1.2 to prevent packet sniffing.
- **API Authentication:** Edge communication is secured via token-based API authentication.

## 7. Hardware-Level Security
- **Secure Boot:** Enforced to ensure only signed, verified firmware images can be executed.
- **Flash Encryption:** NVS and application partitions are encrypted. This protects sensitive WiFi credentials, API tokens, and operational thresholds from being dumped.

## 8. Over-The-Air (OTA) Updates
- **Dual-Partition Architecture:** The ESP32 uses an OTA-0 and OTA-1 partition layout. Updates download in the background.
- **Rollback Mechanism:** If a newly booted firmware fails health checks, the ESP32 automatically rolls back.
- **Signature Verification:** All OTA update binaries must be cryptographically signed.
