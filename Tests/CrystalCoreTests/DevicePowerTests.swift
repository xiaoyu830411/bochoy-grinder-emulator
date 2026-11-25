import XCTest
@testable import CrystalCore

@MainActor
final class DevicePowerTests: XCTestCase {
    private func makeModel(_ scenario: Scenario = .default) -> DeviceModel {
        DeviceModel(scenario: scenario, logger: EventLog())
    }

    private func write(_ value: UInt16, _ characteristic: Characteristic, to model: DeviceModel) {
        _ = model.write(UInt16Codec.encode(value), to: characteristic)
    }

    func testDeviceStartsPoweredOn() {
        XCTAssertTrue(makeModel().poweredOn)
    }

    func testPowerOffCancelsRunAndApplyQuietlyAndRetainsSettings() {
        let model = makeModel(Scenario(
            name: "power-off-operations",
            faults: [FaultRule(id: "delay", type: .applyDelay, delayMs: 2_000)]
        ))
        write(1200, .mtRPM, to: model)
        write(100, .xdRPM, to: model)
        write(1000, .tfAngle, to: model)
        write(5, .bootSign, to: model)
        guard let apply = model.pendingApply else { return XCTFail("missing pending Apply") }
        write(2, .bootSign, to: model)
        guard let run = model.activeRun else { return XCTFail("missing active Run") }

        let effects = model.powerOff(source: "test")

        XCTAssertFalse(model.poweredOn)
        XCTAssertNil(model.activeRun)
        XCTAssertNil(model.pendingApply)
        XCTAssertEqual(model.registers.sysState, 0)
        XCTAssertEqual(model.registers.mtRPM, 1200)
        XCTAssertEqual(model.registers.xdRPM, 100)
        XCTAssertEqual(model.registers.tfAngle, 1000)
        XCTAssertEqual(model.registers.servoAngle, 830)
        XCTAssertEqual(model.registers.bootSign, 2)
        XCTAssertTrue(effects.contains(.cancelRun(id: run.id)))
        XCTAssertTrue(effects.contains(.cancelApply(id: apply.id)))
        XCTAssertFalse(effects.contains(.notify(characteristic: .sysState, value: 0)))
        XCTAssertEqual(model.completeRun(id: run.id), [])
        XCTAssertEqual(model.completeApply(id: apply.id), [])
        XCTAssertEqual(model.registers.servoAngle, 830)

        let quietEvent = model.logger.events.last {
            $0.kind == .notification && $0.characteristic == .sysState
        }
        XCTAssertNotNil(quietEvent)
        XCTAssertFalse(quietEvent?.testOverride ?? true)
        XCTAssertEqual(quietEvent?.details["reason"], "device-power")
    }

    func testRepeatedPowerTransitionsAreIdempotent() {
        let model = makeModel()
        _ = model.powerOff(source: "test")
        let eventCount = model.logger.events.count
        XCTAssertEqual(model.powerOff(source: "test"), [])
        XCTAssertEqual(model.logger.events.count, eventCount)

        XCTAssertEqual(model.powerOn(source: "test"), [])
        let poweredOnEventCount = model.logger.events.count
        XCTAssertEqual(model.powerOn(source: "test"), [])
        XCTAssertEqual(model.logger.events.count, poweredOnEventCount)
    }

    func testPowerOffRejectsNormalWritesButAllowsExplicitOverride() {
        let model = makeModel()
        write(1200, .mtRPM, to: model)
        _ = model.powerOff(source: "test")
        let before = model.registers

        XCTAssertEqual(model.write(UInt16Codec.encode(1300), to: .mtRPM), [])
        XCTAssertEqual(model.write(UInt16Codec.encode(1), to: .bootSign), [])
        XCTAssertEqual(model.registers, before)
        let rejection = model.logger.events.last {
            $0.message == "normal write rejected: Device Powered Off"
        }
        XCTAssertNotNil(rejection)
        XCTAssertFalse(rejection?.testOverride ?? true)

        XCTAssertEqual(
            model.overrideRegister(.sysState, value: 65_535, notify: false),
            []
        )
        XCTAssertEqual(model.registers.sysState, 65_535)
        XCTAssertTrue(model.logger.events.contains { $0.kind == .override && $0.testOverride })
    }

    func testPowerOnAlwaysEntersQuietIdleWithoutRestoringOperations() {
        let model = makeModel(Scenario(
            name: "power-on-idle",
            faults: [FaultRule(id: "delay", type: .applyDelay, delayMs: 2_000)]
        ))
        write(1000, .tfAngle, to: model)
        write(5, .bootSign, to: model)
        write(2, .bootSign, to: model)
        _ = model.powerOff(source: "test")
        _ = model.overrideRegister(.sysState, value: 9, notify: true)

        let effects = model.powerOn(source: "test")

        XCTAssertTrue(model.poweredOn)
        XCTAssertEqual(model.registers.sysState, 0)
        XCTAssertNil(model.activeRun)
        XCTAssertNil(model.pendingApply)
        XCTAssertFalse(effects.contains(.notify(characteristic: .sysState, value: 0)))
        XCTAssertEqual(model.registers.tfAngle, 1000)
        XCTAssertEqual(model.registers.bootSign, 2)
        let quietEvent = model.logger.events.last {
            $0.kind == .notification && $0.characteristic == .sysState
        }
        XCTAssertEqual(quietEvent?.details["reason"], "device-power")
        XCTAssertFalse(quietEvent?.testOverride ?? true)
    }

    func testPowerOffDoesNotApplyDisconnectPolicyOrEraseSessionObservation() {
        let model = makeModel(Scenario(
            name: "power-not-session-end",
            behavior: BehaviorConfiguration(disconnectPolicy: .stop)
        ))
        _ = model.sessionBegan(source: "test")
        write(2, .bootSign, to: model)
        let sessionEventCount = model.logger.events.filter { $0.kind == .session }.count

        _ = model.powerOff(source: "test")

        XCTAssertTrue(model.sessionActive)
        XCTAssertFalse(model.timersPaused)
        XCTAssertEqual(model.logger.events.filter { $0.kind == .session }.count, sessionEventCount)
        _ = model.powerOn(source: "test")
        XCTAssertTrue(model.sessionActive)
        XCTAssertFalse(model.timersPaused)
    }
}
