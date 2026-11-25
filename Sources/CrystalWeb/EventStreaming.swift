import Foundation
import CrystalCore

public enum EventReplay: Equatable, Sendable {
    case replay([SimEvent])
    case resync([SimEvent])
}

public struct EventRing: Sendable {
    public let capacity: Int
    public private(set) var events: [SimEvent] = []

    public init(capacity: Int = 500) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    public var newestSequence: UInt64? { events.last?.sequence }

    public mutating func append(_ event: SimEvent) {
        events.append(event)
        if events.count > capacity {
            events.removeFirst(events.count - capacity)
        }
    }

    public func replay(after requested: UInt64?) -> EventReplay {
        guard let requested else { return .replay(events) }
        guard let oldest = events.first?.sequence, let newest = newestSequence else {
            return .replay([])
        }
        if requested > newest || (requested < oldest && requested != oldest - 1) {
            return .resync(events)
        }
        return .replay(events.filter { $0.sequence > requested })
    }
}

public enum SSEFrame {
    public static let heartbeat = ": keepalive\n\n"

    public static func event(name: String, id: UInt64? = nil, data: String) -> String {
        let safeName = name.replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        let normalizedData = data.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines: [String] = []
        if let id { lines.append("id: \(id)") }
        lines.append("event: \(safeName)")
        lines.append(contentsOf: normalizedData.components(separatedBy: "\n").map { "data: \($0)" })
        return lines.joined(separator: "\n") + "\n\n"
    }
}

public struct BoundedSendQueue: Sendable {
    public let maximumBytes: Int
    private var chunks: [Data] = []
    public private(set) var byteCount = 0
    public private(set) var isClosed = false

    public init(maximumBytes: Int) {
        precondition(maximumBytes >= 0)
        self.maximumBytes = maximumBytes
    }

    public var pendingCount: Int { chunks.count }

    @discardableResult
    public mutating func enqueue(_ data: Data) -> Bool {
        guard !isClosed, data.count <= maximumBytes - byteCount else {
            isClosed = true
            chunks.removeAll()
            byteCount = 0
            return false
        }
        chunks.append(data)
        byteCount += data.count
        return true
    }

    public mutating func drain() -> [Data] {
        defer {
            chunks.removeAll()
            byteCount = 0
        }
        return chunks
    }
}
