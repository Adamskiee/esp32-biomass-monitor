import unittest

from simulator.model import SafetyOverrideError, SimulatorState


class FakeClock:
    def __init__(self):
        self.now = 0.0

    def __call__(self):
        return self.now

    def advance(self, seconds):
        self.now += seconds


class SimulatorStateTests(unittest.TestCase):
    def setUp(self):
        self.clock = FakeClock()
        self.state = SimulatorState(clock=self.clock)

    def test_normal_snapshot_has_documented_fields_and_changing_readings(self):
        first = self.state.snapshot()
        second = self.state.snapshot()
        self.assertEqual(set(first), {
            "temperature_c", "chamber_temp_c", "mq135_v", "mq2_v",
            "threshold_chamber_temp_c", "threshold_mq2_v", "fan_on",
            "sprinkler_on", "pump_on", "manual_sprinkler", "active_triggers",
        })
        self.assertEqual(first["threshold_chamber_temp_c"], 80.0)
        self.assertEqual(first["threshold_mq2_v"], 2.5)
        self.assertTrue(first["fan_on"])
        self.assertEqual(first["active_triggers"], [])
        self.assertNotEqual(first["temperature_c"], second["temperature_c"])

    def test_heat_forces_valve_then_pump_and_fault_latches(self):
        self.state.select_scenario("heat")
        first = self.state.snapshot()
        self.assertEqual(first["chamber_temp_c"], 100.0)
        self.assertIn("high_chamber_temp", first["active_triggers"])
        self.assertTrue(first["sprinkler_on"])
        self.assertFalse(first["pump_on"])
        with self.assertRaises(SafetyOverrideError):
            self.state.set_manual_sprinkler(False)
        self.clock.advance(0.5)
        self.assertTrue(self.state.snapshot()["pump_on"])
        self.state.select_scenario("temp-fault")
        fault = self.state.snapshot()
        self.assertIsNone(fault["chamber_temp_c"])
        self.assertIn("temp_sensor_fault", fault["active_triggers"])
        self.assertIn("catastrophic_latch", fault["active_triggers"])
        self.state.select_scenario("normal")
        self.assertTrue(self.state.snapshot()["sprinkler_on"])

    def test_gas_alert_does_not_start_sprinkler(self):
        self.state.select_scenario("gas")
        state = self.state.snapshot()
        self.assertEqual(state["mq2_v"], 2.8)
        self.assertIn("high_mq2_gas", state["active_triggers"])
        self.assertFalse(state["sprinkler_on"])

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
        self.assertFalse(self.state.snapshot()["sprinkler_on"])
        crossing = self.state.snapshot()
        self.assertGreaterEqual(crossing["chamber_temp_c"], 45.1)
        self.assertIn("high_chamber_temp", crossing["active_triggers"])
        self.assertTrue(crossing["sprinkler_on"])

    def test_rapid_manual_toggle_preserves_valve_pump_order(self):
        self.state.set_manual_sprinkler(True)
        self.assertEqual((self.state.snapshot()["sprinkler_on"], self.state.snapshot()["pump_on"]), (True, False))
        self.clock.advance(0.2)
        self.state.set_manual_sprinkler(False)
        self.assertFalse(self.state.snapshot()["pump_on"])
        self.clock.advance(0.1)
        self.state.set_manual_sprinkler(True)
        self.clock.advance(0.2)
        self.assertFalse(self.state.snapshot()["pump_on"])
        self.clock.advance(0.3)
        self.assertTrue(self.state.snapshot()["pump_on"])
        self.state.set_manual_sprinkler(False)
        shutdown = self.state.snapshot()
        self.assertTrue(shutdown["sprinkler_on"])
        self.assertFalse(shutdown["pump_on"])
        self.clock.advance(0.5)
        self.assertFalse(self.state.snapshot()["sprinkler_on"])

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
        self.assertFalse(state["sprinkler_on"])


if __name__ == "__main__":
    unittest.main()
