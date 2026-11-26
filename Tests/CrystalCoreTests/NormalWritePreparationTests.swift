import Foundation
import XCTest
@testable import CrystalCore

@MainActor
final class NormalWritePreparationTests: XCTestCase {
    private func makeModel(_ scenario: Scenario = .default) -> DeviceModel {
        DeviceModel(scenario: scenario, logger: EventLog())
    }

    func testSuccessfulBLEAndWebWritesUseSameModelPathAndRecordTheirSource() {
        for source in [NormalWriteSource.ble, .web] {
            let model = makeModel()
            let result = model.prepareWrite(
                UInt16Codec.encode(1200),
                to: .mtRPM,
                source: source
            )
            XCTAssertEqual(result.status, ATTStatus.success)
            XCTAssertNil(result.faultID)
            XCTAssertEqual(result.value, 1200)
            XCTAssertEqual(result.effects, [.notify(characteristic: .mtRPM, value: 1200)])
            XCTAssertEqual(model.registers.mtRPM, 1200)
            let event = model.logger.events.last { $0.message == "write received" }
            XCTAssertEqual(event?.details["source"], source.rawValue)
        }
    }

    func testWriteErrorRejectsBeforeMutationAndReturnsATTDetails() {
        let model = makeModel(Scenario(
            name: "write-error",
            faults: [FaultRule(
                id: "reject-motor",
                type: .writeError,
                characteristic: .mtRPM,
                value: 1200,
                attStatus: ATTStatus.insufficientResources
            )]
        ))
        let before = model.registers
        let result = model.prepareWrite(
            UInt16Codec.encode(1200),
            to: .mtRPM,
            source: .web
        )
        XCTAssertEqual(result.status, ATTStatus.insufficientResources)
        XCTAssertEqual(result.faultID, "reject-motor")
        XCTAssertEqual(result.value, 1200)
        XCTAssertEqual(result.effects, [])
        XCTAssertEqual(model.registers, before)
        let event = model.logger.events.last {
            $0.message == "write rejected by injected ATT error; model unchanged"
        }
        XCTAssertEqual(event?.details["source"], "web")
    }

    func testExistingValidationRemainsSuccessfulAndNonMutating() {
        let model = makeModel()
        let before = model.registers
        let invalidLength = model.prepareWrite(Data([0x01]), to: .mtRPM, source: .web)
        XCTAssertEqual(invalidLength.status, ATTStatus.success)
        XCTAssertNil(invalidLength.value)
        XCTAssertEqual(invalidLength.effects, [])

        let outOfRange = model.prepareWrite(UInt16Codec.encode(1501), to: .mtRPM, source: .ble)
        XCTAssertEqual(outOfRange.status, ATTStatus.success)
        XCTAssertEqual(outOfRange.value, 1501)
        XCTAssertEqual(outOfRange.effects, [])
        XCTAssertEqual(model.registers, before)
    }

    func testTerminationAndRunApplyEffectsPassThroughPreparation() {
        let terminating = makeModel(Scenario(
            name: "terminate",
            faults: [FaultRule(id: "quit", type: .terminateProcess, characteristic: .mtRPM)]
        ))
        XCTAssertTrue(terminating.prepareWrite(
            UInt16Codec.encode(1200),
            to: .mtRPM,
            source: .web
        ).effects.contains(.terminateProcess))

        let applying = makeModel(Scenario(
            name: "apply",
            faults: [FaultRule(id: "delay", type: .applyDelay, delayMs: 100)]
        ))
        _ = applying.write(UInt16Codec.encode(830), to: .tfAngle)
        let result = applying.prepareWrite(UInt16Codec.encode(5), to: .bootSign, source: .web)
        guard let apply = applying.pendingApply else { return XCTFail("missing pending Apply") }
        XCTAssertEqual(result.status, ATTStatus.success)
        XCTAssertTrue(result.effects.contains(.scheduleApply(id: apply.id, target: 830, delayMs: 100)))
    }

    func testATTOnlyFaultsAreNotConsumedByLocalWebWrite() {
        let model = makeModel(Scenario(
            name: "att-only",
            faults: [
                FaultRule(id: "read", type: .readError, characteristic: .mtRPM),
                FaultRule(id: "delay", type: .responseDelay, characteristic: .mtRPM, delayMs: 100),
            ]
        ))
        let result = model.prepareWrite(UInt16Codec.encode(1200), to: .mtRPM, source: .web)
        XCTAssertEqual(result.status, ATTStatus.success)
        XCTAssertEqual(model.registers.mtRPM, 1200)
        XCTAssertFalse(model.logger.events.contains {
            $0.kind == .fault && ($0.faultID == "read" || $0.faultID == "delay")
        })
    }

    func testPoweredOffPreparationReturnsDeterministicStatusWithoutMutationOrFaultConsumption() {
        let model = makeModel(Scenario(
            name: "off-write",
            faults: [FaultRule(id: "reject", type: .writeError, characteristic: .mtRPM)]
        ))
        _ = model.powerOff(source: "test")
        let before = model.registers
        for source in [NormalWriteSource.ble, .web] {
            let result = model.prepareWrite(UInt16Codec.encode(1200), to: .mtRPM, source: source)
            XCTAssertEqual(result.status, ATTStatus.writeNotPermitted)
            XCTAssertNil(result.faultID)
            XCTAssertEqual(result.value, 1200)
            XCTAssertEqual(result.effects, [])
            XCTAssertEqual(model.registers, before)
            let rejection = model.logger.events.last {
                $0.message == "normal write rejected: Device Powered Off"
            }
            XCTAssertEqual(rejection?.details["source"], source.rawValue)
        }
        XCTAssertFalse(model.logger.events.contains { $0.kind == .fault && $0.faultID == "reject" })
    }
}
