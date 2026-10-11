import base64
import json
import threading
import unittest
from http.server import ThreadingHTTPServer
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from simulator.model import SimulatorState
from simulator.server import make_handler


class ServerTests(unittest.TestCase):
    def setUp(self):
        self.state = SimulatorState()
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(self.state, "demo", "demo"))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base = f"http://127.0.0.1:{self.server.server_port}"

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def request(self, path, method="GET", body=None, authorization=None):
        headers = {}
        if authorization is None:
            authorization = "Basic " + base64.b64encode(b"demo:demo").decode("ascii")
        if authorization:
            headers["Authorization"] = authorization
        if body is not None:
            headers["Content-Type"] = "application/json"
            if not isinstance(body, bytes):
                body = json.dumps(body).encode()
        request = Request(self.base + path, data=body, headers=headers, method=method)
        try:
            response = urlopen(request, timeout=2)
        except HTTPError as error:
            response = error
        with response:
            data = response.read()
            return response.status, response.headers, json.loads(data) if data and response.headers.get_content_type() == "application/json" else data

    def test_state_and_settings_routes_return_documented_fields(self):
        status, _, state = self.request("/api/state")
        self.assertEqual(status, 200)
        self.assertTrue({
            "temperature_c", "chamber_temp_c", "mq135_v", "mq2_v",
            "pm1_0_ug_m3", "pm2_5_ug_m3", "pm10_ug_m3",
            "threshold_chamber_temp_c", "threshold_mq2_v", "fan_on",
            "sprinkler_on", "pump_on", "manual_sprinkler", "active_triggers",
            "mq2_response_ratio", "mq135_response_ratio", "mq2_calibration_id",
            "mq135_calibration_id", "mq2_calibration_status", "mq135_calibration_status",
            "mq2_threshold_mode", "mq2_safety_mode", "threshold_mq2_response_ratio",
        }.issubset(state))
        status, _, settings = self.request("/api/settings")
        self.assertEqual(status, 200)
        self.assertEqual(settings, {"threshold_chamber_temp_c": 80.0, "threshold_mq2_v": 2.5})

    def test_control_and_both_threshold_routes_apply_valid_writes(self):
        status, _, body = self.request("/api/control", "POST", {"sprinkler": True})
        self.assertEqual((status, body), (200, {"status": "ok"}))
        self.assertTrue(self.state.snapshot()["manual_sprinkler"])
        for route, field, value in (
            ("/api/thresholds", "threshold_chamber_temp_c", 120),
            ("/api/settings", "threshold_mq2_v", 3.0),
        ):
            status, _, body = self.request(route, "POST", {field: value})
            self.assertEqual((status, body), (200, {"status": "ok"}))
        self.assertEqual(self.request("/api/settings")[2], {
            "threshold_chamber_temp_c": 120.0, "threshold_mq2_v": 3.0,
        })

    def test_missing_and_malformed_basic_auth_return_challenge(self):
        malformed = ["", "Bearer token", "Basic !!!", "Basic " + base64.b64encode(b"nocolon").decode(),
                     "Basic " + base64.b64encode(b"demo:wrong").decode()]
        for authorization in malformed:
            with self.subTest(authorization=authorization):
                status, headers, _ = self.request("/api/state", authorization=authorization)
                self.assertEqual(status, 401)
                self.assertEqual(headers["WWW-Authenticate"], 'Basic realm="Login Required"')

    def test_non_ascii_basic_auth_returns_401_and_configured_credentials_work(self):
        bad = "Basic " + base64.b64encode("démo:demo".encode()).decode()
        status, headers, _ = self.request("/api/state", authorization=bad)
        self.assertEqual(status, 401)
        self.assertEqual(headers["WWW-Authenticate"], 'Basic realm="Login Required"')

        with ThreadingHTTPServer(("127.0.0.1", 0), make_handler(self.state, "démo", "secret")) as server:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                auth = "Basic " + base64.b64encode("démo:secret".encode()).decode()
                request = Request(f"http://127.0.0.1:{server.server_port}/api/state", headers={"Authorization": auth})
                with urlopen(request, timeout=2) as response:
                    self.assertEqual(response.status, 200)
            finally:
                server.shutdown()
                thread.join()

    def test_boolean_threshold_is_rejected_atomically(self):
        status, _, _ = self.request("/api/thresholds", "POST", {
            "threshold_chamber_temp_c": True, "threshold_mq2_v": 3,
        })
        self.assertEqual(status, 400)
        self.assertEqual(self.request("/api/settings")[2], {
            "threshold_chamber_temp_c": 80.0, "threshold_mq2_v": 2.5,
        })

    def test_malformed_json_and_oversized_body_leave_control_unchanged(self):
        for body in (b"{bad", b" " * 257):
            with self.subTest(body=body[:10]):
                status, _, _ = self.request("/api/control", "POST", body)
                self.assertEqual(status, 400)
                self.assertFalse(self.state.snapshot()["manual_sprinkler"])

    def test_rejected_threshold_body_does_not_mutate_settings(self):
        for body in (b"{bad", b" " * 257, [], {}, {"threshold_mq2_v": 9}):
            with self.subTest(body=body):
                status, _, _ = self.request("/api/settings", "POST", body)
                self.assertEqual(status, 400)
                self.assertEqual(self.request("/api/settings")[2]["threshold_mq2_v"], 2.5)

    def test_non_boolean_control_is_rejected(self):
        for body in ({"sprinkler": 1}, {}, [], {"sprinkler": None}):
            with self.subTest(body=body):
                self.assertEqual(self.request("/api/control", "POST", body)[0], 400)
                self.assertFalse(self.state.snapshot()["sprinkler_on"])

    def test_safety_block_returns_conflict(self):
        self.state.select_scenario("heat")
        status, _, body = self.request("/api/control", "POST", {"sprinkler": False})
        self.assertEqual(status, 409)
        self.assertEqual(body["status"], "error")
        self.assertTrue(self.state.snapshot()["sprinkler_on"])

    def test_offline_requires_auth_then_returns_503(self):
        self.state.select_scenario("offline")
        status, headers, _ = self.request("/api/state", authorization="")
        self.assertEqual(status, 401)
        self.assertEqual(headers["WWW-Authenticate"], 'Basic realm="Login Required"')
        self.assertEqual(self.request("/api/state")[0], 503)
        self.assertEqual(self.request("/api/control", "POST", {"sprinkler": True})[0], 503)
        self.assertFalse(self.state.snapshot()["manual_sprinkler"])

    def test_unknown_route_returns_404(self):
        self.assertEqual(self.request("/api/missing")[0], 404)


if __name__ == "__main__":
    unittest.main()
