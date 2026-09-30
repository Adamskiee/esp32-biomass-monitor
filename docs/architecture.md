# System architecture

## What owns the safety state?

The ESP32 firmware is the source of truth for sensor readings, actuator state,
and safety triggers. Its polling loop reads the thermocouple, MQ2, MQ135, and
temperature sensors, caches their values under a mutex, evaluates sprinkler
safety, and drives the fan, status LEDs, and buzzer. The HTTP server reads this
state and accepts bounded, authenticated control requests. The Flutter app
shows reported state and cannot override automatic sprinkler safety.

## How does the firmware respond to readings?

- Chamber temperature at or above its configured threshold activates the
  sprinkler. It releases after the temperature falls below 95% of the threshold.
- If the thermocouple fails during a temperature alarm, a catastrophic latch
  holds the sprinkler on until the ESP32 restarts.
- An MQ2 reading at or above 2.5 V raises a gas trigger but does not
  automatically open the sprinkler. Only `NaN` readings and readings above
  4.8 V raise an MQ2 fault. A 0 V reading is valid.
- The fan runs from startup. The status LED starts yellow until the first
  sensor evaluation, then shows danger, fault, or safe state. The buzzer sounds
  for a valid chamber reading
  above the temperature threshold.
- A manual sprinkler request is accepted only while temperature safety and the
  catastrophic latch are inactive. The API reports the actual output state.

MQ135 is included in telemetry but does not currently trigger automatic
actuation. The fan output is an on/off relay; variable PWM speed is not
implemented.

## How are settings and network access handled?

The adjustable chamber-temperature limit ranges from 20 to 150 °C. The API
continues to accept and store its legacy MQ2 threshold field for compatibility,
but gas safety uses the fixed 2.5 V threshold. Accepted settings changes are
saved to nonvolatile storage at most once per 60 seconds to limit flash wear.
The firmware connects to the Wi-Fi credentials compiled into `Secrets.h` and
serves a local HTTP API with Basic authentication. It has no cloud sync,
offline telemetry buffer, access point provisioning, secure boot setup, or
over-the-air update flow in this repository.

See [the API reference](api.md) for request and response examples and
[the operations guide](operations-guide.md) for commissioning.
