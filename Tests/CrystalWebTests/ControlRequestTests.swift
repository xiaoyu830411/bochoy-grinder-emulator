import Foundation
import XCTest
import CrystalCore
@testable import CrystalWeb

final class ControlRequestTests: XCTestCase {
    private func command(_ json: String) throws -> ControlCommand {
        try ControlRequest.decode(Data(json.utf8))
    }

    func testNormalRunSettingAndApplyActions() throws {
        for mode in [RunMode.manual, .timed, .smart] {
            XCTAssertEqual(try command(#"{"action":"start","mode":"\#(mode.rawValue)"}"#), .start(mode))
        }
        XCTAssertEqual(try command(#"{"action":"stop"}"#), .stop)
        XCTAssertEqual(try command(#"{"action":"setMT","value":1200}"#), .setMotor(1200))
        XCTAssertEqual(try command(#"{"action":"setXD","value":80}"#), .setFeed(80))
        XCTAssertEqual(try command(#"{"action":"setTF","value":1000}"#), .setTarget(1000))
        XCTAssertEqual(try command(#"{"action":"apply"}"#), .apply)
        XCTAssertEqual(
            try command(#"{"action":"setTFAndApply","value":1000}"#),
            .setTargetAndApply(1000)
        )
    }

    func testOverrideRequiresExplicitNotificationAndAcceptsEntireUInt16Range() throws {
        XCTAssertEqual(
            try command(#"{"action":"override","characteristic":"SYS_STATE","value":65535,"notification":"notify"}"#),
            .override(characteristic: .sysState, value: 65_535, notify: true)
        )
        XCTAssertEqual(
            try command(#"{"action":"override","characteristic":"MT_RPM","value":0,"notification":"quiet"}"#),
            .override(characteristic: .mtRPM, value: 0, notify: false)
        )
        XCTAssertThrowsError(try command(#"{"action":"override","characteristic":"SYS_STATE","value":2}"#))
        XCTAssertThrowsError(try command(#"{"action":"override","characteristic":"SYS_STATE","value":65536,"notification":"quiet"}"#))
    }

    func testAdvancedPowerFaultScenarioSessionAndDisconnectActions() throws {
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let expected: [(String, ControlCommand)] = [
            (#"{"action":"powerOff"}"#, .power(false)),
            (#"{"action":"powerOn"}"#, .power(true)),
            (#"{"action":"finishRun"}"#, .finishRun),
            (#"{"action":"finishApply"}"#, .finishApply),
            (#"{"action":"advertising","enabled":false}"#, .advertising(false)),
            (#"{"action":"sessionBegin"}"#, .session(true)),
            (#"{"action":"sessionEnd"}"#, .session(false)),
            (#"{"action":"scenarioLoad","scenario":"default"}"#, .loadScenario("default")),
            (#"{"action":"scenarioReset"}"#, .resetScenario),
            (#"{"action":"faultSet","faultID":"delay","enabled":true}"#, .setFault(id: "delay", enabled: true)),
            (#"{"action":"disconnectCentral","centralID":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"}"#, .disconnectCentral(id)),
            (#"{"action":"markObservationDisconnected","recordID":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"}"#, .markObservationDisconnected(id)),
            (#"{"action":"hideObservation","recordID":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"}"#, .hideObservation(id)),
            (#"{"action":"restoreObservation","recordID":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"}"#, .restoreObservation(id)),
            (#"{"action":"restoreHiddenObservations"}"#, .restoreHiddenObservations),
        ]
        for (json, command) in expected {
            XCTAssertEqual(try self.command(json), command)
        }
    }

    func testRejectsProcessExitArbitraryPathsUnknownActionsAndMissingParameters() {
        let invalid = [
            #"{"action":"quit"}"#,
            #"{"action":"loadPath","path":"/tmp/scenario.json"}"#,
            #"{"action":"scenarioLoad","scenario":"../../etc/passwd"}"#,
            #"{"action":"scenarioLoad","scenario":"/tmp/default"}"#,
            #"{"action":"unknown"}"#,
            #"{"action":"start"}"#,
            #"{"action":"setMT"}"#,
            #"{"action":"faultSet","faultID":"delay"}"#,
            #"{"action":"disconnectCentral"}"#,
            #"{"action":"markObservationDisconnected"}"#,
            #"{"action":"hideObservation"}"#,
            #"{"action":"restoreObservation"}"#,
            #"{"action":"restoreHiddenObservations","recordID":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"}"#,
            #"{"action":"hideObservation","centralID":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"}"#,
            #"{"value":1}"#,
            "not json",
        ]
        for json in invalid {
            XCTAssertThrowsError(try command(json), json) { error in
                XCTAssertTrue(error is ControlValidationError)
            }
        }
    }

    func testRejectsAmbiguousParametersForSimpleActions() {
        XCTAssertThrowsError(try command(#"{"action":"stop","value":4}"#))
        XCTAssertThrowsError(try command(#"{"action":"powerOff","scenario":"default"}"#))
        XCTAssertThrowsError(try command(#"{"action":"start","mode":"manual","value":1}"#))
    }
}
