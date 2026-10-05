# Operations guide

## How do I commission a device?

The firmware uses credentials compiled into the sketch, so configure the
device before installation. Run `./firmware/install_deps.sh` on Linux or macOS,
or `firmware\install_deps.bat` on Windows, to install the Arduino libraries and
link the shared `BiomassConfig` library. Then copy `firmware/main/Secrets.h.example` to
`firmware/main/Secrets.h`, set Wi-Fi and API credentials, and upload
`firmware/main/main.ino` with Arduino IDE. Select the correct ESP32 board and
port. Open Serial Monitor at 115200 baud to read the assigned IP address and
check sensor readings. Set that IP address for the node in the Flutter app.

Keep the ESP32 and electronics isolated from chamber heat. Use suitable voltage
dividers for analog sensor outputs, and verify actuator wiring against the
actual hardware before powering the device. The ESP32 serves Basic Auth over
plain HTTP, so keep it on a trusted local network and replace the example API
password.

## How do I commission the relay outputs?

1. Disconnect all 12 V loads. Power the ESP32 and relay module, then verify
   every relay is released at startup. Confirm `HIGH` releases a channel and
   `LOW` energizes it before connecting a load.
2. Confirm the seven assigned channels one at a time: solenoid GPIO 27, pump
   GPIO 13, buzzer GPIO 4, fan GPIO 26, red GPIO 25, yellow GPIO 33, and green
   GPIO 14. Keep channel 8 disconnected.
3. Connect the fan, lights, and buzzer, then verify their expected status
   behavior. Connect the solenoid and pump through their separate fused 12 V
   branches with the required inductive-load suppression.
4. Restart the ESP32 and verify that the normally open contacts leave all 12 V
   loads off until firmware commands them. Repeat after a relay-module power
   cycle.
5. Request the sprinkler with the loads connected. Verify the valve relay
   energizes at least 500 ms before the pump relay. Request shutdown and verify
   the pump relay releases at least 500 ms before the valve relay releases.

The API and Pump Status indicator report commanded relay outputs. They do not
confirm that the valve moved, the pump ran, or water flowed.

## What should I check during operation?

- A green LED indicates the current readings are safe. The fan runs from
  startup, including in this state. The LED starts yellow until the first poll.
- A red LED indicates chamber temperature at or above its configured limit.
  It also means the sprinkler has opened automatically. An MQ2 gas alert does
  not change the green LED or open the sprinkler. Check `active_triggers` and
  the measured values in the app.
- A yellow LED indicates an invalid thermocouple or MQ2 reading. MQ2 readings
  are invalid only when they are `NaN` or above 4.8 V. A 0 V MQ2 reading is
  valid. Check sensor wiring and power. A thermocouple failure during a
  temperature alarm latches the sprinkler on until restart.
- The buzzer indicates a valid chamber reading above the configured limit.
- A rejected manual sprinkler command can mean automatic temperature safety
  is active. The app refreshes the reported output state after rejection.

Inspect the fan intake and sensor covers for soot. Confirm sensor behavior and
thresholds after maintenance. This repository does not implement mobile Wi-Fi
provisioning, factory reset through a button, cloud telemetry, or firmware
updates over the air; changing Wi-Fi credentials requires a new upload.
