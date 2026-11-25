import Foundation

public enum CentralActivity: String, Codable, Sendable {
    case subscribe
    case unsubscribe
    case read
    case write
}

public enum ObservationMutationError: Error, Equatable {
    case recordNotFound
    case requiresManualDisconnect
}

public struct ObservedCentral: Codable, Equatable, Sendable {
    public let id: UUID
    public let recordID: UUID
    public let firstSeen: Date
    public internal(set) var lastSeen: Date
    public internal(set) var lastActivity: CentralActivity
    public internal(set) var subscriptions: [Characteristic]
    public internal(set) var inferredSessionActive: Bool
    public internal(set) var hasObservedSubscription: Bool
    public internal(set) var manuallyDisconnected: Bool
    public internal(set) var hidden: Bool
    public internal(set) var disconnectRequested: Bool

    init(
        id: UUID,
        recordID: UUID,
        firstSeen: Date,
        lastSeen: Date,
        lastActivity: CentralActivity,
        subscriptions: [Characteristic] = [],
        inferredSessionActive: Bool = false,
        hasObservedSubscription: Bool = false,
        manuallyDisconnected: Bool = false,
        hidden: Bool = false,
        disconnectRequested: Bool = false
    ) {
        self.id = id
        self.recordID = recordID
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.lastActivity = lastActivity
        self.subscriptions = subscriptions
        self.inferredSessionActive = inferredSessionActive
        self.hasObservedSubscription = hasObservedSubscription
        self.manuallyDisconnected = manuallyDisconnected
        self.hidden = hidden
        self.disconnectRequested = disconnectRequested
    }
}

@MainActor
public final class ObservedCentralStore {
    private var storage: [UUID: ObservedCentral] = [:]
    private var currentRecordIDs: [UUID: UUID] = [:]
    private let now: () -> Date
    private let makeRecordID: () -> UUID

    public init(
        now: @escaping () -> Date = Date.init,
        makeRecordID: @escaping () -> UUID = UUID.init
    ) {
        self.now = now
        self.makeRecordID = makeRecordID
    }

    public var centrals: [ObservedCentral] {
        storage.values.sorted {
            if $0.firstSeen != $1.firstSeen { return $0.firstSeen < $1.firstSeen }
            return $0.recordID.uuidString < $1.recordID.uuidString
        }
    }

    public func observe(
        central id: UUID,
        activity: CentralActivity,
        characteristic: Characteristic
    ) {
        let timestamp = now()
        var central: ObservedCentral
        if let recordID = currentRecordIDs[id], let current = storage[recordID] {
            central = current
        } else {
            central = ObservedCentral(
                id: id,
                recordID: makeRecordID(),
                firstSeen: timestamp,
                lastSeen: timestamp,
                lastActivity: activity
            )
            currentRecordIDs[id] = central.recordID
        }
        central.lastSeen = timestamp
        central.lastActivity = activity
        var subscriptions = Set(central.subscriptions)
        switch activity {
        case .subscribe:
            subscriptions.insert(characteristic)
            central.hasObservedSubscription = true
        case .unsubscribe:
            subscriptions.remove(characteristic)
        case .read, .write:
            break
        }
        central.subscriptions = Characteristic.allCases.filter { subscriptions.contains($0) }
        central.inferredSessionActive = !subscriptions.isEmpty
        storage[central.recordID] = central
    }

    public func markDisconnected(recordID: UUID) throws {
        guard var central = storage[recordID] else {
            throw ObservationMutationError.recordNotFound
        }
        central.manuallyDisconnected = true
        storage[recordID] = central
        if currentRecordIDs[central.id] == recordID {
            currentRecordIDs.removeValue(forKey: central.id)
        }
    }

    public func hide(recordID: UUID) throws {
        guard var central = storage[recordID] else {
            throw ObservationMutationError.recordNotFound
        }
        guard central.manuallyDisconnected else {
            throw ObservationMutationError.requiresManualDisconnect
        }
        central.hidden = true
        storage[recordID] = central
    }

    public func restore(recordID: UUID) throws {
        guard var central = storage[recordID] else {
            throw ObservationMutationError.recordNotFound
        }
        central.hidden = false
        storage[recordID] = central
    }

    @discardableResult
    public func restoreAllHidden() -> Int {
        let hiddenIDs = storage.values.filter(\.hidden).map(\.recordID)
        for recordID in hiddenIDs {
            storage[recordID]?.hidden = false
        }
        return hiddenIDs.count
    }

    @discardableResult
    public func noteDisconnectRequest(central id: UUID) -> Bool {
        guard let recordID = currentRecordIDs[id], var central = storage[recordID] else {
            return false
        }
        central.disconnectRequested = true
        storage[recordID] = central
        return true
    }
}
