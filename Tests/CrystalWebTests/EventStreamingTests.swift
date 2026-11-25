import Foundation
import XCTest
import CrystalCore
@testable import CrystalWeb

final class EventStreamingTests: XCTestCase {
    private func event(_ sequence: UInt64, message: String = "event") -> SimEvent {
        SimEvent(
            sequence: sequence,
            timestamp: Date(timeIntervalSince1970: TimeInterval(sequence)),
            kind: .control,
            message: "\(message)-\(sequence)"
        )
    }

    func testRingRetainsExactlyMostRecent500Events() {
        var ring = EventRing()
        for sequence in 1...501 {
            ring.append(event(UInt64(sequence)))
        }
        XCTAssertEqual(ring.events.count, 500)
        XCTAssertEqual(ring.events.first?.sequence, 2)
        XCTAssertEqual(ring.events.last?.sequence, 501)
        XCTAssertEqual(ring.newestSequence, 501)
    }

    func testReplayResumeAndGapResyncSemantics() {
        var ring = EventRing(capacity: 2)
        for sequence in 1...3 { ring.append(event(UInt64(sequence))) }
        XCTAssertEqual(ring.replay(after: nil), .replay([event(2), event(3)]))
        XCTAssertEqual(ring.replay(after: 1), .replay([event(2), event(3)]))
        XCTAssertEqual(ring.replay(after: 2), .replay([event(3)]))
        XCTAssertEqual(ring.replay(after: 3), .replay([]))
        XCTAssertEqual(ring.replay(after: 0), .resync([event(2), event(3)]))
        XCTAssertEqual(ring.replay(after: 4), .resync([event(2), event(3)]))
    }

    func testSSEFramesIncludeSequenceIDMultilineDataAndHeartbeat() {
        let frame = SSEFrame.event(name: "log", id: 42, data: "first\nsecond")
        XCTAssertEqual(frame, "id: 42\nevent: log\ndata: first\ndata: second\n\n")
        XCTAssertEqual(SSEFrame.heartbeat, ": keepalive\n\n")
        let injected = SSEFrame.event(name: "log\nignored", id: nil, data: "value")
        XCTAssertFalse(injected.contains("log\nignored"))
    }

    func testBoundedSendQueueIsFIFOAndDisconnectsSlowClientOnOverflow() {
        var queue = BoundedSendQueue(maximumBytes: 10)
        XCTAssertTrue(queue.enqueue(Data([1, 2, 3])))
        XCTAssertTrue(queue.enqueue(Data([4, 5])))
        XCTAssertEqual(queue.byteCount, 5)
        XCTAssertEqual(queue.drain(), [Data([1, 2, 3]), Data([4, 5])])
        XCTAssertEqual(queue.byteCount, 0)

        XCTAssertTrue(queue.enqueue(Data(repeating: 1, count: 6)))
        XCTAssertFalse(queue.enqueue(Data(repeating: 2, count: 5)))
        XCTAssertTrue(queue.isClosed)
        XCTAssertEqual(queue.byteCount, 0)
        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertFalse(queue.enqueue(Data([3])))
        XCTAssertEqual(queue.drain(), [])
    }
}
