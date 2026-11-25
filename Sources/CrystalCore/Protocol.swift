import Foundation

public enum Characteristic: String, Codable, CaseIterable, Sendable {
    case mtRPM = "MT_RPM"
    case xdRPM = "XD_RPM"
    case bootSign = "BOOT_SIGN"
    case sysState = "SYS_STATE"
    case servoAngle = "SERVO_ANGLE"
    case tfAngle = "TF_ANGLE"

    public var uuid: String {
        let suffix: String
        switch self {
        case .mtRPM: suffix = "01"
        case .xdRPM: suffix = "02"
        case .bootSign: suffix = "03"
        case .sysState: suffix = "04"
        case .servoAngle: suffix = "05"
        case .tfAngle: suffix = "06"
        }
        return "7fa2d10c-12f3-4b9e-9d77-1a9b654321\(suffix)"
    }

    public var writableRange: ClosedRange<UInt16>? {
        switch self {
        case .mtRPM, .servoAngle, .tfAngle: return 0...1500
        case .xdRPM: return 0...150
        case .bootSign: return 0...10
        case .sysState: return nil
        }
    }

    public var isRequiredSubscription: Bool {
        switch self {
        case .mtRPM, .sysState, .servoAngle: return true
        case .xdRPM, .bootSign, .tfAngle: return false
        }
    }
}

public enum UInt16Codec {
    public static func encode(_ value: UInt16) -> Data {
        Data([UInt8(value >> 8), UInt8(value & 0xff)])
    }

    public static func decode(_ data: Data) -> UInt16? {
        guard data.count == 2 else { return nil }
        return (UInt16(data[data.startIndex]) << 8) | UInt16(data[data.index(after: data.startIndex)])
    }

    public static func hex(_ value: UInt16) -> String {
        encode(value).map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    public static func base64(_ value: UInt16) -> String {
        encode(value).base64EncodedString()
    }
}

public struct RegisterValues: Codable, Equatable, Sendable {
    public var mtRPM: UInt16
    public var xdRPM: UInt16
    public var bootSign: UInt16
    public var sysState: UInt16
    public var servoAngle: UInt16
    public var tfAngle: UInt16

    public static let `default` = RegisterValues(
        mtRPM: 900,
        xdRPM: 40,
        bootSign: 0,
        sysState: 0,
        servoAngle: 830,
        tfAngle: 830
    )

    public init(
        mtRPM: UInt16,
        xdRPM: UInt16,
        bootSign: UInt16,
        sysState: UInt16,
        servoAngle: UInt16,
        tfAngle: UInt16
    ) {
        self.mtRPM = mtRPM
        self.xdRPM = xdRPM
        self.bootSign = bootSign
        self.sysState = sysState
        self.servoAngle = servoAngle
        self.tfAngle = tfAngle
    }

    public subscript(characteristic: Characteristic) -> UInt16 {
        get {
            switch characteristic {
            case .mtRPM: return mtRPM
            case .xdRPM: return xdRPM
            case .bootSign: return bootSign
            case .sysState: return sysState
            case .servoAngle: return servoAngle
            case .tfAngle: return tfAngle
            }
        }
        set {
            switch characteristic {
            case .mtRPM: mtRPM = newValue
            case .xdRPM: xdRPM = newValue
            case .bootSign: bootSign = newValue
            case .sysState: sysState = newValue
            case .servoAngle: servoAngle = newValue
            case .tfAngle: tfAngle = newValue
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case mtRPM, xdRPM, bootSign, sysState, servoAngle, tfAngle
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            mtRPM: try container.decodeIfPresent(UInt16.self, forKey: .mtRPM) ?? 900,
            xdRPM: try container.decodeIfPresent(UInt16.self, forKey: .xdRPM) ?? 40,
            bootSign: try container.decodeIfPresent(UInt16.self, forKey: .bootSign) ?? 0,
            sysState: try container.decodeIfPresent(UInt16.self, forKey: .sysState) ?? 0,
            servoAngle: try container.decodeIfPresent(UInt16.self, forKey: .servoAngle) ?? 830,
            tfAngle: try container.decodeIfPresent(UInt16.self, forKey: .tfAngle) ?? 830
        )
    }
}

public enum ATTStatus {
    public static let success: UInt8 = 0x00
    public static let readNotPermitted: UInt8 = 0x02
    public static let writeNotPermitted: UInt8 = 0x03
    public static let requestNotSupported: UInt8 = 0x06
    public static let invalidOffset: UInt8 = 0x07
    public static let invalidAttributeValueLength: UInt8 = 0x0d
    public static let unlikelyError: UInt8 = 0x0e
    public static let insufficientResources: UInt8 = 0x11
}
