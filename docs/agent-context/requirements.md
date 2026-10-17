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
*   **DHT-22:** Measures ambient temperature (Celsius) and relative humidity (percent).
*   **PMS5003:** Measures environmental PM1.0, PM2.5, and PM10 mass concentrations (µg/m³).

**Actuators (Outputs):**
*   **Status LED (RGB):** Visual system state indicator.
*   **Buzzer:** Audible overheat alarm.
*   **Water Sprinkler Pump:** Runs immediately during a chamber-temperature danger and supports authenticated manual control while no automatic safety override is active.

## 3. Core Control Loop & State Management
The system operates on a continuous, non-blocking evaluation loop.

*   **Polling Interval:** Hardware sensors are read every `POLL_INTERVAL_MS`.
*   **Concurrency & Data Access:** Hardware readings are safely cached into global state variables, protected by a FreeRTOS mutex (`stateMutex`). This allows the API server to serve data to the visualization dashboard rapidly without blocking the hardware control loop.
*   **Threshold Persistence:** Nine limits cover chamber temperature, MQ-2, MQ-135, ambient temperature, PM1.0, PM2.5, PM10, and humidity minimum/maximum. New optional limits begin unset; chamber and MQ-2 default to 80 C and 2.5 V. The validated record is saved atomically to NVS at most once every 60 seconds.
*   **Attempt recording:** The mobile app may record one connected local attempt at a time as with or without filtration. It persists readings locally and presents descriptive comparisons without a success verdict.

## 4. Safety Rules & Automation Logic
The core responsibility of the system is evaluating sensor data against safety thresholds and triggering the appropriate actuators.

### 4.1 Danger State
The system enters a danger state if the following threshold condition is met:
1.  **Temperature Threshold:** Chamber Temperature reaches or exceeds `safe_chamber_limit`.

**Actions taken when in this state:**
*   Status LED is set to **RED**.
*   Water Sprinkler Pump is turned **ON** immediately.

The temperature danger uses 5% hysteresis. After entering danger, it remains
active until the chamber temperature falls to or below 95% of
`safe_chamber_limit`.

If the thermocouple fails while temperature danger is active, the system sets
a catastrophic fire latch. The sprinkler remains on until the ESP32 restarts;
remote manual commands cannot clear this latch.

### 4.2 Configured environmental alerts
Upper limits activate at equality and humidity activates strictly outside its
configured range. Chamber, MQ-2, MQ-135, ambient, particulate, and humidity
conditions add named triggers and app alerts. Only chamber temperature opens
the sprinkler or activates the buzzer; other alerts do not change pump or LED
ownership.

### 4.3 Hardware Fault State
The system enters a hardware fault state if **ANY** of the following conditions are met, ensuring fail-safe filtration:
1.  **Sensor Fault (Thermocouple):** Chamber Temperature reads `NaN`.
2.  **Sensor Fault (MQ2):** MQ2 voltage reads `NaN`.
3.  **Sensor Rail Short (MQ2):** MQ2 voltage reads above `4.8V`.

**Actions taken when in this state:**
*   Status LED is set to **YELLOW**.

### 4.4 Safe State
If **NONE** of the conditions in Sections 4.1 through 4.3 are met, the system is in a safe state.

**Actions taken when in this state:**
*   Status LED is set to **GREEN**.

### 4.5 Overheat Alarm (Buzzer)
The audible alarm operates on an independent rule focused strictly on overheating.
*   **Condition:** The buzzer activates ONLY if the Chamber Temperature is a valid number AND strictly exceeds the `safe_chamber_limit`.
*   *(Note: The buzzer does not sound for MQ2 gas thresholds or sensor disconnects).*

## 5. Mobile safety configuration

The admin-only Emergency Control & Local Alerts section on Control embeds the
pump status, manual sprinkler switch, active conditions, and four threshold
groups directly. Temperature has chamber and ambient upper limits, Gas has
MQ-2 and MQ-135 upper limits, Particulate Matter has three upper limits, and
Humidity has minimum and maximum. Each reading displays its confirmed saved
limit, current value, and status; only chamber protection owns automatic outputs.

Drafts survive polling, scrolling, offline periods, and failed writes. Every
accepted observation refreshes saved settings independently of drafts. Apply
submits changed fields and clears edits only after all submitted fields are
confirmed by the device. Humidity validates against its latest saved partner.
Unsupported fields are individually disabled; supported null limits remain
editable. New MQ-2 limits cannot exceed 4.8 V, but an untouched legacy 5 V limit
does not block unrelated edits. Configured limits cannot be cleared.

Sensor faults take status priority; MQ warm-up instead shows a 300-second
countdown. A catastrophic latch remains visible and locks manual control even
with a chamber fault. Environmental alerts leave manual control enabled.
Offline readings are stale and controls are disabled until reconnecting.
The API remains authoritative if protection changes before a manual request.

All production pollers share ordered observation acceptance and persistent
activation keys. Ongoing conditions are recorded once across polls and restarts;
recovery allows a later activation. Fault warnings group by hardware sensor.
Muting sound cannot change device protection or local history. History requires
a running connected app; there is no push delivery or device history.
