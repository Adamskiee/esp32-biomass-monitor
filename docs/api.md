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
The mobile dashboard uses the IP of the node selected in the app.

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
  "pm1_ug_m3": 10,
  "pm25_ug_m3": 20,
  "pm10_ug_m3": 30,
  "chamber_temp_c": 120.0,
  "mq135_v": 2.1,
  "mq2_v": 1.5,
  "threshold_chamber_temp_c": 130.0,
  "threshold_mq2_v": 2.5,
  "fan_on": true,
  "sprinkler_on": true,
  "pump_on": false,
  "manual_sprinkler": false,
  "active_triggers": []
}
```

`sprinkler_on` reports the commanded solenoid relay output and `pump_on`
reports the commanded pump relay output. They can temporarily differ during
the 500 ms startup and shutdown sequence. The example above shows startup:
the valve is commanded on while the pump is still off. Neither field confirms
that the valve moved, the pump ran, or water flowed.

Sensor reads represented internally as `NaN` are returned as `null`. A missing
DHT-22 makes both temperature and `humidity_percent` null. A missing PMS5003
makes all three PM fields null. PM values use PMS5003 environmental mass
concentrations in µg/m³. MQ2
readings from 0.0 V through 2.4 V are safe. Readings at or above 2.5 V add the
`high_mq2_gas` trigger, while only `NaN` values and values above 4.8 V add the
`mq2_sensor_fault` trigger. `active_triggers` can contain:

- `high_chamber_temp`
- `high_mq2_gas`
- `temp_sensor_fault`
- `mq2_sensor_fault`
- `catastrophic_latch`

## Control the sprinkler

### `POST /api/control`

Requests manual sprinkler state while automatic temperature safety is inactive:

```json
{"sprinkler": true}
```

The field must be a JSON boolean. A successful request returns:

```json
{"status":"ok"}
```

When temperature safety or the catastrophic latch owns the sprinkler, the API
returns `409 Conflict`. The catastrophic latch remains active until the ESP32
restarts.

## Update thresholds

### `POST /api/thresholds`

Updates the chamber-temperature threshold and, for API compatibility, the
stored MQ2 threshold value:

```json
{
  "threshold_chamber_temp_c": 120.0,
  "threshold_mq2_v": 2.0
}
```

- `threshold_chamber_temp_c`: JSON number from 20.0 through 150.0.
- `threshold_mq2_v`: JSON number from 0.1 through 5.0. This legacy field is
  stored and returned, but does not change the fixed 2.5 V MQ2 gas threshold.
- At least one field is required.
- The JSON body must not exceed 256 bytes.
- Validation is transactional. If either field is invalid, neither changes.
- Accepted changes take effect immediately and are persisted to non-volatile
  storage at most once every 60 seconds.

Success returns `200 OK` with `{"status":"ok"}`. Invalid payloads return
`400 Bad Request`.

## Compatibility settings endpoints

### `GET /api/settings`

Returns the two current threshold values using the same names as
`POST /api/thresholds`.

### `POST /api/settings`

Supports existing clients that update thresholds through the original route.
It uses the same buffered JSON parsing, 256-byte limit, and validation as
`/api/thresholds`. New clients should use `/api/thresholds`.

## Error responses

- `400 Bad Request`: Malformed JSON, wrong field type, missing fields, or values
  outside the documented range.
- `401 Unauthorized`: Missing or invalid Basic Auth credentials.
- `404 Not Found`: Unknown route.
- `409 Conflict`: Manual sprinkler control is blocked by automatic safety.
- `503 Server Busy`: The state mutex was unavailable within the request timeout.
