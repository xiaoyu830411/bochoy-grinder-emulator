import Foundation

public enum SimulationLimits {
    public static let maximumDelayMs: UInt64 = 86_400_000
}

public enum RunMode: String, Codable, Sendable {
    case manual
    case timed
    case smart
}

public enum DisconnectPolicy: String, Codable, Sendable {
    case pause
    case `continue`
    case stop
}

public enum FaultType: String, Codable, Sendable {
    case readError
    case writeError
    case responseDelay
    case notificationDrop
    case notificationDelay
    case notificationDuplicate
    case applyDelay
    case applyStall
    case runStall
    case terminateProcess
}

public struct BehaviorConfiguration: Codable, Equatable, Sendable {
    public var timedDurationMs: UInt64
    public var smartDurationMs: UInt64?
    public var disconnectPolicy: DisconnectPolicy

    public init(
        timedDurationMs: UInt64 = 5_000,
        smartDurationMs: UInt64? = 5_000,
        disconnectPolicy: DisconnectPolicy = .pause
    ) {
        self.timedDurationMs = timedDurationMs
        self.smartDurationMs = smartDurationMs
        self.disconnectPolicy = disconnectPolicy
    }

    private enum CodingKeys: String, CodingKey {
        case timedDurationMs, smartDurationMs, disconnectPolicy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let smartDuration: UInt64? = container.contains(.smartDurationMs)
            ? try container.decode(UInt64?.self, forKey: .smartDurationMs)
            : 5_000
        let timedDuration: UInt64 = container.contains(.timedDurationMs)
            ? try container.decode(UInt64.self, forKey: .timedDurationMs)
            : 5_000
        self.init(
            timedDurationMs: timedDuration,
            smartDurationMs: smartDuration,
            disconnectPolicy: try container.decodeIfPresent(DisconnectPolicy.self, forKey: .disconnectPolicy) ?? .pause
        )
    }
}

public struct LayoutConfiguration: Codable, Equatable, Sendable {
    public var includeService: Bool
    public var omittedCharacteristics: [Characteristic]
    public var notifyDisabled: [Characteristic]

    public init(
        includeService: Bool = true,
        omittedCharacteristics: [Characteristic] = [],
        notifyDisabled: [Characteristic] = []
    ) {
        self.includeService = includeService
        self.omittedCharacteristics = omittedCharacteristics
        self.notifyDisabled = notifyDisabled
    }

    private enum CodingKeys: String, CodingKey {
        case includeService, omittedCharacteristics, notifyDisabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            includeService: try container.decodeIfPresent(Bool.self, forKey: .includeService) ?? true,
            omittedCharacteristics: try container.decodeIfPresent([Characteristic].self, forKey: .omittedCharacteristics) ?? [],
            notifyDisabled: try container.decodeIfPresent([Characteristic].self, forKey: .notifyDisabled) ?? []
        )
    }
}

public struct FaultRule: Codable, Equatable, Sendable {
    public var id: String
    public var type: FaultType
    public var characteristic: Characteristic?
    public var value: UInt16?
    public var delayMs: UInt64?
    public var attStatus: UInt8?
    public var onOccurrence: Int?
    public var maxTriggers: Int?
    public var extraCopies: Int

    public init(
        id: String,
        type: FaultType,
        characteristic: Characteristic? = nil,
        value: UInt16? = nil,
        delayMs: UInt64? = nil,
        attStatus: UInt8? = nil,
        onOccurrence: Int? = nil,
        maxTriggers: Int? = nil,
        extraCopies: Int = 1
    ) {
        self.id = id
        self.type = type
        self.characteristic = characteristic
        self.value = value
        self.delayMs = delayMs
        self.attStatus = attStatus
        self.onOccurrence = onOccurrence
        self.maxTriggers = maxTriggers
        self.extraCopies = extraCopies
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, characteristic, value, delayMs, attStatus, onOccurrence, maxTriggers, extraCopies
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            type: try container.decode(FaultType.self, forKey: .type),
            characteristic: try container.decodeIfPresent(Characteristic.self, forKey: .characteristic),
            value: try container.decodeIfPresent(UInt16.self, forKey: .value),
            delayMs: try container.decodeIfPresent(UInt64.self, forKey: .delayMs),
            attStatus: try container.decodeIfPresent(UInt8.self, forKey: .attStatus),
            onOccurrence: try container.decodeIfPresent(Int.self, forKey: .onOccurrence),
            maxTriggers: try container.decodeIfPresent(Int.self, forKey: .maxTriggers),
            extraCopies: try container.decodeIfPresent(Int.self, forKey: .extraCopies) ?? 1
        )
    }
}

public struct Scenario: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var name: String
    public var deviceName: String
    public var initialRegisters: RegisterValues
    public var behavior: BehaviorConfiguration
    public var layout: LayoutConfiguration
    public var faults: [FaultRule]

    public static let `default` = Scenario(name: "default")

    public init(
        schemaVersion: Int = 1,
        name: String,
        deviceName: String = "CRYSTAL-E57C",
        initialRegisters: RegisterValues = .default,
        behavior: BehaviorConfiguration = BehaviorConfiguration(),
        layout: LayoutConfiguration = LayoutConfiguration(),
        faults: [FaultRule] = []
    ) {
        self.schemaVersion = schemaVersion
        self.name = name
        self.deviceName = deviceName
        self.initialRegisters = initialRegisters
        self.behavior = behavior
        self.layout = layout
        self.faults = faults
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, name, deviceName, initialRegisters, behavior, layout, faults
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1,
            name: try container.decodeIfPresent(String.self, forKey: .name) ?? "default",
            deviceName: try container.decodeIfPresent(String.self, forKey: .deviceName) ?? "CRYSTAL-E57C",
            initialRegisters: try container.decodeIfPresent(RegisterValues.self, forKey: .initialRegisters) ?? .default,
            behavior: try container.decodeIfPresent(BehaviorConfiguration.self, forKey: .behavior) ?? BehaviorConfiguration(),
            layout: try container.decodeIfPresent(LayoutConfiguration.self, forKey: .layout) ?? LayoutConfiguration(),
            faults: try container.decodeIfPresent([FaultRule].self, forKey: .faults) ?? []
        )
    }

    public func validated() throws -> Scenario {
        guard schemaVersion == 1 else {
            throw ScenarioError.invalid("schemaVersion must be 1")
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ScenarioError.invalid("scenario name must not be empty")
        }
        guard deviceName.range(of: #"^CRYSTAL-[0-9A-F]{4}$"#, options: .regularExpression) != nil else {
            throw ScenarioError.invalid("deviceName must match CRYSTAL-XXXX with four uppercase hex digits")
        }
        guard behavior.timedDurationMs <= SimulationLimits.maximumDelayMs else {
            throw ScenarioError.invalid("timedDurationMs must not exceed \(SimulationLimits.maximumDelayMs)")
        }
        if let smartDuration = behavior.smartDurationMs, smartDuration > SimulationLimits.maximumDelayMs {
            throw ScenarioError.invalid("smartDurationMs must not exceed \(SimulationLimits.maximumDelayMs)")
        }
        var ids = Set<String>()
        for fault in faults {
            guard !fault.id.isEmpty else { throw ScenarioError.invalid("fault id must not be empty") }
            guard ids.insert(fault.id).inserted else {
                throw ScenarioError.invalid("duplicate fault id: \(fault.id)")
            }
            if let occurrence = fault.onOccurrence, occurrence < 1 {
                throw ScenarioError.invalid("fault \(fault.id): onOccurrence must be at least 1")
            }
            if let maximum = fault.maxTriggers, maximum < 1 {
                throw ScenarioError.invalid("fault \(fault.id): maxTriggers must be at least 1")
            }
            if [.applyDelay, .applyStall, .runStall].contains(fault.type),
               fault.characteristic != nil || fault.value != nil {
                throw ScenarioError.invalid("fault \(fault.id): \(fault.type.rawValue) does not accept characteristic or value filters")
            }
            if [.readError, .writeError].contains(fault.type), fault.attStatus == 0 {
                throw ScenarioError.invalid("fault \(fault.id): attStatus 0 is success, not an error")
            }
            if ![.readError, .writeError].contains(fault.type), fault.attStatus != nil {
                throw ScenarioError.invalid("fault \(fault.id): attStatus is only valid for readError or writeError")
            }
            if [.responseDelay, .notificationDelay, .applyDelay].contains(fault.type), fault.delayMs == nil {
                throw ScenarioError.invalid("fault \(fault.id): delayMs is required")
            }
            if let delay = fault.delayMs, delay > SimulationLimits.maximumDelayMs {
                throw ScenarioError.invalid("fault \(fault.id): delayMs must not exceed \(SimulationLimits.maximumDelayMs)")
            }
            if [.readError, .writeError, .responseDelay, .notificationDrop, .notificationDelay, .notificationDuplicate].contains(fault.type),
               fault.characteristic == nil {
                throw ScenarioError.invalid("fault \(fault.id): characteristic is required")
            }
            if fault.type == .notificationDuplicate, fault.extraCopies <= 0 {
                throw ScenarioError.invalid("fault \(fault.id): extraCopies must be positive")
            }
        }
        return self
    }

    public static func load(from url: URL) throws -> Scenario {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Scenario.self, from: data).validated()
    }
}

public enum ScenarioError: Error, LocalizedError {
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        }
    }
}
