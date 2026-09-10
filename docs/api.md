# ESP32 API Documentation

## 1. Overview & Connection

### Authentication
An `Authorization: Basic <base64(user:pass)>` header must be sent manually with all requests. A `401 Unauthorized` response will include the standard `WWW-Authenticate: Basic realm="Login Required"` header.
*Note:* Route resolution happens *before* authentication. If you query a mistyped endpoint (e.g., `/api/statee`) without authentication, the server will return a `404 Not Found` rather than a `401 Unauthorized`.

### CORS & Preflight
The API has full CORS support:
- `OPTIONS` preflight requests bypass authentication and return `200 OK` automatically.
- The ESP32 provides `Access-Control-Allow-Origin` (echoing the request Origin), `Access-Control-Allow-Methods: GET, POST, OPTIONS`, and `Access-Control-Allow-Headers: Authorization, Content-Type`.
- **Crucially:** It explicitly sets `Access-Control-Allow-Credentials: true`.

### SPA UX Warning (Credentials)
When fetching manually with the `Authorization` header, ensure you use `credentials: 'omit'` (or the default). If you use `credentials: 'include'`, a `401 Unauthorized` response will cause the browser to trigger its unstylable native OS login modal, hijacking your custom SPA UI flow.

### Network Discovery
The ESP32 IP must be manually discovered via your router or serial output (mDNS is not currently supported).

### HTTPS Limitations (Mixed Content)
The ESP32 serves via plain HTTP. Frontends hosted on HTTPS will face Mixed Content blocks from browsers. Local development must be HTTP, or a proxy must be used in production.

### Connection Limits & Polling
Avoid aggressive concurrent polling (e.g., using `Promise.all`). Poll sequentially (e.g., every 1-2 seconds) to avoid `503 Server Busy` errors caused by hardware lock contention.

---

## 2. Endpoints

### `GET /api/state`
Returns the current sensor readings.
- **Success (200 OK):** Returns `Content-Type: application/json`.
  - Example: `{"temperature_c": 25.5, "chamber_temp_c": 120.0, "mq135_v": 2.1, "mq2_v": 1.5}`
  - Note: Disconnected or failed sensors return `null` instead of a float value.

### `GET /api/settings`
Returns the current active threshold settings.
- **Success (200 OK):** Returns `Content-Type: application/json`.
  - Example: `{"threshold_chamber_temp_c": 130.0, "threshold_mq2_v": 2.5}`

### `POST /api/settings`
Updates the active threshold settings.
- **Headers Recommended:** `Content-Type: application/json` *(Note: The firmware does not actually enforce this header).*
- **Request Body:** JSON object. Partial updates are allowed.
  - `threshold_chamber_temp_c` (range: 20.0 - 150.0)
  - `threshold_mq2_v` (range: 0.1 - 5.0)
  - *Note:* The firmware gracefully coerces strings like `"120.5"` to floats, but strict JSON Numbers are recommended.
  - *Warning (Silent Success):* If you send an invalid JSON type (e.g., a JSON Array `[...]` or a raw string instead of a JSON Object), the firmware will silently fail to parse the keys but will still return a misleading **`200 OK {"status":"success"}`** without updating any state.
- **Transactionality:** The payload is processed as an "all-or-nothing" transaction. If one field is valid and another is out-of-range, the *entire* request is rejected.
- **Payload Constraints & TCP Fragmentation Warning:** 
  The JSON body MUST be <= 256 bytes. The ESP32 firmware does not buffer TCP streams and will reject *any* fragmented payload. While massive browser headers can push the request over the TCP MTU limit, be aware that intermediaries (like Ngrok, Vite dev servers, or load balancers) may also arbitrarily repackage and chunk the HTTP stream. If the JSON body is fragmented for *any* reason, the ESP32 will return a `400 Bad Request`.
- **Success (200 OK):** Returns `Content-Type: application/json` with `{"status":"success"}`.
  - *Note:* The newly merged state is NOT returned. To avoid triggering a 503 lock contention, frontends should apply optimistic local state updates rather than immediately issuing a subsequent GET request.

---

## 3. Error Handling

- **401 Unauthorized:** Invalid or missing Basic Auth. Returns a `text/plain` body "Unauthorized" with the `WWW-Authenticate` header.
- **404 Not Found:** Invalid endpoint. Returns a `text/plain` body "Not Found".
- **400 Bad Request:** 
  - Empty payloads return `{"status":"error","message":"Empty payload"}`. 
  - All other errors (invalid JSON, payload > 256 bytes, values out of range, or **fragmented payloads**) return a hardcoded catch-all: `{"status":"error", "message":"Invalid JSON, Payload Exceeds 256 bytes, or Invalid Values"}`.
- **503 Server Busy:** The system state is locked. Returns `Content-Type: application/json` with `{"status":"error", "message":"Server busy"}`.
