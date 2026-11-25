import Foundation

public enum EventKind: String, Codable, Sendable {
    case bluetooth
    case advertising
    case service
    case read
    case write
    case attResponse
    case subscription
    case session
    case register
    case runMode
    case apply
    case notification
    case scenario
    case fault
    case override
    case control
    case error
}

public struct SimEvent: Codable, Equatable, Sendable {
    public var sequence: UInt64
    public var timestamp: Date
    public var kind: EventKind
    public var message: String
    public var scenario: String?
    public var characteristic: Characteristic?
    public var hex: String?
    public var value: UInt16?
    public var base64: String?
    public var attStatus: UInt8?
    public var before: RegisterValues?
    public var after: RegisterValues?
    public var runMode: RunMode?
    public var faultID: String?
    public var testOverride: Bool
    public var details: [String: String]

    public init(
        sequence: UInt64,
        timestamp: Date,
        kind: EventKind,
        message: String,
        scenario: String? = nil,
        characteristic: Characteristic? = nil,
        hex: String? = nil,
        value: UInt16? = nil,
        base64: String? = nil,
        attStatus: UInt8? = nil,
        before: RegisterValues? = nil,
        after: RegisterValues? = nil,
        runMode: RunMode? = nil,
        faultID: String? = nil,
        testOverride: Bool = false,
        details: [String: String] = [:]
    ) {
        self.sequence = sequence
        self.timestamp = timestamp
        self.kind = kind
        self.message = message
        self.scenario = scenario
        self.characteristic = characteristic
        self.hex = hex
        self.value = value
        self.base64 = base64
        self.attStatus = attStatus
        self.before = before
        self.after = after
        self.runMode = runMode
        self.faultID = faultID
        self.testOverride = testOverride
        self.details = details
    }
}

@MainActor
public final class EventLog {
    public private(set) var events: [SimEvent] = []
    private var handlers: [(SimEvent) -> Void] = []
    private var nextSequence: UInt64 = 1
    private let now: () -> Date

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    public func addHandler(_ handler: @escaping (SimEvent) -> Void) {
        handlers.append(handler)
    }

    @discardableResult
    public func record(
        _ kind: EventKind,
        _ message: String,
        scenario: String? = nil,
        characteristic: Characteristic? = nil,
        value: UInt16? = nil,
        raw: Data? = nil,
        attStatus: UInt8? = nil,
        before: RegisterValues? = nil,
        after: RegisterValues? = nil,
        runMode: RunMode? = nil,
        faultID: String? = nil,
        testOverride: Bool = false,
        details: [String: String] = [:]
    ) -> SimEvent {
        let resolvedRaw = raw ?? value.map(UInt16Codec.encode)
        let event = SimEvent(
            sequence: nextSequence,
            timestamp: now(),
            kind: kind,
            message: message,
            scenario: scenario,
            characteristic: characteristic,
            hex: resolvedRaw.map { $0.map { String(format: "%02X", $0) }.joined(separator: " ") },
            value: value,
            base64: resolvedRaw?.base64EncodedString(),
            attStatus: attStatus,
            before: before,
            after: after,
            runMode: runMode,
            faultID: faultID,
            testOverride: testOverride,
            details: details
        )
        nextSequence += 1
        events.append(event)
        handlers.forEach { $0(event) }
        return event
    }

    public static func humanLine(_ event: SimEvent) -> String {
        var parts = [
            "#\(event.sequence)",
            ISO8601DateFormatter().string(from: event.timestamp),
            event.kind.rawValue,
            event.message,
        ]
        if let characteristic = event.characteristic {
            parts.append("char=\(characteristic.rawValue)")
        }
        if let value = event.value {
            parts.append("value=\(value)")
        }
        if let hex = event.hex {
            parts.append("hex=\(hex)")
        }
        if let base64 = event.base64 {
            parts.append("base64=\(base64)")
        }
        if let status = event.attStatus {
            parts.append(String(format: "att=0x%02X", status))
        }
        if let faultID = event.faultID {
            parts.append("fault=\(faultID)")
        }
        if event.testOverride {
            parts.append("TEST_OVERRIDE")
        }
        if let runMode = event.runMode {
            parts.append("runMode=\(runMode.rawValue)")
        }
        for key in event.details.keys.sorted() {
            parts.append("\(key)=\(event.details[key] ?? "")")
        }
        return parts.joined(separator: " ")
    }

    public static func jsonLine(_ event: SimEvent) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(event)
        return String(decoding: data, as: UTF8.self)
    }
}
