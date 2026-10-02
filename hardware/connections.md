# Wiring connections

## Relay control wiring

Power the 8-channel relay module from a regulated 5 V supply and connect its
ground to ESP32 ground. Its inputs must accept 3.3 V ESP32 logic. Inputs are
active-low: `LOW` energizes a relay and `HIGH` releases it.

| Relay channel | Load | ESP32 GPIO | Relay behavior |
|---|---|---:|---|
| 1 | Solenoid valve | GPIO 27 | Coordinated sprinkler output |
| 2 | Pump | GPIO 13 | Coordinated sprinkler output |
| 3 | Buzzer | GPIO 4 | Temperature alarm output |
| 4 | Fan | GPIO 26 | Always on after startup |
| 5 | Red status light | GPIO 25 | Temperature danger |
| 6 | Yellow status light | GPIO 33 | Sensor fault |
| 7 | Green status light | GPIO 14 | Safe state |
| 8 | Spare | None | Leave disconnected |

## 12 V load wiring

Use normally open relay contacts for every 12 V load so a loss of relay control
power leaves the load off. Feed the pump and solenoid from separate fused 12 V
branches sized from their measured running and startup current. Keep the ESP32
out of every 12 V load-current path. Fit correctly oriented flyback diodes or
other suitable suppression across inductive DC loads unless the load module
already provides it.
