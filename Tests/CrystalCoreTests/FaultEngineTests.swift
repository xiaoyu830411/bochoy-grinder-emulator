import Foundation
import XCTest
@testable import CrystalCore

@MainActor
final class FaultEngineTests: XCTestCase {
    func testOccurrenceAndMaximumTriggerCount() {
        let logger = EventLog()
        let engine = FaultEngine(
            rules: [
                FaultRule(id: "second", type: .notificationDrop, characteristic: .sysState, onOccurrence: 2),
                FaultRule(id: "once", type: .writeError, characteristic: .mtRPM, maxTriggers: 1),
            ],
            logger: logger,
            scenarioName: "test"
        )
        XCTAssertFalse(engine.shouldApply(.notificationDrop, characteristic: .sysState, value: 1))
        XCTAssertTrue(engine.shouldApply(.notificationDrop, characteristic: .sysState, value: 0))
        XCTAssertFalse(engine.shouldApply(.notificationDrop, characteristic: .sysState, value: 1))
        XCTAssertNotNil(engine.attError(.writeError, characteristic: .mtRPM, value: 1200))
        XCTAssertNil(engine.attError(.writeError, characteristic: .mtRPM, value: 900))
    }

    func testDisableAndEnableResetsRuleProgress() {
        let engine = FaultEngine(
            rules: [FaultRule(id: "second", type: .readError, characteristic: .mtRPM, onOccurrence: 2)],
            logger: EventLog(),
            scenarioName: "test"
        )
        XCTAssertNil(engine.attError(.readError, characteristic: .mtRPM))
        XCTAssertTrue(engine.setEnabled("second", enabled: false))
        XCTAssertTrue(engine.setEnabled("second", enabled: true))
        XCTAssertNil(engine.attError(.readError, characteristic: .mtRPM))
        XCTAssertEqual(engine.attError(.readError, characteristic: .mtRPM)?.status, ATTStatus.unlikelyError)
    }

    func testDelayUsesMaximumAndATTErrorCanBeExplicit() {
        let engine = FaultEngine(
            rules: [
                FaultRule(id: "short", type: .responseDelay, characteristic: .mtRPM, delayMs: 100),
                FaultRule(id: "long", type: .responseDelay, characteristic: .mtRPM, delayMs: 250),
                FaultRule(id: "error", type: .writeError, characteristic: .mtRPM, attStatus: ATTStatus.insufficientResources),
            ],
            logger: EventLog(),
            scenarioName: "test"
        )
        XCTAssertEqual(engine.maximumDelay(.responseDelay, characteristic: .mtRPM), 250)
        XCTAssertEqual(engine.attError(.writeError, characteristic: .mtRPM)?.status, ATTStatus.insufficientResources)
    }
}
