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
  automatically open the sprinkler or change the green LED. Only `NaN`
  readings and readings above 4.8 V raise an MQ2 fault. A 0 V reading is
  valid.
- The fan runs from startup. The status LED starts yellow until the first
  sensor evaluation, then shows danger, fault, or safe state. The buzzer sounds
  for a valid chamber reading
  above the temperature threshold.
- A manual sprinkler request is accepted only while temperature safety and the
  catastrophic latch are inactive. The API reports the actual output state.

MQ135 is included in telemetry but does not currently trigger automatic
actuation. The fan output is an on/off relay; variable PWM speed is not
implemented.

The PMS5003 is also telemetry only. Each two-second poll attempts one validated
UART frame and records environmental PM1.0, PM2.5, and PM10 together. Invalid
or absent frames leave the previous sample unchanged, so the API reports it
until it ages out after ten seconds. PMS data never contributes to safety
triggers or actuator decisions.

## How are the valve and pump sequenced?

`Actuators` owns the requested sprinkler state and the commanded solenoid and
pump relay outputs. Every manual or automatic sprinkler decision requests that
coordinator, while the main loop advances its transition on every pass without
blocking sensor polling or HTTP handling.

For activation, it energizes the solenoid relay and waits at least 500 ms before
energizing the pump relay. For shutdown, it releases the pump relay and waits
at least 500 ms before releasing the solenoid relay. `sprinkler_on` and
`pump_on` report those commanded relay outputs, so they can differ during a
transition and do not verify valve movement or water flow.

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
