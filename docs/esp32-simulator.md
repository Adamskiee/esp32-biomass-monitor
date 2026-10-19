# ESP32 simulator

## Why use it?

The simulator lets the Flutter app connect to a local ESP32-style API when no
board is available. It exercises the app's existing login, polling, alerts,
sprinkler controls, and threshold settings. Its readings and relay states are
simulated; they do not prove physical sensor, pump, or water-flow behavior.

## How do I start it?

Install Python 3.10 or newer. From the repository root, run:

```bash
python3 -m simulator
```

The default address is `127.0.0.1:8765`, and the username and password are
both `demo`. The simulator prints its address and available terminal commands.
Stop it with `quit` or an end-of-input signal. State lives in memory and returns
to defaults when the process starts again.

For computer-only use, you can change the port or credentials:

```bash
python3 -m simulator --port 8766 --user local --password secret
```

This still listens on `127.0.0.1`, which a physical phone cannot reach.
Use the network listener below when connecting a phone.

## How do I connect an Android emulator?

1. Start the simulator on the computer running the Android emulator.
2. Enter `10.0.2.2:8765` as the ESP32 address in the app. The emulator uses
   `10.0.2.2` to reach the host computer's loopback listener.
3. Log in with `demo` / `demo` and open Control, then Emergency Control & Local Alerts.

## How do I connect a physical phone?

The default listener accepts connections from the computer only. For a phone
on the same trusted Wi-Fi network, run this from the repository root and keep
the terminal open:

```bash
python3 -m simulator --host 0.0.0.0 --port 8765
```

Find the computer's Wi-Fi IPv4 address. On Linux, `ip -4 addr` lists it beside
the active Wi-Fi interface. For example, if the address is `192.168.1.50`,
enter **`192.168.1.50:8765`** in the app and log in with `demo` / `demo`.
Enter only the address and port, without `http://` or `/api`. Use the port
printed by the simulator if you changed `--port`.

`127.0.0.1` refers to the phone itself, and `10.0.2.2` works only inside the
Android emulator. `0.0.0.0` is the server's bind address, not the address to
enter in the app. Binding to it makes the simulator reachable on the local
network. Use it only on a trusted network because Basic authentication travels
over plain HTTP.

## Which scenarios can I show?

Type one command into the simulator terminal while the app is open:

| Command | Expected app result |
| --- | --- |
| `normal` | Readings near 25 °C ambient, 50% humidity, 45 °C chamber, 1.2 V MQ135, and 1.0 V MQ2. Temperature and gas readings change slightly on each poll so charts grow. Alerts depend on configured limits. |
| `gas` | MQ2 rises to 2.8 V. After warm-up, `high_mq2_gas` appears with the default 2.5 V limit. The sprinkler stays under manual control. |
| `heat` | Chamber temperature rises to 100 °C. With the default 80 °C limit, `high_chamber_temp` forces the sprinkler on and blocks manual control. |
| `temp-fault` | Chamber temperature becomes unavailable. If `heat` was active immediately before it, a catastrophic latch keeps the sprinkler on until `reset`. |
| `mq2-fault` | MQ2 becomes unavailable and `mq2_sensor_fault` appears after warm-up. |
| `offline` | Authenticated requests return 503 and the app shows its disconnected state. The simulator retains readings and settings. |
| `warmup` | Restart the five-minute MQ-135 and MQ-2 warm-up countdown without changing the selected scenario. |
| `status` | Print the selected scenario. |
| `reset` | Restore `normal`, clear safety latches, reading overrides, and manual control, restore all nine default thresholds, and start the five-minute MQ warm-up countdown. |
| `help` | Print available commands. |
| `quit` | Stop the server. |

Every online scenario also returns stable PMS telemetry: PM1.0 is 8 µg/m³,
PM2.5 is 12 µg/m³, and PM10 is 18 µg/m³. Each snapshot simulates a fresh
PMS frame unless a test explicitly overrides a particulate reading. These
readings activate alerts when they cross their configured limits.

`pump_on` represents the commanded pump relay and changes immediately when a
manual or safety sprinkler request is accepted. It does not confirm pump
operation or water flow.

All nine threshold fields follow the firmware's validation and recovery rules.
MQ2 uses its saved limit; a reading above 4.8 V reports a fault instead of a new
threshold crossing. Defaults are 80 °C chamber, 2.5 V MQ-2, 2 V MQ-135,
35 °C ambient, 15 µg/m³ PM1.0, 15 µg/m³ PM2.5, 45 µg/m³ PM10, and
30–60% humidity. These are project alert settings; see the
[API reference](api.md) for their rationale and limitations. Either humidity
boundary can be updated while minimum remains below maximum. Thresholds and
latches are never persisted to disk.
The simulator starts with, and `reset` simulates, an ESP32
restart. During the first five minutes, `mq_warming_up` is `true`,
`mq_warmup_remaining_seconds` counts down from 300, both MQ readings are
`null`, and both MQ gas and fault triggers are suppressed. This lets the app show
the same warm-up state it receives from firmware.

Upper-limit alerts activate at equality. Chamber, MQ, and particulate alerts
clear at 95% of their limits. Ambient temperature clears at its limit minus
the larger of 0.5 °C or 5% of the absolute limit. Humidity alerts activate
strictly outside the configured range and clear inside it by the smaller of
two percentage points or one quarter of the range width.

Changed limits immediately reevaluate cached readings, clearing the affected
threshold latch first when its reading is valid. Environmental faults clear
their threshold alerts. Chamber and MQ2 faults preserve existing danger;
a chamber fault during danger also sets the catastrophic latch until reset.
Only chamber protection can take pump ownership from manual control.

## How do I check the API?

With the simulator running, request state from another terminal:

```bash
curl --user demo:demo http://127.0.0.1:8765/api/state
```

The response includes humidity and particulate values alongside all saved limits:

```json
{
  "humidity_percent": 50.0,
  "pm1_0_ug_m3": 8,
  "pm2_5_ug_m3": 12,
  "pm10_ug_m3": 18
}
```

Configure humidity and particulate alerts together:

```bash
curl --user demo:demo http://127.0.0.1:8765/api/thresholds \
  -H 'Content-Type: application/json' \
  -d '{"threshold_humidity_min_percent":30,"threshold_humidity_max_percent":70,"threshold_pm2_5_ug_m3":50}'
```

Both `/api/thresholds` and `/api/settings` accept nonempty partial updates and
return `{"status":"ok","thresholds":{...}}` with all nine accepted values.
Unknown fields, booleans, non-finite numbers, and invalid ranges return 400
without changing any settings. These routes accept up to 1024 body bytes;
`/api/control` accepts up to 256. Oversized bodies return 413.
`GET /api/settings` returns all nine limits without advancing telemetry drift.

See the [API reference](api.md) for request bodies, response fields, and
threshold ranges. Run the simulator tests with:

```bash
python3 -m unittest discover -s simulator/tests -v
```

Run the shared firmware API checks against an isolated simulator you started.
Write checks temporarily change limits and restore the original configuration:

```bash
BIOMASS_TEST_BASE_URL=http://127.0.0.1:8765 \
BIOMASS_TEST_USER=demo BIOMASS_TEST_PASSWORD=demo \
BIOMASS_TEST_ALLOW_WRITES=1 BIOMASS_TEST_DISPOSABLE=1 \
python3 firmware/tests/safety_api_contract.py
```

## How do I inject exact readings in a test?

Use `SimulatorState(clock=...)` and `set_readings()` from Python to exercise
boundary conditions without waiting for drift or warm-up. Keys use the same
canonical sensor names as `/api/state`. Values accept numbers or `None` for
faults; non-finite readings are also reported as faults. Overrides stay fixed
until replaced, reset, or an online scenario is selected. Unspecified readings
retain normal scenario behavior, and `offline` retains the current inputs.

```python
from simulator.model import SimulatorState

now = 0.0
state = SimulatorState(clock=lambda: now)
now = 300.0
state.update_thresholds({
    "threshold_humidity_min_percent": 30,
    "threshold_humidity_max_percent": 70,
})
state.set_readings({"humidity_percent": 29})
sample = state.snapshot()
assert "low_humidity" in sample["active_triggers"]
assert sample["pump_on"] is False

state.set_readings({"pm2_5_ug_m3": 20})
now += 10.001
sample = state.snapshot()
assert "pms_sensor_fault" in sample["active_triggers"]
assert sample["pm2_5_ug_m3"] is None
```

Once any PMS reading is overridden, only another PMS override refreshes its
sample timestamp. Polling, settings changes, and other sensor overrides do not
refresh it. After more than ten seconds without a fresh sample, all three PMS readings
become `null` and one `pms_sensor_fault` appears. A missing channel also faults
the whole PMS sample. Use `thresholds_snapshot()` to inspect configuration
without advancing the injected clock or telemetry.

## What if the app cannot connect?

- First open `http://<computer-ip>:8765/api/state` in the phone's browser,
  replacing `<computer-ip>` with the computer's Wi-Fi IPv4 address. A login
  prompt followed by JSON confirms the phone can reach the simulator. Use the
  same address and credentials in the app.
- If the phone's browser cannot connect, confirm the simulator printed
  `http://0.0.0.0:8765/api`, the phone and computer use the same Wi-Fi network,
  and the computer's firewall allows inbound TCP traffic on port `8765`.
  Guest Wi-Fi or client isolation can also block devices on the same network.
- A `401` response means the username or password does not match the
  simulator's startup credentials. Check any `--user` or `--password` options.
- A connection refusal usually means the simulator is stopped or the address
  or port is wrong. A listener bound to `127.0.0.1` also refuses connections
  through the computer's Wi-Fi address.
- A `503` response is expected after selecting `offline`. Enter `normal` or
  another scenario to reconnect.
- If startup says the port is already in use, stop the other listener or set
  another port with `--port` and use that same port in the app.
