import math
import threading
import time
from collections.abc import Mapping


class SafetyOverrideError(Exception):
    pass


class SimulatorState:
    _MQ_WARMUP_SECONDS = 300
    _PMS_FRESHNESS_SECONDS = 10
    _READINGS = {
        "gas": {"mq2_v": 2.8},
        "heat": {"chamber_temp_c": 100.0},
        "temp-fault": {"chamber_temp_c": None},
        "mq2-fault": {"mq2_v": None},
    }
    _DEFAULT_READINGS = {
        "temperature_c": 25.0, "humidity_percent": 50.0,
        "chamber_temp_c": 45.0, "mq135_v": 1.2, "mq2_v": 1.0,
        "pm1_0_ug_m3": 8, "pm2_5_ug_m3": 12, "pm10_ug_m3": 18,
    }
    _PMS_FIELDS = ("pm1_0_ug_m3", "pm2_5_ug_m3", "pm10_ug_m3")
    _DEFAULT_THRESHOLDS = {
        "threshold_chamber_temp_c": 80.0, "threshold_mq2_v": 2.5,
        "threshold_mq135_v": 2.0, "threshold_temperature_c": 35.0,
        "threshold_pm1_0_ug_m3": 15.0, "threshold_pm2_5_ug_m3": 15.0,
        "threshold_pm10_ug_m3": 45.0, "threshold_humidity_min_percent": 30.0,
        "threshold_humidity_max_percent": 60.0,
    }
    _LIMITS = {
        "threshold_chamber_temp_c": (20.0, 150.0),
        "threshold_mq2_v": (0.1, 5.0),
        "threshold_mq135_v": (0.1, 5.0),
        "threshold_temperature_c": (-40.0, 80.0),
        "threshold_pm1_0_ug_m3": (0.0, 65535.0),
        "threshold_pm2_5_ug_m3": (0.0, 65535.0),
        "threshold_pm10_ug_m3": (0.0, 65535.0),
        "threshold_humidity_min_percent": (0.0, 100.0),
        "threshold_humidity_max_percent": (0.0, 100.0),
    }
    _UPPER_TRIGGERS = {
        "chamber_temp_c": "high_chamber_temp",
        "mq2_v": "high_mq2_gas",
        "mq135_v": "high_mq135_gas",
        "temperature_c": "high_ambient_temp",
        "pm1_0_ug_m3": "high_pm1_0",
        "pm2_5_ug_m3": "high_pm2_5",
        "pm10_ug_m3": "high_pm10",
    }
    _FAULT_TRIGGERS = {
        "chamber_temp_c": "temp_sensor_fault",
        "mq2_v": "mq2_sensor_fault",
        "mq135_v": "mq135_sensor_fault",
        "temperature_c": "ambient_temp_sensor_fault",
        "humidity_percent": "humidity_sensor_fault",
    }

    def __init__(self, clock=time.monotonic):
        self._lock = threading.RLock()
        self._clock = clock
        self.reset()

    @property
    def scenario(self) -> str:
        with self._lock:
            return self._scenario

    def reset(self) -> None:
        with self._lock:
            now = self._clock()
            self._scenario = "normal"
            self._tick = 0
            self._readings = self._DEFAULT_READINGS.copy()
            self._overrides = set()
            self._pms_sampled_at = now
            self._thresholds = self._DEFAULT_THRESHOLDS.copy()
            self._upper_danger = dict.fromkeys(self._UPPER_TRIGGERS, False)
            self._low_humidity_danger = False
            self._high_humidity_danger = False
            self._catastrophic_latch = False
            self._manual_sprinkler = False
            self._pump_on = False
            self._mq_warmup_started_at = now

    def start_mq_warmup(self) -> None:
        with self._lock:
            now = self._clock()
            self._mq_warmup_started_at = now
            self._evaluate_safety(self._valid_readings(now), True)

    def select_scenario(self, name: str) -> None:
        if name not in (*self._READINGS, "normal", "offline"):
            raise ValueError(f"Unknown scenario: {name}")
        with self._lock:
            self._scenario = name
            if name == "offline":
                return
            now = self._clock()
            self._readings = {**self._DEFAULT_READINGS, **self._READINGS.get(name, {})}
            self._overrides.clear()
            self._pms_sampled_at = now
            self._evaluate_safety(self._valid_readings(now), self._mq_warmup_remaining_seconds(now) > 0)

    def set_readings(self, values: Mapping[str, object]) -> None:
        if not isinstance(values, Mapping) or any(key not in self._DEFAULT_READINGS for key in values):
            raise ValueError("Provide documented sensor readings")
        validated = {}
        for key, value in values.items():
            if value is not None and type(value) not in (int, float):
                raise ValueError(f"Invalid {key}")
            validated[key] = float(value) if value is not None else None
        with self._lock:
            now = self._clock()
            self._readings.update(validated)
            self._overrides.update(validated)
            if any(field in validated for field in self._PMS_FIELDS):
                self._pms_sampled_at = now
            self._evaluate_safety(self._valid_readings(now), self._mq_warmup_remaining_seconds(now) > 0)

    def thresholds_snapshot(self) -> dict[str, object]:
        with self._lock:
            return self._thresholds.copy()

    def update_thresholds(self, values: Mapping[str, object]) -> dict[str, object]:
        if not isinstance(values, Mapping) or not values or any(key not in self._LIMITS for key in values):
            raise ValueError("Provide at least one documented threshold")
        validated = {}
        for key, value in values.items():
            low, high = self._LIMITS[key]
            if (type(value) not in (int, float) or not low <= value <= high
                    or not math.isfinite(value) or (key.startswith("threshold_pm") and value == 0)):
                raise ValueError(f"Invalid {key}")
            validated[key] = float(value)
        with self._lock:
            candidate = {**self._thresholds, **validated}
            minimum = candidate["threshold_humidity_min_percent"]
            maximum = candidate["threshold_humidity_max_percent"]
            if (minimum is None) != (maximum is None) or (minimum is not None and minimum >= maximum):
                raise ValueError("Humidity requires a minimum strictly below its maximum")
            changed = {key for key in validated if candidate[key] != self._thresholds[key]}
            if changed:
                now = self._clock()
                readings = self._valid_readings(now)
                for field in self._UPPER_TRIGGERS:
                    if "threshold_" + field in changed and readings[field] is not None:
                        self._upper_danger[field] = False
                if any(key.startswith("threshold_humidity_") for key in changed) and readings["humidity_percent"] is not None:
                    self._low_humidity_danger = False
                    self._high_humidity_danger = False
                self._thresholds = candidate
                self._evaluate_safety(readings, self._mq_warmup_remaining_seconds(now) > 0)
            return self._thresholds.copy()

    def set_manual_sprinkler(self, enabled: bool) -> None:
        if type(enabled) is not bool:
            raise ValueError("sprinkler must be a boolean")
        with self._lock:
            if self._upper_danger["chamber_temp_c"] or self._catastrophic_latch:
                raise SafetyOverrideError("Automatic safety control is active")
            self._manual_sprinkler = enabled
            self._pump_on = enabled

    def snapshot(self) -> dict[str, object]:
        with self._lock:
            now = self._clock()
            if self._scenario == "normal":
                drift = (self._tick % 5) * 0.1
                for field, scale in (("temperature_c", 1), ("chamber_temp_c", 1),
                                     ("mq135_v", 0.1), ("mq2_v", 0.1)):
                    if field not in self._overrides:
                        self._readings[field] = self._DEFAULT_READINGS[field] + drift * scale
                self._tick += 1
            if self._scenario != "offline" and not self._overrides.intersection(self._PMS_FIELDS):
                self._pms_sampled_at = now
            remaining = self._mq_warmup_remaining_seconds(now)
            readings = self._valid_readings(now)
            triggers = self._evaluate_safety(readings, remaining > 0)
            return {
                **readings, **self._thresholds,
                "mq_warming_up": remaining > 0,
                "mq_warmup_remaining_seconds": remaining,
                "pump_on": self._pump_on,
                "manual_sprinkler": self._manual_sprinkler,
                "active_triggers": triggers,
            }

    def _valid_readings(self, now: float) -> dict[str, float | None]:
        readings = {key: value if value is not None and math.isfinite(value) else None
                    for key, value in self._readings.items()}
        for field, low, high in (("temperature_c", -40, 80), ("humidity_percent", 0, 100)):
            if readings[field] is not None and not low <= readings[field] <= high:
                readings[field] = None
        if readings["mq2_v"] is not None and readings["mq2_v"] > 4.8:
            readings["mq2_v"] = None
        if self._mq_warmup_remaining_seconds(now) > 0:
            readings["mq2_v"] = readings["mq135_v"] = None
        # A PMS frame is one sample, so a missing channel invalidates all three.
        if (now - self._pms_sampled_at > self._PMS_FRESHNESS_SECONDS
                or any(readings[field] is None for field in self._PMS_FIELDS)):
            for field in self._PMS_FIELDS:
                readings[field] = None
        return readings

    def _evaluate_safety(self, readings: Mapping[str, float | None], mq_warming_up: bool) -> list[str]:
        for field in self._UPPER_TRIGGERS:
            value = readings[field]
            limit = self._thresholds["threshold_" + field]
            if limit is None or (mq_warming_up and field in ("mq2_v", "mq135_v")):
                self._upper_danger[field] = False
            elif value is None:
                if field not in ("chamber_temp_c", "mq2_v"):
                    self._upper_danger[field] = False
            else:
                recovery = limit - max(0.5, abs(limit) * 0.05) if field == "temperature_c" else limit * 0.95
                if value >= limit:
                    self._upper_danger[field] = True
                elif value <= recovery:
                    self._upper_danger[field] = False

        humidity = readings["humidity_percent"]
        minimum = self._thresholds["threshold_humidity_min_percent"]
        maximum = self._thresholds["threshold_humidity_max_percent"]
        if humidity is None or minimum is None or maximum is None:
            self._low_humidity_danger = self._high_humidity_danger = False
        else:
            margin = min(2, (maximum - minimum) / 4)
            if humidity < minimum:
                self._low_humidity_danger = True
            elif humidity >= minimum + margin:
                self._low_humidity_danger = False
            if humidity > maximum:
                self._high_humidity_danger = True
            elif humidity <= maximum - margin:
                self._high_humidity_danger = False

        if readings["chamber_temp_c"] is None and self._upper_danger["chamber_temp_c"]:
            self._catastrophic_latch = True
        if self._upper_danger["chamber_temp_c"] or self._catastrophic_latch:
            self._manual_sprinkler = False
            self._pump_on = True
        else:
            self._pump_on = self._manual_sprinkler

        triggers = ["catastrophic_latch"] if self._catastrophic_latch else []
        triggers.extend(trigger for field, trigger in self._UPPER_TRIGGERS.items() if self._upper_danger[field])
        if self._low_humidity_danger:
            triggers.append("low_humidity")
        if self._high_humidity_danger:
            triggers.append("high_humidity")
        for field, trigger in self._FAULT_TRIGGERS.items():
            if readings[field] is None and not (mq_warming_up and field in ("mq2_v", "mq135_v")):
                triggers.append(trigger)
        if readings["pm1_0_ug_m3"] is None:
            triggers.append("pms_sensor_fault")
        return triggers

    def _mq_warmup_remaining_seconds(self, now: float) -> int:
        elapsed = now - self._mq_warmup_started_at
        return max(0, math.ceil(self._MQ_WARMUP_SECONDS - elapsed))
