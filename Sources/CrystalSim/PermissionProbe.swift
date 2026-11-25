import CoreBluetooth
import Darwin
import Foundation

@MainActor
final class PermissionProbe: NSObject, @MainActor CBPeripheralManagerDelegate {
    private var manager: CBPeripheralManager!
    private var timeoutWorkItem: DispatchWorkItem?
    private var poweredOnFlowStarted = false
    private let service = CBMutableService(
        type: CBUUID(string: "7fa2d10c-12f3-4b9e-9d77-1a9b65432100"),
        primary: true
    )

    override init() {
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: nil)
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        print("PROBE_STATE \(peripheral.state.rawValue)")
        switch peripheral.state {
        case .poweredOn:
            guard !poweredOnFlowStarted else { return }
            poweredOnFlowStarted = true
            let timeout = DispatchWorkItem {
                print("PROBE_ERROR timed out after Bluetooth powered on while publishing or advertising")
                exit(8)
            }
            timeoutWorkItem = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(20), execute: timeout)
            peripheral.add(service)
        case .poweredOff:
            print("PROBE_ERROR Bluetooth is powered off")
            exit(2)
        case .unauthorized:
            print("PROBE_ERROR Bluetooth access is unauthorized")
            exit(3)
        case .unsupported:
            print("PROBE_ERROR Bluetooth LE peripheral mode is unsupported")
            exit(4)
        case .resetting, .unknown:
            break
        @unknown default:
            print("PROBE_ERROR Unknown Bluetooth state")
            exit(5)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error {
            print("PROBE_ERROR add service: \(error.localizedDescription)")
            exit(6)
        }
        print("PROBE_SERVICE_ADDED \(service.uuid.uuidString)")
        peripheral.startAdvertising([
            CBAdvertisementDataLocalNameKey: "CRYSTAL-E57C",
        ])
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            print("PROBE_ERROR advertising: \(error.localizedDescription)")
            exit(7)
        }
        print("PROBE_ADVERTISING CRYSTAL-E57C")
        timeoutWorkItem?.cancel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            exit(0)
        }
    }
}
