import Foundation
import XCTest
@testable import CrystalCore

@MainActor
final class EventLogTests: XCTestCase {
    func testStructuredEventContainsRawValueBase64AndState() throws {
        let logger = EventLog(now: { Date(timeIntervalSince1970: 1_700_000_000) })
        let event = logger.record(
            .override,
            "test event",
            scenario: "test",
            characteristic: .tfAngle,
            value: 830,
            attStatus: ATTStatus.success,
            before: .default,
            after: .default,
            testOverride: true,
            details: ["source": "unit-test"]
        )
        XCTAssertEqual(event.sequence, 1)
        XCTAssertEqual(event.hex, "03 3E")
        XCTAssertEqual(event.base64, "Az4=")
        let line = try EventLog.jsonLine(event)
        XCTAssertTrue(line.contains("\"base64\":\"Az4=\""))
        XCTAssertTrue(line.contains("\"testOverride\":true"))
        XCTAssertTrue(line.contains("\"characteristic\":\"TF_ANGLE\""))
        XCTAssertTrue(EventLog.humanLine(event).contains("TEST_OVERRIDE"))
    }
}
