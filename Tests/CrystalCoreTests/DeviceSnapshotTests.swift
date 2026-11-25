import Foundation
import XCTest
@testable import CrystalCore

@MainActor
final class DeviceSnapshotTests: XCTestCase {
    func testSnapshotEncodesPowerRegistersOperationsScenarioAndFaultEnablement() throws {
        let fault = FaultRule(id: "delay", type: .applyDelay, delayMs: 2_000)
        let disabledFault = FaultRule(id: "read", type: .readError, characteristic: .mtRPM)
        let model = DeviceModel(
            scenario: Scenario(name: "snapshot", faults: [fault, disabledFault]),
            logger: EventLog()
        )
        _ = model.faults.setEnabled("read", enabled: false)
        _ = model.write(UInt16Codec.encode(1000), to: .tfAngle)
        _ = model.write(UInt16Codec.encode(5), to: .bootSign)
        _ = model.write(UInt16Codec.encode(2), to: .bootSign)
        _ = model.sessionBegan(source: "test")
        _ = model.sessionEnded(source: "test")

        let snapshot = model.snapshot()
        XCTAssertEqual(snapshot.scenarioName, "snapshot")
        XCTAssertEqual(snapshot.deviceName, "CRYSTAL-E57C")
        XCTAssertEqual(snapshot.disconnectPolicy, .pause)
        XCTAssertEqual(snapshot.registers, model.registers)
        XCTAssertTrue(snapshot.poweredOn)
        XCTAssertEqual(snapshot.activeRun, model.activeRun)
        XCTAssertEqual(snapshot.pendingApply, model.pendingApply)
        XCTAssertFalse(snapshot.sessionActive)
        XCTAssertTrue(snapshot.timersPaused)
        XCTAssertEqual(snapshot.faults.count, 2)
        XCTAssertEqual(snapshot.faults[0].rule, fault)
        XCTAssertTrue(snapshot.faults[0].enabled)
        XCTAssertEqual(snapshot.faults[1].rule, disabledFault)
        XCTAssertFalse(snapshot.faults[1].enabled)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        let decoded = try JSONDecoder().decode(DeviceSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in [
            "scenarioName", "deviceName", "disconnectPolicy", "registers", "poweredOn",
            "activeRun", "pendingApply", "sessionActive", "timersPaused", "faults",
        ] {
            XCTAssertNotNil(object[key], "missing snapshot key \(key)")
        }
    }

    func testPoweredOffSnapshotReflectsCancelledOperationsWithoutChangingSettings() {
        let model = DeviceModel(scenario: .default, logger: EventLog())
        _ = model.write(UInt16Codec.encode(1200), to: .mtRPM)
        _ = model.write(UInt16Codec.encode(2), to: .bootSign)
        _ = model.powerOff(source: "test")

        let snapshot = model.snapshot()
        XCTAssertFalse(snapshot.poweredOn)
        XCTAssertNil(snapshot.activeRun)
        XCTAssertNil(snapshot.pendingApply)
        XCTAssertEqual(snapshot.registers.mtRPM, 1200)
        XCTAssertEqual(snapshot.registers.sysState, 0)
    }
}
