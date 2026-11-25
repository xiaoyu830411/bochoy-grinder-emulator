import Foundation

@MainActor
public final class FaultEngine {
    private let rules: [FaultRule]
    private let logger: EventLog
    private let scenarioName: String
    private var disabledIDs = Set<String>()
    private var candidateCounts: [String: Int] = [:]

    public init(rules: [FaultRule], logger: EventLog, scenarioName: String) {
        self.rules = rules
        self.logger = logger
        self.scenarioName = scenarioName
    }

    public var allRules: [FaultRule] { rules }

    public func isEnabled(_ id: String) -> Bool {
        rules.contains { $0.id == id } && !disabledIDs.contains(id)
    }

    @discardableResult
    public func setEnabled(_ id: String, enabled: Bool) -> Bool {
        guard rules.contains(where: { $0.id == id }) else { return false }
        if enabled {
            disabledIDs.remove(id)
        } else {
            disabledIDs.insert(id)
        }
        candidateCounts[id] = 0
        logger.record(
            .fault,
            "fault \(enabled ? "enabled" : "disabled")",
            scenario: scenarioName,
            faultID: id,
            details: ["enabled": enabled ? "true" : "false"]
        )
        return true
    }

    public func resetCounts() {
        candidateCounts.removeAll()
    }

    @discardableResult
    public func match(
        _ type: FaultType,
        characteristic: Characteristic? = nil,
        value: UInt16? = nil
    ) -> [FaultRule] {
        var triggered: [FaultRule] = []
        for rule in rules where rule.type == type && !disabledIDs.contains(rule.id) {
            if let expected = rule.characteristic, expected != characteristic { continue }
            if let expected = rule.value, expected != value { continue }

            let count = candidateCounts[rule.id, default: 0] + 1
            candidateCounts[rule.id] = count
            if let occurrence = rule.onOccurrence, occurrence != count { continue }
            if let maximum = rule.maxTriggers, count > maximum { continue }

            triggered.append(rule)
            logger.record(
                .fault,
                "fault triggered: \(type.rawValue)",
                scenario: scenarioName,
                characteristic: characteristic,
                value: value,
                faultID: rule.id,
                details: [
                    "occurrence": String(count),
                    "delayMs": rule.delayMs.map(String.init) ?? "",
                ]
            )
        }
        return triggered
    }

    public func maximumDelay(
        _ type: FaultType,
        characteristic: Characteristic? = nil,
        value: UInt16? = nil
    ) -> UInt64? {
        match(type, characteristic: characteristic, value: value).compactMap(\.delayMs).max()
    }

    public func attError(
        _ type: FaultType,
        characteristic: Characteristic,
        value: UInt16? = nil
    ) -> (status: UInt8, faultID: String)? {
        guard let rule = match(type, characteristic: characteristic, value: value).first else { return nil }
        return (rule.attStatus ?? ATTStatus.unlikelyError, rule.id)
    }

    public func shouldApply(
        _ type: FaultType,
        characteristic: Characteristic? = nil,
        value: UInt16? = nil
    ) -> Bool {
        !match(type, characteristic: characteristic, value: value).isEmpty
    }
}
