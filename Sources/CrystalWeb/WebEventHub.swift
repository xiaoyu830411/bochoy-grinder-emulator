import Foundation
import CrystalCore

@MainActor
public final class WebEventHub {
    public typealias Sink = @Sendable (Data) -> Void

    private var ring = EventRing(capacity: 500)
    private var subscribers: [UUID: Sink] = [:]
    private let snapshotProvider: @MainActor () -> SimulatorSnapshot
    private var snapshotScheduled = false
    private let encoder = JSONEncoder()

    public init(
        initialEvents: [SimEvent],
        snapshotProvider: @escaping @MainActor () -> SimulatorSnapshot
    ) {
        self.snapshotProvider = snapshotProvider
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        initialEvents.forEach { ring.append($0) }
    }

    public func subscribe(lastEventID: UInt64?, sink: @escaping Sink) -> UUID {
        let id = UUID()
        let replay = ring.replay(after: lastEventID)
        let events: [SimEvent]
        switch replay {
        case .replay(let replayed):
            events = replayed
        case .resync(let replayed):
            sink(frame(name: "resync", value: ["reason": "sequence-gap"]))
            events = replayed
        }
        for event in events {
            sink(logFrame(event))
        }
        sink(snapshotFrame())
        subscribers[id] = sink
        return id
    }

    public func unsubscribe(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }

    public func record(_ event: SimEvent) {
        ring.append(event)
        let data = logFrame(event)
        subscribers.values.forEach { $0(data) }
        guard !snapshotScheduled else { return }
        snapshotScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.snapshotScheduled = false
            let snapshot = self.snapshotFrame()
            self.subscribers.values.forEach { $0(snapshot) }
        }
    }

    private func logFrame(_ event: SimEvent) -> Data {
        frame(name: "log", id: event.sequence, value: event)
    }

    private func snapshotFrame() -> Data {
        frame(name: "snapshot", value: snapshotProvider())
    }

    private func frame<T: Encodable>(name: String, id: UInt64? = nil, value: T) -> Data {
        do {
            let json = String(decoding: try encoder.encode(value), as: UTF8.self)
            return Data(SSEFrame.event(name: name, id: id, data: json).utf8)
        } catch {
            let fallback = SSEFrame.event(
                name: "log",
                data: "{\"kind\":\"error\",\"message\":\"Web event encoding failed\"}"
            )
            return Data(fallback.utf8)
        }
    }
}
