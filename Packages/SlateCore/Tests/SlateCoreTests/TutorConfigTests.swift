import XCTest
@testable import SlateCore

final class TutorConfigTests: XCTestCase {

    func testDefaultsAreValid() {
        XCTAssertTrue(TutorConfig.default.isValid, "\(TutorConfig.default.validationIssues())")
    }

    // Pinned deliberately. These numbers are product decisions recorded in the
    // founding brief, not incidental values, so changing one should require
    // changing this test and noticing that you did.
    func testDefaultsMatchTheBrief() {
        let config = TutorConfig.default

        XCTAssertEqual(config.stallThreshold, 4.0)
        XCTAssertEqual(config.hintCooldown, 20.0)
        XCTAssertEqual(config.postHintQuietPeriod, 8.0)
        XCTAssertEqual(config.dwellThreshold, 90.0)
        XCTAssertEqual(config.eraseBurstFraction, 0.40)
        XCTAssertEqual(config.eraseBurstWindow, 10.0)
        XCTAssertEqual(config.maxHintsPerProblem, 6)
        XCTAssertEqual(config.maxLevel4PerProblem, 2)
        XCTAssertEqual(config.confidenceFloor, 0.60)
        XCTAssertEqual(config.regionRenderScale, 2.0)
        XCTAssertEqual(config.regionRenderMaxEdge, 1536)
        XCTAssertEqual(config.regionPaddingFraction, 0.08)
        XCTAssertEqual(config.strokeDebounce, 0.4)
        XCTAssertTrue(config.ladderRequiresAttempt)
        XCTAssertTrue(config.enforceNoAnswer)
    }

    func testNonPositiveDurationIsRejected() {
        var config = TutorConfig.default
        config.stallThreshold = 0

        XCTAssertFalse(config.isValid)
        XCTAssertTrue(config.validationIssues().contains { $0.field == "stallThreshold" })
    }

    func testFractionOutsideZeroToOneIsRejected() {
        var config = TutorConfig.default
        config.confidenceFloor = 1.4

        XCTAssertFalse(config.isValid)
        XCTAssertTrue(config.validationIssues().contains { $0.field == "confidenceFloor" })
    }

    func testZeroHintCapIsRejected() {
        var config = TutorConfig.default
        config.maxHintsPerProblem = 0

        XCTAssertFalse(config.isValid)
        XCTAssertTrue(config.validationIssues().contains { $0.field == "maxHintsPerProblem" })
    }

    // A worked-step cap above the overall hint cap is unreachable, which makes
    // it look like a setting that does nothing rather than one that is wrong.
    func testWorkedStepCapAboveTotalHintCapIsRejected() {
        var config = TutorConfig.default
        config.maxLevel4PerProblem = config.maxHintsPerProblem + 1

        XCTAssertFalse(config.isValid)
        XCTAssertTrue(config.validationIssues().contains { $0.field == "maxLevel4PerProblem" })
    }

    // Dwell is meant to catch the student who never stops writing. If it is not
    // strictly longer than the stall threshold, the stall trigger always wins
    // and dwell silently never fires.
    func testDwellThresholdBelowStallThresholdIsRejected() {
        var config = TutorConfig.default
        config.dwellThreshold = config.stallThreshold

        XCTAssertFalse(config.isValid)
        XCTAssertTrue(config.validationIssues().contains { $0.field == "dwellThreshold" })
    }

    func testValidationReportsEveryProblemAtOnce() {
        var config = TutorConfig.default
        config.stallThreshold = -1
        config.confidenceFloor = 9
        config.maxHintsPerProblem = 0

        let fields = Set(config.validationIssues().map(\.field))
        XCTAssertTrue(fields.isSuperset(of: ["stallThreshold", "confidenceFloor", "maxHintsPerProblem"]))
    }

    func testConfigSurvivesACodableRoundTrip() throws {
        var original = TutorConfig.default
        original.stallThreshold = 3.25
        original.regionRenderMaxEdge = 2048

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TutorConfig.self, from: data)

        XCTAssertEqual(decoded, original)
    }
}
