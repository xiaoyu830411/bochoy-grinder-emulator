import Foundation
import CrystalCore

public struct ControlValidationError: Error, Equatable, LocalizedError, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

public enum OverrideNotification: String, Codable, Sendable {
    case notify
    case quiet
}

public enum ControlCommand: Equatable, Sendable {
    case power(Bool)
    case start(RunMode)
    case stop
    case setMotor(UInt16)
    case setFeed(UInt16)
    case setTarget(UInt16)
    case apply
    case setTargetAndApply(UInt16)
    case finishRun
    case finishApply
    case override(characteristic: Characteristic, value: UInt16, notify: Bool)
    case advertising(Bool)
    case session(Bool)
    case loadScenario(String)
    case resetScenario
    case setFault(id: String, enabled: Bool)
    case disconnectCentral(UUID)
    case markObservationDisconnected(UUID)
    case hideObservation(UUID)
    case restoreObservation(UUID)
    case restoreHiddenObservations
}

public struct ControlRequest: Codable, Sendable {
    public let action: String
    public let mode: RunMode?
    public let value: UInt16?
    public let characteristic: Characteristic?
    public let notification: OverrideNotification?
    public let enabled: Bool?
    public let scenario: String?
    public let faultID: String?
    public let centralID: UUID?
    public let recordID: UUID?

    public static func decode(_ data: Data) throws -> ControlCommand {
        let request: ControlRequest
        do {
            request = try JSONDecoder().decode(ControlRequest.self, from: data)
        } catch {
            throw ControlValidationError("Invalid JSON control request")
        }
        return try request.validated()
    }

    public func validated() throws -> ControlCommand {
        switch action {
        case "start":
            try only("mode")
            return .start(try required(mode, name: "mode"))
        case "stop":
            try only()
            return .stop
        case "setMT":
            try only("value")
            return .setMotor(try required(value, name: "value"))
        case "setXD":
            try only("value")
            return .setFeed(try required(value, name: "value"))
        case "setTF":
            try only("value")
            return .setTarget(try required(value, name: "value"))
        case "apply":
            try only()
            return .apply
        case "setTFAndApply":
            try only("value")
            return .setTargetAndApply(try required(value, name: "value"))
        case "powerOff":
            try only()
            return .power(false)
        case "powerOn":
            try only()
            return .power(true)
        case "finishRun":
            try only()
            return .finishRun
        case "finishApply":
            try only()
            return .finishApply
        case "override":
            try only("characteristic", "value", "notification")
            let notification = try required(self.notification, name: "notification")
            return .override(
                characteristic: try required(characteristic, name: "characteristic"),
                value: try required(value, name: "value"),
                notify: notification == .notify
            )
        case "advertising":
            try only("enabled")
            return .advertising(try required(enabled, name: "enabled"))
        case "sessionBegin":
            try only()
            return .session(true)
        case "sessionEnd":
            try only()
            return .session(false)
        case "scenarioLoad":
            try only("scenario")
            let scenario = try required(self.scenario, name: "scenario")
            guard !scenario.isEmpty, !scenario.contains(".."),
                  !scenario.contains("/"), !scenario.contains("\\") else {
                throw ControlValidationError("Scenario must be a catalog name, not a path")
            }
            return .loadScenario(scenario)
        case "scenarioReset":
            try only()
            return .resetScenario
        case "faultSet":
            try only("faultID", "enabled")
            let faultID = try required(self.faultID, name: "faultID")
            guard !faultID.isEmpty else { throw ControlValidationError("faultID must not be empty") }
            return .setFault(id: faultID, enabled: try required(enabled, name: "enabled"))
        case "disconnectCentral":
            try only("centralID")
            return .disconnectCentral(try required(centralID, name: "centralID"))
        case "markObservationDisconnected":
            try only("recordID")
            return .markObservationDisconnected(try required(recordID, name: "recordID"))
        case "hideObservation":
            try only("recordID")
            return .hideObservation(try required(recordID, name: "recordID"))
        case "restoreObservation":
            try only("recordID")
            return .restoreObservation(try required(recordID, name: "recordID"))
        case "restoreHiddenObservations":
            try only()
            return .restoreHiddenObservations
        default:
            throw ControlValidationError("Unknown control action")
        }
    }

    private func required<T>(_ value: T?, name: String) throws -> T {
        guard let value else { throw ControlValidationError("Missing parameter: \(name)") }
        return value
    }

    private func only(_ allowed: String...) throws {
        let supplied: [(String, Bool)] = [
            ("mode", mode != nil),
            ("value", value != nil),
            ("characteristic", characteristic != nil),
            ("notification", notification != nil),
            ("enabled", enabled != nil),
            ("scenario", scenario != nil),
            ("faultID", faultID != nil),
            ("centralID", centralID != nil),
            ("recordID", recordID != nil),
        ]
        let unexpected = supplied.filter { $0.1 && !allowed.contains($0.0) }.map(\.0)
        guard unexpected.isEmpty else {
            throw ControlValidationError("Unexpected parameter for \(action): \(unexpected[0])")
        }
    }
}
