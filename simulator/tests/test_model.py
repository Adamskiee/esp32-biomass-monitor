import unittest

from simulator.model import SafetyOverrideError, SimulatorState

DEFAULT_THRESHOLDS = {
    "threshold_chamber_temp_c": 80.0, "threshold_mq2_v": 2.5,
    "threshold_mq135_v": 2.0, "threshold_temperature_c": 35.0,
    "threshold_pm1_0_ug_m3": 15.0, "threshold_pm2_5_ug_m3": 15.0,
    "threshold_pm10_ug_m3": 45.0, "threshold_humidity_min_percent": 30.0,
    "threshold_humidity_max_percent": 60.0,
}


class SimulatorStateTests(unittest.TestCase):
    def setUp(self):
        self.now = 0.0
        self.state = SimulatorState(clock=lambda: self.now)
        self.now = 301.0

    def test_startup_warmup_hides_mq_readings_and_suppresses_gas_alerts(self):
        now = 0.0
        state = SimulatorState(clock=lambda: now)
        state.select_scenario("gas")

        snapshot = state.snapshot()

        self.assertTrue(snapshot["mq_warming_up"])
        self.assertEqual(snapshot["mq_warmup_remaining_seconds"], 300)
        self.assertIsNone(snapshot["mq135_v"])
        self.assertIsNone(snapshot["mq2_v"])
        self.assertNotIn("high_mq2_gas", snapshot["active_triggers"])
        self.assertNotIn("mq2_sensor_fault", snapshot["active_triggers"])

    def test_mq_readings_and_gas_alerts_resume_when_warmup_expires(self):
        now = 0.0
        state = SimulatorState(clock=lambda: now)
        state.select_scenario("gas")
        now = 300.0

        snapshot = state.snapshot()

        self.assertFalse(snapshot["mq_warming_up"])
        self.assertEqual(snapshot["mq_warmup_remaining_seconds"], 0)
        self.assertEqual(snapshot["mq2_v"], 2.8)
        self.assertIn("high_mq2_gas", snapshot["active_triggers"])

    def test_snapshot_keeps_safety_and_warmup_status_consistent_at_expiry(self):
        times = iter((0.0, 0.0, 299.999, 300.0))
        state = SimulatorState(clock=lambda: next(times))
        state.select_scenario("gas")

        snapshot = state.snapshot()

        self.assertTrue(snapshot["mq_warming_up"])
        self.assertEqual(snapshot["mq_warmup_remaining_seconds"], 1)
        self.assertIsNone(snapshot["mq2_v"])
        self.assertNotIn("high_mq2_gas", snapshot["active_triggers"])

    def test_normal_snapshot_has_documented_fields_and_changing_readings(self):
        first = self.state.snapshot()
        second = self.state.snapshot()
        self.assertEqual(set(first), {
            "temperature_c", "humidity_percent", "chamber_temp_c", "mq135_v", "mq2_v",
            "mq_warming_up", "mq_warmup_remaining_seconds",
            "pm1_0_ug_m3", "pm2_5_ug_m3", "pm10_ug_m3",
            "threshold_chamber_temp_c", "threshold_mq2_v", "pump_on",
            "manual_sprinkler", "active_triggers",
            "threshold_mq135_v", "threshold_temperature_c",
            "threshold_pm1_0_ug_m3", "threshold_pm2_5_ug_m3", "threshold_pm10_ug_m3",
            "threshold_humidity_min_percent", "threshold_humidity_max_percent",
        })
        self.assertEqual(first["threshold_chamber_temp_c"], 80.0)
        self.assertEqual(first["threshold_mq2_v"], 2.5)
        self.assertEqual(first["active_triggers"], [])
        self.assertNotEqual(first["temperature_c"], second["temperature_c"])
        self.assertIsInstance(first["humidity_percent"], float)

    def test_pms_fields_in_all_online_scenarios(self):
        for scenario in ("normal", "gas", "heat", "temp-fault", "mq2-fault"):
            with self.subTest(scenario=scenario):
                self.state.select_scenario(scenario)
                state = self.state.snapshot()
                self.assertEqual(
                    (state["pm1_0_ug_m3"], state["pm2_5_ug_m3"], state["pm10_ug_m3"]),
                    (8, 12, 18),
                )

    def test_heat_forces_pump_and_fault_latches(self):
        self.state.select_scenario("heat")
        first = self.state.snapshot()
        self.assertEqual(first["chamber_temp_c"], 100.0)
        self.assertIn("high_chamber_temp", first["active_triggers"])
        self.assertTrue(first["pump_on"])
        with self.assertRaises(SafetyOverrideError):
            self.state.set_manual_sprinkler(False)
        self.state.select_scenario("temp-fault")
        fault = self.state.snapshot()
        self.assertIsNone(fault["chamber_temp_c"])
        self.assertIn("temp_sensor_fault", fault["active_triggers"])
        self.assertIn("catastrophic_latch", fault["active_triggers"])
        self.state.select_scenario("normal")
        self.assertTrue(self.state.snapshot()["pump_on"])

    def test_gas_alert_does_not_start_sprinkler(self):
        self.state.select_scenario("gas")
        state = self.state.snapshot()
        self.assertEqual(state["mq2_v"], 2.8)
        self.assertIn("high_mq2_gas", state["active_triggers"])
        self.assertFalse(state["pump_on"])

    def test_fault_scenarios_report_null_and_triggers(self):
        self.state.select_scenario("temp-fault")
        temp = self.state.snapshot()
        self.assertIsNone(temp["chamber_temp_c"])
        self.assertIn("temp_sensor_fault", temp["active_triggers"])
        self.assertNotIn("catastrophic_latch", temp["active_triggers"])
        self.state.select_scenario("mq2-fault")
        gas = self.state.snapshot()
        self.assertIsNone(gas["mq2_v"])
        self.assertIn("mq2_sensor_fault", gas["active_triggers"])

    def test_threshold_update_is_atomic_and_rejects_bool(self):
        for bad in (True, float("nan"), 19.9, 150.1):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                self.state.update_thresholds({
                    "threshold_chamber_temp_c": bad, "threshold_mq2_v": 3.0,
                })
            state = self.state.snapshot()
            self.assertEqual((state["threshold_chamber_temp_c"], state["threshold_mq2_v"]), (80.0, 2.5))
        with self.assertRaises(ValueError):
            self.state.update_thresholds({})
        self.state.update_thresholds({"threshold_chamber_temp_c": 20, "threshold_mq2_v": 5})
        self.assertEqual(self.state.snapshot()["threshold_chamber_temp_c"], 20.0)

    def test_gas_uses_saved_limit(self):
        self.state.update_thresholds({"threshold_mq2_v": 5.0})
        self.state.select_scenario("gas")
        self.assertNotIn("high_mq2_gas", self.state.snapshot()["active_triggers"])

    def test_mq2_zero_is_valid_and_above_4_8_is_fault(self):
        self.state.select_scenario("gas")
        self.state.set_readings({"mq2_v": 0.0})
        self.assertNotIn("mq2_sensor_fault", self.state.snapshot()["active_triggers"])
        self.state.set_readings({"mq2_v": 4.81})
        self.assertIn("mq2_sensor_fault", self.state.snapshot()["active_triggers"])

    def test_temperature_and_gas_hysteresis(self):
        self.state.select_scenario("heat")
        self.state.update_thresholds({"threshold_chamber_temp_c": 102})
        self.assertNotIn("high_chamber_temp", self.state.snapshot()["active_triggers"])
        self.state.update_thresholds({"threshold_chamber_temp_c": 110})
        self.assertNotIn("high_chamber_temp", self.state.snapshot()["active_triggers"])
        self.state.select_scenario("gas")
        self.state.set_readings({"mq2_v": 2.4})
        self.assertIn("high_mq2_gas", self.state.snapshot()["active_triggers"])
        self.state.set_readings({"mq2_v": 2.375})
        self.assertNotIn("high_mq2_gas", self.state.snapshot()["active_triggers"])

    def test_normal_reading_crossing_threshold_activates_safety(self):
        self.state.update_thresholds({"threshold_chamber_temp_c": 45.1})
        self.assertFalse(self.state.snapshot()["pump_on"])
        crossing = self.state.snapshot()
        self.assertGreaterEqual(crossing["chamber_temp_c"], 45.1)
        self.assertIn("high_chamber_temp", crossing["active_triggers"])
        self.assertTrue(crossing["pump_on"])

    def test_manual_pump_changes_immediately(self):
        self.state.set_manual_sprinkler(True)
        self.assertEqual((self.state.snapshot()["manual_sprinkler"], self.state.snapshot()["pump_on"]), (True, True))
        self.state.set_manual_sprinkler(False)
        self.assertEqual((self.state.snapshot()["manual_sprinkler"], self.state.snapshot()["pump_on"]), (False, False))
        self.state.set_manual_sprinkler(True)
        self.assertEqual((self.state.snapshot()["manual_sprinkler"], self.state.snapshot()["pump_on"]), (True, True))

    def test_threshold_update_immediately_controls_pump(self):
        self.state.select_scenario("heat")
        self.assertTrue(self.state.snapshot()["pump_on"])
        self.state.update_thresholds({"threshold_chamber_temp_c": 110})
        self.assertFalse(self.state.snapshot()["pump_on"])
        self.state.update_thresholds({"threshold_chamber_temp_c": 80})
        self.assertTrue(self.state.snapshot()["pump_on"])

    def test_all_limits_have_defaults_and_confirmation_does_not_advance_drift(self):
        first = self.state.snapshot()
        self.assertEqual(first["humidity_percent"], 50.0)
        limits = self.state.thresholds_snapshot()
        self.assertEqual(limits, DEFAULT_THRESHOLDS)
        limits["threshold_mq2_v"] = 4
        self.assertEqual(self.state.thresholds_snapshot()["threshold_mq2_v"], 2.5)
        self.assertEqual(self.state.snapshot()["temperature_c"], 25.1)

    def test_every_upper_limit_activates_and_recovers_at_boundaries(self):
        cases = (
            ("chamber_temp_c", "high_chamber_temp", 80, 77, 76),
            ("mq2_v", "high_mq2_gas", 2, 1.95, 1.9),
            ("mq135_v", "high_mq135_gas", 2, 1.95, 1.9),
            ("temperature_c", "high_ambient_temp", 30, 29, 28.5),
            ("pm1_0_ug_m3", "high_pm1_0", 20, 19.5, 19),
            ("pm2_5_ug_m3", "high_pm2_5", 20, 19.5, 19),
            ("pm10_ug_m3", "high_pm10", 20, 19.5, 19),
        )
        for field, trigger, limit, hold, recovery in cases:
            with self.subTest(field=field):
                self.state.update_thresholds({"threshold_" + field: limit})
                for reading, active in ((limit - 0.01, False), (limit, True),
                                        (hold, True), (recovery, False)):
                    self.state.set_readings({field: reading})
                    sample = self.state.snapshot()
                    self.assertEqual(trigger in sample["active_triggers"], active)
                    self.assertEqual(sample["pump_on"], active and field == "chamber_temp_c")

    def test_zero_and_negative_ambient_recovery(self):
        for limit, hold, recovery in ((0, -0.4, -0.5), (-20, -20.9, -21)):
            with self.subTest(limit=limit):
                self.state.update_thresholds({"threshold_temperature_c": limit})
                for value, active in ((limit, True), (hold, True), (recovery, False)):
                    self.state.set_readings({"temperature_c": value})
                    self.assertEqual("high_ambient_temp" in self.state.snapshot()["active_triggers"], active)

    def test_humidity_boundaries_recovery_and_direction_changes(self):
        for low, high, low_recovery, high_recovery in ((30, 70, 32, 68), (40, 42, 40.5, 41.5)):
            with self.subTest(low=low):
                self.state.update_thresholds({"threshold_humidity_min_percent": low,
                                              "threshold_humidity_max_percent": high})
                for value, expected in ((low, []), (high, []), (low - 1, ["low_humidity"]),
                                        (low, ["low_humidity"]), (low_recovery, []),
                                        (high + 1, ["high_humidity"]), (high, ["high_humidity"]),
                                        (high_recovery, []), (low - 1, ["low_humidity"]),
                                        (high + 1, ["high_humidity"])):
                    self.state.set_readings({"humidity_percent": value})
                    sample = self.state.snapshot()
                    self.assertEqual(sample["active_triggers"], expected)
                    self.assertFalse(sample["pump_on"])

    def test_invalid_readings_report_faults_without_configured_limits(self):
        cases = (("chamber_temp_c", "temp_sensor_fault", (None, float("nan"))),
                 ("mq2_v", "mq2_sensor_fault", (None, float("inf"), 4.81)),
                 ("mq135_v", "mq135_sensor_fault", (None, float("nan"))),
                 ("temperature_c", "ambient_temp_sensor_fault", (None, -40.1, 80.1)),
                 ("humidity_percent", "humidity_sensor_fault", (None, -0.1, 100.1)),
                 ("pm1_0_ug_m3", "pms_sensor_fault", (None, float("nan"))))
        for field, fault, invalids in cases:
            for value in invalids:
                with self.subTest(field=field, value=value):
                    self.state.select_scenario("normal")
                    self.state.set_readings({field: value})
                    sample = self.state.snapshot()
                    self.assertIn(fault, sample["active_triggers"])
                    self.assertIsNone(sample[field])
                    self.assertFalse(sample["pump_on"])

    def test_environmental_faults_clear_alerts_but_mq2_fault_preserves_alert(self):
        for field, trigger, fault, limit in (
            ("mq135_v", "high_mq135_gas", "mq135_sensor_fault", 2),
            ("temperature_c", "high_ambient_temp", "ambient_temp_sensor_fault", 30),
            ("pm2_5_ug_m3", "high_pm2_5", "pms_sensor_fault", 20),
            ("mq2_v", "high_mq2_gas", "mq2_sensor_fault", 2),
        ):
            with self.subTest(field=field):
                self.state.select_scenario("normal")
                self.state.update_thresholds({"threshold_" + field: limit})
                self.state.set_readings({field: limit})
                self.assertIn(trigger, self.state.snapshot()["active_triggers"])
                self.state.set_readings({field: None})
                sample = self.state.snapshot()
                self.assertIn(fault, sample["active_triggers"])
                self.assertEqual(trigger in sample["active_triggers"], field == "mq2_v")
                self.state.set_readings({field: limit * 0.97})
                self.assertEqual(trigger in self.state.snapshot()["active_triggers"], field == "mq2_v")

    def test_pms_override_expires_only_after_ten_seconds_and_groups_faults(self):
        self.state.update_thresholds({"threshold_pm1_0_ug_m3": 10, "threshold_pm2_5_ug_m3": 10})
        self.state.set_readings({"pm1_0_ug_m3": 20, "pm2_5_ug_m3": 20})
        self.now += 10
        self.assertIn("high_pm1_0", self.state.snapshot()["active_triggers"])
        self.state.set_readings({"humidity_percent": 55})
        self.state.update_thresholds({"threshold_mq2_v": 3})
        self.now += 0.001
        sample = self.state.snapshot()
        self.assertEqual(sample["active_triggers"], ["pms_sensor_fault"])
        for field in ("pm1_0_ug_m3", "pm2_5_ug_m3", "pm10_ug_m3"):
            self.assertIsNone(sample[field])
        self.state.set_readings({"pm1_0_ug_m3": 0, "pm2_5_ug_m3": 0, "pm10_ug_m3": 0})
        self.assertEqual(self.state.snapshot()["active_triggers"], [])
        self.state.select_scenario("normal")
        self.now += 100
        self.assertNotIn("pms_sensor_fault", self.state.snapshot()["active_triggers"])

    def test_changed_limits_reset_valid_latches_but_never_catastrophic_protection(self):
        for field, trigger, limit, changed in (
            ("chamber_temp_c", "high_chamber_temp", 80, 81),
            ("mq2_v", "high_mq2_gas", 2, 2.01),
            ("mq135_v", "high_mq135_gas", 2, 2.01),
            ("temperature_c", "high_ambient_temp", 30, 30.1),
            ("pm1_0_ug_m3", "high_pm1_0", 20, 20.1),
            ("pm2_5_ug_m3", "high_pm2_5", 20, 20.1),
            ("pm10_ug_m3", "high_pm10", 20, 20.1),
        ):
            with self.subTest(field=field):
                self.state.update_thresholds({"threshold_" + field: limit})
                self.state.set_readings({field: limit})
                self.assertIn(trigger, self.state.snapshot()["active_triggers"])
                self.state.update_thresholds({"threshold_" + field: changed})
                self.assertNotIn(trigger, self.state.snapshot()["active_triggers"])
        self.state.select_scenario("heat")
        self.state.set_readings({"chamber_temp_c": None})
        self.state.update_thresholds({"threshold_chamber_temp_c": 150})
        self.assertIn("catastrophic_latch", self.state.snapshot()["active_triggers"])
        with self.assertRaises(SafetyOverrideError):
            self.state.set_manual_sprinkler(False)

    def test_simultaneous_environmental_alerts_leave_manual_pump_ownership(self):
        self.state.update_thresholds({"threshold_mq135_v": 1, "threshold_temperature_c": 20,
                                      "threshold_pm10_ug_m3": 10,
                                      "threshold_humidity_min_percent": 60,
                                      "threshold_humidity_max_percent": 80})
        sample = self.state.snapshot()
        self.assertEqual(set(sample["active_triggers"]), {
            "high_mq135_gas", "high_ambient_temp", "high_pm10", "low_humidity"})
        self.assertFalse(sample["pump_on"])
        for enabled in (True, False):
            self.state.set_manual_sprinkler(enabled)
            self.assertEqual(self.state.snapshot()["pump_on"], enabled)

    def test_warmup_suppresses_both_gas_faults_and_alerts_only(self):
        self.state.update_thresholds({"threshold_mq135_v": 1, "threshold_temperature_c": 20})
        self.state.set_readings({"mq135_v": None, "mq2_v": None})
        self.state.start_mq_warmup()
        self.assertEqual(self.state.snapshot()["active_triggers"], ["high_ambient_temp"])
        self.now += 300
        self.assertEqual(set(self.state.snapshot()["active_triggers"]), {
            "high_ambient_temp", "mq135_sensor_fault", "mq2_sensor_fault"})

    def test_overrides_are_stable_validate_atomically_and_reset_with_scenarios(self):
        self.state.set_readings({"temperature_c": 27, "humidity_percent": 60})
        for invalid in ({"temperature": 5}, {"temperature_c": True}, {"temperature_c": "25"}):
            with self.assertRaises(ValueError):
                self.state.set_readings({"humidity_percent": 80, **invalid})
        for _ in range(3):
            sample = self.state.snapshot()
            self.assertEqual((sample["temperature_c"], sample["humidity_percent"]), (27, 60))
        self.state.update_thresholds({"threshold_temperature_c": 20})
        self.state.reset()
        sample = self.state.snapshot()
        self.assertEqual((sample["temperature_c"], sample["humidity_percent"]), (25, 50))
        self.assertEqual(sample["threshold_temperature_c"], 35)
        self.assertEqual(sample["active_triggers"], [])

    def test_humidity_validation_uses_complete_candidate_atomically(self):
        before = self.state.thresholds_snapshot()
        for patch in ({"threshold_humidity_min_percent": 60},
                      {"threshold_humidity_max_percent": 30},
                      {"threshold_humidity_min_percent": 70, "threshold_humidity_max_percent": 30}):
            with self.assertRaises(ValueError):
                self.state.update_thresholds({"threshold_mq2_v": 3, **patch})
            self.assertEqual(self.state.thresholds_snapshot(), before)
        self.state.update_thresholds({"threshold_humidity_min_percent": 30, "threshold_humidity_max_percent": 70})
        self.state.update_thresholds({"threshold_humidity_min_percent": 35})
        self.assertEqual(self.state.thresholds_snapshot()["threshold_humidity_min_percent"], 35)
        for invalid in (None, True, "30", float("inf"), 70, -1):
            with self.assertRaises(ValueError):
                self.state.update_thresholds({"threshold_humidity_min_percent": invalid})

    def test_unchanged_limit_keeps_hysteresis_and_changed_limit_releases_pump_immediately(self):
        self.state.set_readings({"chamber_temp_c": 80})
        self.state.set_readings({"chamber_temp_c": 79})
        self.state.update_thresholds({"threshold_chamber_temp_c": 80})
        with self.assertRaises(SafetyOverrideError):
            self.state.set_manual_sprinkler(False)
        self.state.update_thresholds({"threshold_chamber_temp_c": 81})
        self.state.set_manual_sprinkler(False)
        self.state.update_thresholds({"threshold_chamber_temp_c": 78})
        with self.assertRaises(SafetyOverrideError):
            self.state.set_manual_sprinkler(False)

    def test_humidity_changed_range_resets_both_latches_and_fault_clears_them(self):
        self.state.update_thresholds({"threshold_humidity_min_percent": 30,
                                      "threshold_humidity_max_percent": 70})
        self.state.set_readings({"humidity_percent": 29})
        self.state.update_thresholds({"threshold_humidity_min_percent": 28})
        self.assertNotIn("low_humidity", self.state.snapshot()["active_triggers"])
        self.state.set_readings({"humidity_percent": 71})
        self.state.update_thresholds({"threshold_humidity_max_percent": 72})
        self.assertNotIn("high_humidity", self.state.snapshot()["active_triggers"])
        for danger, recovered in ((27, 29), (73, 71)):
            self.state.set_readings({"humidity_percent": danger})
            self.assertTrue(set(self.state.snapshot()["active_triggers"]) & {"low_humidity", "high_humidity"})
            self.state.set_readings({"humidity_percent": None})
            self.assertEqual(self.state.snapshot()["active_triggers"], ["humidity_sensor_fault"])
            self.state.set_readings({"humidity_percent": recovered})
            self.assertEqual(self.state.snapshot()["active_triggers"], [])

    def test_normal_snapshot_reads_clock_once_for_pms_and_warmup(self):
        times = iter((0, 300, 310, 310.001))
        state = SimulatorState(clock=lambda: next(times))
        state.set_readings({"pm1_0_ug_m3": 0})
        first = state.snapshot()
        self.assertEqual(first["pm1_0_ug_m3"], 0)
        self.assertNotIn("pms_sensor_fault", first["active_triggers"])
        second = state.snapshot()
        self.assertIsNone(second["pm1_0_ug_m3"])
        self.assertEqual(second["active_triggers"], ["pms_sensor_fault"])

    def test_reset_clears_every_configured_limit_and_override(self):
        self.state.update_thresholds({
            "threshold_chamber_temp_c": 100, "threshold_mq2_v": 3,
            "threshold_mq135_v": 2, "threshold_temperature_c": 35,
            "threshold_pm1_0_ug_m3": 10, "threshold_pm2_5_ug_m3": 20,
            "threshold_pm10_ug_m3": 30, "threshold_humidity_min_percent": 30,
            "threshold_humidity_max_percent": 70,
        })
        self.state.set_readings({"chamber_temp_c": 120, "humidity_percent": 20, "pm1_0_ug_m3": None})
        self.state.reset()
        sample = self.state.snapshot()
        self.assertEqual(sample["active_triggers"], [])
        self.assertFalse(sample["pump_on"])
        self.assertEqual(sample["humidity_percent"], 50)
        self.assertEqual(sample["pm1_0_ug_m3"], 8)
        self.assertEqual(self.state.thresholds_snapshot(), DEFAULT_THRESHOLDS)

    def test_unknown_scenario_keeps_state(self):
        self.state.select_scenario("heat")
        with self.assertRaises(ValueError):
            self.state.select_scenario("unknown")
        self.assertEqual(self.state.scenario, "heat")

    def test_offline_retains_state(self):
        self.state.update_thresholds({"threshold_mq2_v": 3.0})
        self.state.select_scenario("heat")
        self.state.select_scenario("offline")
        self.assertEqual(self.state.scenario, "offline")
        self.assertEqual(self.state.snapshot()["chamber_temp_c"], 100.0)
        self.assertEqual(self.state.snapshot()["threshold_mq2_v"], 3.0)

    def test_reset_clears_latch_and_thresholds(self):
        self.state.select_scenario("heat")
        self.state.select_scenario("temp-fault")
        self.state.update_thresholds({"threshold_chamber_temp_c": 120, "threshold_mq2_v": 3.5})
        self.state.reset()
        state = self.state.snapshot()
        self.assertEqual(self.state.scenario, "normal")
        self.assertEqual((state["threshold_chamber_temp_c"], state["threshold_mq2_v"]), (80.0, 2.5))
        self.assertEqual(state["active_triggers"], [])
        self.assertFalse(state["pump_on"])


if __name__ == "__main__":
    unittest.main()
