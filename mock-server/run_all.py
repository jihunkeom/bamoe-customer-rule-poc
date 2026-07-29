"""Run all four PoC mock APIs in one OpenShift container."""

from __future__ import annotations

import signal
import subprocess
import sys
import time
from pathlib import Path


MOCKS = (
    "case01_mock_server.py",
    "case02_mock_server.py",
    "case03_mock_server.py",
    "case04_mock_server.py",
)


def stop_all(processes: list[subprocess.Popen[bytes]]) -> None:
    for process in processes:
        if process.poll() is None:
            process.terminate()

    deadline = time.monotonic() + 5
    for process in processes:
        if process.poll() is not None:
            continue
        remaining = max(0, deadline - time.monotonic())
        try:
            process.wait(timeout=remaining)
        except subprocess.TimeoutExpired:
            process.kill()


def main() -> int:
    base = Path(__file__).resolve().parent
    processes = [
        subprocess.Popen([sys.executable, str(base / script)])
        for script in MOCKS
    ]

    def request_stop(_signum: int, _frame: object) -> None:
        stop_all(processes)

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)

    try:
        while True:
            for process in processes:
                return_code = process.poll()
                if return_code is not None:
                    stop_all(processes)
                    return return_code or 1
            time.sleep(0.5)
    finally:
        stop_all(processes)


if __name__ == "__main__":
    raise SystemExit(main())
