import Foundation
import XCTest
@testable import CrystalCore

@MainActor
final class DeviceModelTests: XCTestCase {
    private func makeModel(_ scenario: Scenario = .default) -> DeviceModel {
        DeviceModel(scenario: scenario, logger: EventLog())
    }

    private func write(_ value: UInt16, _ characteristic: Characteristic, to model: DeviceModel) -> [ModelEffect] {
        model.write(UInt16Codec.encode(value), to: characteristic)
    }

    private func stateResetID(in effects: [ModelEffect], delayMs: UInt64 = 5_000) -> UInt64? {
        for effect in effects {
            if case .scheduleStateReset(let id, let delay) = effect, delay == delayMs {
                return id
            }
        }
        return nil
    }

    func testDefaultRegistersAndNormalWriteNotification() {
        let model = makeModel()
        XCTAssertEqual(model.registers, .default)
        XCTAssertEqual(write(1200, .mtRPM, to: model), [.notify(characteristic: .mtRPM, value: 1200)])
        XCTAssertEqual(model.registers.mtRPM, 1200)
        XCTAssertEqual(write(1200, .mtRPM, to: model), [])
    }

    func testInvalidLengthOutOfRangeAndReadOnlyWritesDoNotChangeState() {
        let model = makeModel()
        let original = model.registers
        XCTAssertEqual(model.write(Data([0x04]), to: .mtRPM), [])
        XCTAssertEqual(write(1501, .mtRPM, to: model), [])
        XCTAssertEqual(write(151, .xdRPM, to: model), [])
        XCTAssertEqual(write(1, .sysState, to: model), [])
        XCTAssertEqual(write(900, .servoAngle, to: model), [])
        XCTAssertEqual(model.registers, original)
    }

    func testBootRegisterRetainsLastDefinedCommandAndIgnoresReservedValues() {
        let model = makeModel()
        _ = write(1, .bootSign, to: model)
        XCTAssertEqual(model.registers.bootSign, 1)
        _ = write(0, .bootSign, to: model)
        XCTAssertEqual(model.registers.bootSign, 1)
        _ = write(6, .bootSign, to: model)
        XCTAssertEqual(model.registers.bootSign, 1)
        _ = write(11, .bootSign, to: model)
        XCTAssertEqual(model.registers.bootSign, 1)
    }

    func testManualStartRequiresBootStopAndRPMZeroIsNotStop() {
        let model = makeModel()
        let startEffects = write(1, .bootSign, to: model)
        XCTAssertEqual(model.runMode, .manual)
        XCTAssertEqual(model.registers.sysState, 1)
        XCTAssertTrue(startEffects.contains(.notify(characteristic: .sysState, value: 1)))
        XCTAssertFalse(startEffects.contains { if case .scheduleRun = $0 { return true } else { return false } })

        _ = write(0, .mtRPM, to: model)
        XCTAssertEqual(model.registers.mtRPM, 0)
        XCTAssertEqual(model.registers.sysState, 1)
        XCTAssertEqual(model.runMode, .manual)

        let stopEffects = write(4, .bootSign, to: model)
        XCTAssertEqual(model.registers.sysState, 0)
        XCTAssertNil(model.activeRun)
        XCTAssertTrue(stopEffects.contains(.notify(characteristic: .sysState, value: 0)))
    }

    func testTimedAndSmartRunsScheduleDeterministicCompletion() {
        let model = makeModel()
        let effects = write(2, .bootSign, to: model)
        guard let run = model.activeRun else { return XCTFail("missing active run") }
        XCTAssertTrue(effects.contains(.scheduleRun(id: run.id, delayMs: 5_000)))
        XCTAssertEqual(model.completeRun(id: run.id), [.notify(characteristic: .sysState, value: 0)])
        XCTAssertEqual(model.registers.sysState, 0)
        XCTAssertEqual(model.completeRun(id: run.id), [])

        let smart = write(3, .bootSign, to: model)
        guard let smartRun = model.activeRun else { return XCTFail("missing smart run") }
        XCTAssertTrue(smart.contains(.scheduleRun(id: smartRun.id, delayMs: 5_000)))
    }

    func testNullSmartDurationWaitsForManualFinish() {
        let scenario = Scenario(
            name: "manual-smart",
            behavior: BehaviorConfiguration(smartDurationMs: nil)
        )
        let model = makeModel(scenario)
        let effects = write(3, .bootSign, to: model)
        XCTAssertFalse(effects.contains { if case .scheduleRun = $0 { return true } else { return false } })
        _ = model.forceFinishRun()
        XCTAssertEqual(model.registers.sysState, 0)
        XCTAssertNil(model.activeRun)
    }

    func testRepeatedStartReplacesModeAndInvalidatesOldTimer() {
        let model = makeModel()
        _ = write(2, .bootSign, to: model)
        let firstRun = model.activeRun
        let effects = write(3, .bootSign, to: model)
        guard let firstRun, let secondRun = model.activeRun else { return XCTFail("missing runs") }
        XCTAssertNotEqual(firstRun.id, secondRun.id)
        XCTAssertEqual(secondRun.mode, .smart)
        XCTAssertTrue(effects.contains(.cancelRun(id: firstRun.id)))
        XCTAssertEqual(model.completeRun(id: firstRun.id), [])
        XCTAssertEqual(model.registers.sysState, 1)
        _ = model.completeRun(id: secondRun.id)
        XCTAssertEqual(model.registers.sysState, 0)
    }

    func testApplySchedulesFiveSecondAutoIdle() {
        let model = makeModel()
        _ = write(1000, .tfAngle, to: model)
        let effects = write(5, .bootSign, to: model)
        XCTAssertTrue(effects.contains(.notify(characteristic: .sysState, value: 1)))
        guard let id = stateResetID(in: effects) else { return XCTFail("missing state reset") }
        XCTAssertEqual(model.pendingStateResetID, id)
        XCTAssertEqual(model.registers.sysState, 1)

        XCTAssertEqual(
            model.completeStateReset(id: id),
            [.notify(characteristic: .sysState, value: 0)]
        )
        XCTAssertEqual(model.registers.sysState, 0)
        XCTAssertNil(model.pendingStateResetID)
    }

    func testManualStartCancelsApplyAutoIdle() {
        let model = makeModel()
        _ = write(1000, .tfAngle, to: model)
        guard let id = stateResetID(in: write(5, .bootSign, to: model)) else {
            return XCTFail("missing state reset")
        }
        let effects = write(1, .bootSign, to: model)
        XCTAssertTrue(effects.contains(.cancelStateReset(id: id)))
        XCTAssertEqual(model.completeStateReset(id: id), [])
        XCTAssertEqual(model.registers.sysState, 1)
    }

    func testStopCancelsApplyAutoIdleWithoutSecondNotification() {
        let model = makeModel()
        _ = write(1000, .tfAngle, to: model)
        guard let id = stateResetID(in: write(5, .bootSign, to: model)) else {
            return XCTFail("missing state reset")
        }
        let stopEffects = write(4, .bootSign, to: model)
        XCTAssertTrue(stopEffects.contains(.cancelStateReset(id: id)))
        XCTAssertTrue(stopEffects.contains(.notify(characteristic: .sysState, value: 0)))
        XCTAssertEqual(model.completeStateReset(id: id), [])
        XCTAssertEqual(model.registers.sysState, 0)
    }

    func testApplyDuringRunDoesNotScheduleAutoIdle() {
        let model = makeModel()
        _ = write(1, .bootSign, to: model)
        _ = write(1000, .tfAngle, to: model)
        let effects = write(5, .bootSign, to: model)
        XCTAssertNil(stateResetID(in: effects))
        XCTAssertNil(model.pendingStateResetID)
        XCTAssertEqual(model.registers.sysState, 1)
    }

    func testRepeatedApplyRestartsAutoIdleTimer() {
        let model = makeModel()
        _ = write(1000, .tfAngle, to: model)
        guard let first = stateResetID(in: write(5, .bootSign, to: model)) else {
            return XCTFail("missing first state reset")
        }
        let secondEffects = write(5, .bootSign, to: model)
        guard let second = stateResetID(in: secondEffects) else {
            return XCTFail("missing second state reset")
        }
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(secondEffects.contains(.cancelStateReset(id: first)))
        XCTAssertEqual(model.completeStateReset(id: first), [])
        XCTAssertEqual(model.registers.sysState, 1)
        XCTAssertEqual(model.completeStateReset(id: second), [.notify(characteristic: .sysState, value: 0)])
    }

    func testPowerOffCancelsApplyAutoIdle() {
        let model = makeModel()
        _ = write(1000, .tfAngle, to: model)
        guard let id = stateResetID(in: write(5, .bootSign, to: model)) else {
            return XCTFail("missing state reset")
        }
        let effects = model.powerOff(source: "test")
        XCTAssertTrue(effects.contains(.cancelStateReset(id: id)))
        XCTAssertNil(model.pendingStateResetID)
        XCTAssertEqual(model.completeStateReset(id: id), [])
        XCTAssertEqual(model.registers.sysState, 0)
    }

    func testDelayedApplyCompletionDoesNotClearSysStateEarly() {
        let scenario = Scenario(
            name: "delayed-apply",
            faults: [FaultRule(id: "delay", type: .applyDelay, delayMs: 2_000)]
        )
        let model = makeModel(scenario)
        _ = write(900, .tfAngle, to: model)
        let effects = write(5, .bootSign, to: model)
        guard let reset = stateResetID(in: effects), let apply = model.pendingApply else {
            return XCTFail("missing Apply or state reset")
        }
        XCTAssertEqual(model.registers.sysState, 1)
        _ = model.completeApply(id: apply.id)
        XCTAssertEqual(model.registers.servoAngle, 900)
        XCTAssertEqual(model.registers.sysState, 1)
        XCTAssertEqual(model.pendingStateResetID, reset)
        XCTAssertEqual(model.completeStateReset(id: reset), [.notify(characteristic: .sysState, value: 0)])
    }

    func testStateResetFiresDuringApplyStallAndRetainsPendingApply() {
        let scenario = Scenario(
            name: "stalled-apply",
            faults: [FaultRule(id: "stall", type: .applyStall)]
        )
        let model = makeModel(scenario)
        _ = write(900, .tfAngle, to: model)
        let effects = write(5, .bootSign, to: model)
        guard let reset = stateResetID(in: effects), let apply = model.pendingApply else {
            return XCTFail("missing Apply or state reset")
        }
        XCTAssertEqual(model.completeApply(id: apply.id), [])
        XCTAssertNotNil(model.pendingApply)
        XCTAssertEqual(model.completeStateReset(id: reset), [.notify(characteristic: .sysState, value: 0)])
        XCTAssertEqual(model.registers.sysState, 0)
        XCTAssertEqual(model.pendingApply, apply)
    }

    func testSystemStateOverrideCancelsApplyAutoIdle() {
        let model = makeModel()
        _ = write(1000, .tfAngle, to: model)
        guard let id = stateResetID(in: write(5, .bootSign, to: model)) else {
            return XCTFail("missing state reset")
        }
        let effects = model.overrideRegister(.sysState, value: 2, notify: true)
        XCTAssertTrue(effects.contains(.cancelStateReset(id: id)))
        XCTAssertNil(model.pendingStateResetID)
        XCTAssertEqual(model.completeStateReset(id: id), [])
        XCTAssertEqual(model.registers.sysState, 2)
    }

    func testStaleStateResetIDFromReplacedModelDoesNotAffectNewModel() {
        let old = makeModel()
        _ = write(1000, .tfAngle, to: old)
        guard let staleID = stateResetID(in: write(5, .bootSign, to: old)) else {
            return XCTFail("missing state reset")
        }

        let replacement = makeModel()
        XCTAssertNil(replacement.pendingStateResetID)
        XCTAssertEqual(replacement.completeStateReset(id: staleID), [])
        XCTAssertEqual(replacement.registers.sysState, 0)
    }

    func testSessionPauseKeepsApplyAutoIdlePendingUntilResume() {
        let model = makeModel()
        _ = write(1000, .tfAngle, to: model)
        guard let id = stateResetID(in: write(5, .bootSign, to: model)) else {
            return XCTFail("missing state reset")
        }

        XCTAssertEqual(model.sessionBegan(source: "test"), [])
        XCTAssertEqual(model.sessionEnded(source: "test"), [.pauseTimers])
        XCTAssertTrue(model.timersPaused)
        XCTAssertEqual(model.pendingStateResetID, id, "pause must not consume or cancel the auto-idle timer")

        XCTAssertEqual(model.sessionBegan(source: "test"), [.resumeTimers])
        XCTAssertEqual(model.completeStateReset(id: id), [.notify(characteristic: .sysState, value: 0)])
        XCTAssertEqual(model.registers.sysState, 0)
    }

    func testImmediateApplyUsesTargetWithoutClaimingMechanicalCompletion() {
        let model = makeModel()
        _ = write(1000, .tfAngle, to: model)
        let effects = write(5, .bootSign, to: model)
        XCTAssertEqual(model.registers.servoAngle, 1000)
        XCTAssertNil(model.pendingApply)
        XCTAssertEqual(model.registers.sysState, 1)
        XCTAssertNotNil(model.pendingStateResetID)
        XCTAssertTrue(effects.contains(.notify(characteristic: .servoAngle, value: 1000)))
        XCTAssertEqual(model.registers.tfAngle, 1000)
    }

    func testDelayedApplyCapturesTargetAndSurvivesMotorStop() {
        let scenario = Scenario(
            name: "delayed-apply",
            faults: [FaultRule(id: "delay", type: .applyDelay, delayMs: 2_000)]
        )
        let model = makeModel(scenario)
        _ = write(900, .tfAngle, to: model)
        let applyEffects = write(5, .bootSign, to: model)
        guard let apply = model.pendingApply else { return XCTFail("missing pending Apply") }
        XCTAssertEqual(apply.target, 900)
        XCTAssertTrue(applyEffects.contains(.scheduleApply(id: apply.id, target: 900, delayMs: 2_000)))

        _ = write(1000, .tfAngle, to: model)
        _ = write(1, .bootSign, to: model)
        let stopEffects = write(4, .bootSign, to: model)
        XCTAssertFalse(stopEffects.contains(.cancelApply(id: apply.id)))
        _ = model.completeApply(id: apply.id)
        XCTAssertEqual(model.registers.servoAngle, 900)
        XCTAssertEqual(model.registers.tfAngle, 1000)
    }

    func testNewApplySupersedesOldCapturedOperation() {
        let scenario = Scenario(
            name: "delayed-apply",
            faults: [FaultRule(id: "delay", type: .applyDelay, delayMs: 2_000)]
        )
        let model = makeModel(scenario)
        _ = write(900, .tfAngle, to: model)
        _ = write(5, .bootSign, to: model)
        let first = model.pendingApply
        _ = write(1000, .tfAngle, to: model)
        let effects = write(5, .bootSign, to: model)
        guard let first, let second = model.pendingApply else { return XCTFail("missing Apply operations") }
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(second.target, 1000)
        XCTAssertTrue(effects.contains(.cancelApply(id: first.id)))
        XCTAssertEqual(model.completeApply(id: first.id), [])
        _ = model.completeApply(id: second.id)
        XCTAssertEqual(model.registers.servoAngle, 1000)
    }

    func testApplyStallPersistsUntilExplicitOverride() {
        let scenario = Scenario(
            name: "stalled-apply",
            faults: [FaultRule(id: "stall", type: .applyStall)]
        )
        let model = makeModel(scenario)
        _ = write(900, .tfAngle, to: model)
        _ = write(5, .bootSign, to: model)
        XCTAssertNotNil(model.pendingApply)
        XCTAssertEqual(model.registers.servoAngle, 830)
        _ = model.forceFinishApply()
        XCTAssertNil(model.pendingApply)
        XCTAssertEqual(model.registers.servoAngle, 900)
    }

    func testRunStallAffectsOnlyAutomaticCompletion() {
        let scenario = Scenario(
            name: "stalled-run",
            faults: [FaultRule(id: "stall", type: .runStall)]
        )
        let model = makeModel(scenario)
        _ = write(2, .bootSign, to: model)
        let id = model.activeRun!.id
        XCTAssertEqual(model.completeRun(id: id), [])
        XCTAssertEqual(model.registers.sysState, 1)
        XCTAssertNotNil(model.activeRun)
        _ = model.forceFinishRun()
        XCTAssertEqual(model.registers.sysState, 0)
        XCTAssertNil(model.activeRun)
    }

    func testObservedSessionPauseAndResumeAreDistinctFromLinkLoss() {
        let model = makeModel()
        XCTAssertEqual(model.sessionBegan(source: "test"), [])
        _ = write(2, .bootSign, to: model)
        XCTAssertEqual(model.sessionEnded(source: "test"), [.pauseTimers])
        XCTAssertTrue(model.timersPaused)
        XCTAssertFalse(model.sessionActive)
        XCTAssertEqual(model.sessionEnded(source: "duplicate"), [])
        XCTAssertEqual(model.sessionBegan(source: "test"), [.resumeTimers])
        XCTAssertFalse(model.timersPaused)
        let event = model.logger.events.last { $0.message.contains("deduplication reset") }
        XCTAssertNotNil(event)
    }

    func testStopDisconnectPolicyStopsRunButRetainsApply() {
        let scenario = Scenario(
            name: "stop-on-session-end",
            behavior: BehaviorConfiguration(disconnectPolicy: .stop),
            faults: [FaultRule(id: "delay", type: .applyDelay, delayMs: 1_000)]
        )
        let model = makeModel(scenario)
        _ = model.sessionBegan(source: "test")
        _ = write(2, .bootSign, to: model)
        _ = write(5, .bootSign, to: model)
        let apply = model.pendingApply
        _ = model.sessionEnded(source: "test")
        XCTAssertNil(model.activeRun)
        XCTAssertEqual(model.registers.sysState, 0)
        XCTAssertEqual(model.pendingApply, apply)
    }

    func testTestOverrideAllowsUnknownValuesAndControlsNotifications() {
        let model = makeModel()
        XCTAssertEqual(
            model.overrideRegister(.sysState, value: 2, notify: true),
            [.notify(characteristic: .sysState, value: 2)]
        )
        XCTAssertEqual(model.registers.sysState, 2)
        XCTAssertEqual(model.overrideRegister(.sysState, value: 2, notify: false), [])
        XCTAssertEqual(
            model.overrideRegister(.sysState, value: 2, notify: true),
            [.notify(characteristic: .sysState, value: 2)]
        )
        XCTAssertEqual(model.overrideRegister(.mtRPM, value: 1200, notify: false), [])
        XCTAssertEqual(model.registers.mtRPM, 1200)
        XCTAssertEqual(
            model.overrideRegister(.bootSign, value: 65_535, notify: true),
            [.notify(characteristic: .bootSign, value: 65_535)]
        )
    }

    func testServoOverrideCancelsPendingApply() {
        let scenario = Scenario(
            name: "delayed-apply",
            faults: [FaultRule(id: "delay", type: .applyDelay, delayMs: 2_000)]
        )
        let model = makeModel(scenario)
        _ = write(900, .tfAngle, to: model)
        guard let reset = stateResetID(in: write(5, .bootSign, to: model)) else {
            return XCTFail("missing state reset")
        }
        let apply = model.pendingApply!
        let effects = model.overrideRegister(.servoAngle, value: 42, notify: false)
        XCTAssertTrue(effects.contains(.cancelApply(id: apply.id)))
        XCTAssertTrue(effects.contains(.cancelStateReset(id: reset)))
        XCTAssertTrue(effects.contains(.notify(characteristic: .sysState, value: 0)))
        XCTAssertNil(model.pendingApply)
        XCTAssertNil(model.pendingStateResetID)
        XCTAssertEqual(model.registers.sysState, 0)
        XCTAssertEqual(model.registers.servoAngle, 42)
    }

    func testSessionStartResetsNotificationDeduplication() {
        let scenario = Scenario(
            name: "continue",
            behavior: BehaviorConfiguration(disconnectPolicy: .continue)
        )
        let model = makeModel(scenario)
        _ = model.sessionBegan(source: "test")
        _ = write(1200, .mtRPM, to: model)
        _ = model.overrideRegister(.mtRPM, value: 900, notify: false)
        XCTAssertEqual(
            write(1200, .mtRPM, to: model),
            [.notify(characteristic: .mtRPM, value: 1200)],
            "a quiet Override must advance the baseline so returning to the last notified value is observable"
        )
        XCTAssertEqual(write(1200, .mtRPM, to: model), [])
        _ = model.sessionEnded(source: "test")
        _ = model.sessionBegan(source: "test")
        XCTAssertEqual(
            write(1200, .mtRPM, to: model),
            [.notify(characteristic: .mtRPM, value: 1200)],
            "the first synchronization of a new session publishes even an unchanged value"
        )
        XCTAssertEqual(write(1200, .mtRPM, to: model), [])
    }

    func testOverrideEventContainsProjectedAfterSnapshot() {
        let model = makeModel()
        _ = model.overrideRegister(.sysState, value: 2, notify: false)
        let event = model.logger.events.last {
            $0.kind == .override && $0.message == "register Test Override"
        }
        XCTAssertEqual(event?.before?.sysState, 0)
        XCTAssertEqual(event?.after?.sysState, 2)
        XCTAssertEqual(event?.testOverride, true)
    }

    func testTerminateFaultOnlyRunsForDefinedProcessedOperations() {
        let scenario = Scenario(
            name: "terminate-guard",
            faults: [FaultRule(id: "quit", type: .terminateProcess)]
        )
        let model = makeModel(scenario)
        XCTAssertFalse(model.write(Data([0x01]), to: .mtRPM).contains(.terminateProcess))
        XCTAssertFalse(write(1501, .mtRPM, to: model).contains(.terminateProcess))
        XCTAssertFalse(write(1, .sysState, to: model).contains(.terminateProcess))
        XCTAssertFalse(write(900, .servoAngle, to: model).contains(.terminateProcess))
        XCTAssertFalse(write(0, .bootSign, to: model).contains(.terminateProcess))
        XCTAssertFalse(write(6, .bootSign, to: model).contains(.terminateProcess))
        XCTAssertTrue(write(1200, .mtRPM, to: model).contains(.terminateProcess))
    }

    func testTerminateFaultIsAnEffectAfterValidWrite() {
        let scenario = Scenario(
            name: "terminate",
            faults: [FaultRule(id: "quit", type: .terminateProcess, characteristic: .bootSign, value: 3)]
        )
        let model = makeModel(scenario)
        XCTAssertTrue(write(3, .bootSign, to: model).contains(.terminateProcess))
        XCTAssertFalse(write(1, .bootSign, to: model).contains(.terminateProcess))
    }
}
