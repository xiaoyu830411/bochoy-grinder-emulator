#!/usr/bin/env python3
"""Local smoke test: real CoreBluetooth startup and console/model checks, no BLE central."""

import json
from pathlib import Path
import queue
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / ".build" / "debug" / "bochoy-grinder-emulator"


def fail(message, process=None, lines=None):
    if process is not None and process.poll() is None:
        process.kill()
        process.wait()
    if lines:
        sys.stderr.write("".join(lines))
    raise SystemExit(message)


def verify_version():
    result = subprocess.run(
        [str(BINARY), "--version"],
        capture_output=True,
        text=True,
        timeout=5,
        check=False,
    )
    expected = "bochoy-grinder-emulator 1.0.0-beta.1\n"
    if result.returncode != 0 or result.stdout != expected or result.stderr:
        fail(
            "--version must print only the release version and exit successfully without starting services",
            lines=[result.stdout, result.stderr],
        )


def main():
    if not BINARY.exists():
        fail(f"missing {BINARY}; run Scripts/build.sh first")
    verify_version()
    with tempfile.TemporaryDirectory(prefix="crystal-sim-smoke-") as directory:
        log_path = Path(directory) / "events.jsonl"
        process = subprocess.Popen(
            [str(BINARY), "--json-log", str(log_path)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        lines = []
        lines_queue = queue.Queue()

        def read_output():
            for line in process.stdout:
                lines_queue.put(line)
            lines_queue.put(None)

        def send(commands):
            process.stdin.write(commands)
            process.stdin.flush()

        threading.Thread(target=read_output, daemon=True).start()
        phase = "initial"
        service_publications = 0
        advertising_starts = 0
        deadline = time.monotonic() + 30
        try:
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    fail("simulator smoke test timed out", process, lines)
                try:
                    line = lines_queue.get(timeout=remaining)
                except queue.Empty:
                    fail("simulator smoke test timed out", process, lines)
                if line is None:
                    break
                lines.append(line)

                if "unknown command: power" in line:
                    fail("Device Power CLI is not implemented", process, lines)

                if "GATT service published" in line:
                    if "characteristics=6" not in line:
                        fail("full six-characteristic service was not published", process, lines)
                    service_publications += 1
                    if phase == "reset" and service_publications == 2:
                        output = "".join(lines)
                        if advertising_starts != 1 or output.count("advertising requested") != 1:
                            fail("reset restarted advertising after an explicit advertise off", process, lines)
                        send("status\nadvertise on\nadvertise on\n")
                        phase = "restarting"

                if "advertising advertising started" in line:
                    advertising_starts += 1
                    if phase == "initial" and advertising_starts == 1:
                        if service_publications != 1:
                            fail("advertising started before the full service was confirmed", process, lines)
                        send(
                            "status\n"
                            "read TF_ANGLE\n"
                            "set SYS_STATE 2 notify\n"
                            "read SYS_STATE\n"
                            "session-end\n"
                            "session-begin\n"
                            "set SYS_STATE 0 quiet\n"
                            "set XD_RPM 0x58 quiet\n"
                            "read XD_RPM\n"
                            "session-end\n"
                            "advertise off\n"
                            "advertise off\n"
                            "reset\n"
                        )
                        phase = "reset"
                    elif phase == "restarting" and advertising_starts == 2:
                        send(
                            "advertise off\n"
                            "power off\n"
                            "power off\n"
                            "status\n"
                            "advertise on\n"
                            "reset\n"
                            "set SYS_STATE 2 quiet\n"
                            "read SYS_STATE\n"
                            "power on\n"
                        )
                        phase = "power-first"
                    elif phase == "power-first" and advertising_starts == 3:
                        send(
                            "set MT_RPM 1200 quiet\n"
                            "set XD_RPM 100 quiet\n"
                            "set TF_ANGLE 1000 quiet\n"
                            "set SERVO_ANGLE 900 quiet\n"
                            "power off\n"
                            "power on\n"
                        )
                        phase = "power-second"
                    elif phase == "power-second" and advertising_starts == 4:
                        send(
                            "status\n"
                            "read SYS_STATE\n"
                            "read MT_RPM\n"
                            "read XD_RPM\n"
                            "read TF_ANGLE\n"
                            "read SERVO_ANGLE\n"
                            "read BOOT_SIGN\n"
                            "quit\n"
                        )
                        phase = "quitting"
                    else:
                        fail("unexpected advertising start", process, lines)
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            fail("simulator did not exit in time", process, lines)

        output = "".join(lines)
        if process.returncode != 0:
            fail(f"simulator exited {process.returncode}", lines=lines)
        if phase != "quitting" or advertising_starts != 4 or service_publications != 4:
            fail("did not complete startup, reset, advertising and two Device Power restart cycles", lines=lines)
        required = [
            "TF_ANGLE=0 hex=00 00 base64=AAA=",
            "SYS_STATE=2 hex=00 02 base64=AAI=",
            "XD_RPM=88 hex=00 58 base64=AFg=",
            "No active session; Disconnect Policy was not applied",
            "Observed Session End simulated only",
            "advertising=false advertisingRequested=false advertisingStartPending=false",
            "Device Powered Off; active Run and pending Apply cancelled",
            "GATT services removed; Disconnect Request issued; disconnection unconfirmed",
            "advertise on rejected: Device Powered Off",
            "scenario reload rejected: Device Powered Off",
            "poweredOn=false",
            "Device Powered On in idle state; volatile settings reset, SERVO_ANGLE retained",
            "poweredOn=true",
            "SYS_STATE=0 hex=00 00 base64=AAA=",
            "MT_RPM=0 hex=00 00 base64=AAA=",
            "XD_RPM=0 hex=00 00 base64=AAA=",
            "SERVO_ANGLE=900 hex=03 84 base64=A4Q=",
            "BOOT_SIGN=0 hex=00 00 base64=AAA=",
            "crystal-sim exiting normally",
        ]
        for expected in required:
            if expected not in output:
                fail(f"missing expected output: {expected}", lines=lines)
        before_power = output.split("Device Powered Off;", 1)[0]
        if before_power.count("advertising requested") != 2:
            fail("repeated advertise on was not idempotent before Device Power transitions", lines=lines)
        if "advertising already active or starting" not in output:
            fail("repeated advertise on did not report its idempotent state", lines=lines)

        events = [json.loads(line) for line in log_path.read_text().splitlines()]
        override = next(event for event in events if event["kind"] == "override" and event.get("value") == 2)
        assert override["hex"] == "00 02"
        assert override["base64"] == "AAI="
        assert override["testOverride"] is True
        assert override["after"]["sysState"] == 2
        assert sum(event["message"] == "advertising started" for event in events) == 4
        assert sum("advertising requested" in event["message"] for event in events) == 4
        power_events = [event for event in events if event["message"].startswith("notification suppressed for Device Power")]
        assert len(power_events) == 4
        assert all(event["testOverride"] is False for event in power_events)
        assert sum(event["message"].startswith("Device Powered Off;") for event in events) == 2
        assert sum(event["message"].startswith("Device Powered On") for event in events) == 2

        invalid_probe = subprocess.run(
            [str(BINARY), "--permission-probe", "--name", "CRYSTAL-AB12"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
        if invalid_probe.returncode != 1 or "--permission-probe cannot be combined" not in invalid_probe.stderr:
            fail(
                "permission-probe option combination was not explicitly rejected",
                lines=[invalid_probe.stdout, invalid_probe.stderr],
            )
        print("SMOKE_OK GATT, advertising controls, console, hex overrides and JSONL verified")


if __name__ == "__main__":
    main()
