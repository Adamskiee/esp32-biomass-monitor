import argparse
import sys
import threading
from http.server import ThreadingHTTPServer

from simulator.model import SimulatorState
from simulator.server import make_handler


SCENARIOS = ("normal", "gas", "heat", "temp-fault", "mq2-fault", "offline")
COMMANDS = (*SCENARIOS, "status", "reset", "help", "quit")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run the local ESP32 API simulator")
    parser.add_argument("--host", default="127.0.0.1", help="listener address (default: 127.0.0.1)")
    parser.add_argument("--port", type=int, default=8765, help="listener port (default: 8765)")
    parser.add_argument("--user", default="demo", help="Basic authentication username (default: demo)")
    parser.add_argument("--password", default="demo", help="Basic authentication password (default: demo)")
    return parser


def process_command(state: SimulatorState, command: str) -> str:
    name = command.strip().lower()
    if name in SCENARIOS:
        state.select_scenario(name)
        return f"Scenario: {name}"
    if name == "reset":
        state.reset()
        return "Reset complete. Scenario: normal"
    if name == "status":
        return f"Scenario: {state.scenario}"
    if name == "quit":
        return "Goodbye"
    if name == "help":
        return "Commands: " + ", ".join(COMMANDS)
    return "Unknown command. Commands: " + ", ".join(COMMANDS)


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    state = SimulatorState()
    try:
        server = ThreadingHTTPServer((args.host, args.port), make_handler(state, args.user, args.password))
    except OSError as error:
        print(f"Cannot listen on {args.host}:{args.port}: {error}. Choose another --port or --host.", file=sys.stderr)
        return 1

    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    print(f"ESP32 simulator listening on http://{args.host}:{server.server_port}/api")
    print(f"Credentials: {args.user} / {args.password}")
    print(process_command(state, "help"))
    try:
        while True:
            try:
                command = input("simulator> ")
            except (EOFError, KeyboardInterrupt):
                print()
                break
            print(process_command(state, command))
            if command.strip().lower() == "quit":
                break
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
