import XCTest
import SlateCore
@testable import SlatePlatform

final class SystemTimeSourceTests: XCTestCase {

    func testReportsAPlausibleCurrentMoment() {
        let source = SystemTimeSource()
        let drift = abs(source.now.timeIntervalSince(Date()))

        XCTAssertLessThan(drift, 1.0)
    }

    func testMovesForward() {
        let source = SystemTimeSource()
        let first = source.now
        Thread.sleep(forTimeInterval: 0.01)

        XCTAssertGreaterThan(source.now, first)
    }

    // Proves the seam: domain code written against the protocol works unchanged
    // when handed the real adapter instead of a fake.
    func testSatisfiesTheDomainProtocol() {
        let source: any TimeSource = SystemTimeSource()
        let past = source.now.addingTimeInterval(-5)

        XCTAssertTrue(source.hasElapsed(4.0, since: past))
    }
}
