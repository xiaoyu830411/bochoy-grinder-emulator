import Foundation
import CrystalCore

@MainActor
final class DeviceScheduler {
    private struct Entry {
        var remainingMs: UInt64
        var deadline: DispatchTime?
        var workItem: DispatchWorkItem?
        let action: () -> Void
    }

    private var entries: [String: Entry] = [:]
    private(set) var paused = false

    var count: Int { entries.count }

    func schedule(id: String, delayMs: UInt64, action: @escaping () -> Void) {
        cancel(id: id)
        entries[id] = Entry(remainingMs: delayMs, deadline: nil, workItem: nil, action: action)
        if !paused {
            arm(id: id)
        }
    }

    func cancel(id: String) {
        entries[id]?.workItem?.cancel()
        entries.removeValue(forKey: id)
    }

    func cancelAll() {
        entries.values.forEach { $0.workItem?.cancel() }
        entries.removeAll()
        paused = false
    }

    func pause() {
        guard !paused else { return }
        paused = true
        let now = DispatchTime.now().uptimeNanoseconds
        for (id, var entry) in entries {
            entry.workItem?.cancel()
            entry.workItem = nil
            if let deadline = entry.deadline {
                let remainingNanoseconds = deadline.uptimeNanoseconds > now
                    ? deadline.uptimeNanoseconds - now
                    : 0
                entry.remainingMs = remainingNanoseconds / 1_000_000
            }
            entry.deadline = nil
            entries[id] = entry
        }
    }

    func resume() {
        guard paused else { return }
        paused = false
        for id in entries.keys {
            arm(id: id)
        }
    }

    private func arm(id: String) {
        guard var entry = entries[id], !paused else { return }
        let delay = entry.remainingMs
        let milliseconds = Int(min(delay, SimulationLimits.maximumDelayMs))
        let deadline = DispatchTime.now() + .milliseconds(milliseconds)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let fired = self.entries.removeValue(forKey: id) else { return }
            fired.action()
        }
        entry.deadline = deadline
        entry.workItem = workItem
        entries[id] = entry
        DispatchQueue.main.asyncAfter(deadline: deadline, execute: workItem)
    }
}
