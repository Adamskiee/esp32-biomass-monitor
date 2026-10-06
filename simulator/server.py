import base64
import binascii
import hmac
import json
from http.server import BaseHTTPRequestHandler

from simulator.model import SafetyOverrideError, SimulatorState


def make_handler(state: SimulatorState, username: str, password: str) -> type[BaseHTTPRequestHandler]:
    expected = f"{username}:{password}"

    class SimulatorHandler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:
            if not self._authenticate():
                return
            if self.path not in ("/api/state", "/api/settings"):
                self._send_json(404, {"status": "error", "message": "Not found"})
                return
            if state.scenario == "offline":
                self._send_json(503, {"status": "error", "message": "Device offline"})
                return
            snapshot = state.snapshot()
            if self.path == "/api/state":
                self._send_json(200, snapshot)
            else:
                self._send_json(200, {
                    "threshold_chamber_temp_c": snapshot["threshold_chamber_temp_c"],
                    "threshold_mq2_v": snapshot["threshold_mq2_v"],
                })

        def do_POST(self) -> None:
            if not self._authenticate():
                return
            if self.path not in ("/api/control", "/api/thresholds", "/api/settings"):
                self._send_json(404, {"status": "error", "message": "Not found"})
                return
            if state.scenario == "offline":
                self._send_json(503, {"status": "error", "message": "Device offline"})
                return
            payload = self._read_payload()
            if payload is None:
                return
            try:
                if self.path == "/api/control":
                    if type(payload.get("sprinkler")) is not bool:
                        raise ValueError("sprinkler must be a boolean")
                    state.set_manual_sprinkler(payload["sprinkler"])
                else:
                    state.update_thresholds(payload)
            except SafetyOverrideError as error:
                self._send_json(409, {"status": "error", "message": str(error)})
                return
            except ValueError as error:
                self._send_json(400, {"status": "error", "message": str(error)})
                return
            self._send_json(200, {"status": "ok"})

        def _authenticate(self) -> bool:
            header = self.headers.get("Authorization", "")
            valid = False
            if header.startswith("Basic "):
                try:
                    credentials = base64.b64decode(header[6:], validate=True).decode("utf-8")
                    valid = hmac.compare_digest(credentials, expected)
                except (binascii.Error, UnicodeDecodeError, ValueError):
                    pass
            if not valid:
                self._send_json(
                    401, {"status": "error", "message": "Unauthorized"},
                    {"WWW-Authenticate": 'Basic realm="Login Required"'},
                )
            return valid

        def _read_payload(self) -> dict[str, object] | None:
            try:
                length = int(self.headers.get("Content-Length", ""))
            except ValueError:
                length = -1
            if length < 0 or length > 256:
                self._send_json(400, {"status": "error", "message": "Invalid body length"})
                return None
            raw = self.rfile.read(min(length, 257))
            try:
                payload = json.loads(raw)
            except (UnicodeDecodeError, json.JSONDecodeError):
                self._send_json(400, {"status": "error", "message": "Malformed JSON"})
                return None
            if not isinstance(payload, dict):
                self._send_json(400, {"status": "error", "message": "Expected a JSON object"})
                return None
            return payload

        def _send_json(self, status: int, value: dict[str, object], headers: dict[str, str] | None = None) -> None:
            body = json.dumps(value, separators=(",", ":")).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            for key, header_value in (headers or {}).items():
                self.send_header(key, header_value)
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format: str, *args: object) -> None:
            pass

    return SimulatorHandler
