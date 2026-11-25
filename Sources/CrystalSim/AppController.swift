import Darwin
import Foundation
import CrystalCore
import CrystalWeb

@MainActor
final class AppController {
    private let output: ConsoleOutput
    private let logger: EventLog
    private var model: DeviceModel
    private let peripheral: BLEPeripheral
    private let centralStore = ObservedCentralStore()
    private let webEndpoint: WebEndpoint?
    private let webToken: String?
    private var webServer: WebServer?
    private var webHub: WebEventHub?

    private static let scenarioFiles = [
        "default": "default.json",
        "delayed-apply": "delayed-apply.json",
        "notification-lab": "notification-lab.json",
        "optional-notify-off": "optional-notify-off.json",
        "required-notify-off": "required-notify-off.json",
        "smart-manual-finish": "smart-manual-finish.json",
        "stop-on-session-end": "stop-on-session-end.json",
    ]

    private static let scenarioDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Scenarios", isDirectory: true)

    private let helpText = """
    Commands:
      status                         Show registers, run/Apply state, BLE and scheduler state.
      read <CHAR>                    Show value, big-endian hex and Decaid base64.
      set <CHAR> <0-65535|0xXXXX> <notify|quiet>
                                     Test Override; quiet updates the synchronization baseline.
      notify <CHAR>                  Force notification of the current value (Test Override).
      finish                         Force the active run to idle, ignoring runStall.
      apply-finish                   Force the pending Apply to its captured target.
      faults                         List scenario fault rules and enabled state.
      fault <id> <on|off>            Toggle a fault and reset its occurrence counter.
      session-end                    Apply Disconnect Policy; DOES NOT disconnect BLE.
      session-begin                  Begin/resume an inferred test session and reset dedup.
      load <path.json>               Load/reset a scenario only when no session/subscribers exist.
      reset                          Reset the current scenario under the same restriction.
      advertise <on|off>             Start/stop advertising; off does not disconnect existing links.
      power <on|off>                Power the virtual grinder; off removes GATT and requests disconnection.
      help                           Show this command list.
      quit                           Stop advertising and exit normally.

    Characteristics: MT_RPM XD_RPM BOOT_SIGN SYS_STATE SERVO_ANGLE TF_ANGLE
    Real link-loss tests must be performed from another phone/tablet or by terminating this process.
    """

    init(options: AppOptions) throws {
        output = try ConsoleOutput(jsonLogPath: options.jsonLogPath)
        let logger = EventLog()
        logger.addHandler { [output] event in
            output.event(event)
        }
        self.logger = logger
        model = DeviceModel(scenario: options.scenario, logger: logger)
        peripheral = BLEPeripheral(model: model, logger: logger)
        webEndpoint = options.webEndpoint
        webToken = options.webToken
        peripheral.onTermination = { code in
            exit(Int32(code))
        }
        peripheral.onCentralActivity = { [centralStore] id, activity, characteristic in
            centralStore.observe(central: id, activity: activity, characteristic: characteristic)
        }
    }

    func start() {
        output.command("CRYSTAL BLE Mock started. Type 'help' for commands.")
        if let webEndpoint {
            startWeb(endpoint: webEndpoint, token: webToken)
        }
        startReadingStandardInput()
    }

    private func startWeb(endpoint: WebEndpoint, token: String?) {
        let hub = WebEventHub(initialEvents: logger.events) { [self] in
            snapshot()
        }
        webHub = hub
        logger.addHandler { [hub] event in
            hub.record(event)
        }
        let server = WebServer(
            endpoint: endpoint,
            token: token,
            eventHub: hub,
            snapshotProvider: { [self] in snapshot() },
            controlHandler: { [self] command in dispatch(command, source: .web) },
            onReady: { [logger, output] address in
                DispatchQueue.main.async {
                    logger.record(.control, "Web listening", details: ["address": address])
                    output.command("Web listening on http://\(address)")
                }
            },
            onFailure: { [logger] message in
                DispatchQueue.main.async {
                    logger.record(.error, "Web listener failed", details: ["reason": message])
                    FileHandle.standardError.write(Data("ERROR: Web listener failed: \(message)\n".utf8))
                    exit(1)
                }
            }
        )
        webServer = server
        server.start()
    }

    func snapshot() -> SimulatorSnapshot {
        SimulatorSnapshot(
            device: model.snapshot(),
            bluetooth: peripheral.snapshot(),
            centrals: centralStore.centrals,
            availableScenarios: Self.scenarioFiles.keys.sorted()
        )
    }

    func dispatch(_ command: ControlCommand, source: ControlSource) -> ControlResult {
        if source == .web {
            logger.record(
                .control,
                "Web control",
                scenario: model.scenario.name,
                details: ["source": "web", "command": String(describing: command)]
            )
        }
        if !model.poweredOn, source == .web {
            if case .power(true) = command {
                // Power-on is the only Web command accepted while off.
            } else {
                return .failure(409, "Device Powered Off")
            }
        }

        switch command {
        case .power(let enabled):
            if enabled {
                guard !model.poweredOn else { return .success("Device already Powered On") }
                let effects = model.powerOn(source: source.rawValue)
                peripheral.powerUp()
                peripheral.execute(effects)
                return .success("Device Powered On; advertising requested")
            }
            guard model.poweredOn else { return .success("Device already Powered Off") }
            let effects = model.powerOff(source: source.rawValue)
            peripheral.execute(effects)
            peripheral.powerDown()
            return .success("Device Powered Off; disconnection unconfirmed")
        case .start(let mode):
            let value: UInt16 = mode == .manual ? 1 : mode == .timed ? 2 : 3
            return normalWrite(.bootSign, value: value, action: "start \(mode.rawValue)")
        case .stop:
            return normalWrite(.bootSign, value: 4, action: "stop")
        case .setMotor(let value):
            return normalWrite(.mtRPM, value: value, action: "set MT_RPM")
        case .setFeed(let value):
            return normalWrite(.xdRPM, value: value, action: "set XD_RPM")
        case .setTarget(let value):
            return normalWrite(.tfAngle, value: value, action: "set TF_ANGLE")
        case .apply:
            return normalWrite(.bootSign, value: 5, action: "Apply")
        case .setTargetAndApply(let value):
            let first = normalWrite(.tfAngle, value: value, action: "set TF_ANGLE")
            guard first.ok else { return first }
            let second = normalWrite(.bootSign, value: 5, action: "Apply")
            guard second.ok else {
                return .failure(
                    second.httpStatus,
                    "Apply failed; TF_ANGLE change retained",
                    attStatus: second.attStatus,
                    faultID: second.faultID
                )
            }
            return .success("TF_ANGLE written, then Apply executed; not a transaction")
        case .finishRun:
            peripheral.execute(model.forceFinishRun())
            return .success("force finish Run requested")
        case .finishApply:
            peripheral.execute(model.forceFinishApply())
            return .success("force finish Apply requested")
        case .override(let characteristic, let value, let notify):
            peripheral.execute(model.overrideRegister(characteristic, value: value, notify: notify))
            return .success("Test Override applied")
        case .advertising(let enabled):
            peripheral.setAdvertisingEnabled(enabled)
            return .success(enabled
                ? "advertising requested"
                : "advertising stopped; existing BLE links are not disconnected")
        case .session(let enabled):
            if enabled {
                peripheral.execute(model.sessionBegan(source: source.rawValue))
                return .success("test session began")
            }
            peripheral.execute(model.sessionEnded(source: source.rawValue))
            return .success("Observed Session End simulated only; no BLE link was disconnected")
        case .loadScenario(let name):
            guard let file = Self.scenarioFiles[name] else {
                return .failure(404, "Unknown Scenario")
            }
            do {
                let scenario = try Scenario.load(from: Self.scenarioDirectory.appendingPathComponent(file))
                return scenarioReplacementResult(scenario)
            } catch {
                return .failure(400, "Scenario load failed: \(error.localizedDescription)")
            }
        case .resetScenario:
            return scenarioReplacementResult(model.scenario)
        case .setFault(let id, let enabled):
            guard model.faults.setEnabled(id, enabled: enabled) else {
                return .failure(404, "Unknown fault id")
            }
            return .success("fault \(enabled ? "enabled" : "disabled")")
        case .disconnectCentral(let id):
            guard centralStore.centrals.contains(where: { $0.id == id }) else {
                return .failure(404, "Unknown Observed Central")
            }
            _ = centralStore.noteDisconnectRequest(central: id)
            peripheral.requestDisconnect(centralID: id)
            return .success("Disconnect Request issued; per-central and Link Loss confirmation unavailable")
        case .markObservationDisconnected(let recordID):
            return observationMutation(recordID: recordID, success: "Observation manually marked disconnected; no Link Loss callback inferred") {
                try centralStore.markDisconnected(recordID: recordID)
            }
        case .hideObservation(let recordID):
            return observationMutation(recordID: recordID, success: "Observation hidden for all browsers; events and BLE state unchanged") {
                try centralStore.hide(recordID: recordID)
            }
        case .restoreObservation(let recordID):
            return observationMutation(recordID: recordID, success: "Observation restored for all browsers") {
                try centralStore.restore(recordID: recordID)
            }
        case .restoreHiddenObservations:
            let count = centralStore.restoreAllHidden()
            return .success("Restored \(count) hidden Observation(s) for all browsers")
        }
    }

    private func observationMutation(
        recordID: UUID,
        success: String,
        mutation: () throws -> Void
    ) -> ControlResult {
        do {
            try mutation()
            return .success(success)
        } catch ObservationMutationError.recordNotFound {
            return .failure(404, "Unknown Observation Record")
        } catch ObservationMutationError.requiresManualDisconnect {
            return .failure(409, "Manual disconnection confirmation required before hiding")
        } catch {
            return .failure(400, "Observation mutation failed")
        }
    }

    private func normalWrite(
        _ characteristic: Characteristic,
        value: UInt16,
        action: String
    ) -> ControlResult {
        let preparation = model.prepareWrite(
            UInt16Codec.encode(value),
            to: characteristic,
            source: .web
        )
        guard preparation.succeeded else {
            return .failure(
                422,
                "write rejected by injected ATT error; model unchanged",
                attStatus: preparation.status,
                faultID: preparation.faultID
            )
        }
        peripheral.execute(preparation.effects)
        return .success("\(action) processed")
    }

    private func startReadingStandardInput() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            while let line = readLine(strippingNewline: true) {
                DispatchQueue.main.async {
                    self?.handleCommand(line)
                }
            }
            DispatchQueue.main.async {
                self?.output.command("stdin closed; BLE simulation continues. Use process signals to stop.")
            }
        }
    }

    private func handleCommand(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        logger.record(
            .control,
            "console command",
            scenario: model.scenario.name,
            details: ["command": trimmed, "source": "cli"]
        )
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let command = parts.first else { return }

        switch command {
        case "help":
            output.command(helpText)
        case "status":
            (model.statusLines + peripheral.statusLines).forEach(output.command)
        case "read":
            guard parts.count == 2, let characteristic = characteristic(parts[1]) else {
                return commandError("usage: read <CHAR>")
            }
            let value = model.registers[characteristic]
            output.command("\(characteristic.rawValue)=\(value) hex=\(UInt16Codec.hex(value)) base64=\(UInt16Codec.base64(value))")
        case "set":
            guard parts.count == 4, let characteristic = characteristic(parts[1]),
                  let value = parseUInt16(parts[2]), let notify = notificationFlag(parts[3]) else {
                return commandError("usage: set <CHAR> <0-65535|0xXXXX> <notify|quiet>")
            }
            peripheral.execute(model.overrideRegister(characteristic, value: value, notify: notify))
        case "notify":
            guard parts.count == 2, let characteristic = characteristic(parts[1]) else {
                return commandError("usage: notify <CHAR>")
            }
            peripheral.execute(model.overrideRegister(
                characteristic,
                value: model.registers[characteristic],
                notify: true
            ))
        case "finish":
            peripheral.execute(model.forceFinishRun())
        case "apply-finish":
            peripheral.execute(model.forceFinishApply())
        case "faults":
            if model.faults.allRules.isEmpty {
                output.command("no fault rules")
            }
            for rule in model.faults.allRules {
                output.command("\(rule.id) type=\(rule.type.rawValue) enabled=\(model.faults.isEnabled(rule.id)) char=\(rule.characteristic?.rawValue ?? "any") occurrence=\(rule.onOccurrence.map(String.init) ?? "every")")
            }
        case "fault":
            guard parts.count == 3, let enabled = onOff(parts[2]) else {
                return commandError("usage: fault <id> <on|off>")
            }
            if !model.faults.setEnabled(parts[1], enabled: enabled) {
                commandError("unknown fault id: \(parts[1])")
            }
        case "session-end":
            let hadActiveSession = model.sessionActive
            peripheral.execute(model.sessionEnded(source: "manual-command"))
            if hadActiveSession {
                output.command("Observed Session End simulated only; no BLE link was disconnected.")
            } else {
                output.command("No active session; Disconnect Policy was not applied; no BLE link was disconnected.")
            }
        case "session-begin":
            peripheral.execute(model.sessionBegan(source: "manual-command"))
        case "load":
            let path = String(trimmed.dropFirst(command.count)).trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { return commandError("usage: load <path.json>") }
            do {
                let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
                let scenario = try Scenario.load(from: url)
                replaceScenario(scenario)
            } catch {
                commandError("load failed: \(error.localizedDescription)")
            }
        case "reset":
            replaceScenario(model.scenario)
        case "power":
            guard parts.count == 2, let enabled = onOff(parts[1]) else {
                return commandError("usage: power <on|off>")
            }
            if enabled {
                guard !model.poweredOn else {
                    output.command("Device already Powered On")
                    break
                }
            } else {
                guard model.poweredOn else {
                    output.command("Device already Powered Off")
                    break
                }
            }
            let result = dispatch(.power(enabled), source: .cli)
            if !result.ok { commandError(result.message) }
        case "advertise":
            guard parts.count == 2, let enabled = onOff(parts[1]) else {
                return commandError("usage: advertise <on|off>")
            }
            guard model.poweredOn else {
                return commandError("advertise \(enabled ? "on" : "off") rejected: Device Powered Off")
            }
            peripheral.setAdvertisingEnabled(enabled)
        case "quit":
            peripheral.setAdvertisingEnabled(false)
            output.command("crystal-sim exiting normally")
            exit(0)
        default:
            commandError("unknown command: \(command); type 'help'")
        }
    }

    private func replaceScenario(_ scenario: Scenario) {
        let result = scenarioReplacementResult(scenario)
        if !result.ok {
            commandError(result.message)
        }
    }

    private func scenarioReplacementResult(_ scenario: Scenario) -> ControlResult {
        guard model.poweredOn else {
            return .failure(409, "scenario reload rejected: Device Powered Off")
        }
        guard peripheral.canReload else {
            return .failure(409, "scenario reload rejected: end the session and disconnect phone/tablet subscriptions first")
        }
        let newModel = DeviceModel(scenario: scenario, logger: logger)
        model = newModel
        peripheral.replaceModel(newModel)
        output.command("scenario loaded: \(scenario.name); timers, Apply, faults and dedup were reset")
        return .success("scenario loaded: \(scenario.name)")
    }

    private func characteristic(_ text: String) -> Characteristic? {
        Characteristic(rawValue: text.uppercased())
    }

    private func parseUInt16(_ text: String) -> UInt16? {
        if text.hasPrefix("0x") || text.hasPrefix("0X") {
            return UInt16(text.dropFirst(2), radix: 16)
        }
        return UInt16(text)
    }

    private func notificationFlag(_ text: String) -> Bool? {
        switch text.lowercased() {
        case "notify": return true
        case "quiet": return false
        default: return nil
        }
    }

    private func onOff(_ text: String) -> Bool? {
        switch text.lowercased() {
        case "on": return true
        case "off": return false
        default: return nil
        }
    }

    private func commandError(_ message: String) {
        logger.record(.error, message, scenario: model.scenario.name)
    }
}
