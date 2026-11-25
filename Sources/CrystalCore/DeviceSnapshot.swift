import Foundation

public struct FaultSnapshot: Codable, Equatable, Sendable {
    public let rule: FaultRule
    public let enabled: Bool

    public init(rule: FaultRule, enabled: Bool) {
        self.rule = rule
        self.enabled = enabled
    }
}

public struct DeviceSnapshot: Codable, Equatable, Sendable {
    public let scenarioName: String
    public let deviceName: String
    public let disconnectPolicy: DisconnectPolicy
    public let registers: RegisterValues
    public let poweredOn: Bool
    public let activeRun: ActiveRun?
    public let pendingApply: PendingApply?
    public let sessionActive: Bool
    public let timersPaused: Bool
    public let faults: [FaultSnapshot]

    public init(
        scenarioName: String,
        deviceName: String,
        disconnectPolicy: DisconnectPolicy,
        registers: RegisterValues,
        poweredOn: Bool,
        activeRun: ActiveRun?,
        pendingApply: PendingApply?,
        sessionActive: Bool,
        timersPaused: Bool,
        faults: [FaultSnapshot]
    ) {
        self.scenarioName = scenarioName
        self.deviceName = deviceName
        self.disconnectPolicy = disconnectPolicy
        self.registers = registers
        self.poweredOn = poweredOn
        self.activeRun = activeRun
        self.pendingApply = pendingApply
        self.sessionActive = sessionActive
        self.timersPaused = timersPaused
        self.faults = faults
    }

    private enum CodingKeys: String, CodingKey {
        case scenarioName, deviceName, disconnectPolicy, registers, poweredOn
        case activeRun, pendingApply, sessionActive, timersPaused, faults
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scenarioName, forKey: .scenarioName)
        try container.encode(deviceName, forKey: .deviceName)
        try container.encode(disconnectPolicy, forKey: .disconnectPolicy)
        try container.encode(registers, forKey: .registers)
        try container.encode(poweredOn, forKey: .poweredOn)
        if let activeRun {
            try container.encode(activeRun, forKey: .activeRun)
        } else {
            try container.encodeNil(forKey: .activeRun)
        }
        if let pendingApply {
            try container.encode(pendingApply, forKey: .pendingApply)
        } else {
            try container.encodeNil(forKey: .pendingApply)
        }
        try container.encode(sessionActive, forKey: .sessionActive)
        try container.encode(timersPaused, forKey: .timersPaused)
        try container.encode(faults, forKey: .faults)
    }
}

extension DeviceModel {
    public func snapshot() -> DeviceSnapshot {
        DeviceSnapshot(
            scenarioName: scenario.name,
            deviceName: scenario.deviceName,
            disconnectPolicy: scenario.behavior.disconnectPolicy,
            registers: registers,
            poweredOn: poweredOn,
            activeRun: activeRun,
            pendingApply: pendingApply,
            sessionActive: sessionActive,
            timersPaused: timersPaused,
            faults: faults.allRules.map {
                FaultSnapshot(rule: $0, enabled: faults.isEnabled($0.id))
            }
        )
    }
}
