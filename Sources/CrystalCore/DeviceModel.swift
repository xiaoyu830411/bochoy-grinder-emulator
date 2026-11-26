import Foundation

public struct PendingApply: Codable, Equatable, Sendable {
    public let id: UInt64
    public let target: UInt16
}

public struct ActiveRun: Codable, Equatable, Sendable {
    public let id: UInt64
    public let mode: RunMode
}

public enum ModelEffect: Equatable, Sendable {
    case notify(characteristic: Characteristic, value: UInt16)
    case scheduleApply(id: UInt64, target: UInt16, delayMs: UInt64)
    case scheduleRun(id: UInt64, delayMs: UInt64)
    case cancelApply(id: UInt64)
    case cancelRun(id: UInt64)
    case scheduleStateReset(id: UInt64, delayMs: UInt64)
    case cancelStateReset(id: UInt64)
    case pauseTimers
    case resumeTimers
    case terminateProcess
}

public enum NormalWriteSource: String, Codable, Sendable {
    case ble
    case web
}

public struct NormalWritePreparation: Equatable, Sendable {
    public let status: UInt8
    public let faultID: String?
    public let value: UInt16?
    public let effects: [ModelEffect]

    public init(status: UInt8, faultID: String?, value: UInt16?, effects: [ModelEffect]) {
        self.status = status
        self.faultID = faultID
        self.value = value
        self.effects = effects
    }

    public var succeeded: Bool { status == ATTStatus.success }
}

@MainActor
public final class DeviceModel {
    public let scenario: Scenario
    public let logger: EventLog
    public let faults: FaultEngine

    public private(set) var registers: RegisterValues
    public private(set) var activeRun: ActiveRun?
    public private(set) var pendingApply: PendingApply?
    public private(set) var pendingStateResetID: UInt64?
    public private(set) var sessionActive = false
    public private(set) var timersPaused = false
    public private(set) var poweredOn = true

    private var runCounter: UInt64 = 0
    private var applyCounter: UInt64 = 0
    private var stateResetCounter: UInt64 = 0
    private var notificationBaseline: [Characteristic: UInt16] = [:]

    public var runMode: RunMode? { activeRun?.mode }

    public init(scenario: Scenario, logger: EventLog) {
        self.scenario = scenario
        self.logger = logger
        self.registers = scenario.initialRegisters
        self.notificationBaseline = Dictionary(
            uniqueKeysWithValues: Characteristic.allCases
                .filter { $0 != .bootSign }
                .map { ($0, scenario.initialRegisters[$0]) }
        )
        self.faults = FaultEngine(rules: scenario.faults, logger: logger, scenarioName: scenario.name)
        logger.record(
            .scenario,
            "scenario initialized",
            scenario: scenario.name,
            after: registers,
            details: ["deviceName": scenario.deviceName]
        )
    }

    public func data(for characteristic: Characteristic) -> Data {
        UInt16Codec.encode(registers[characteristic])
    }

    public func prepareWrite(
        _ data: Data,
        to characteristic: Characteristic,
        source: NormalWriteSource
    ) -> NormalWritePreparation {
        let value = UInt16Codec.decode(data)
        if !poweredOn {
            let effects = write(data, to: characteristic, source: source)
            return NormalWritePreparation(
                status: ATTStatus.writeNotPermitted,
                faultID: nil,
                value: value,
                effects: effects
            )
        }
        if let error = faults.attError(.writeError, characteristic: characteristic, value: value) {
            logger.record(
                .write,
                "write rejected by injected ATT error; model unchanged",
                scenario: scenario.name,
                characteristic: characteristic,
                value: value,
                raw: data,
                attStatus: error.status,
                before: registers,
                after: registers,
                faultID: error.faultID,
                details: ["source": source.rawValue]
            )
            return NormalWritePreparation(
                status: error.status,
                faultID: error.faultID,
                value: value,
                effects: []
            )
        }
        return NormalWritePreparation(
            status: ATTStatus.success,
            faultID: nil,
            value: value,
            effects: write(data, to: characteristic, source: source)
        )
    }

    @discardableResult
    public func write(_ data: Data, to characteristic: Characteristic) -> [ModelEffect] {
        write(data, to: characteristic, source: .ble)
    }

    @discardableResult
    private func write(
        _ data: Data,
        to characteristic: Characteristic,
        source: NormalWriteSource
    ) -> [ModelEffect] {
        guard poweredOn else {
            logger.record(
                .control,
                "normal write rejected: Device Powered Off",
                scenario: scenario.name,
                characteristic: characteristic,
                raw: data,
                attStatus: ATTStatus.writeNotPermitted,
                before: registers,
                after: registers,
                details: ["source": source.rawValue]
            )
            return []
        }
        let before = registers
        let decoded = UInt16Codec.decode(data)
        logger.record(
            .write,
            "write received",
            scenario: scenario.name,
            characteristic: characteristic,
            value: decoded,
            raw: data,
            before: before,
            after: registers,
            details: ["source": source.rawValue]
        )

        guard data.count == 2, let value = decoded else {
            logger.record(
                .write,
                "invalid length ignored; current value retained without notification",
                scenario: scenario.name,
                characteristic: characteristic,
                raw: data,
                attStatus: ATTStatus.success,
                before: before,
                after: registers,
                details: ["action": "retainedCurrentValue"]
            )
            return []
        }
        if let range = characteristic.writableRange, !range.contains(value) {
            logger.record(
                .write,
                "out-of-range value ignored without writeback or notification",
                scenario: scenario.name,
                characteristic: characteristic,
                value: value,
                attStatus: ATTStatus.success,
                before: before,
                after: registers
            )
            return []
        }

        var effects: [ModelEffect]
        let eligibleForTermination: Bool
        switch characteristic {
        case .sysState, .servoAngle:
            logger.record(
                .write,
                "protocol violation ignored: state/current-value writes have no defined behavior",
                scenario: scenario.name,
                characteristic: characteristic,
                value: value,
                attStatus: ATTStatus.success,
                before: before,
                after: registers
            )
            effects = []
            eligibleForTermination = false
        case .mtRPM, .xdRPM, .tfAngle:
            effects = setRegister(characteristic, value: value, source: "\(source.rawValue)-write")
            eligibleForTermination = true
        case .bootSign:
            effects = writeBootSign(value, source: source)
            eligibleForTermination = (1...5).contains(value)
        }

        if eligibleForTermination && faults.shouldApply(.terminateProcess, characteristic: characteristic, value: value) {
            effects.append(.terminateProcess)
        }
        return effects
    }

    private func writeBootSign(_ value: UInt16, source: NormalWriteSource) -> [ModelEffect] {
        guard (1...5).contains(value) else {
            logger.record(
                .write,
                "reserved BOOT_SIGN command ignored; command register retained",
                scenario: scenario.name,
                characteristic: .bootSign,
                value: value,
                before: registers,
                after: registers
            )
            return []
        }

        var effects = setRegister(.bootSign, value: value, source: "\(source.rawValue)-command")
        switch value {
        case 1:
            effects.append(contentsOf: start(mode: .manual))
        case 2:
            effects.append(contentsOf: start(mode: .timed))
        case 3:
            effects.append(contentsOf: start(mode: .smart))
        case 4:
            effects.append(contentsOf: stopRun(source: "\(source.rawValue)-stop", testOverride: false))
        case 5:
            effects.append(contentsOf: beginApply())
        default:
            break
        }
        return effects
    }

    private func start(mode: RunMode) -> [ModelEffect] {
        let previousMode = runMode
        var effects = cancelStateReset()
        if let activeRun {
            effects.append(.cancelRun(id: activeRun.id))
        }
        runCounter += 1
        let run = ActiveRun(id: runCounter, mode: mode)
        activeRun = run
        logger.record(
            .runMode,
            "run started or restarted; previous timer replaced",
            scenario: scenario.name,
            before: registers,
            after: registers,
            runMode: mode,
            details: [
                "runID": String(run.id),
                "previousMode": previousMode?.rawValue ?? "none",
            ]
        )
        effects.append(contentsOf: setRegister(.sysState, value: 1, source: "run-start"))

        let duration: UInt64?
        switch mode {
        case .manual: duration = nil
        case .timed: duration = scenario.behavior.timedDurationMs
        case .smart: duration = scenario.behavior.smartDurationMs
        }
        if let duration {
            effects.append(.scheduleRun(id: run.id, delayMs: duration))
            logger.record(
                .runMode,
                "automatic run completion scheduled",
                scenario: scenario.name,
                runMode: mode,
                details: ["runID": String(run.id), "delayMs": String(duration)]
            )
        }
        return effects
    }

    private func stopRun(source: String, testOverride: Bool) -> [ModelEffect] {
        var effects = cancelStateReset()
        let previousMode = runMode
        if let activeRun {
            effects.append(.cancelRun(id: activeRun.id))
        }
        activeRun = nil
        logger.record(
            testOverride ? .override : .runMode,
            "run stopped; pending Apply is intentionally retained",
            scenario: scenario.name,
            before: registers,
            after: registers,
            runMode: previousMode,
            testOverride: testOverride,
            details: ["source": source]
        )
        effects.append(contentsOf: setRegister(.sysState, value: 0, source: source, testOverride: testOverride))
        return effects
    }

    private func beginApply() -> [ModelEffect] {
        var effects: [ModelEffect] = []
        effects.append(contentsOf: setRegister(.sysState, value: 1, source: "apply-start"))
        if activeRun == nil {
            effects.append(contentsOf: scheduleStateReset())
        } else {
            effects.append(contentsOf: cancelStateReset())
        }
        if let pendingApply {
            effects.append(.cancelApply(id: pendingApply.id))
            logger.record(
                .apply,
                "previous Apply superseded",
                scenario: scenario.name,
                value: pendingApply.target,
                details: ["applyID": String(pendingApply.id)]
            )
        }
        applyCounter += 1
        let apply = PendingApply(id: applyCounter, target: registers.tfAngle)
        pendingApply = apply
        let delay = faults.maximumDelay(.applyDelay, characteristic: .bootSign, value: 5) ?? 0
        logger.record(
            .apply,
            "Apply created with captured target",
            scenario: scenario.name,
            characteristic: .tfAngle,
            value: apply.target,
            before: registers,
            after: registers,
            details: ["applyID": String(apply.id), "delayMs": String(delay)]
        )
        if delay > 0 {
            effects.append(.scheduleApply(id: apply.id, target: apply.target, delayMs: delay))
        } else {
            effects.append(contentsOf: completeApply(id: apply.id))
        }
        return effects
    }

    public func completeApply(id: UInt64, ignoringStall: Bool = false, testOverride: Bool = false) -> [ModelEffect] {
        guard let pendingApply, pendingApply.id == id else { return [] }
        if !ignoringStall && faults.shouldApply(.applyStall) {
            logger.record(
                .apply,
                "Apply completion stalled; captured target remains pending",
                scenario: scenario.name,
                value: pendingApply.target,
                details: ["applyID": String(id)]
            )
            return []
        }
        self.pendingApply = nil
        logger.record(
            testOverride ? .override : .apply,
            "Apply completed with captured target",
            scenario: scenario.name,
            characteristic: .servoAngle,
            value: pendingApply.target,
            before: registers,
            after: registers,
            testOverride: testOverride,
            details: ["applyID": String(id)]
        )
        return setRegister(
            .servoAngle,
            value: pendingApply.target,
            source: testOverride ? "apply-test-override" : "apply-complete",
            testOverride: testOverride
        )
    }

    public func forceFinishApply() -> [ModelEffect] {
        guard let pendingApply else { return [] }
        var effects: [ModelEffect] = [.cancelApply(id: pendingApply.id)]
        effects.append(contentsOf: completeApply(id: pendingApply.id, ignoringStall: true, testOverride: true))
        return effects
    }

    private func scheduleStateReset(delayMs: UInt64 = 5_000) -> [ModelEffect] {
        var effects = cancelStateReset()
        stateResetCounter += 1
        pendingStateResetID = stateResetCounter
        effects.append(.scheduleStateReset(id: stateResetCounter, delayMs: delayMs))
        return effects
    }

    private func cancelStateReset() -> [ModelEffect] {
        guard let id = pendingStateResetID else { return [] }
        pendingStateResetID = nil
        return [.cancelStateReset(id: id)]
    }

    public func completeStateReset(id: UInt64) -> [ModelEffect] {
        guard pendingStateResetID == id, poweredOn else { return [] }
        pendingStateResetID = nil
        guard activeRun == nil else { return [] }
        return setRegister(.sysState, value: 0, source: "apply-auto-idle")
    }

    public func completeRun(id: UInt64) -> [ModelEffect] {
        guard let activeRun, activeRun.id == id else { return [] }
        if faults.shouldApply(.runStall) {
            logger.record(
                .runMode,
                "automatic run completion stalled",
                scenario: scenario.name,
                runMode: activeRun.mode,
                details: ["runID": String(id)]
            )
            return []
        }
        self.activeRun = nil
        logger.record(
            .runMode,
            "automatic run completion",
            scenario: scenario.name,
            before: registers,
            after: registers,
            runMode: activeRun.mode,
            details: ["runID": String(id)]
        )
        return setRegister(.sysState, value: 0, source: "run-auto-complete")
    }

    public func forceFinishRun() -> [ModelEffect] {
        stopRun(source: "run-test-override", testOverride: true)
    }

    public func overrideRegister(
        _ characteristic: Characteristic,
        value: UInt16,
        notify: Bool
    ) -> [ModelEffect] {
        let before = registers
        var effects: [ModelEffect] = []
        if characteristic == .sysState {
            effects.append(contentsOf: cancelStateReset())
        }
        if characteristic == .servoAngle, let pendingApply {
            effects.append(.cancelApply(id: pendingApply.id))
            self.pendingApply = nil
            logger.record(
                .override,
                "SERVO_ANGLE override cancelled pending Apply",
                scenario: scenario.name,
                characteristic: characteristic,
                value: value,
                testOverride: true,
                details: ["applyID": String(pendingApply.id)]
            )
            effects.append(contentsOf: cancelStateReset())
            if activeRun == nil {
                effects.append(contentsOf: setRegister(
                    .sysState,
                    value: 0,
                    source: "servo-override-cancels-apply",
                    testOverride: true
                ))
            }
        }
        var overriddenRegisters = registers
        overriddenRegisters[characteristic] = value
        logger.record(
            .override,
            "register Test Override",
            scenario: scenario.name,
            characteristic: characteristic,
            value: value,
            before: before,
            after: overriddenRegisters,
            testOverride: true,
            details: ["notify": notify ? "true" : "false"]
        )
        effects.append(contentsOf: setRegister(
            characteristic,
            value: value,
            source: "test-override",
            testOverride: true,
            forceNotification: notify,
            suppressNotification: !notify
        ))
        return effects
    }

    private func setRegister(
        _ characteristic: Characteristic,
        value: UInt16,
        source: String,
        testOverride: Bool = false,
        forceNotification: Bool = false,
        suppressNotification: Bool = false
    ) -> [ModelEffect] {
        let before = registers
        let oldValue = registers[characteristic]
        registers[characteristic] = value
        let changed = oldValue != value
        if changed {
            logger.record(
                testOverride ? .override : .register,
                "register changed",
                scenario: scenario.name,
                characteristic: characteristic,
                value: value,
                before: before,
                after: registers,
                runMode: runMode,
                testOverride: testOverride,
                details: ["oldValue": String(oldValue), "source": source]
            )
        }

        if suppressNotification {
            notificationBaseline[characteristic] = value
            logger.record(
                .notification,
                testOverride
                    ? "notification suppressed by Test Override; synchronization baseline updated"
                    : "notification suppressed for Device Power; synchronization baseline updated",
                scenario: scenario.name,
                characteristic: characteristic,
                value: value,
                testOverride: testOverride,
                details: [
                    "source": source,
                    "reason": testOverride ? "test-override" : "device-power",
                ]
            )
            return []
        }
        if characteristic == .bootSign && !forceNotification { return [] }
        if !forceNotification, notificationBaseline[characteristic] == value {
            logger.record(
                .notification,
                changed
                    ? "notification deduplicated: value matches synchronization baseline"
                    : "notification deduplicated: value unchanged",
                scenario: scenario.name,
                characteristic: characteristic,
                value: value,
                details: ["source": source]
            )
            return []
        }
        if !changed && !forceNotification {
            logger.record(
                .notification,
                "first synchronization after session reset publishes the unchanged value",
                scenario: scenario.name,
                characteristic: characteristic,
                value: value,
                details: ["source": source]
            )
        }
        notificationBaseline[characteristic] = value
        return [.notify(characteristic: characteristic, value: value)]
    }

    @discardableResult
    public func powerOff(source: String) -> [ModelEffect] {
        guard poweredOn else { return [] }
        let before = registers
        poweredOn = false
        var effects = cancelStateReset()
        if let activeRun {
            effects.append(.cancelRun(id: activeRun.id))
            self.activeRun = nil
        }
        if let pendingApply {
            effects.append(.cancelApply(id: pendingApply.id))
            self.pendingApply = nil
        }
        effects.append(contentsOf: setRegister(
            .sysState,
            value: 0,
            source: "device-power-off",
            suppressNotification: true
        ))
        logger.record(
            .control,
            "Device Powered Off; active Run and pending Apply cancelled",
            scenario: scenario.name,
            before: before,
            after: registers,
            details: ["source": source, "poweredOn": "false"]
        )
        return effects
    }

    @discardableResult
    public func powerOn(source: String) -> [ModelEffect] {
        guard !poweredOn else { return [] }
        let before = registers
        poweredOn = true
        activeRun = nil
        pendingApply = nil
        var effects = cancelStateReset()
        for characteristic: Characteristic in [.mtRPM, .xdRPM, .tfAngle, .bootSign] {
            registers[characteristic] = 0
            notificationBaseline[characteristic] = 0
        }
        effects.append(contentsOf: setRegister(
            .sysState,
            value: 0,
            source: "device-power-on",
            suppressNotification: true
        ))
        logger.record(
            .control,
            "Device Powered On in idle state; volatile settings reset, SERVO_ANGLE retained",
            scenario: scenario.name,
            before: before,
            after: registers,
            details: ["source": source, "poweredOn": "true"]
        )
        return effects
    }

    public func sessionBegan(source: String) -> [ModelEffect] {
        guard !sessionActive else { return [] }
        sessionActive = true
        notificationBaseline.removeAll()
        logger.record(
            .session,
            "session began; notification deduplication reset",
            scenario: scenario.name,
            after: registers,
            details: ["source": source]
        )
        guard timersPaused else { return [] }
        timersPaused = false
        logger.record(.session, "paused device timers resumed", scenario: scenario.name)
        return [.resumeTimers]
    }

    public func sessionEnded(source: String) -> [ModelEffect] {
        guard sessionActive else {
            logger.record(
                .session,
                "session end ignored because no session is active",
                scenario: scenario.name,
                details: ["source": source]
            )
            return []
        }
        sessionActive = false
        logger.record(
            .session,
            "Observed Session End; applying Disconnect Policy",
            scenario: scenario.name,
            before: registers,
            after: registers,
            details: [
                "source": source,
                "policy": scenario.behavior.disconnectPolicy.rawValue,
                "linkLossConfirmed": "false",
            ]
        )
        switch scenario.behavior.disconnectPolicy {
        case .pause:
            guard !timersPaused else { return [] }
            timersPaused = true
            logger.record(.session, "device timers paused", scenario: scenario.name)
            return [.pauseTimers]
        case .continue:
            logger.record(.session, "device timers continue", scenario: scenario.name)
            return []
        case .stop:
            logger.record(.session, "Disconnect Policy stops the run; Apply continues", scenario: scenario.name)
            return stopRun(source: "session-policy-stop", testOverride: false)
        }
    }

    public var statusLines: [String] {
        [
            "scenario=\(scenario.name) device=\(scenario.deviceName) poweredOn=\(poweredOn)",
            "SYS_STATE=\(registers.sysState) SERVO_ANGLE=\(registers.servoAngle) TF_ANGLE=\(registers.tfAngle)",
            "MT_RPM=\(registers.mtRPM) XD_RPM=\(registers.xdRPM) BOOT_SIGN=\(registers.bootSign)",
            "runMode=\(runMode?.rawValue ?? "none") runID=\(activeRun?.id.description ?? "none")",
            "pendingApply=\(pendingApply.map { "id=\($0.id),target=\($0.target)" } ?? "none")",
            "sessionActive=\(sessionActive) timersPaused=\(timersPaused)",
        ]
    }
}
