"""Run against an explicitly selected simulator or authorized test device.

Reads only unless BIOMASS_TEST_ALLOW_WRITES=1. See docs/api.md for setup.
"""

import base64
import json
import math
import os
import unittest
import urllib.error
import urllib.request


LIMITS = {
    "threshold_chamber_temp_c": (20, 150),
    "threshold_mq2_v": (0.1, 5),
    "threshold_mq135_v": (0.1, 5),
    "threshold_temperature_c": (-40, 80),
    "threshold_pm1_0_ug_m3": (0, 65535),
    "threshold_pm2_5_ug_m3": (0, 65535),
    "threshold_pm10_ug_m3": (0, 65535),
    "threshold_humidity_min_percent": (0, 100),
    "threshold_humidity_max_percent": (0, 100),
}
CONFIGURED = dict(zip(LIMITS, (80, 2.5, 2.0, 35, 25, 50, 100, 30, 70)))
ROUTES = ("/api/thresholds", "/api/settings")


class ApiContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.base_url = os.environ.get("BIOMASS_TEST_BASE_URL", "").rstrip("/")
        if not cls.base_url:
            raise unittest.SkipTest("Set BIOMASS_TEST_BASE_URL to select a test target")
        user = os.environ.get("BIOMASS_TEST_USER")
        password = os.environ.get("BIOMASS_TEST_PASSWORD")
        if user is None or password is None:
            raise RuntimeError("Set BIOMASS_TEST_USER and BIOMASS_TEST_PASSWORD")
        cls.authorization = "Basic " + base64.b64encode(
            f"{user}:{password}".encode()
        ).decode()

    @classmethod
    def request(cls, path, payload=None, *, raw=None, authenticated=True):
        if payload is not None:
            raw = json.dumps(payload, allow_nan=False).encode()
        headers = {"Content-Type": "application/json"}
        if authenticated:
            headers["Authorization"] = cls.authorization
        request = urllib.request.Request(cls.base_url + path, data=raw, headers=headers)
        try:
            response = urllib.request.urlopen(request, timeout=5)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            body = response.read().decode()
            try:
                body = json.loads(body)
            except json.JSONDecodeError:
                pass
            return response.status, body

    def settings(self):
        status, body = self.request("/api/settings")
        self.assertEqual(status, 200, body)
        return body

    def assert_thresholds(self, thresholds):
        self.assertEqual(set(thresholds), set(LIMITS))
        for field, (lower, upper) in LIMITS.items():
            value = thresholds[field]
            if value is None and field not in tuple(LIMITS)[:2]:
                continue
            self.assertIn(type(value), (int, float), field)
            self.assertTrue(math.isfinite(value), field)
            self.assertGreaterEqual(value, lower, field)
            self.assertLessEqual(value, upper, field)
            if field.startswith("threshold_pm"):
                self.assertGreater(value, 0, field)
        minimum = thresholds["threshold_humidity_min_percent"]
        maximum = thresholds["threshold_humidity_max_percent"]
        if minimum is None:
            self.assertIsNone(maximum)
        else:
            self.assertIsNotNone(maximum)
            self.assertLess(minimum, maximum)


class ReadContract(ApiContract):
    def test_settings_exposes_all_limits(self):
        self.assert_thresholds(self.settings())

    def test_state_matches_settings_and_exposes_telemetry(self):
        settings = self.settings()
        status, state = self.request("/api/state")
        self.assertEqual(status, 200, state)
        self.assertTrue(set(LIMITS).issubset(state))
        self.assertEqual({field: state[field] for field in LIMITS}, settings)
        for field in ("temperature_c", "humidity_percent", "chamber_temp_c",
                      "mq135_v", "mq2_v", "pm1_0_ug_m3", "pm2_5_ug_m3",
                      "pm10_ug_m3"):
            self.assertIn(field, state)
            value = state[field]
            if value is not None:
                self.assertIn(type(value), (int, float), field)
                self.assertTrue(math.isfinite(value), field)
        humidity = state["humidity_percent"]
        if humidity is not None:
            self.assertGreaterEqual(humidity, 0)
            self.assertLessEqual(humidity, 100)
        self.assertIsInstance(state["active_triggers"], list)
        self.assertTrue(all(isinstance(item, str) for item in state["active_triggers"]))
        self.assertIs(type(state["mq_warming_up"]), bool)
        remaining = state["mq_warmup_remaining_seconds"]
        self.assertIs(type(remaining), int)
        self.assertGreaterEqual(remaining, 0)
        self.assertLessEqual(remaining, 300)
        if state["mq_warming_up"]:
            self.assertIsNone(state["mq2_v"])
            self.assertIsNone(state["mq135_v"])
            self.assertFalse(set(state["active_triggers"]) & {
                "high_mq2_gas", "high_mq135_gas", "mq2_sensor_fault",
                "mq135_sensor_fault",
            })

    def test_reads_require_authentication(self):
        for path in ("/api/state", "/api/settings"):
            with self.subTest(path=path):
                status, _ = self.request(path, authenticated=False)
                self.assertEqual(status, 401)


class WriteContract(ApiContract):
    @classmethod
    def setUpClass(cls):
        if os.environ.get("BIOMASS_TEST_ALLOW_WRITES") != "1":
            raise unittest.SkipTest("Writes require BIOMASS_TEST_ALLOW_WRITES=1")
        super().setUpClass()
        status, original = cls.request("/api/settings")
        if status != 200 or not isinstance(original, dict):
            raise RuntimeError(f"Cannot capture original settings: HTTP {status}")
        disposable = os.environ.get("BIOMASS_TEST_DISPOSABLE") == "1"
        if not disposable and any(original.get(field) is None for field in LIMITS):
            raise RuntimeError(
                "Refusing writes: an unset or missing limit cannot be restored. "
                "BIOMASS_TEST_DISPOSABLE=1 is only for a disposable simulator."
            )
        cls.original = {key: value for key, value in original.items()
                        if key in LIMITS and value is not None}
        cls.addClassCleanup(cls.restore)

    @classmethod
    def restore(cls):
        status, body = cls.request("/api/thresholds", cls.original)
        if status != 200:
            raise AssertionError(f"RESTORE FAILED: HTTP {status}: {body}")
        status, restored = cls.request("/api/settings")
        if status != 200 or any(restored.get(key) != value
                                for key, value in cls.original.items()):
            raise AssertionError("RESTORE FAILED: saved limits differ from original")

    def assert_accepted(self, path, patch, *, raw=None):
        before = self.settings()
        status, body = self.request(path, patch if raw is None else None, raw=raw)
        self.assertEqual(status, 200, body)
        self.assertIsInstance(body, dict)
        self.assertEqual(body.get("status"), "ok")
        self.assertIn("thresholds", body)
        self.assert_thresholds(body["thresholds"])
        self.assertEqual(body["thresholds"], {**before, **patch})
        self.assertEqual(self.settings(), body["thresholds"])

    def assert_rejected(self, path, patch=None, *, raw=None, status=400):
        before = self.settings()
        code, body = self.request(path, patch, raw=raw)
        self.assertEqual(code, status, body)
        self.assertEqual(self.settings(), before)

    def test_01_first_humidity_update_requires_pair(self):
        before = self.settings()
        if before.get("threshold_humidity_min_percent") is not None:
            self.skipTest("Humidity is already configured")
        for path in ROUTES:
            for field, value in (("threshold_humidity_min_percent", 30),
                                 ("threshold_humidity_max_percent", 70)):
                with self.subTest(path=path, field=field):
                    self.assert_rejected(path, {field: value})

    def test_02_full_configuration_and_confirmation(self):
        for path in ROUTES:
            with self.subTest(path=path):
                self.assert_accepted(path, CONFIGURED)

    def test_02_legacy_field_returns_full_confirmation(self):
        for path in ROUTES:
            with self.subTest(path=path):
                self.assert_accepted(path, {"threshold_chamber_temp_c": 82})

    def test_03_partial_updates_preserve_other_limits(self):
        values = (85, 3, 2.25, -5, 26, 51, 101, 31, 71)
        for path in ROUTES:
            self.assertEqual(self.request(path, CONFIGURED)[0], 200)
            for field, value in zip(LIMITS, values):
                with self.subTest(path=path, field=field):
                    self.assert_accepted(path, {field: value})

    def test_04_invalid_payloads_leave_snapshot_unchanged(self):
        for path in ROUTES:
            for field in LIMITS:
                for value in (True, False, "42", None, [], {}):
                    with self.subTest(path=path, field=field, value=value):
                        self.assert_rejected(path, {field: value})
                with self.subTest(path=path, field=field, value="non-finite"):
                    self.assert_rejected(path, raw=(
                        '{"' + field + '":1e400}'
                    ).encode())
            for patch in ({}, {"unknown": 42}, [], {"threshold_mq2_v": 3,
                          "unknown": 42}, {"threshold_humidity_min_percent": 70,
                          "threshold_humidity_max_percent": 30},
                          {"threshold_humidity_min_percent": 40,
                           "threshold_humidity_max_percent": 40},
                          {"threshold_humidity_min_percent": 100},
                          {"threshold_humidity_max_percent": 0}):
                with self.subTest(path=path, patch=patch):
                    self.assert_rejected(path, patch)
            for field, (lower, upper) in LIMITS.items():
                for value in (lower - 1, upper + 1):
                    with self.subTest(path=path, field=field, value=value):
                        self.assert_rejected(path, {**CONFIGURED, field: value})
                if field.startswith("threshold_pm"):
                    with self.subTest(path=path, field=field, value=0):
                        self.assert_rejected(path, {field: 0})

    def test_05_body_limits(self):
        raw = json.dumps(CONFIGURED).encode()
        self.assertGreater(len(raw), 256)
        self.assertLessEqual(len(raw), 1024)
        for path in ROUTES:
            with self.subTest(path=path, size=len(raw)):
                self.assert_accepted(path, CONFIGURED, raw=raw)
            with self.subTest(path=path, size=1024):
                self.assert_accepted(path, CONFIGURED, raw=raw.ljust(1024, b" "))
            with self.subTest(path=path, size=1025):
                self.assert_rejected(path, raw=raw.ljust(1025, b" "), status=413)

    def test_06_writes_require_authentication(self):
        for path in ROUTES:
            with self.subTest(path=path):
                before = self.settings()
                status, _ = self.request(path, CONFIGURED, authenticated=False)
                self.assertEqual(status, 401)
                self.assertEqual(self.settings(), before)


if __name__ == "__main__":
    unittest.main(verbosity=2)
