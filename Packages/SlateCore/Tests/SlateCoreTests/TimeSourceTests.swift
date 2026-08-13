import XCTest
@testable import SlateCore

/// A time source the test can move forward by hand.
///
/// Lives here rather than in the library because it is mutable, and a mutable
/// reference type in Layer 1 would need locking to stay safely shareable for no
/// benefit outside tests.
private final class AdvanceableTimeSource: TimeSource, @unchecked Sendable {
    private var current: Date

    init(start: Date) {
        self.current = start
    }

    var now: Date { current }

    func advance(by interval: TimeInterval) {
        current = current.addingTimeInterval(interval)
    }
}

final class TimeSourceTests: XCTestCase {

    func testElapsedMeasuresForwardTime() {
        let source = AdvanceableTimeSource(start: FixedTimeSource.reference.now)
        let start = source.now
        source.advance(by: 7.5)

        XCTAssertEqual(source.elapsed(since: start), 7.5, accuracy: 0.0001)
    }

    // A timestamp in the future means the clock moved backwards — a manual
    // adjustment, a timezone change, or eventually a synced device. Every
    // caller in the tutor loop treats negative elapsed time as nonsense, and
    // clamping to zero delays a hint instead of firing every trigger at once.
    func testElapsedClampsAtZeroForFutureTimestamps() {
        let source = FixedTimeSource.reference
        let future = source.now.addingTimeInterval(3_600)

        XCTAssertEqual(source.elapsed(since: future), 0)
    }

    func testHasElapsedIsTrueExactlyAtTheThreshold() {
        let source = AdvanceableTimeSource(start: FixedTimeSource.reference.now)
        let start = source.now
        source.advance(by: 4.0)

        XCTAssertTrue(source.hasElapsed(4.0, since: start))
    }

    func testHasElapsedIsFalseBeforeTheThreshold() {
        let source = AdvanceableTimeSource(start: FixedTimeSource.reference.now)
        let start = source.now
        source.advance(by: 3.9)

        XCTAssertFalse(source.hasElapsed(4.0, since: start))
    }

    func testFixedTimeSourceDoesNotMove() {
        let source = FixedTimeSource.reference
        let first = source.now
        let second = source.now

        XCTAssertEqual(first, second)
    }
}
