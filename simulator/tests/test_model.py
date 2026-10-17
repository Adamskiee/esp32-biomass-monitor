import unittest

from simulator.model import SafetyOverrideError, SimulatorState


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

    def test_gas_uses_fixed_limit(self):
        self.state.update_thresholds({"threshold_mq2_v": 5.0})
        self.state.select_scenario("gas")
        self.assertIn("high_mq2_gas", self.state.snapshot()["active_triggers"])

    def test_mq2_zero_is_valid_and_above_4_8_is_fault(self):
        self.state.select_scenario("gas")
        self.state._mq2_v = 0.0
        self.state._evaluate_safety()
        self.assertNotIn("mq2_sensor_fault", self.state.snapshot()["active_triggers"])
        self.state._mq2_v = 4.81
        self.state._evaluate_safety()
        self.assertIn("mq2_sensor_fault", self.state.snapshot()["active_triggers"])

    def test_temperature_and_gas_hysteresis(self):
        self.state.select_scenario("heat")
        self.state.update_thresholds({"threshold_chamber_temp_c": 102})
        self.assertIn("high_chamber_temp", self.state.snapshot()["active_triggers"])
        self.state.update_thresholds({"threshold_chamber_temp_c": 110})
        self.assertNotIn("high_chamber_temp", self.state.snapshot()["active_triggers"])
        self.state.select_scenario("gas")
        self.state._mq2_v = 2.4
        self.state._evaluate_safety()
        self.assertIn("high_mq2_gas", self.state.snapshot()["active_triggers"])
        self.state._mq2_v = 2.375
        self.state._evaluate_safety()
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
