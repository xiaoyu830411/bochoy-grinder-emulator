# Bochoy Grinder Emulator

中文（默认）：**[中文](README.md)** · English

A native CRYSTAL BLE GATT peripheral emulator for macOS. It advertises `CRYSTAL-E57C` through CoreBluetooth, exposes six protocol characteristics, and provides a CLI, Web monitoring and control, scenarios, and fault injection in the same process.

Repository: <https://github.com/xiaoyu830411/bochoy-grinder-emulator>

Current pre-release: [`1.0.0-beta.1`](https://github.com/xiaoyu830411/bochoy-grinder-emulator/releases/tag/v1.0.0-beta.1) · [Changelog](CHANGELOG.md) · [All Releases](https://github.com/xiaoyu830411/bochoy-grinder-emulator/releases)

> This project is for development and integration testing. It is not real grinder firmware and does not simulate mechanical motion. The original protocol reference is vendored in [`docs/PROTOCOL.md`](docs/PROTOCOL.md) and remains in Chinese.

## Features

- **Real BLE transport**: publishes a service with macOS `CBPeripheralManager`, rather than an in-process fake GATT host.
- **Six protocol registers**: fixed two-byte big-endian `uint16` values with reads, writes-with-response, and notifications.
- **Grinding behavior**: manual/timed/smart start, stop, target grind setting, and non-transactional Apply.
- **Same-process Web console**: controls beside live logs, with Chinese/English switching while raw logs remain unchanged.
- **Device activity**: multiple Observed Centrals, independent observation records, manual disconnect confirmation, and shared hide/restore.
- **Repeatable testing**: seven built-in scenarios, ATT/notification/delay faults, and explicit Test Overrides.
- **Structured events**: terminal output, optional JSONL, and SSE with sequence IDs and resynchronization.
- **No third-party packages**: no external Swift packages, npm packages, or frontend frameworks.

## Architecture

```text
Another phone / tablet                       Local browser
nRF Connect / LightBlue / Decaid             Controls and live logs
              │ BLE GATT                              │ HTTP + SSE
              ▼                                       ▼
┌─────────────────────────────────────────────────────────────┐
│ bochoy-grinder-emulator (single process / MainActor)        │
│                                                             │
│  CoreBluetooth Peripheral ──→ DeviceModel ←── Web / CLI      │
│                                   │                         │
│                         Scenario / Fault / EventLog          │
└─────────────────────────────────────────────────────────────┘
```

Swift modules:

- `CrystalCore`: protocol, device model, scenarios, faults, events, and observation records.
- `CrystalWeb`: HTTP/SSE, security policy, and Web assets without a CoreBluetooth dependency.
- `CrystalSim`: CoreBluetooth lifecycle, CLI, scheduling, and process composition.
- Web and CLI operate on the same `DeviceModel`; they do not create a second simulated device.

The public product and executable are named `bochoy-grinder-emulator`; internal modules retain their `Crystal*` names. The bundle identifier remains `local.bocai.crystal-ble-mock` to preserve the existing local Bluetooth authorization identity.

## Requirements

- macOS 13 or later as the package target; development verification used macOS 26.5.2.
- Swift 6.3 or a compatible toolchain and Xcode command-line tools.
- Node.js for frontend unit tests only, using the built-in `node:test` runner.
- Python 3 for BLE/Web integration smoke tests.
- macOS Bluetooth permission and another phone or tablet for real BLE acceptance.

Build products embed `Resources/Info.plist` and are code-signed. Ad-hoc signing is the default:

```bash
bash Scripts/build.sh debug
```

To use a stable signing identity:

```bash
CODESIGN_IDENTITY="Apple Development" bash Scripts/build.sh release
```

Reset only this simulator's Bluetooth authorization when necessary:

```bash
tccutil reset Bluetooth local.bocai.crystal-ble-mock
```

## Quick Start

```bash
git clone https://github.com/xiaoyu830411/bochoy-grinder-emulator.git
cd bochoy-grinder-emulator

# Debug build and signing
bash Scripts/build.sh debug

# Default scenario with BLE + CLI only
bash Scripts/run.sh

# Same-process Web console on loopback
bash Scripts/run.sh --web 127.0.0.1:8080 --json-log Logs/web-session.jsonl

# Load a specific scenario
bash Scripts/run.sh --scenario Scenarios/delayed-apply.json

# Verify permission, service publication, and advertising, then exit
bash Scripts/run.sh --permission-probe
```

You can also invoke the built executable directly:

```bash
.build/debug/bochoy-grinder-emulator --help
.build/debug/bochoy-grinder-emulator --version
# bochoy-grinder-emulator 1.0.0-beta.1
```

Enter `help` in the CLI for available commands. Bluetooth initialization and advertising are asynchronous; wait for `advertising started` before scanning from another device. A requested Web listener that cannot bind reports `Web listener failed` and exits nonzero.

> One Mac cannot reliably advertise to, scan, and connect to itself. HTTP/API automation is not a substitute for acceptance with a real phone.

## BLE Usage

The default advertised name is `CRYSTAL-E57C`. Override it with `--name CRYSTAL-AB12`; the suffix must contain four uppercase hexadecimal digits.

Primary service: `7fa2d10c-12f3-4b9e-9d77-1a9b65432100`

| Characteristic | Suffix | Default | Normal write range |
|---|---|---:|---:|
| `MT_RPM` | `...0101` | 900 | 0–1500 |
| `XD_RPM` | `...0102` | 40 | 0–150 |
| `BOOT_SIGN` | `...0103` | 0 | Firmware record 0–10; only 1–5 defined |
| `SYS_STATE` | `...0104` | 0 | Not written by plugin; 0=idle, 1=grinding |
| `SERVO_ANGLE` | `...0105` | 830 | Not written by plugin |
| `TF_ANGLE` | `...0106` | 830 | 0–1500 |

Every value is a fixed **two-byte big-endian `uint16`**. Base64 appears only in Decaid bridge comparisons; never write base64 text to BLE.

Choose **Write Request / Write With Response** in a general BLE tool:

| Operation | Characteristic | Raw hex |
|---|---|---|
| Set target grind setting to 830 | `TF_ANGLE` | `03 3E` |
| Apply target grind setting | `BOOT_SIGN` | `00 05` |
| Set motor value to 1200 | `MT_RPM` | `04 B0` |
| Set feed value to 88 | `XD_RPM` | `00 58` |
| Manual / timed / smart start | `BOOT_SIGN` | `00 01` / `00 02` / `00 03` |
| Stop | `BOOT_SIGN` | `00 04` |

`TF_ANGLE → BOOT_SIGN=5` consists of two ordered writes, not a transaction. A failed Apply does not roll back the target already written. An ATT write response does not prove mechanical completion.

See [`docs/IPAD_ACCEPTANCE.md`](docs/IPAD_ACCEPTANCE.md) for general BLE tool checks.

## Web Console

No HTTP listener is created unless `--web` is supplied. Loopback is the recommended default:

```bash
bash Scripts/run.sh --web 127.0.0.1:8080
# Open http://127.0.0.1:8080/
```

A non-loopback bind requires a non-empty access token:

```bash
CRYSTAL_WEB_TOKEN='replace-with-a-long-random-token' \
  bash Scripts/run.sh --web 0.0.0.0:8080
```

Console capabilities:

- The top bar provides **中文 / English** switching. Chinese is the initial default; the choice persists in this browser's `localStorage`. Registers, device states, buttons, feedback, and dates follow the interface language. Raw logs, SSE, and JSONL remain unchanged.
- Desktop controls and logs occupy equal, independently scrolling panes; narrow screens use Control/Log tabs.
- Normal operations include start, stop, motor speed setting, feed parameter, target grind setting, and Apply.
- Six register cards show a title, raw name, decimal value, four-digit hex, and explanation. `MT_RPM` is a setting, not a measured burr speed. Undefined BOOT/SYS values are marked “Undefined / Test Override.”
- Device activity supports multiple centrals and multiple historical observation records. Green=subscribing, yellow=no subscriptions or unconfirmed disconnect, blue=read/write activity only, gray=manually marked disconnected.
- Only gray records can be hidden. Hide/restore is shared across browsers through snapshot/SSE without deleting JSONL, raw events, aliases, or changing BLE state.
- The latest 500 events can be filtered by kind, source, text, and Test Override. JSONL is the persistent record.
- Advanced controls expose scenarios, faults, sessions, advertising, and explicit Overrides.

The Web UI has no simulator-process quit action and does not accept arbitrary scenario paths. CLI and Web commands execute serially on the same MainActor and record `source=cli` or `source=web`.

See [`docs/WEB_ACCEPTANCE.md`](docs/WEB_ACCEPTANCE.md) for combined Web and real-central acceptance.

## Scenarios and Faults

Built-in scenarios live in [`Scenarios/`](Scenarios/):

| Scenario | Purpose |
|---|---|
| `default.json` | Normal default behavior |
| `delayed-apply.json` | Apply delayed by two seconds |
| `notification-lab.json` | Response delay, dropped and duplicate notifications |
| `optional-notify-off.json` | Optional-characteristic subscription failure path |
| `required-notify-off.json` | Required-characteristic subscription failure path |
| `smart-manual-finish.json` | Smart start waits for manual completion |
| `stop-on-session-end.json` | Stop grinding when the inferred session ends |

See [`docs/SCENARIOS.md`](docs/SCENARIOS.md) for fields, fault types, and semantics.

Common CLI commands:

```text
status
set SYS_STATE 2 notify
set SERVO_ANGLE 1000 quiet
notify BOOT_SIGN
fault apply-delay-2000 off
session-end
power off
power on
quit
```

`power off` turns off the virtual grinder: it cancels Run/Apply, stops advertising, and removes GATT while monitoring, logging, and the simulator process continue. It does not prove Link Loss; `power on` requests advertising by default.

## Testing

Complete local entry point:

```bash
bash Scripts/test.sh
```

It runs Swift tests, Node frontend tests, the Debug build and signing, and real CoreBluetooth and HTTP/SSE integration smoke tests. The complete suite starts a BLE peripheral and an isolated HTTP port, so local Bluetooth permission is required.

Individual commands:

```bash
swift test
node --test Scripts/web-tests/*.test.js
bash Scripts/build.sh debug
python3 Scripts/smoke_test.py
python3 Scripts/web_smoke_test.py

swift test -c release
bash Scripts/build.sh release
codesign --verify --verbose .build/release/bochoy-grinder-emulator
```

`swift test` is the subset most suitable for CI. This repository does not claim or fabricate CI status. Automated instances use isolated device names, ports, and temporary logs and must not operate on a user's own simulator process.

## Security and Limitations

- CoreBluetooth has no reliable per-central connect/disconnect callback and no public per-central force-disconnect API. A Disconnect Request is best-effort; disconnection remains unconfirmed.
- Submitting a notification to CoreBluetooth does not prove phone receipt. Unsubscription, session-end, and service removal are not Link Loss.
- Manual disconnect confirmation is user input, not a system callback.
- Non-loopback Web binding requires a token. Host/Origin checks and the absence of CORS permission do not replace a trusted network and careful token handling. Do not share SSE URLs containing tokens.
- The protocol has no application-layer authentication, command sequence, or replay protection. BLE STOP is not an emergency stop.
- Undefined states must not be treated as safely idle. Register values do not prove mechanical position, burr speed, or a physical feed unit.
- This project does not emulate the Decaid HTTP/WebSocket API and does not replace `bochoy-grinder` plugin unit tests.
- The `bluetoothd unused` disconnect observed in real-device logs remains a separate unresolved issue. This project does not hide it with heartbeats or fabricated presence.

See [`docs/ASSUMPTIONS.md`](docs/ASSUMPTIONS.md) for the detailed boundaries.

## Documentation

- [`CHANGELOG.md`](CHANGELOG.md): bilingual release notes and pre-release limitations.
- [`docs/PROTOCOL.md`](docs/PROTOCOL.md): vendored CRYSTAL BLE protocol snapshot with source and version provenance.
- [`CONTEXT.md`](CONTEXT.md): domain vocabulary.
- [`docs/ASSUMPTIONS.md`](docs/ASSUMPTIONS.md): simulation assumptions and platform limitations.
- [`docs/SCENARIOS.md`](docs/SCENARIOS.md): scenario and fault format.
- [`docs/IPAD_ACCEPTANCE.md`](docs/IPAD_ACCEPTANCE.md): general BLE tool acceptance.
- [`docs/WEB_ACCEPTANCE.md`](docs/WEB_ACCEPTANCE.md): Web and real-central acceptance checklist.
- [`AGENTS.md`](AGENTS.md): bilingual AI-agent development guide, imported by Claude Code through `CLAUDE.md`.

## AI-Assisted Development

This repository was developed with Claude Code assistance. This statement applies only to `bochoy-grinder-emulator`; it does not describe the development history of upstream `bochoy-grinder`, the Decaid plugin, CRYSTAL firmware, or the vendored protocol document, and it does not imply endorsement by Anthropic. It does not change the project's copyright or Apache-2.0 license. AI assistance does not replace code review, automated testing, or real-device acceptance.

Other AI agents do not need Claude Code-specific commands:

1. Ask the agent to read [`AGENTS.md`](AGENTS.md#english), then follow its reading order for the protocol, domain vocabulary, and simulation assumptions. For a tool that cannot load the file automatically, provide its contents as project instructions manually.
2. Run baseline tests before changes and record the results. Distinguish existing failures before adding new changes.
3. Give the agent one narrowly scoped task and require an observed failing test before the minimal implementation reaches Green.
4. Require existing tests, protocol semantics, and safety boundaries to remain intact, with no undisclosed dependencies or operations on existing simulator processes.
5. Run relevant tests and the complete `bash Scripts/test.sh` afterward. Report exact commands, actual results, and unverified items; never describe unexecuted real-device acceptance as passing.

Copy this **starter prompt** for any AI agent:

```text
Start by reading `AGENTS.md`, `docs/PROTOCOL.md`, `CONTEXT.md`, and `docs/ASSUMPTIONS.md`.
Run baseline tests and report the results before editing. For the task I provide next, write a test that fails because the target behavior is missing; observe Red before adding the minimal implementation to reach Green.
Do not weaken existing tests or fabricate browser or real-device conclusions. Finish with the commands actually run, their results, and unverified items. Do not commit, push, or operate on user-started processes without explicit authorization.
```

The complete bilingual rules are in [AGENTS.md](AGENTS.md#english). Real-central acceptance still follows [`docs/WEB_ACCEPTANCE.md`](docs/WEB_ACCEPTANCE.md).

## Contributing

Issues and pull requests are welcome at <https://github.com/xiaoyu830411/bochoy-grinder-emulator>.

- Keep protocol behavior, internal module boundaries, and safety semantics explicit.
- All code and bug fixes follow strict Red–Green–Refactor: write a test and observe it fail for the missing behavior, add the minimal implementation to reach Green, and rerun after refactoring.
- Do not introduce third-party dependencies without discussion.
- Do not present HTTP success, notification submission, unsubscription, or service removal as proof of mechanical behavior or Link Loss.

## License

Copyright 2026 xiaoyu830411

Licensed under the [Apache License 2.0](LICENSE).
