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
3. Log in with `demo` / `demo` and open the dashboard.

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

Every online scenario also returns stable PMS telemetry: PM1.0 is 8 µg/m³,
PM2.5 is 12 µg/m³, and PM10 is 18 µg/m³. These values exercise the same
device-state fields as the firmware without affecting simulated safety rules.

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

The response includes particulate values alongside the existing telemetry:

```json
{
  "pm1_0_ug_m3": 8,
  "pm2_5_ug_m3": 12,
  "pm10_ug_m3": 18
}
```

See the [API reference](api.md) for request bodies, response fields, and
threshold ranges. Run the simulator tests with:

```bash
python3 -m unittest discover -s simulator/tests -v
```

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
