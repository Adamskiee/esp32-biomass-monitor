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

## What should I check during operation?

- A green LED indicates the current readings are safe. The fan runs from
  startup, including in this state. The LED starts yellow until the first poll.
- A red LED indicates chamber temperature or MQ2 voltage above its limit.
  Check `active_triggers` and the measured values in the app.
- A yellow LED indicates an invalid thermocouple or MQ2 reading. Check sensor
  wiring and power. A thermocouple failure during a temperature alarm latches
  the sprinkler on until restart.
- The buzzer indicates a valid chamber reading above the configured limit.
- A rejected manual sprinkler command can mean automatic temperature safety
  is active. The app refreshes the reported output state after rejection.

Inspect the fan intake and sensor covers for soot. Confirm sensor behavior and
thresholds after maintenance. This repository does not implement mobile Wi-Fi
provisioning, factory reset through a button, cloud telemetry, or firmware
updates over the air; changing Wi-Fi credentials requires a new upload.
