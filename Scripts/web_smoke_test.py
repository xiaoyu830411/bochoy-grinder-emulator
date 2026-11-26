#!/usr/bin/env python3
"""Real loopback HTTP/SSE integration tests for the same-process Web control plane."""

import http.client
import json
import os
from pathlib import Path
import queue
import socket
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / ".build" / "debug" / "bochoy-grinder-emulator"


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def request(port, method, path, body=None, headers=None, timeout=5):
    headers = dict(headers or {})
    if isinstance(body, (dict, list)):
        body = json.dumps(body).encode()
        headers.setdefault("Content-Type", "application/json")
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=timeout)
    try:
        connection.request(method, path, body=body, headers=headers)
        response = connection.getresponse()
        raw = response.read()
        content_type = response.getheader("Content-Type", "")
        parsed = json.loads(raw) if "application/json" in content_type and raw else None
        return response.status, dict(response.getheaders()), parsed, raw
    finally:
        connection.close()


def control(port, action, **parameters):
    return request(port, "POST", "/api/control", {"action": action, **parameters})[0::2]


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def check_success(reply, message="control failed"):
    status, body = reply
    check(status == 200 and body.get("ok") is True, f"{message}: {status} {body}")
    return body["snapshot"]


def wait_register(port, register, expected, timeout=6.5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        snapshot = request(port, "GET", "/api/snapshot")[2]
        if snapshot["device"]["registers"][register] == expected:
            return snapshot
        time.sleep(0.1)
    raise AssertionError(f"{register} did not become {expected} within {timeout}s")


class SimulatorProcess:
    def __init__(self, port, name, extra_args=None, token=None, bind_host="127.0.0.1"):
        self.tempdir = tempfile.TemporaryDirectory(prefix="crystal-web-smoke-")
        self.log_path = Path(self.tempdir.name) / "events.jsonl"
        self.port = port
        self.lines = []
        self.line_queue = queue.Queue()
        env = dict(os.environ)
        if token is None:
            env.pop("CRYSTAL_WEB_TOKEN", None)
        else:
            env["CRYSTAL_WEB_TOKEN"] = token
        arguments = [
            str(BINARY), "--web", f"{bind_host}:{port}", "--name", name,
            "--json-log", str(self.log_path),
        ] + list(extra_args or [])
        self.process = subprocess.Popen(
            arguments,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            env=env,
        )
        threading.Thread(target=self._read_output, daemon=True).start()

    def _read_output(self):
        for line in self.process.stdout:
            self.lines.append(line)
            self.line_queue.put(line)

    def wait_output(self, text, timeout=15):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if text in "".join(self.lines):
                return
            if self.process.poll() is not None:
                break
            try:
                self.line_queue.get(timeout=0.1)
            except queue.Empty:
                pass
        raise AssertionError(f"missing output {text!r}; process output:\n{''.join(self.lines)}")

    def wait_http(self, timeout=15):
        deadline = time.monotonic() + timeout
        last_error = None
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                raise AssertionError(f"simulator exited early: {self.process.returncode}\n{''.join(self.lines)}")
            try:
                status, _, body, _ = request(self.port, "GET", "/api/snapshot", timeout=1)
                if status == 200:
                    return body
            except Exception as error:
                last_error = error
            time.sleep(0.05)
        raise AssertionError(f"HTTP server did not become ready: {last_error}\n{''.join(self.lines)}")

    def send_cli(self, line):
        self.process.stdin.write(line + "\n")
        self.process.stdin.flush()

    def stop(self):
        if self.process.poll() is None:
            try:
                self.send_cli("quit")
                self.process.wait(timeout=3)
            except Exception:
                self.process.terminate()
                try:
                    self.process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait()
        self.tempdir.cleanup()


class SSEClient:
    def __init__(self, port, last_event_id=None, token=None):
        self.socket = socket.create_connection(("127.0.0.1", port), timeout=5)
        self.socket.settimeout(10)
        self.buffer = b""
        self.last_id = None
        target = "/api/events" + (f"?token={token}" if token else "")
        headers = [f"GET {target} HTTP/1.1", f"Host: 127.0.0.1:{port}"]
        if last_event_id is not None:
            headers.append(f"Last-Event-ID: {last_event_id}")
        request_text = "\r\n".join(headers) + "\r\n\r\n"
        self.socket.sendall(request_text.encode())
        while b"\r\n\r\n" not in self.buffer:
            self.buffer += self.socket.recv(4096)
        header, self.buffer = self.buffer.split(b"\r\n\r\n", 1)
        status_line = header.split(b"\r\n", 1)[0].decode()
        check(" 200 " in status_line, f"SSE connection failed: {status_line}")

    def frame(self):
        while b"\n\n" not in self.buffer:
            chunk = self.socket.recv(4096)
            if not chunk:
                raise AssertionError("SSE connection closed")
            self.buffer += chunk
        raw, self.buffer = self.buffer.split(b"\n\n", 1)
        lines = raw.decode().splitlines()
        if all(line.startswith(":") for line in lines):
            return {"event": "heartbeat", "data": None, "id": None}
        result = {"event": "message", "data": "", "id": None}
        data = []
        for line in lines:
            if line.startswith("event:"):
                result["event"] = line[6:].strip()
            elif line.startswith("id:"):
                result["id"] = line[3:].strip()
                self.last_id = result["id"]
            elif line.startswith("data:"):
                data.append(line[5:].lstrip())
        result["data"] = json.loads("\n".join(data)) if data else None
        return result

    def until(self, event_name, predicate=lambda value: True, maximum=700):
        seen = []
        for _ in range(maximum):
            frame = self.frame()
            seen.append(frame)
            if frame["event"] == event_name and predicate(frame["data"]):
                return frame, seen
        raise AssertionError(f"SSE event {event_name} not found; last frames: {seen[-5:]}")

    def close(self):
        self.socket.close()


def run_main_control_and_sse():
    port = free_port()
    simulator = SimulatorProcess(port, "CRYSTAL-B16E")
    try:
        snapshot = simulator.wait_http()
        check(snapshot["device"]["poweredOn"] is True, "device should start powered on")
        for register in ["mtRPM", "xdRPM", "tfAngle", "bootSign", "sysState"]:
            check(snapshot["device"]["registers"][register] == 0, f"default {register} mismatch")
        check(snapshot["device"]["registers"]["servoAngle"] == 830, "default SERVO mismatch")
        check(snapshot["centrals"] == [], "unexpected observed centrals")
        check(len(snapshot["availableScenarios"]) >= 7, "scenario catalog incomplete")
        check("advertisingRequested" in snapshot["bluetooth"], "BLE state missing")

        status, headers, _, raw = request(port, "GET", "/")
        check(status == 200 and raw, "static index unavailable")
        check("text/html" in headers["Content-Type"], "index content type mismatch")
        check("Access-Control-Allow-Origin" not in headers, "CORS must not be enabled")
        check(request(port, "GET", "/missing")[0] == 404, "unknown route should be 404")
        check(request(port, "POST", "/api/snapshot")[0] == 405, "wrong method should be 405")
        check(request(port, "POST", "/api/control", "not json")[0] == 400, "invalid JSON should be 400")
        check(request(port, "POST", "/api/control", b"x" * 16385)[0] == 413, "body limit missing")
        check(request(port, "GET", "/api/snapshot", headers={"Host": "evil.example"})[0] == 403, "Host check missing")
        check(request(port, "GET", "/api/snapshot", headers={"Origin": "http://evil.example"})[0] == 403, "Origin check missing")
        check(request(port, "GET", "/api/snapshot", headers={"Origin": f"http://127.0.0.1:{port}"})[0] == 200, "matching Origin rejected")

        snapshot = check_success(control(port, "setMT", value=1200))
        check(snapshot["device"]["registers"]["mtRPM"] == 1200, "setMT did not mutate model")
        snapshot = check_success(control(port, "setXD", value=80))
        check(snapshot["device"]["registers"]["xdRPM"] == 80, "setXD did not mutate model")
        check_success(control(port, "setTF", value=1000))
        snapshot = check_success(control(port, "apply"))
        check(snapshot["device"]["registers"]["servoAngle"] == 1000, "Apply did not update SERVO")
        check(snapshot["device"]["registers"]["sysState"] == 1, "Apply did not enter Device Active")
        snapshot = check_success(control(port, "setTFAndApply", value=950))
        check(snapshot["device"]["registers"]["tfAngle"] == 950, "combined TF write missing")
        check(snapshot["device"]["registers"]["servoAngle"] == 950, "combined Apply missing")
        check(snapshot["device"]["registers"]["sysState"] == 1, "combined Apply did not stay Device Active")
        snapshot = wait_register(port, "sysState", 0)
        check(snapshot["device"]["activeRun"] is None, "Apply auto-idle must not fabricate a Run")
        check(snapshot["device"]["registers"]["servoAngle"] == 950, "auto-idle changed SERVO")

        check_success(control(port, "sessionBegin"))
        snapshot = check_success(control(port, "apply"))
        check(snapshot["device"]["registers"]["sysState"] == 1, "Apply before pause did not enter Device Active")
        check_success(control(port, "sessionEnd"))
        time.sleep(6.0)
        snapshot = request(port, "GET", "/api/snapshot")[2]
        check(snapshot["device"]["registers"]["sysState"] == 1, "paused Apply auto-idle timer still fired")
        check_success(control(port, "sessionBegin"))
        snapshot = wait_register(port, "sysState", 0)
        check_success(control(port, "sessionEnd"))

        for mode in ["manual", "timed", "smart"]:
            snapshot = check_success(control(port, "start", mode=mode))
            check(snapshot["device"]["activeRun"]["mode"] == mode, f"{mode} run missing")
            if mode == "timed":
                snapshot = check_success(control(port, "finishRun"))
            else:
                snapshot = check_success(control(port, "stop"))
            check(snapshot["device"]["registers"]["sysState"] == 0, "run did not stop")
        check_success(control(port, "finishApply"))
        snapshot = check_success(control(
            port, "override", characteristic="SYS_STATE", value=65535, notification="quiet"
        ))
        check(snapshot["device"]["registers"]["sysState"] == 65535, "uint16 Override failed")
        check_success(control(port, "override", characteristic="SYS_STATE", value=0, notification="quiet"))
        check(control(port, "override", characteristic="SYS_STATE", value=2)[0] == 400, "Override notification must be explicit")
        check_success(control(port, "advertising", enabled=False))
        check_success(control(port, "advertising", enabled=True))
        check_success(control(port, "sessionBegin"))
        check(control(port, "scenarioLoad", scenario="default")[0] == 409, "active session should block reload")
        check_success(control(port, "sessionEnd"))

        check_success(control(port, "scenarioLoad", scenario="delayed-apply"))
        check_success(control(port, "setTF", value=1100))
        snapshot = check_success(control(port, "apply"))
        check(snapshot["device"]["pendingApply"] is not None, "delayed Apply should remain pending")
        snapshot = check_success(control(port, "finishApply"))
        check(snapshot["device"]["registers"]["servoAngle"] == 1100, "force Apply finish failed")
        check_success(control(port, "faultSet", faultID="apply-delay-2000", enabled=False))
        check_success(control(port, "setTF", value=1000))
        snapshot = check_success(control(port, "apply"))
        check(snapshot["device"]["pendingApply"] is None, "disabled Apply delay still active")
        check_success(control(port, "faultSet", faultID="apply-delay-2000", enabled=True))
        check_success(control(port, "scenarioReset"))
        check_success(control(port, "scenarioLoad", scenario="default"))
        check(control(port, "scenarioLoad", scenario="missing")[0] == 404, "unknown scenario should be 404")
        check(control(port, "scenarioLoad", scenario="../../etc/passwd")[0] == 400, "scenario path accepted")
        check(control(port, "disconnectCentral", centralID="AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")[0] == 404, "unknown central accepted")
        for action in ["markObservationDisconnected", "hideObservation", "restoreObservation"]:
            check(control(port, action, recordID="AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")[0] == 404, f"unknown observation accepted by {action}")
        snapshot = check_success(control(port, "restoreHiddenObservations"))
        check(snapshot["centrals"] == [], "empty observation restore changed records")
        check(control(port, "hideObservation", centralID="AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")[0] == 400, "central UUID incorrectly accepted as recordID")
        check(control(port, "quit")[0] == 400 and simulator.process.poll() is None, "Web quit must not exist")

        simulator.send_cli("set MT_RPM 1234 quiet")
        simulator.wait_output("console command command=set MT_RPM 1234 quiet source=cli")
        snapshot = request(port, "GET", "/api/snapshot")[2]
        check(snapshot["device"]["registers"]["mtRPM"] == 1234, "CLI and Web do not share model")

        client = SSEClient(port)
        client.until("snapshot")
        check_success(control(port, "setMT", value=1300))
        _, frames = client.until("snapshot", lambda value: value["device"]["registers"]["mtRPM"] == 1300)
        check(any(frame["event"] == "log" for frame in frames), "live log frame missing")
        resume_id = client.last_id
        client.close()
        client = SSEClient(port, last_event_id=resume_id)
        check_success(control(port, "setMT", value=1301))
        client.until("snapshot", lambda value: value["device"]["registers"]["mtRPM"] == 1301)
        client.close()

        for index in range(140):
            check_success(control(port, "setMT", value=1000 + (index % 2)))
        client = SSEClient(port, last_event_id=1)
        frame, _ = client.until("resync")
        check(frame["data"]["reason"] == "sequence-gap", "resync reason missing")
        _, frames = client.until("snapshot")
        check(sum(item["event"] == "log" for item in frames) <= 500, "SSE history exceeds 500")
        client.close()

        snapshot = check_success(control(
            port, "override", characteristic="SERVO_ANGLE", value=999, notification="quiet"
        ))
        check(snapshot["device"]["registers"]["servoAngle"] == 999, "SERVO setup for power cycle failed")
        snapshot = check_success(control(port, "powerOff"))
        check(snapshot["device"]["poweredOn"] is False, "powerOff failed")
        off_actions = [
            ("start", {"mode": "manual"}), ("stop", {}), ("setMT", {"value": 1}),
            ("setXD", {"value": 1}), ("setTF", {"value": 1}), ("apply", {}),
            ("setTFAndApply", {"value": 1}), ("finishRun", {}), ("finishApply", {}),
            ("override", {"characteristic": "SYS_STATE", "value": 2, "notification": "quiet"}),
            ("advertising", {"enabled": True}), ("sessionBegin", {}), ("sessionEnd", {}),
            ("scenarioLoad", {"scenario": "default"}), ("scenarioReset", {}),
            ("faultSet", {"faultID": "x", "enabled": True}),
            ("disconnectCentral", {"centralID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"}),
            ("markObservationDisconnected", {"recordID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"}),
            ("hideObservation", {"recordID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"}),
            ("restoreObservation", {"recordID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"}),
            ("restoreHiddenObservations", {}),
            ("powerOff", {}),
        ]
        for action, parameters in off_actions:
            status, body = control(port, action, **parameters)
            check(status == 409 and body["message"] == "Device Powered Off", f"off-state {action}: {status} {body}")
        check(request(port, "GET", "/api/snapshot")[0] == 200, "monitoring unavailable while off")
        snapshot = check_success(control(port, "powerOn"))
        check(snapshot["device"]["poweredOn"] is True, "powerOn failed")
        for register in ["mtRPM", "xdRPM", "tfAngle", "bootSign", "sysState"]:
            check(snapshot["device"]["registers"][register] == 0, f"powerOn did not reset {register}")
        check(snapshot["device"]["registers"]["servoAngle"] == 999, "power cycle did not retain SERVO")

        events = [json.loads(line) for line in simulator.log_path.read_text().splitlines()]
        check(any(event["kind"] == "write" and event.get("details", {}).get("source") == "web" for event in events), "Web write source missing")
        check(any(event["message"] == "console command" and event.get("details", {}).get("source") == "cli" for event in events), "CLI source missing")
        check(any(event["kind"] == "override" and event["testOverride"] is True for event in events), "Override label missing")
        check(any(event["message"].startswith("Device Powered Off") and event["details"]["source"] == "web" for event in events), "Web power source missing")
    finally:
        simulator.stop()


def run_fault_and_nontransaction_test():
    port = free_port()
    with tempfile.TemporaryDirectory(prefix="crystal-web-fault-") as directory:
        scenario = Path(directory) / "fault.json"
        scenario.write_text(json.dumps({
            "name": "web-faults",
            "faults": [
                {"id": "reject-apply", "type": "writeError", "characteristic": "BOOT_SIGN", "value": 5, "attStatus": 17},
                {"id": "att-delay", "type": "responseDelay", "characteristic": "MT_RPM", "delayMs": 2000},
                {"id": "terminate", "type": "terminateProcess", "characteristic": "XD_RPM", "value": 77},
            ],
        }))
        simulator = SimulatorProcess(port, "CRYSTAL-B16D", ["--scenario", str(scenario)])
        try:
            simulator.wait_http()
            started = time.monotonic()
            check_success(control(port, "setMT", value=1200))
            check(time.monotonic() - started < 1.5, "Web incorrectly applied ATT responseDelay")
            status, body = control(port, "setTFAndApply", value=1000)
            check(status == 422 and body["ok"] is False, f"writeError should map to 422: {status} {body}")
            check(body["attStatus"] == 17 and body["faultID"] == "reject-apply", "ATT fault details missing")
            check(body["snapshot"]["device"]["registers"]["tfAngle"] == 1000, "first combined step was rolled back")
            check(body["snapshot"]["device"]["registers"]["servoAngle"] == 830, "failed Apply changed SERVO")
            try:
                control(port, "setXD", value=77)
            except (http.client.RemoteDisconnected, ConnectionResetError):
                pass
            simulator.process.wait(timeout=5)
            check(simulator.process.returncode == 70, f"terminateProcess semantics changed: {simulator.process.returncode}")
        finally:
            simulator.stop()


def run_startup_and_token_tests():
    occupied = socket.socket()
    occupied.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    occupied.bind(("127.0.0.1", 0))
    occupied.listen()
    port = occupied.getsockname()[1]
    simulator = SimulatorProcess(port, "CRYSTAL-B16C")
    try:
        simulator.process.wait(timeout=10)
        check(simulator.process.returncode != 0, "occupied Web port did not fail startup")
        check("Web listener failed" in "".join(simulator.lines), "bind failure was not explicit")
    finally:
        simulator.stop()
        occupied.close()

    port = free_port()
    arguments = [str(BINARY), "--web", f"0.0.0.0:{port}", "--name", "CRYSTAL-B16B"]
    env = dict(os.environ)
    env.pop("CRYSTAL_WEB_TOKEN", None)
    missing = subprocess.run(arguments, capture_output=True, text=True, timeout=10, env=env, check=False)
    check(missing.returncode != 0 and "CRYSTAL_WEB_TOKEN" in missing.stderr, "non-loopback token requirement missing")

    secret = "integration-secret"
    simulator = SimulatorProcess(port, "CRYSTAL-B16A", token=secret, bind_host="0.0.0.0")
    try:
        simulator.wait_output("Web listening")
        check(request(port, "GET", "/api/snapshot")[0] == 401, "token-protected snapshot was public")
        check(request(port, "GET", "/api/snapshot", headers={"Authorization": "Bearer wrong"})[0] == 401, "wrong token accepted")
        check(request(port, "GET", "/api/snapshot", headers={"Authorization": f"Bearer {secret}"})[0] == 200, "Bearer token rejected")
        check(request(port, "GET", "/")[0] == 200, "static asset should not need API token")
        client = SSEClient(port, token=secret)
        client.until("snapshot")
        client.close()
        if simulator.log_path.exists():
            check(secret not in simulator.log_path.read_text(), "token leaked into JSONL")
    finally:
        simulator.stop()


def main():
    if not BINARY.exists():
        raise SystemExit(f"missing {BINARY}; run Scripts/build.sh first")
    run_main_control_and_sse()
    run_fault_and_nontransaction_test()
    run_startup_and_token_tests()
    print("WEB_SMOKE_OK controls, power, scenarios, faults, CLI/Web ordering, HTTP security and SSE verified")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        raise
