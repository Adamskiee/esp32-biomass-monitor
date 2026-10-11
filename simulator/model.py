import math
import threading
import time
from collections.abc import Callable, Mapping


class SafetyOverrideError(Exception):
    pass


class SimulatorState:
    _READINGS = {
        "gas": (25.0, 45.0, 1.2, 2.8),
        "heat": (25.0, 100.0, 1.2, 1.0),
        "temp-fault": (25.0, None, 1.2, 1.0),
        "mq2-fault": (25.0, 45.0, 1.2, None),
    }
    _LIMITS = {
        "threshold_chamber_temp_c": (20.0, 150.0),
        "threshold_mq2_v": (0.1, 5.0),
        "threshold_mq2_response_ratio": (1.0000001, 100.0),
    }

    def __init__(self, clock: Callable[[], float] = time.monotonic):
        self._clock = clock
        self._lock = threading.RLock()
        self.reset()

    @property
    def scenario(self) -> str:
        with self._lock:
            return self._scenario

    def reset(self) -> None:
        with self._lock:
            self._scenario = "normal"
            self._tick = 0
            self._temperature_c = 25.0
            self._chamber_temp_c = 45.0
            self._mq135_v = 1.2
            self._mq2_v = 1.0
            self._threshold_chamber_temp_c = 80.0
            self._threshold_mq2_v = 2.5
            self._threshold_mq2_response_ratio = None
            self._mq2_baseline_v = None
            self._mq135_baseline_v = None
            self._mq2_calibration_id = None
            self._mq135_calibration_id = None
            self._next_calibration_id = 1
            self._started_at = self._clock()
            self._last_mq_write_at = None
            self._temp_danger = False
            self._gas_danger = False
            self._catastrophic_latch = False
            self._manual_sprinkler = False
            self._sprinkler_on = False
            self._pump_on = False
            self._sprinkler_requested = False
            self._phase = "off"
            self._transition_started_at = self._clock()

    def select_scenario(self, name: str) -> None:
        if name not in (*self._READINGS, "normal", "offline"):
            raise ValueError(f"Unknown scenario: {name}")
        with self._lock:
            if name == "offline":
                self._scenario = name
                return
            self._scenario = name
            if name == "normal":
                self._temperature_c, self._chamber_temp_c, self._mq135_v, self._mq2_v = (25.0, 45.0, 1.2, 1.0)
            else:
                self._temperature_c, self._chamber_temp_c, self._mq135_v, self._mq2_v = self._READINGS[name]
            self._evaluate_safety()

    def update_thresholds(self, values: Mapping[str, object]) -> None:
        if not values or any(key not in self._LIMITS for key in values):
            raise ValueError("Provide at least one documented threshold")
        validated = {}
        for key, value in values.items():
            low, high = self._LIMITS[key]
            if type(value) not in (int, float) or not math.isfinite(value) or not low <= value <= high:
                raise ValueError(f"Invalid {key}")
            validated[key] = float(value)
        with self._lock:
            if "threshold_mq2_response_ratio" in validated and self._mq2_baseline_v is None:
                raise ValueError("MQ-2 calibration required")
            for key, value in validated.items():
                setattr(self, f"_{key}", value)
            self._evaluate_safety()

    def capture_mq_calibration(self, sensor: str) -> dict[str, object]:
        if sensor not in ("mq2", "mq135"):
            raise ValueError("sensor must be mq2 or mq135")
        with self._lock:
            if self._clock() - self._started_at < 300:
                raise ValueError("warming up")
            if self._last_mq_write_at is not None and self._clock() - self._last_mq_write_at < 60:
                raise RuntimeError("write cooldown")
            value = self._mq2_v if sensor == "mq2" else self._mq135_v
            if value is None or not 0.1 < value < 4.5 or (sensor == "mq2" and value >= 2.5):
                raise ValueError("invalid calibration samples")
            calibration_id = self._next_calibration_id
            self._next_calibration_id += 1
            self._last_mq_write_at = self._clock()
            if sensor == "mq2":
                self._mq2_baseline_v, self._mq2_calibration_id = value, calibration_id
            else:
                self._mq135_baseline_v, self._mq135_calibration_id = value, calibration_id
            return {"calibration_id": calibration_id, "baseline_v": value, "circuit_supply_v": 5.0}

    def set_manual_sprinkler(self, enabled: bool) -> None:
        if type(enabled) is not bool:
            raise ValueError("sprinkler must be a boolean")
        with self._lock:
            if self._temp_danger or self._catastrophic_latch:
                raise SafetyOverrideError("Automatic safety control is active")
            self._manual_sprinkler = enabled
            self._request_sprinkler(enabled)

    def snapshot(self) -> dict[str, object]:
        with self._lock:
            if self._scenario == "normal":
                drift = (self._tick % 5) * 0.1
                self._temperature_c = 25.0 + drift
                self._chamber_temp_c = 45.0 + drift
                self._mq135_v = 1.2 + drift / 10
                self._mq2_v = 1.0 + drift / 10
                self._tick += 1
                self._evaluate_safety()
            self._advance_actuators()
            mq2_response = self._response(self._mq2_v, self._mq2_baseline_v)
            mq135_response = self._response(self._mq135_v, self._mq135_baseline_v)
            triggers = []
            if self._catastrophic_latch:
                triggers.append("catastrophic_latch")
            if self._temp_danger:
                triggers.append("high_chamber_temp")
            if self._gas_danger:
                triggers.append("high_mq2_gas")
            if self._chamber_temp_c is None:
                triggers.append("temp_sensor_fault")
            if self._mq2_v is None or self._mq2_v > 4.8:
                triggers.append("mq2_sensor_fault")
            return {
                "temperature_c": self._temperature_c,
                "chamber_temp_c": self._chamber_temp_c,
                "mq135_v": self._mq135_v,
                "mq2_v": self._mq2_v,
                "mq2_response_ratio": mq2_response,
                "mq135_response_ratio": mq135_response,
                "mq2_calibration_id": self._mq2_calibration_id,
                "mq135_calibration_id": self._mq135_calibration_id,
                "mq2_calibration_status": "ready" if mq2_response is not None else ("uncalibrated" if self._mq2_baseline_v is None else "invalid"),
                "mq135_calibration_status": "ready" if mq135_response is not None else ("uncalibrated" if self._mq135_baseline_v is None else "invalid"),
                "mq2_threshold_mode": "response_ratio" if self._threshold_mq2_response_ratio is not None else "legacy_voltage",
                "mq2_safety_mode": "response_ratio" if self._threshold_mq2_response_ratio is not None and mq2_response is not None else "legacy_voltage",
                "threshold_mq2_response_ratio": self._threshold_mq2_response_ratio,
                "pm1_0_ug_m3": 8,
                "pm2_5_ug_m3": 12,
                "pm10_ug_m3": 18,
                "threshold_chamber_temp_c": self._threshold_chamber_temp_c,
                "threshold_mq2_v": self._threshold_mq2_v,
                "fan_on": True,
                "sprinkler_on": self._sprinkler_on,
                "pump_on": self._pump_on,
                "manual_sprinkler": self._manual_sprinkler,
                "active_triggers": triggers,
            }

    def _evaluate_safety(self) -> None:
        temp_fault = self._chamber_temp_c is None
        gas_fault = self._mq2_v is None or self._mq2_v > 4.8
        if not temp_fault:
            if self._chamber_temp_c >= self._threshold_chamber_temp_c:
                self._temp_danger = True
            elif self._chamber_temp_c <= self._threshold_chamber_temp_c * 0.95:
                self._temp_danger = False
        response = self._response(self._mq2_v, self._mq2_baseline_v)
        gas_value = response if self._threshold_mq2_response_ratio is not None and response is not None else self._mq2_v
        gas_limit = self._threshold_mq2_response_ratio if response is not None and self._threshold_mq2_response_ratio is not None else 2.5
        if not gas_fault:
            if gas_value >= gas_limit:
                self._gas_danger = True
            elif gas_value <= gas_limit * 0.95:
                self._gas_danger = False
        if temp_fault and self._temp_danger:
            self._catastrophic_latch = True
        if self._temp_danger or self._catastrophic_latch:
            self._manual_sprinkler = False
            self._request_sprinkler(True)
        else:
            self._request_sprinkler(self._manual_sprinkler)

    @staticmethod
    def _response(value, baseline):
        if value is None or baseline is None or not 0.1 < value < 4.8 or not 0.1 < baseline < 4.8:
            return None
        return value * (5.0 - baseline) / (baseline * (5.0 - value))

    def _request_sprinkler(self, enabled: bool) -> None:
        self._sprinkler_requested = enabled
        if enabled and self._phase in ("off", "stopping_valve"):
            self._pump_on = False
            self._sprinkler_on = True
            self._transition_started_at = self._clock()
            self._phase = "starting_pump"
        elif not enabled and self._phase in ("on", "starting_pump"):
            self._pump_on = False
            self._transition_started_at = self._clock()
            self._phase = "stopping_valve"

    def _advance_actuators(self) -> None:
        if self._clock() - self._transition_started_at < 0.5:
            return
        if self._phase == "starting_pump" and self._sprinkler_requested and self._sprinkler_on:
            self._pump_on = True
            self._phase = "on"
        elif self._phase == "stopping_valve" and not self._sprinkler_requested:
            self._sprinkler_on = False
            self._phase = "off"
