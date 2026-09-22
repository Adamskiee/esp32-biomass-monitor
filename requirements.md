# Biomass Monitor & Filtration System Requirements

## 1. System Overview & Purpose
**Context:** The open burning of biodegradable waste (leaves, grass, branches) creates significant air pollution and health risks. 
**Purpose:** This system acts as an intelligent environmental monitor and controller for a biomass burning chamber. It is designed to mitigate emissions by actively monitoring smoke/gas levels and triggering a filtration system when safety thresholds are exceeded, allowing for efficient waste disposal with reduced environmental impact.

## 2. Hardware Constraints & Interfaces
The system is built around an ESP32 microcontroller utilizing FreeRTOS.

**Sensors (Inputs):**
*   **MQ135:** Air quality sensor (Reads as Voltage).
*   **MQ2:** Smoke and combustible gas sensor (Reads as Voltage).
*   **Internal Temperature:** Board-level temperature monitoring (Celsius).
*   **Thermocouple:** Measures the internal chamber temperature where burning occurs (Celsius).

**Actuators (Outputs):**
*   **Filtration Fan:** Active ventilation and smoke filtration.
*   **Status LED (RGB):** Visual system state indicator.
*   **Buzzer:** Audible overheat alarm.

## 3. Core Control Loop & State Management
The system operates on a continuous, non-blocking evaluation loop.

*   **Polling Interval:** Hardware sensors are read every `POLL_INTERVAL_MS`.
*   **Concurrency & Data Access:** Hardware readings are safely cached into global state variables, protected by a FreeRTOS mutex (`stateMutex`). This allows the API server to serve data to the visualization dashboard rapidly without blocking the hardware control loop.
*   **Threshold Persistence:** Dynamic safety limits (`safe_chamber_limit`, `safe_mq2_limit`) can be updated. To prevent flash memory wear, changes to these thresholds are saved to Non-Volatile Storage (NVS) with a hard rate limit of at most once every 60 seconds.

## 4. Safety Rules & Automation Logic
The core responsibility of the system is evaluating sensor data against safety thresholds and triggering the appropriate actuators.

### 4.1 Fault & Filtration State (Fan & LED)
The system enters an active filtration and danger state if **ANY** of the following conditions are met:
1.  **Sensor Fault (Thermocouple):** Chamber Temperature reads `NaN`.
2.  **Sensor Fault (MQ2):** MQ2 voltage reads `NaN`.
3.  **Sensor Disconnect (MQ2):** MQ2 voltage reads `< 0.1V`.
4.  **Smoke/Gas Threshold:** MQ2 voltage exceeds `safe_mq2_limit`.
5.  **Temperature Threshold:** Chamber Temperature exceeds `safe_chamber_limit`.

**Actions taken when in this state:**
*   Filtration Fan is turned **ON**.
*   Status LED is set to **RED**.

### 4.2 Safe State
If **NONE** of the conditions in Section 4.1 are met, the system is in a safe state.

**Actions taken when in this state:**
*   Filtration Fan is turned **OFF**.
*   Status LED is set to **GREEN**.

### 4.3 Overheat Alarm (Buzzer)
The audible alarm operates on an independent rule focused strictly on overheating.
*   **Condition:** The buzzer activates ONLY if the Chamber Temperature is a valid number AND strictly exceeds the `safe_chamber_limit`.
*   *(Note: The buzzer does not sound for MQ2 gas thresholds or sensor disconnects).*
