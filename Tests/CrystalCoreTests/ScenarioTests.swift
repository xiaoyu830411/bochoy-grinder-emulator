import Foundation
import XCTest
@testable import CrystalCore

final class ScenarioTests: XCTestCase {
    func testMinimalScenarioUsesDefaults() throws {
        let scenario = try JSONDecoder().decode(Scenario.self, from: Data("{}".utf8)).validated()
        XCTAssertEqual(scenario.schemaVersion, 1)
        XCTAssertEqual(scenario.deviceName, "CRYSTAL-E57C")
        XCTAssertEqual(scenario.initialRegisters, .default)
        XCTAssertEqual(scenario.behavior.timedDurationMs, 5_000)
        XCTAssertEqual(scenario.behavior.smartDurationMs, 5_000)
        XCTAssertEqual(scenario.behavior.disconnectPolicy, .pause)
        XCTAssertTrue(scenario.faults.isEmpty)
    }

    func testNullSmartDurationMeansManualCompletion() throws {
        let json = #"{"behavior":{"smartDurationMs":null}}"#
        let scenario = try JSONDecoder().decode(Scenario.self, from: Data(json.utf8)).validated()
        XCTAssertNil(scenario.behavior.smartDurationMs)
    }

    func testRejectsInvalidIdentityAndFaultDefinitions() throws {
        XCTAssertThrowsError(try Scenario(name: "bad", deviceName: "crystal-e57c").validated())
        XCTAssertThrowsError(try Scenario(name: "bad", deviceName: "CRYSTAL-12345").validated())
        let duplicate = FaultRule(id: "x", type: .runStall)
        XCTAssertThrowsError(try Scenario(name: "bad", faults: [duplicate, duplicate]).validated())
        XCTAssertThrowsError(try Scenario(
            name: "bad",
            faults: [FaultRule(id: "delay", type: .responseDelay, characteristic: .mtRPM)]
        ).validated())
    }

    func testRejectsNullTimedDurationAndExcessiveDelays() throws {
        let nullTimed = #"{"behavior":{"timedDurationMs":null}}"#
        XCTAssertThrowsError(try JSONDecoder().decode(Scenario.self, from: Data(nullTimed.utf8)))
        let excessive = SimulationLimits.maximumDelayMs + 1
        XCTAssertThrowsError(try Scenario(
            name: "bad",
            behavior: BehaviorConfiguration(timedDurationMs: excessive)
        ).validated())
        XCTAssertThrowsError(try Scenario(
            name: "bad",
            behavior: BehaviorConfiguration(smartDurationMs: excessive)
        ).validated())
        XCTAssertThrowsError(try Scenario(
            name: "bad",
            faults: [FaultRule(
                id: "too-long",
                type: .responseDelay,
                characteristic: .mtRPM,
                delayMs: excessive
            )]
        ).validated())
    }

    func testRejectsFaultFieldsThatWouldBeIgnoredOrContradictory() throws {
        XCTAssertThrowsError(try Scenario(
            name: "bad",
            faults: [FaultRule(id: "apply", type: .applyDelay, characteristic: .bootSign, delayMs: 10)]
        ).validated())
        XCTAssertThrowsError(try Scenario(
            name: "bad",
            faults: [FaultRule(id: "apply", type: .applyStall, value: 5)]
        ).validated())
        XCTAssertThrowsError(try Scenario(
            name: "bad",
            faults: [FaultRule(id: "run", type: .runStall, characteristic: .sysState)]
        ).validated())
        XCTAssertThrowsError(try Scenario(
            name: "bad",
            faults: [FaultRule(id: "read", type: .readError, characteristic: .mtRPM, attStatus: 0)]
        ).validated())
        XCTAssertThrowsError(try Scenario(
            name: "bad",
            faults: [FaultRule(id: "write", type: .writeError, characteristic: .mtRPM, attStatus: 0)]
        ).validated())
        XCTAssertThrowsError(try Scenario(
            name: "bad",
            faults: [FaultRule(
                id: "drop",
                type: .notificationDrop,
                characteristic: .mtRPM,
                attStatus: ATTStatus.unlikelyError
            )]
        ).validated())
    }

    func testDecodesLayoutAndFaults() throws {
        let json = """
        {
          "name": "optional-notify-off",
          "layout": {"notifyDisabled": ["TF_ANGLE", "XD_RPM"]},
          "faults": [{
            "id": "drop-second-sys",
            "type": "notificationDrop",
            "characteristic": "SYS_STATE",
            "onOccurrence": 2,
            "maxTriggers": 1
          }]
        }
        """
        let scenario = try JSONDecoder().decode(Scenario.self, from: Data(json.utf8)).validated()
        XCTAssertEqual(scenario.layout.notifyDisabled, [.tfAngle, .xdRPM])
        XCTAssertEqual(scenario.faults.first?.onOccurrence, 2)
        XCTAssertEqual(scenario.faults.first?.maxTriggers, 1)
    }
}
