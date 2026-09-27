# System Architecture

## 1. Hardware Architecture
The core of the Biomass IoT Monitor is the ESP32 microcontroller, chosen for its built-in WiFi, dual-core processing, and robust FreeRTOS support. 

### Sensors (Inputs)
- **MQ135 (Air Quality):** Analog voltage input.
- **MQ2 (Smoke & Combustible Gas):** Analog voltage input.
- **Internal Temperature:** Board-level thermal monitoring.
- **Thermocouple:** Measures internal chamber temperature (Celsius).

### Actuators (Outputs)
- **Filtration Fan:** Relay-driven active ventilation and smoke filtration.
- **Status LED (RGB):** Visual system state indicator.
- **Buzzer:** Audible overheat alarm.

## 2. Software Architecture
The firmware utilizes FreeRTOS to manage concurrent tasks efficiently.

- **Control Loop:** Hardware sensors are polled every `POLL_INTERVAL_MS`. 
- **State Management:** Hardware readings are safely cached into global state variables, protected by a FreeRTOS mutex (`stateMutex`). This non-blocking architecture allows the API server to rapidly serve data to the visualization dashboard without delaying the hardware control loop.

## 3. Safety Logic & State Recovery
The system evaluates sensor data continuously against safety thresholds.

### Danger State (Active Filtration)
Triggered when Chamber Temperature exceeds `safe_chamber_limit`.
- **Action:** Filtration Fan ON, LED RED.

### Hardware Fault State (Fail-Safe)
Triggered on sensor failure (e.g., MQ2 voltage < 0.1V, or `NaN` temperature readings).
- **Action:** Filtration Fan ON, LED YELLOW.

### Safe State
Triggered when no Danger or Fault conditions are met.
- **Action:** Filtration Fan ON (baseline ventilation), LED GREEN.

### Power-Loss State Recovery
If the ESP32 suffers a power loss or brownout during a Danger state, upon reboot, the system will initialize in a Fail-Safe mode (Filtration Fan ON) until the first successful sensor polling cycle completes, ensuring the environment is not left unventilated.

## 4. Data Persistence
Dynamic safety limits (e.g., `safe_chamber_limit`) can be updated remotely. To prevent flash memory wear, changes are saved to the ESP32's Non-Volatile Storage (NVS) with a hard rate limit (maximum once per 60 seconds).

## 5. Network Resilience & Offline Behavior
The monitor operates in potentially unstable field environments.
- **Offline Data Buffering:** Telemetry data is buffered in a local flash ring buffer when WiFi connectivity is lost.
- **Reconnection Synchronization:** Once connectivity is restored, the buffered historical data is transmitted to the backend asynchronously to prevent data loss.

## 6. Security, Connectivity & Edge/Cloud Boundary
- **Edge/Cloud Boundary:** The system operates in a hybrid model. It can function purely at the Edge (Local Station mode) using the Mobile App for local dashboarding via direct HTTP requests. It can also securely transmit telemetry to a central Cloud backend for fleet-wide monitoring.
- **API Authentication:** Communication between the Mobile App and the ESP32 is secured via token-based API authentication.

## 7. Hardware-Level Security
To protect devices deployed in the field from physical tampering and IP theft:
- **Secure Boot:** Enforced to ensure only signed, verified firmware images can be executed. This prevents malicious actors from flashing rogue firmware via the physical UART pins.
- **Flash Encryption:** NVS and application partitions are encrypted. This protects sensitive WiFi credentials, API tokens, and operational thresholds from being dumped.

## 8. Over-The-Air (OTA) Updates
Field updates are handled securely via OTA functionality.
- **Dual-Partition Architecture:** The ESP32 uses an OTA-0 and OTA-1 partition layout. Updates are downloaded in the background to the inactive partition.
- **Rollback Mechanism:** If a newly booted firmware fails health checks (e.g., crashes repeatedly), the ESP32 automatically rolls back to the previous stable partition.
- **Signature Verification:** All OTA update binaries must be cryptographically signed. The bootloader rejects any unsigned or improperly signed binaries.
