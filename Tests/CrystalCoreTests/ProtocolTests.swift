import Foundation
import XCTest
@testable import CrystalCore

final class ProtocolTests: XCTestCase {
    func testDocumentedEncodingVectors() {
        let vectors: [(UInt16, String, String)] = [
            (0, "00 00", "AAA="),
            (1, "00 01", "AAE="),
            (3, "00 03", "AAM="),
            (4, "00 04", "AAQ="),
            (5, "00 05", "AAU="),
            (88, "00 58", "AFg="),
            (150, "00 96", "AJY="),
            (830, "03 3E", "Az4="),
            (1200, "04 B0", "BLA="),
            (1500, "05 DC", "Bdw="),
        ]
        for (value, hex, base64) in vectors {
            XCTAssertEqual(UInt16Codec.hex(value), hex)
            XCTAssertEqual(UInt16Codec.base64(value), base64)
            XCTAssertEqual(UInt16Codec.decode(UInt16Codec.encode(value)), value)
        }
    }

    func testDecodeRequiresExactlyTwoBytesAndHandlesDataSlices() {
        XCTAssertNil(UInt16Codec.decode(Data()))
        XCTAssertNil(UInt16Codec.decode(Data([0x03])))
        XCTAssertNil(UInt16Codec.decode(Data([0x03, 0x3e, 0x00])))
        let slice = Data([0xff, 0x03, 0x3e, 0x00]).dropFirst().dropLast()
        XCTAssertEqual(UInt16Codec.decode(slice), 830)
    }

    func testPowerOnDefaultsMatchVendorConfirmedValues() {
        let values = RegisterValues.default
        XCTAssertEqual(values.sysState, 0)
        XCTAssertEqual(values.servoAngle, 830)
        XCTAssertEqual(values.tfAngle, 0)
        XCTAssertEqual(values.mtRPM, 0)
        XCTAssertEqual(values.xdRPM, 0)
        XCTAssertEqual(values.bootSign, 0)
    }

    func testDecodeFallbacksMatchPowerOnDefaults() throws {
        let values = try JSONDecoder().decode(RegisterValues.self, from: Data(#"{"servoAngle": 1000}"#.utf8))
        XCTAssertEqual(values.sysState, 0)
        XCTAssertEqual(values.servoAngle, 1000)
        XCTAssertEqual(values.tfAngle, 0)
        XCTAssertEqual(values.mtRPM, 0)
        XCTAssertEqual(values.xdRPM, 0)
        XCTAssertEqual(values.bootSign, 0)
    }

    func testCharacteristicUUIDsAndRanges() {
        XCTAssertEqual(Characteristic.mtRPM.uuid, "7fa2d10c-12f3-4b9e-9d77-1a9b65432101")
        XCTAssertEqual(Characteristic.xdRPM.uuid, "7fa2d10c-12f3-4b9e-9d77-1a9b65432102")
        XCTAssertEqual(Characteristic.bootSign.uuid, "7fa2d10c-12f3-4b9e-9d77-1a9b65432103")
        XCTAssertEqual(Characteristic.sysState.uuid, "7fa2d10c-12f3-4b9e-9d77-1a9b65432104")
        XCTAssertEqual(Characteristic.servoAngle.uuid, "7fa2d10c-12f3-4b9e-9d77-1a9b65432105")
        XCTAssertEqual(Characteristic.tfAngle.uuid, "7fa2d10c-12f3-4b9e-9d77-1a9b65432106")
        XCTAssertEqual(Characteristic.mtRPM.writableRange, 0...1500)
        XCTAssertEqual(Characteristic.xdRPM.writableRange, 0...150)
        XCTAssertEqual(Characteristic.bootSign.writableRange, 0...10)
        XCTAssertNil(Characteristic.sysState.writableRange)
    }
}
