import CoreBluetooth
import Foundation
import CrystalCore
import CrystalWeb

@MainActor
final class BLEPeripheral: NSObject, @MainActor CBPeripheralManagerDelegate {
    private struct PendingResponse {
        let request: CBATTRequest
        let effects: [ModelEffect]
        let status: UInt8
        let operation: String
        let characteristic: Characteristic?
        let responseValue: UInt16?
        let faultID: String?
    }

    private struct OutgoingNotification {
        let characteristic: Characteristic
        let value: UInt16
        let copy: Int
        let totalCopies: Int
    }

    private static let serviceUUID = CBUUID(string: "7fa2d10c-12f3-4b9e-9d77-1a9b65432100")
    private static let characteristicsByUUID: [CBUUID: Characteristic] = Dictionary(
        uniqueKeysWithValues: Characteristic.allCases.map { (CBUUID(string: $0.uuid), $0) }
    )

    private var manager: CBPeripheralManager!
    private let logger: EventLog
    private let scheduler = DeviceScheduler()
    private var gattCharacteristics: [Characteristic: CBMutableCharacteristic] = [:]
    private var pendingResponses: [UUID: DispatchWorkItem] = [:]
    private var delayedNotifications: [UUID: DispatchWorkItem] = [:]
    private var outgoingQueue: [OutgoingNotification] = []
    private var bluetoothState: CBManagerState = .unknown
    private var pendingService: CBMutableService?
    private var lifecycleGeneration: UInt64 = 0

    private(set) var model: DeviceModel
    private(set) var advertising = false
    private var advertisingRequested = true
    private var advertisingStartPending = false
    private var advertisingStartName: String?
    var onTermination: (Int) -> Void = { _ in }
    var onCentralActivity: (UUID, CentralActivity, Characteristic) -> Void = { _, _, _ in }

    func snapshot() -> BluetoothSnapshot {
        BluetoothSnapshot(
            state: bluetoothState.rawValue,
            advertising: advertising,
            advertisingRequested: advertisingRequested,
            advertisingStartPending: advertisingStartPending,
            publishedCharacteristics: gattCharacteristics.count,
            subscriberIDs: subscriberIDs
        )
    }

    func requestDisconnect(centralID: UUID) {
        advertising = false
        advertisingStartPending = false
        advertisingStartName = nil
        pendingService = nil
        manager.stopAdvertising()
        manager.removeAllServices()
        if bluetoothState == .poweredOn, model.poweredOn {
            configureServices()
        }
        logger.record(
            .service,
            "Disconnect Request issued for Observed Central; disconnection unconfirmed",
            scenario: model.scenario.name,
            details: [
                "central": centralID.uuidString,
                "linkLossConfirmed": "false",
                "limitation": "CoreBluetooth has no public per-central force-disconnect API",
            ]
        )
    }

    init(model: DeviceModel, logger: EventLog) {
        self.model = model
        self.logger = logger
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: nil)
    }

    var hasKnownSubscribers: Bool {
        gattCharacteristics.values.contains { !($0.subscribedCentrals?.isEmpty ?? true) }
    }

    var subscriberIDs: [String] {
        let identifiers = gattCharacteristics.values.flatMap { $0.subscribedCentrals ?? [] }
        return Set(identifiers.map(\.identifier)).map(\.uuidString).sorted()
    }

    var canReload: Bool {
        !hasKnownSubscribers && pendingResponses.isEmpty && !model.sessionActive
    }

    var statusLines: [String] {
        [
            "bluetoothState=\(bluetoothState.rawValue) advertising=\(advertising) advertisingRequested=\(advertisingRequested) advertisingStartPending=\(advertisingStartPending)",
            "subscribers=\(subscriberIDs.joined(separator: ","))",
            "scheduledTimers=\(scheduler.count) schedulerPaused=\(scheduler.paused)",
            "pendingResponses=\(pendingResponses.count) notificationQueue=\(outgoingQueue.count)",
        ]
    }

    func execute(_ effects: [ModelEffect]) {
        let effectModel = model
        for effect in effects {
            switch effect {
            case .notify(let characteristic, let value):
                prepareNotification(characteristic, value: value)
            case .scheduleApply(let id, _, let delayMs):
                scheduler.schedule(id: "apply-\(id)", delayMs: delayMs) { [weak self] in
                    guard let self, self.model === effectModel, self.model.poweredOn else { return }
                    self.execute(self.model.completeApply(id: id))
                }
            case .scheduleRun(let id, let delayMs):
                scheduler.schedule(id: "run-\(id)", delayMs: delayMs) { [weak self] in
                    guard let self, self.model === effectModel, self.model.poweredOn else { return }
                    self.execute(self.model.completeRun(id: id))
                }
            case .cancelApply(let id):
                scheduler.cancel(id: "apply-\(id)")
            case .cancelRun(let id):
                scheduler.cancel(id: "run-\(id)")
            case .pauseTimers:
                scheduler.pause()
            case .resumeTimers:
                scheduler.resume()
            case .terminateProcess:
                logger.record(.fault, "process termination requested by fault", scenario: model.scenario.name)
                onTermination(70)
            }
        }
    }

    func replaceModel(_ newModel: DeviceModel) {
        lifecycleGeneration &+= 1
        manager.stopAdvertising()
        advertising = false
        advertisingStartPending = false
        // An in-flight callback belongs to the previous service/name configuration.
        advertisingStartName = nil
        pendingService = nil
        clearOutstandingWork(preserveTimerPause: false)
        model = newModel
        if bluetoothState == .poweredOn, model.poweredOn {
            configureServices()
        }
    }

    func powerDown() {
        lifecycleGeneration &+= 1
        advertisingRequested = false
        advertising = false
        advertisingStartPending = false
        advertisingStartName = nil
        pendingService = nil
        manager.stopAdvertising()
        clearOutstandingWork(preserveTimerPause: true)
        gattCharacteristics.removeAll()
        manager.removeAllServices()
        logger.record(
            .service,
            "GATT services removed; Disconnect Request issued; disconnection unconfirmed",
            scenario: model.scenario.name,
            details: ["linkLossConfirmed": "false", "poweredOn": "false"]
        )
    }

    func powerUp() {
        lifecycleGeneration &+= 1
        advertising = false
        advertisingRequested = true
        advertisingStartPending = false
        advertisingStartName = nil
        pendingService = nil
        if bluetoothState == .poweredOn {
            configureServices()
        }
    }

    private func clearOutstandingWork(preserveTimerPause: Bool) {
        let wasPaused = scheduler.paused
        scheduler.cancelAll()
        if preserveTimerPause, wasPaused { scheduler.pause() }
        pendingResponses.values.forEach { $0.cancel() }
        pendingResponses.removeAll()
        delayedNotifications.values.forEach { $0.cancel() }
        delayedNotifications.removeAll()
        outgoingQueue.removeAll()
    }

    func setAdvertisingEnabled(_ enabled: Bool) {
        guard model.poweredOn else { return }
        if enabled {
            if advertisingRequested, advertising || advertisingStartPending {
                logger.record(
                    .advertising,
                    "advertising already active or starting",
                    scenario: model.scenario.name
                )
                return
            }
            advertisingRequested = true
            startAdvertising()
        } else {
            advertisingRequested = false
            manager.stopAdvertising()
            advertising = false
            logger.record(
                .advertising,
                "advertising stopped; existing BLE links are not disconnected",
                scenario: model.scenario.name
            )
        }
    }

    private func configureServices() {
        manager.removeAllServices()
        gattCharacteristics.removeAll()
        pendingService = nil
        guard model.poweredOn else { return }
        guard model.scenario.layout.includeService else {
            logger.record(.service, "primary service omitted by scenario", scenario: model.scenario.name)
            startAdvertising()
            return
        }

        let service = CBMutableService(type: Self.serviceUUID, primary: true)
        let omitted = Set(model.scenario.layout.omittedCharacteristics)
        let notifyDisabled = Set(model.scenario.layout.notifyDisabled)
        let included = Characteristic.allCases.filter { !omitted.contains($0) }
        var mutableCharacteristics: [CBMutableCharacteristic] = []
        for characteristic in included {
            var properties: CBCharacteristicProperties = [.read, .write]
            if !notifyDisabled.contains(characteristic) {
                properties.insert(.notify)
            }
            let mutable = CBMutableCharacteristic(
                type: CBUUID(string: characteristic.uuid),
                properties: properties,
                value: nil,
                permissions: [.readable, .writeable]
            )
            gattCharacteristics[characteristic] = mutable
            mutableCharacteristics.append(mutable)
        }
        service.characteristics = mutableCharacteristics
        pendingService = service
        manager.add(service)
    }

    private func startAdvertising() {
        guard model.poweredOn, advertisingRequested else { return }
        guard bluetoothState == .poweredOn else {
            logger.record(.error, "cannot advertise while Bluetooth is not powered on", scenario: model.scenario.name)
            return
        }
        guard !advertising, !advertisingStartPending else { return }
        advertisingStartPending = true
        advertisingStartName = model.scenario.deviceName
        manager.startAdvertising([
            CBAdvertisementDataLocalNameKey: model.scenario.deviceName,
        ])
        logger.record(
            .advertising,
            "name-only advertising requested; primary service is discovered after connection",
            scenario: model.scenario.name,
            details: ["deviceName": model.scenario.deviceName]
        )
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        bluetoothState = peripheral.state
        logger.record(
            .bluetooth,
            "CoreBluetooth state changed",
            scenario: model.scenario.name,
            details: ["state": String(peripheral.state.rawValue)]
        )
        switch peripheral.state {
        case .poweredOn:
            if model.poweredOn {
                configureServices()
            } else {
                advertising = false
                advertisingStartPending = false
                advertisingStartName = nil
                peripheral.stopAdvertising()
                peripheral.removeAllServices()
            }
        case .poweredOff:
            advertising = false
            advertisingStartPending = false
            advertisingStartName = nil
            logger.record(.error, "Bluetooth powered off; advertising paused", scenario: model.scenario.name)
        case .unauthorized:
            logger.record(.error, "Bluetooth access unauthorized; grant permission and restart", scenario: model.scenario.name)
        case .unsupported:
            logger.record(.error, "BLE peripheral mode unsupported", scenario: model.scenario.name)
        case .resetting, .unknown:
            break
        @unknown default:
            logger.record(.error, "unknown CoreBluetooth state", scenario: model.scenario.name)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard model.poweredOn, let pendingService, service === pendingService else {
            logger.record(
                .service,
                "late GATT service callback ignored for inactive configuration",
                scenario: model.scenario.name
            )
            return
        }
        self.pendingService = nil
        if let error {
            logger.record(.error, "failed to add GATT service: \(error.localizedDescription)", scenario: model.scenario.name)
            onTermination(6)
            return
        }
        logger.record(
            .service,
            "GATT service published",
            scenario: model.scenario.name,
            details: [
                "uuid": service.uuid.uuidString,
                "characteristics": String(gattCharacteristics.count),
            ]
        )
        startAdvertising()
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        let startedName = advertisingStartName
        advertisingStartPending = false
        advertisingStartName = nil
        advertising = false
        guard model.poweredOn else {
            peripheral.stopAdvertising()
            logger.record(
                .advertising,
                "late advertising callback stopped because Device Power is off",
                scenario: model.scenario.name
            )
            return
        }
        if let error {
            logger.record(.error, "advertising failed: \(error.localizedDescription)", scenario: model.scenario.name)
            if lifecycleGeneration == 0, advertisingRequested {
                onTermination(7)
            }
            return
        }
        guard advertisingRequested else {
            peripheral.stopAdvertising()
            logger.record(
                .advertising,
                "late advertising callback stopped because advertising is disabled",
                scenario: model.scenario.name
            )
            return
        }
        guard startedName == model.scenario.deviceName else {
            peripheral.stopAdvertising()
            startAdvertising()
            return
        }
        advertising = true
        logger.record(
            .advertising,
            "advertising started",
            scenario: model.scenario.name,
            details: ["deviceName": model.scenario.deviceName]
        )
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        guard let mapped = Self.characteristicsByUUID[characteristic.uuid] else { return }
        onCentralActivity(central.identifier, .subscribe, mapped)
        guard model.poweredOn else {
            logger.record(.subscription, "late subscription ignored while Device Power is off", scenario: model.scenario.name)
            return
        }
        logger.record(
            .subscription,
            "central subscribed",
            scenario: model.scenario.name,
            characteristic: mapped,
            details: ["central": central.identifier.uuidString]
        )
        execute(model.sessionBegan(source: "subscription"))
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        guard let mapped = Self.characteristicsByUUID[characteristic.uuid] else { return }
        onCentralActivity(central.identifier, .unsubscribe, mapped)
        logger.record(
            .subscription,
            "central unsubscribed",
            scenario: model.scenario.name,
            characteristic: mapped,
            details: ["central": central.identifier.uuidString]
        )
        let generation = lifecycleGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.lifecycleGeneration == generation, self.model.poweredOn,
                  self.model.sessionActive, !self.hasKnownSubscribers else { return }
            self.execute(self.model.sessionEnded(source: "subscriptions-empty-inferred"))
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard let characteristic = Self.characteristicsByUUID[request.characteristic.uuid] else {
            respond(request, effects: [], status: ATTStatus.requestNotSupported, operation: "read", characteristic: nil, responseValue: nil, faultID: nil)
            return
        }
        onCentralActivity(request.central.identifier, .read, characteristic)
        guard model.poweredOn else {
            logger.record(
                .read,
                "read rejected: Device Powered Off",
                scenario: model.scenario.name,
                characteristic: characteristic,
                attStatus: ATTStatus.readNotPermitted
            )
            respond(request, effects: [], status: ATTStatus.readNotPermitted, operation: "read", characteristic: characteristic, responseValue: nil, faultID: nil)
            return
        }
        guard request.offset == 0 else {
            logger.record(
                .read,
                "read rejected: only offset zero is supported",
                scenario: model.scenario.name,
                characteristic: characteristic,
                attStatus: ATTStatus.invalidOffset,
                details: ["offset": String(request.offset)]
            )
            respond(request, effects: [], status: ATTStatus.invalidOffset, operation: "read", characteristic: characteristic, responseValue: nil, faultID: nil)
            return
        }

        let value = model.registers[characteristic]
        var status = ATTStatus.success
        var faultID: String?
        if let error = model.faults.attError(.readError, characteristic: characteristic, value: value) {
            status = error.status
            faultID = error.faultID
            request.value = nil
            logger.record(
                .read,
                "read rejected by injected ATT error",
                scenario: model.scenario.name,
                characteristic: characteristic,
                value: value,
                attStatus: status,
                faultID: faultID
            )
        } else {
            request.value = model.data(for: characteristic)
            logger.record(
                .read,
                "read request",
                scenario: model.scenario.name,
                characteristic: characteristic,
                value: value,
                attStatus: status
            )
        }
        let delay = model.faults.maximumDelay(.responseDelay, characteristic: characteristic, value: value)
        enqueueResponse(
            request,
            effects: [],
            status: status,
            operation: "read",
            characteristic: characteristic,
            responseValue: status == ATTStatus.success ? value : nil,
            faultID: faultID,
            delayMs: delay ?? 0
        )
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            guard let characteristic = Self.characteristicsByUUID[request.characteristic.uuid] else {
                respond(request, effects: [], status: ATTStatus.requestNotSupported, operation: "write", characteristic: nil, responseValue: nil, faultID: nil)
                continue
            }
            onCentralActivity(request.central.identifier, .write, characteristic)
            let data = request.value ?? Data()
            let value = UInt16Codec.decode(data)
            guard request.offset == 0 else {
                logger.record(
                    .write,
                    "write rejected: only offset zero is supported",
                    scenario: model.scenario.name,
                    characteristic: characteristic,
                    value: value,
                    raw: data,
                    attStatus: ATTStatus.invalidOffset
                )
                respond(request, effects: [], status: ATTStatus.invalidOffset, operation: "write", characteristic: characteristic, responseValue: nil, faultID: nil)
                continue
            }

            let preparation = model.prepareWrite(data, to: characteristic, source: .ble)
            let status = preparation.status
            let faultID = preparation.faultID
            let effects = preparation.effects
            let delay = model.poweredOn
                ? model.faults.maximumDelay(.responseDelay, characteristic: characteristic, value: value)
                : nil
            enqueueResponse(
                request,
                effects: effects,
                status: status,
                operation: "write",
                characteristic: characteristic,
                responseValue: nil,
                faultID: faultID,
                delayMs: delay ?? 0
            )
        }
    }

    private func enqueueResponse(
        _ request: CBATTRequest,
        effects: [ModelEffect],
        status: UInt8,
        operation: String,
        characteristic: Characteristic?,
        responseValue: UInt16?,
        faultID: String?,
        delayMs: UInt64
    ) {
        guard delayMs > 0 else {
            respond(request, effects: effects, status: status, operation: operation, characteristic: characteristic, responseValue: responseValue, faultID: faultID)
            return
        }
        let id = UUID()
        logger.record(
            .attResponse,
            "ATT response delayed",
            scenario: model.scenario.name,
            characteristic: characteristic,
            attStatus: status,
            details: ["operation": operation, "delayMs": String(delayMs)]
        )
        let milliseconds = Int(min(delayMs, SimulationLimits.maximumDelayMs))
        let generation = lifecycleGeneration
        let requestModel = model
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.lifecycleGeneration == generation,
                  self.model === requestModel, self.model.poweredOn else { return }
            self.pendingResponses.removeValue(forKey: id)
            self.respond(request, effects: effects, status: status, operation: operation, characteristic: characteristic, responseValue: responseValue, faultID: faultID)
        }
        pendingResponses[id] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(milliseconds), execute: workItem)
    }

    private func respond(
        _ request: CBATTRequest,
        effects: [ModelEffect],
        status: UInt8,
        operation: String,
        characteristic: Characteristic?,
        responseValue: UInt16?,
        faultID: String?
    ) {
        let result = CBATTError.Code(rawValue: Int(status)) ?? .unlikelyError
        manager.respond(to: request, withResult: result)
        logger.record(
            .attResponse,
            "ATT response completed",
            scenario: model.scenario.name,
            characteristic: characteristic,
            value: responseValue,
            attStatus: status,
            faultID: faultID,
            details: ["operation": operation]
        )
        execute(effects)
    }

    private func prepareNotification(_ characteristic: Characteristic, value: UInt16) {
        if model.faults.shouldApply(.notificationDrop, characteristic: characteristic, value: value) {
            logger.record(
                .notification,
                "notification dropped by fault; register change retained",
                scenario: model.scenario.name,
                characteristic: characteristic,
                value: value
            )
            return
        }
        let delay = model.faults.maximumDelay(.notificationDelay, characteristic: characteristic, value: value) ?? 0
        let duplicateRules = model.faults.match(.notificationDuplicate, characteristic: characteristic, value: value)
        let extraCopies = duplicateRules.map(\.extraCopies).max() ?? 0
        let copies = 1 + extraCopies
        for copy in 1...copies {
            let outgoing = OutgoingNotification(
                characteristic: characteristic,
                value: value,
                copy: copy,
                totalCopies: copies
            )
            if delay > 0 {
                let id = UUID()
                let milliseconds = Int(min(delay, SimulationLimits.maximumDelayMs))
                let generation = lifecycleGeneration
                let notificationModel = model
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self, self.lifecycleGeneration == generation,
                          self.model === notificationModel, self.model.poweredOn else { return }
                    self.delayedNotifications.removeValue(forKey: id)
                    self.sendOrQueue(outgoing)
                }
                delayedNotifications[id] = workItem
                logger.record(
                    .notification,
                    "notification delayed",
                    scenario: model.scenario.name,
                    characteristic: characteristic,
                    value: value,
                    details: ["delayMs": String(delay), "copy": String(copy)]
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(milliseconds), execute: workItem)
            } else {
                sendOrQueue(outgoing)
            }
        }
    }

    private func sendOrQueue(_ outgoing: OutgoingNotification) {
        guard outgoingQueue.isEmpty else {
            outgoingQueue.append(outgoing)
            logger.record(
                .notification,
                "notification queued behind backpressure",
                scenario: model.scenario.name,
                characteristic: outgoing.characteristic,
                value: outgoing.value
            )
            return
        }
        submit(outgoing)
    }

    private func submit(_ outgoing: OutgoingNotification) {
        guard let characteristic = gattCharacteristics[outgoing.characteristic] else {
            logger.record(
                .notification,
                "notification not submitted: characteristic absent from layout",
                scenario: model.scenario.name,
                characteristic: outgoing.characteristic,
                value: outgoing.value
            )
            return
        }
        guard !(characteristic.subscribedCentrals?.isEmpty ?? true) else {
            logger.record(
                .notification,
                "notification not submitted: no subscribers",
                scenario: model.scenario.name,
                characteristic: outgoing.characteristic,
                value: outgoing.value
            )
            return
        }
        let accepted = manager.updateValue(
            UInt16Codec.encode(outgoing.value),
            for: characteristic,
            onSubscribedCentrals: nil
        )
        if accepted {
            logger.record(
                .notification,
                "notification submitted to CoreBluetooth",
                scenario: model.scenario.name,
                characteristic: outgoing.characteristic,
                value: outgoing.value,
                details: [
                    "copy": String(outgoing.copy),
                    "totalCopies": String(outgoing.totalCopies),
                    "subscribers": String(characteristic.subscribedCentrals?.count ?? 0),
                ]
            )
        } else {
            outgoingQueue.append(outgoing)
            logger.record(
                .notification,
                "CoreBluetooth notification backpressure",
                scenario: model.scenario.name,
                characteristic: outgoing.characteristic,
                value: outgoing.value
            )
        }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        logger.record(.notification, "CoreBluetooth ready for queued notifications", scenario: model.scenario.name)
        while !outgoingQueue.isEmpty {
            let outgoing = outgoingQueue.removeFirst()
            guard let characteristic = gattCharacteristics[outgoing.characteristic],
                  !(characteristic.subscribedCentrals?.isEmpty ?? true) else {
                logger.record(
                    .notification,
                    "queued notification discarded: no current subscribers",
                    scenario: model.scenario.name,
                    characteristic: outgoing.characteristic,
                    value: outgoing.value
                )
                continue
            }
            let accepted = manager.updateValue(
                UInt16Codec.encode(outgoing.value),
                for: characteristic,
                onSubscribedCentrals: nil
            )
            if accepted {
                logger.record(
                    .notification,
                    "queued notification submitted to CoreBluetooth",
                    scenario: model.scenario.name,
                    characteristic: outgoing.characteristic,
                    value: outgoing.value,
                    details: ["copy": String(outgoing.copy), "totalCopies": String(outgoing.totalCopies)]
                )
            } else {
                outgoingQueue.insert(outgoing, at: 0)
                break
            }
        }
    }
}
