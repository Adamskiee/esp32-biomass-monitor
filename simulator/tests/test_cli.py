import contextlib
import io
import socket
import unittest

from simulator.__main__ import build_parser, main, process_command
from simulator.model import SimulatorState


class CommandTests(unittest.TestCase):
    def setUp(self):
        self.state = SimulatorState()

    def test_each_scenario_command_switches_state(self):
        for name in ("normal", "gas", "heat", "temp-fault", "mq2-fault", "offline"):
            with self.subTest(name=name):
                result = process_command(self.state, name)
                self.assertEqual(self.state.scenario, name)
                self.assertIn(name, result)

    def test_reset_restores_defaults_and_status_reports_scenario(self):
        self.state.select_scenario("heat")
        self.state.update_thresholds({"threshold_mq2_v": 4})
        self.assertIn("heat", process_command(self.state, "status"))
        process_command(self.state, "reset")
        self.assertEqual(self.state.scenario, "normal")
        self.assertEqual(self.state.snapshot()["threshold_mq2_v"], 2.5)

    def test_unknown_command_does_not_change_state_and_lists_commands(self):
        self.state.select_scenario("gas")
        result = process_command(self.state, "typo")
        self.assertEqual(self.state.scenario, "gas")
        for name in ("normal", "gas", "heat", "temp-fault", "mq2-fault", "offline", "status", "reset", "help", "quit"):
            self.assertIn(name, result)

    def test_parser_has_local_demo_defaults(self):
        args = build_parser().parse_args([])
        self.assertEqual((args.host, args.port, args.user, args.password),
                         ("127.0.0.1", 8765, "demo", "demo"))

    def test_port_in_use_returns_error(self):
        with socket.socket() as occupied:
            occupied.bind(("127.0.0.1", 0))
            occupied.listen()
            port = occupied.getsockname()[1]
            output = io.StringIO()
            with contextlib.redirect_stderr(output):
                result = main(["--port", str(port)])
        self.assertNotEqual(result, 0)
        self.assertIn(str(port), output.getvalue())
        self.assertNotIn("Traceback", output.getvalue())


if __name__ == "__main__":
    unittest.main()
