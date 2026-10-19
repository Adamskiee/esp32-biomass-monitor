# ESP32 API

## Overview

The API exposes cached sensor readings, safety status, threshold updates, and
manual sprinkler control. The hardware loop owns automatic safety decisions;
API commands cannot disable a safety-forced sprinkler.

### Authentication

Every documented API request requires HTTP Basic authentication:

```text
Authorization: Basic <base64(user:password)>
```

Invalid or missing credentials return `401 Unauthorized` with
`WWW-Authenticate: Basic realm="Login Required"`.

### Device address

Use the ESP32 IP reported by Serial Monitor or your router:

```text
http://192.168.1.51/api
```

The firmware does not provide mDNS, so `http://esp32.local` is not supported.
The app uses its saved ESP32 address, including the port when connecting to the simulator.

### Transport security

The ESP32 serves plain HTTP. Basic authentication does not encrypt credentials,
so expose the API only on a trusted local network. HTTPS applications also
cannot call it directly because browsers block mixed content.

### Browser access and polling

The API does not enable cross-origin browser requests. Use the Flutter app or
another local HTTP client. This avoids granting arbitrary websites access to
credentialed device controls.

Poll sequentially every one to two seconds. Concurrent requests can receive
`503 Server Busy` while the state mutex is unavailable.

## Read system state

### `GET /api/state`

Returns cached readings and current safety outputs:

```json
{
  "temperature_c": 25.5,
  "humidity_percent": 54.5,
  "chamber_temp_c": 45.0,
  "mq135_v": null,
  "mq2_v": null,
  "mq_warming_up": true,
  "mq_warmup_remaining_seconds": 300,
  "pm1_0_ug_m3": 8,
  "pm2_5_ug_m3": 12,
  "pm10_ug_m3": 18,
  "threshold_chamber_temp_c": 130.0,
  "threshold_mq2_v": 2.5,
  "threshold_mq135_v": 2,
  "threshold_temperature_c": 35,
  "threshold_pm1_0_ug_m3": 15,
  "threshold_pm2_5_ug_m3": 15,
  "threshold_pm10_ug_m3": 45,
  "threshold_humidity_min_percent": 30,
  "threshold_humidity_max_percent": 60,
  "pump_on": false,
  "manual_sprinkler": false,
  "active_triggers": []
}
```

`pump_on` reports the commanded pump relay output immediately. It does not
confirm that the pump ran or that water flowed.

Non-finite sensor readings are returned as `null`. Ambient temperature outside
-40 to 80 °C, humidity outside 0 to 100%, and MQ-2 readings above the 4.8 V
rail-short boundary also return `null` and report their sensor fault. A missing
DHT-22 makes both temperature and `humidity_percent` null. After every ESP32
restart, MQ-135 and MQ-2 have a
five-minute heater warm-up. During warm-up, both MQ voltage fields are `null`,
`mq_warming_up` is `true`, and `mq_warmup_remaining_seconds` counts down from
300. Both MQ threshold alerts and sensor faults are suppressed during warm-up.
Chamber and other environmental protection continues. `active_triggers` can
contain:

- `high_chamber_temp`
- `high_mq2_gas`
- `high_mq135_gas`
- `high_ambient_temp`
- `high_pm1_0`, `high_pm2_5`, `high_pm10`
- `low_humidity`, `high_humidity`
- `temp_sensor_fault`
- `mq2_sensor_fault`
- `mq135_sensor_fault`
- `ambient_temp_sensor_fault`
- `humidity_sensor_fault`
- `pms_sensor_fault`
- `catastrophic_latch`

PMS5003 particulate readings report environmental PM1.0, PM2.5, and PM10 mass
concentrations in µg/m³. All three PMS fields are `null` before the first valid
frame and more than ten seconds after the most recent valid frame. A valid zero
is returned as `0`. Missing or stale PMS data produces one `pms_sensor_fault`.
Sensor faults are reported even when the sensor's threshold is unset.

Only chamber-temperature danger and `catastrophic_latch` force the sprinkler
on. Gas, ambient-temperature, particulate, and humidity conditions produce
alerts without taking control of the pump.

### When do threshold alerts recover?

Upper-limit alerts activate at or above the configured limit. Chamber, MQ-2,
MQ-135, and particulate alerts clear at or below 95% of that limit. Ambient
temperature clears at or below the limit minus the greater of 0.5 °C and 5%
of the limit's absolute value, including for zero and negative limits.

Humidity activates strictly below its minimum or strictly above its maximum.
Its recovery margin is the smaller of two percentage points and one quarter
of the range width. Low humidity clears at minimum plus that margin; high
humidity clears at maximum minus that margin, including equality. For 30–70%,
29% activates low humidity and 32% clears it; 71% activates high humidity and
68% clears it. Exactly 30% or 70% does not start an alert.

Invalid environmental readings clear that sensor's threshold latches and report
a fault. Chamber and MQ-2 retain their existing threshold latches on faults.
Losing a chamber reading during temperature danger activates the catastrophic
latch, which keeps the sprinkler on until restart.

## Control the sprinkler

### `POST /api/control`

Requests manual sprinkler state while automatic temperature safety is inactive:

```json
{"sprinkler": true}
```

The field must be a JSON boolean. The body limit remains 256 bytes.
A successful request returns:

```json
{"status":"ok"}
```

When temperature safety or the catastrophic latch owns the sprinkler, the API
returns `409 Conflict`. The catastrophic latch remains active until the ESP32
restarts.

## Update thresholds

### `POST /api/thresholds`

Updates any nonempty subset of the nine supported limits atomically:

```json
{
  "threshold_chamber_temp_c": 120.0,
  "threshold_mq2_v": 2.0,
  "threshold_humidity_min_percent": 30,
  "threshold_humidity_max_percent": 70
}
```

| Field | Accepted range | Initial value |
| --- | --- | --- |
| `threshold_chamber_temp_c` | 20 to 150 °C | Existing saved value, otherwise 80 |
| `threshold_mq2_v` | 0.1 to 5 V | Existing saved value, otherwise 2.5 |
| `threshold_mq135_v` | 0.1 to 5 V | 2 |
| `threshold_temperature_c` | -40 to 80 °C | 35 |
| `threshold_pm1_0_ug_m3` | Greater than 0, up to 65535 µg/m³ | 15 |
| `threshold_pm2_5_ug_m3` | Greater than 0, up to 65535 µg/m³ | 15 |
| `threshold_pm10_ug_m3` | Greater than 0, up to 65535 µg/m³ | 45 |
| `threshold_humidity_min_percent` | 0 to 100% | 30 |
| `threshold_humidity_max_percent` | 0 to 100%, strictly greater than minimum | 60 |

Ranges are inclusive unless stated otherwise. They are configuration bounds,
not health standards. MQ readings are volts, not calibrated gas concentrations.
MQ-2 now uses its saved limit. Its rail-short fault above 4.8 V takes precedence
over a gas alert, so limits above 4.8 V cannot produce a valid threshold crossing.

Every supplied value must be a finite JSON number. Booleans, strings, `null`,
unknown keys, non-object bodies, and empty objects are rejected. Absent fields
retain their saved values. Either humidity boundary can be edited independently;
the complete candidate must keep minimum strictly below maximum.
Any invalid field rejects the whole request without changing any limit.

The body must not exceed 1024 bytes. Accepted limits immediately reevaluate
cached valid readings, resetting changed-rule threshold latches first. Changing
configuration cannot clear the catastrophic latch. The full configuration is
saved as one versioned record in non-volatile storage at most once every 60
seconds. A successful response confirms in-memory acceptance; power loss before
the pending flash write may lose recent edits.

Every limit starts configured. At startup, existing valid saved values take
precedence; previously unset fields receive the defaults above. The migrated
configuration is queued for persistence using the same flash-write limit.
The API cannot clear a configured limit back to unset.

These are initial alert settings for surrounding-air monitoring, not certified
operating or exposure limits. Ambient temperature at 35 °C and PM1.0 at
15 µg/m³ are project choices. MQ-135 at 2 V and MQ-2 at 2.5 V are provisional
voltage settings that require calibration for the installed circuit and gases.
See the [Winsen MQ135 manual](https://www.winsen-sensor.com/manual/mq135.html).

The PM2.5 and PM10 numbers match the WHO 2021 24-hour guideline values of
15 and 45 µg/m³. Firmware applies them to live readings, so these alerts do not
assess a 24-hour average or WHO compliance. See the
[WHO guidelines](https://www.who.int/Publications/i/Item/9789240034228).
Humidity defaults to 30–60% for general moisture monitoring, informed by
[EPA guidance](https://www.epa.gov/indoor-air-quality-iaq/what-can-i-do-improve-indoor-air-quality-my-home)
to stay below 60%, ideally 30–50%. An open, humid installation may need a
different range. Only chamber protection controls automatic pump operation;
the existing 80 °C chamber setting is retained and requires site validation.

Success returns `200 OK` with the complete configuration accepted by that
request, even if another update follows immediately:

```json
{
  "status": "ok",
  "thresholds": {
    "threshold_chamber_temp_c": 120,
    "threshold_mq2_v": 2,
    "threshold_mq135_v": 2,
    "threshold_temperature_c": 35,
    "threshold_pm1_0_ug_m3": 15,
    "threshold_pm2_5_ug_m3": 15,
    "threshold_pm10_ug_m3": 45,
    "threshold_humidity_min_percent": 30,
    "threshold_humidity_max_percent": 70
  }
}
```

## Compatibility settings endpoints

### `GET /api/settings`

Returns a flat object containing all nine fields shown inside `thresholds`
above. There is no `status` or `thresholds` wrapper. `GET /api/state` includes
the same nine fields alongside telemetry. Current firmware reports numeric
limits after startup migration. Earlier firmware can report explicit `null`
for a supported but unset limit; a missing field means unsupported.

### `POST /api/settings`

Supports existing clients that update thresholds through the original route.
It uses the same buffered JSON parsing, 1024-byte limit, validation, and nested
success response as `/api/thresholds`. New clients should use `/api/thresholds`.

## Error responses

- `400 Bad Request`: Malformed JSON, wrong field type, missing or unknown
  fields, invalid humidity ordering, or values outside the documented range.
- `401 Unauthorized`: Missing or invalid Basic Auth credentials.
- `404 Not Found`: Unknown route.
- `409 Conflict`: Manual sprinkler control is blocked by automatic safety.
- `413 Content Too Large`: JSON body exceeds the route's byte limit.
- `503 Server Busy`: The state mutex was unavailable within the request timeout.

## How do I run contract checks safely?

Use Python 3.10 or newer and an isolated simulator from
[the simulator guide](esp32-simulator.md), or an explicitly authorized test
device. With the target running, this command performs only GET requests:

```bash
BIOMASS_TEST_BASE_URL=http://127.0.0.1:8765 \
BIOMASS_TEST_USER=demo BIOMASS_TEST_PASSWORD=demo \
python3 firmware/tests/safety_api_contract.py
```

Threshold-write checks require `BIOMASS_TEST_ALLOW_WRITES=1`. They capture
and restore the original configured limits and refuse to start if any limit
is unset or missing, because the production API cannot restore unset values.
On a disposable simulator only, add `BIOMASS_TEST_DISPOSABLE=1` to allow
configuration of those limits on older versions. Restart that simulator afterward
to recover its defaults. Current simulators start with all limits configured.
No test sends manual pump commands, but changing chamber limits
on a device can change automatic pump output. Keep other configuration writers
disconnected while testing so snapshot checks and restoration remain valid.

```bash
BIOMASS_TEST_BASE_URL=http://127.0.0.1:8765 \
BIOMASS_TEST_USER=demo BIOMASS_TEST_PASSWORD=demo \
BIOMASS_TEST_ALLOW_WRITES=1 BIOMASS_TEST_DISPOSABLE=1 \
python3 firmware/tests/safety_api_contract.py
```

Simulator results exercise a surrogate. They do not verify the actual Arduino
HTTP handlers, flash persistence, sensors, or relay behavior. A production
firmware build and a separately authorized device run are needed for those
integration checks.
