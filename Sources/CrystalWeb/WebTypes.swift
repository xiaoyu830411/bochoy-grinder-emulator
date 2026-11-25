import Foundation
import CrystalCore

public struct WebEndpoint: Equatable, Sendable {
    public let host: String
    public let port: UInt16

    public init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }

    public static func parse(_ text: String) throws -> WebEndpoint {
        let host: String
        let portText: String
        if text.hasPrefix("[") {
            guard let closing = text.firstIndex(of: "]") else {
                throw WebOptionError.invalidEndpoint("Web endpoint must be <host:port>")
            }
            let afterClosing = text.index(after: closing)
            guard afterClosing < text.endIndex, text[afterClosing] == ":" else {
                throw WebOptionError.invalidEndpoint("Web endpoint must be <host:port>")
            }
            host = String(text[text.index(after: text.startIndex)..<closing])
            portText = String(text[text.index(after: afterClosing)...])
        } else {
            guard let colon = text.lastIndex(of: ":"), text.firstIndex(of: ":") == colon else {
                throw WebOptionError.invalidEndpoint("Web endpoint must be <host:port>")
            }
            host = String(text[..<colon])
            portText = String(text[text.index(after: colon)...])
        }
        guard !host.isEmpty, !host.contains(where: { $0.isWhitespace || "/\\@?#".contains($0) }),
              let port = UInt16(portText), port > 0 else {
            throw WebOptionError.invalidEndpoint("Web endpoint must contain a valid host and port 1...65535")
        }
        return WebEndpoint(host: host, port: port)
    }

    public var description: String { "\(host):\(port)" }
}

public struct WebOptionError: Error, LocalizedError {
    public let message: String
    private init(_ message: String) { self.message = message }
    public static func invalidEndpoint(_ message: String) -> WebOptionError { WebOptionError(message) }
    public var errorDescription: String? { message }
}

public struct BluetoothSnapshot: Codable, Equatable, Sendable {
    public let state: Int
    public let advertising: Bool
    public let advertisingRequested: Bool
    public let advertisingStartPending: Bool
    public let publishedCharacteristics: Int
    public let subscriberIDs: [String]

    public init(
        state: Int,
        advertising: Bool,
        advertisingRequested: Bool,
        advertisingStartPending: Bool,
        publishedCharacteristics: Int,
        subscriberIDs: [String]
    ) {
        self.state = state
        self.advertising = advertising
        self.advertisingRequested = advertisingRequested
        self.advertisingStartPending = advertisingStartPending
        self.publishedCharacteristics = publishedCharacteristics
        self.subscriberIDs = subscriberIDs
    }
}

public struct SimulatorSnapshot: Codable, Equatable, Sendable {
    public let device: DeviceSnapshot
    public let bluetooth: BluetoothSnapshot
    public let centrals: [ObservedCentral]
    public let availableScenarios: [String]

    public init(
        device: DeviceSnapshot,
        bluetooth: BluetoothSnapshot,
        centrals: [ObservedCentral],
        availableScenarios: [String]
    ) {
        self.device = device
        self.bluetooth = bluetooth
        self.centrals = centrals
        self.availableScenarios = availableScenarios
    }
}

public enum ControlSource: String, Codable, Sendable {
    case cli
    case web
}

public struct ControlResult: Sendable {
    public let httpStatus: Int
    public let ok: Bool
    public let message: String
    public let attStatus: UInt8?
    public let faultID: String?

    public init(
        httpStatus: Int,
        ok: Bool,
        message: String,
        attStatus: UInt8? = nil,
        faultID: String? = nil
    ) {
        self.httpStatus = httpStatus
        self.ok = ok
        self.message = message
        self.attStatus = attStatus
        self.faultID = faultID
    }

    public static func success(_ message: String) -> ControlResult {
        ControlResult(httpStatus: 200, ok: true, message: message)
    }

    public static func failure(
        _ status: Int,
        _ message: String,
        attStatus: UInt8? = nil,
        faultID: String? = nil
    ) -> ControlResult {
        ControlResult(httpStatus: status, ok: false, message: message, attStatus: attStatus, faultID: faultID)
    }
}
