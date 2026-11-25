import Foundation
import XCTest
@testable import CrystalCore

@MainActor
final class ObservedCentralStoreTests: XCTestCase {
    func testActivityTracksFixedTimestampsAndStableSubscriptionSet() {
        var now = Date(timeIntervalSince1970: 100)
        let store = ObservedCentralStore(now: { now })
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

        store.observe(central: id, activity: .subscribe, characteristic: .sysState)
        now = Date(timeIntervalSince1970: 110)
        store.observe(central: id, activity: .subscribe, characteristic: .mtRPM)
        now = Date(timeIntervalSince1970: 120)
        store.observe(central: id, activity: .read, characteristic: .tfAngle)

        let central = store.centrals.first
        XCTAssertEqual(central?.id, id)
        XCTAssertEqual(central?.firstSeen, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(central?.lastSeen, Date(timeIntervalSince1970: 120))
        XCTAssertEqual(central?.lastActivity, .read)
        XCTAssertEqual(central?.subscriptions, [.mtRPM, .sysState])
        XCTAssertEqual(central?.inferredSessionActive, true)

        now = Date(timeIntervalSince1970: 130)
        store.observe(central: id, activity: .unsubscribe, characteristic: .sysState)
        XCTAssertEqual(store.centrals.first?.subscriptions, [.mtRPM])
        XCTAssertEqual(store.centrals.first?.inferredSessionActive, true)
        store.observe(central: id, activity: .unsubscribe, characteristic: .mtRPM)
        XCTAssertEqual(store.centrals.first?.subscriptions, [])
        XCTAssertEqual(store.centrals.first?.inferredSessionActive, false)
        XCTAssertEqual(store.centrals.first?.lastActivity, .unsubscribe)
    }

    func testReadOrWriteAloneCreatesActivityOnlyObservation() {
        let store = ObservedCentralStore(now: { Date(timeIntervalSince1970: 200) })
        let id = UUID()
        store.observe(central: id, activity: .write, characteristic: .mtRPM)
        XCTAssertEqual(store.centrals.count, 1)
        XCTAssertEqual(store.centrals[0].firstSeen, store.centrals[0].lastSeen)
        XCTAssertEqual(store.centrals[0].subscriptions, [])
        XCTAssertFalse(store.centrals[0].inferredSessionActive)
        XCTAssertEqual(store.centrals[0].lastActivity, .write)
    }

    func testStoreIsIndependentOfScenarioModelReplacement() {
        let store = ObservedCentralStore()
        let id = UUID()
        store.observe(central: id, activity: .subscribe, characteristic: .sysState)
        _ = DeviceModel(scenario: .default, logger: EventLog())
        _ = DeviceModel(scenario: Scenario(name: "replacement"), logger: EventLog())
        XCTAssertEqual(store.centrals.count, 1)
        XCTAssertEqual(store.centrals[0].id, id)
        XCTAssertEqual(store.centrals[0].subscriptions, [.sysState])
    }

    func testObservationEncodingDoesNotInventPhoneNameAliasOrConfirmedLinkLoss() throws {
        let store = ObservedCentralStore(now: { Date(timeIntervalSince1970: 300) })
        store.observe(central: UUID(), activity: .unsubscribe, characteristic: .sysState)
        let data = try JSONEncoder().encode(store.centrals[0])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["name"])
        XCTAssertNil(object["alias"])
        XCTAssertNil(object["connected"])
        XCTAssertNotEqual(object["linkLossConfirmed"] as? Bool, true)
        XCTAssertNotNil(object["inferredSessionActive"])
    }

    func testMultipleCentralsHaveIndependentObservationRecordIDs() {
        var generatedIDs = [
            UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        ]
        let store = ObservedCentralStore(
            now: { Date(timeIntervalSince1970: 400) },
            makeRecordID: { generatedIDs.removeFirst() }
        )
        let firstCentral = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let secondCentral = UUID(uuidString: "BBBBBBBB-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

        store.observe(central: firstCentral, activity: .subscribe, characteristic: .sysState)
        store.observe(central: secondCentral, activity: .write, characteristic: .mtRPM)

        XCTAssertEqual(store.centrals.count, 2)
        XCTAssertEqual(Set(store.centrals.map(\.id)), [firstCentral, secondCentral])
        XCTAssertEqual(
            Set(store.centrals.map(\.recordID)),
            [
                UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            ]
        )
        XCTAssertFalse(store.centrals.contains { $0.recordID == $0.id })
    }

    func testOnlyManuallyDisconnectedRecordCanBeHiddenAndRestored() throws {
        let store = ObservedCentralStore()
        let centralID = UUID()
        store.observe(central: centralID, activity: .subscribe, characteristic: .sysState)
        let recordID = try XCTUnwrap(store.centrals.first?.recordID)

        XCTAssertThrowsError(try store.hide(recordID: recordID)) { error in
            XCTAssertEqual(error as? ObservationMutationError, .requiresManualDisconnect)
        }
        try store.markDisconnected(recordID: recordID)
        XCTAssertEqual(store.centrals.first?.manuallyDisconnected, true)
        XCTAssertEqual(store.centrals.first?.hidden, false)
        XCTAssertEqual(store.centrals.first?.id, centralID)

        try store.hide(recordID: recordID)
        XCTAssertEqual(store.centrals.first?.hidden, true)
        XCTAssertEqual(store.centrals.first?.manuallyDisconnected, true)
        XCTAssertEqual(store.centrals.count, 1)

        try store.restore(recordID: recordID)
        XCTAssertEqual(store.centrals.first?.hidden, false)
        XCTAssertEqual(store.centrals.first?.manuallyDisconnected, true)
        XCTAssertEqual(store.centrals.first?.recordID, recordID)
        XCTAssertThrowsError(try store.hide(recordID: UUID())) { error in
            XCTAssertEqual(error as? ObservationMutationError, .recordNotFound)
        }
    }

    func testActivityAfterManualDisconnectionStartsOneNewRecordWithoutRevivingOldOne() throws {
        var generatedIDs = [
            UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        ]
        let store = ObservedCentralStore(makeRecordID: { generatedIDs.removeFirst() })
        let centralID = UUID()
        store.observe(central: centralID, activity: .subscribe, characteristic: .sysState)
        let firstRecordID = store.centrals[0].recordID
        store.observe(central: centralID, activity: .unsubscribe, characteristic: .sysState)
        XCTAssertEqual(store.centrals.count, 1, "ordinary unsubscribe must not create a record")

        try store.markDisconnected(recordID: firstRecordID)
        try store.hide(recordID: firstRecordID)
        store.observe(central: centralID, activity: .read, characteristic: .tfAngle)

        XCTAssertEqual(store.centrals.count, 2)
        let old = try XCTUnwrap(store.centrals.first { $0.recordID == firstRecordID })
        let current = try XCTUnwrap(store.centrals.first { $0.recordID != firstRecordID })
        XCTAssertEqual(old.id, current.id)
        XCTAssertTrue(old.manuallyDisconnected)
        XCTAssertTrue(old.hidden)
        XCTAssertFalse(current.manuallyDisconnected)
        XCTAssertFalse(current.hidden)
        XCTAssertEqual(current.lastActivity, .read)

        store.observe(central: centralID, activity: .write, characteristic: .mtRPM)
        store.observe(central: centralID, activity: .subscribe, characteristic: .sysState)
        XCTAssertEqual(store.centrals.count, 2, "subsequent activity belongs to the current record")
        XCTAssertEqual(store.centrals.first { $0.recordID == current.recordID }?.lastActivity, .subscribe)
    }

    func testDisconnectRequestIsUnconfirmedAndDoesNotCreateOrEndRecord() {
        let store = ObservedCentralStore()
        let centralID = UUID()
        store.observe(central: centralID, activity: .subscribe, characteristic: .sysState)
        let recordID = store.centrals[0].recordID

        XCTAssertTrue(store.noteDisconnectRequest(central: centralID))
        XCTAssertEqual(store.centrals.count, 1)
        XCTAssertEqual(store.centrals[0].recordID, recordID)
        XCTAssertTrue(store.centrals[0].disconnectRequested)
        XCTAssertFalse(store.centrals[0].manuallyDisconnected)
        XCTAssertFalse(store.centrals[0].hidden)
    }

    func testRestoreAllHiddenOnlyAffectsHiddenHistory() throws {
        let store = ObservedCentralStore()
        let firstCentral = UUID()
        let secondCentral = UUID()
        store.observe(central: firstCentral, activity: .read, characteristic: .mtRPM)
        store.observe(central: secondCentral, activity: .read, characteristic: .mtRPM)
        let firstRecord = store.centrals[0].recordID
        try store.markDisconnected(recordID: firstRecord)
        try store.hide(recordID: firstRecord)

        XCTAssertEqual(store.restoreAllHidden(), 1)
        XCTAssertEqual(store.restoreAllHidden(), 0)
        XCTAssertFalse(store.centrals[0].hidden)
        XCTAssertTrue(store.centrals[0].manuallyDisconnected)
        XCTAssertFalse(store.centrals[1].hidden)
        XCTAssertFalse(store.centrals[1].manuallyDisconnected)
    }

    func testReadWriteOnlyRecordIsDistinctFromPreviouslySubscribedRecord() {
        let store = ObservedCentralStore()
        let readWriteOnly = UUID()
        let previouslySubscribed = UUID()
        store.observe(central: readWriteOnly, activity: .read, characteristic: .mtRPM)
        store.observe(central: previouslySubscribed, activity: .subscribe, characteristic: .sysState)
        store.observe(central: previouslySubscribed, activity: .unsubscribe, characteristic: .sysState)
        store.observe(central: previouslySubscribed, activity: .read, characteristic: .mtRPM)

        XCTAssertFalse(store.centrals[0].hasObservedSubscription)
        XCTAssertTrue(store.centrals[1].hasObservedSubscription)
        XCTAssertEqual(store.centrals[1].subscriptions, [])
        XCTAssertEqual(store.centrals[1].lastActivity, .read)
        XCTAssertEqual(store.centrals.count, 2)
    }
}
