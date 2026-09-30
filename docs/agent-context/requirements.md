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
*   **Water Sprinkler Solenoid:** Opens automatically during a chamber-temperature danger and supports authenticated manual control while no automatic safety override is active.

## 3. Core Control Loop & State Management
The system operates on a continuous, non-blocking evaluation loop.

*   **Polling Interval:** Hardware sensors are read every `POLL_INTERVAL_MS`.
*   **Concurrency & Data Access:** Hardware readings are safely cached into global state variables, protected by a FreeRTOS mutex (`stateMutex`). This allows the API server to serve data to the visualization dashboard rapidly without blocking the hardware control loop.
*   **Threshold Persistence:** Dynamic safety limits (`safe_chamber_limit`, `safe_mq2_limit`) can be updated. To prevent flash memory wear, changes to these thresholds are saved to Non-Volatile Storage (NVS) with a hard rate limit of at most once every 60 seconds.

## 4. Safety Rules & Automation Logic
The core responsibility of the system is evaluating sensor data against safety thresholds and triggering the appropriate actuators.

### 4.1 Danger State (Active Filtration)
The system enters an active filtration and danger state if the following threshold condition is met:
1.  **Temperature Threshold:** Chamber Temperature exceeds `safe_chamber_limit`.

**Actions taken when in this state:**
*   Filtration Fan is turned **ON**.
*   Status LED is set to **RED**.
*   Water Sprinkler Solenoid is turned **ON** immediately, bypassing command debounce.

The temperature danger uses 5% hysteresis. After entering danger, it remains
active until the chamber temperature falls to or below 95% of
`safe_chamber_limit`.

If the thermocouple fails while temperature danger is active, the system sets
a catastrophic fire latch. The sprinkler remains on until the ESP32 restarts;
remote manual commands cannot clear this latch.

### 4.2 Gas Alert State
The system reports an active gas alert when MQ2 voltage reaches
`safe_mq2_limit`. The alert clears when voltage falls to or below 95% of that
limit. Gas alerts do not automatically open the water sprinkler.

### 4.3 Hardware Fault State
The system enters a hardware fault state if **ANY** of the following conditions are met, ensuring fail-safe filtration:
1.  **Sensor Fault (Thermocouple):** Chamber Temperature reads `NaN`.
2.  **Sensor Fault (MQ2):** MQ2 voltage reads `NaN`.
3.  **Sensor Disconnect (MQ2):** MQ2 voltage reads `< 0.1V`.

**Actions taken when in this state:**
*   Filtration Fan is turned **ON**.
*   Status LED is set to **YELLOW**.

### 4.4 Safe State
If **NONE** of the conditions in Sections 4.1 through 4.3 are met, the system is in a safe state.

**Actions taken when in this state:**
*   Filtration Fan is turned **ON** (providing continuous baseline ventilation).
*   Status LED is set to **GREEN**.

### 4.5 Overheat Alarm (Buzzer)
The audible alarm operates on an independent rule focused strictly on overheating.
*   **Condition:** The buzzer activates ONLY if the Chamber Temperature is a valid number AND strictly exceeds the `safe_chamber_limit`.
*   *(Note: The buzzer does not sound for MQ2 gas thresholds or sensor disconnects).*
