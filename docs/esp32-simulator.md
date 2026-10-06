# ESP32 simulator

## Why use it?

The simulator lets the Flutter app connect to a local ESP32-style API when no
board is available. It exercises the app's existing login, polling, alerts,
sprinkler controls, and threshold settings. Its readings and relay states are
simulated; they do not prove physical sensor, pump, or valve behavior.

## How do I start it?

Install Python 3.10 or newer. From the repository root, run:

```bash
python3 -m simulator
```

The default address is `127.0.0.1:8765`, and the username and password are
both `demo`. The simulator prints its address and available terminal commands.
Stop it with `quit` or an end-of-input signal. State lives in memory and returns
to defaults when the process starts again.

Use these options if you need a different listener or credentials:

```bash
python3 -m simulator --host 127.0.0.1 --port 8766 --user local --password secret
```

## How do I connect the app?

1. Start the simulator on the computer running the Android emulator.
2. Enter `10.0.2.2:8765` as the ESP32 address in the app. The emulator uses
   `10.0.2.2` to reach the host computer's loopback listener.
3. Log in with `demo` / `demo` and open the dashboard.

For a physical phone on the same trusted Wi-Fi network, start the simulator
with `python3 -m simulator --host 0.0.0.0`. Enter the computer's local IP
address followed by `:8765` in the app, such as `192.168.1.50:8765`. Allow
inbound traffic to that port in the computer's firewall if needed. Binding to
`0.0.0.0` makes the simulator reachable from the local network, so use it only
on a trusted network. Basic authentication travels over plain HTTP.

## Which scenarios can I show?

Type one command into the simulator terminal while the app is open:

| Command | Expected app result |
| --- | --- |
| `normal` | Safe readings near 25 °C ambient, 45 °C chamber, 1.2 V MQ135, and 1.0 V MQ2. Readings change slightly on each poll so charts grow. |
| `gas` | MQ2 rises to 2.8 V and `high_mq2_gas` appears. The sprinkler stays under manual control. |
| `heat` | Chamber temperature rises to 100 °C. `high_chamber_temp` forces the sprinkler on and blocks manual control. |
| `temp-fault` | Chamber temperature becomes unavailable. If `heat` was active immediately before it, a catastrophic latch keeps the sprinkler on until `reset`. |
| `mq2-fault` | MQ2 becomes unavailable and `mq2_sensor_fault` appears. |
| `offline` | Authenticated requests return 503 and the app shows its disconnected state. The simulator retains readings and settings. |
| `status` | Print the selected scenario. |
| `reset` | Restore `normal`, clear safety latches and manual control, and restore 80.0 °C and 2.5 V thresholds. |
| `help` | Print available commands. |
| `quit` | Stop the server. |

The sprinkler state represents the commanded valve relay. The pump starts
500 ms after the valve is commanded on. During shutdown, the pump turns off
first and the valve closes 500 ms later. The app may briefly show different
sprinkler and pump states during those transitions.

The stored MQ2 threshold can be edited and displayed, but the gas alarm still
uses a fixed 2.5 V trigger, matching the firmware. Thresholds and latches are
not persisted. `reset` simulates a device restart.

## How do I check the API?

With the simulator running, request state from another terminal:

```bash
curl --user demo:demo http://127.0.0.1:8765/api/state
```

See the [API reference](api.md) for request bodies, response fields, and
threshold ranges. Run the simulator tests with:

```bash
python3 -m unittest discover -s simulator/tests -v
```

## What if the app cannot connect?

- A `401` response means the username or password does not match the
  simulator's startup credentials. Check any `--user` or `--password` options.
- A connection refusal usually means the simulator is stopped or the address
  or port is wrong. Use `10.0.2.2` for the Android emulator, or the computer's
  local IP for a physical phone.
- If a phone times out, check that the phone and computer share a network,
  the server was started with `--host 0.0.0.0`, and the firewall allows the port.
- A `503` response is expected after selecting `offline`. Enter `normal` or
  another scenario to reconnect.
- If startup says the port is already in use, stop the other listener or set
  another port with `--port` and use that same port in the app.
