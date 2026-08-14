import XCTest
@testable import SlateCore

private let t0 = FixedTimeSource.reference.now

private func response(
    level: HintLevel = .orient,
    text: String = "Look again at the step where you cancelled.",
    confidence: Double = 0.9,
    refusal: TutorResponse.Refusal? = nil
) -> TutorResponse {
    TutorResponse(
        level: level, hintText: text, errorClass: nil,
        confidence: confidence, refusal: refusal
    )
}

private func context(
    current: HintLevel? = nil,
    permitted: HintLevel = .orient,
    asked: Bool = false
) -> EvaluationContext {
    EvaluationContext(
        prompt: "simplify (3x^2 - 12)/(x^2 + x - 6)",
        currentLevel: current,
        permittedLevel: permitted,
        studentAskedExplicitly: asked
    )
}

final class HintLevelTests: XCTestCase {

    func testLevelsAreOrdered() {
        XCTAssertLessThan(HintLevel.orient, HintLevel.principle)
        XCTAssertLessThan(HintLevel.appliedNudge, HintLevel.workedStep)
    }

    func testTheLadderRunsOutAtTheTop() {
        XCTAssertEqual(HintLevel.orient.next, .principle)
        XCTAssertNil(HintLevel.workedStep.next)
    }

    // Only a worked step is gated on asking. A stall alone must never produce
    // the closest thing the tutor has to doing the problem.
    func testOnlyTheWorkedStepRequiresAsking() {
        XCTAssertFalse(HintLevel.orient.requiresExplicitRequest)
        XCTAssertFalse(HintLevel.appliedNudge.requiresExplicitRequest)
        XCTAssertTrue(HintLevel.workedStep.requiresExplicitRequest)
    }

    // Length is a proxy for restraint. A level-1 hint running to sixty words
    // has stopped orienting and started explaining — level 2 wearing level 1's
    // label — and the ladder only means anything if the rungs stay distinct.
    func testEarlierRungsAreTighterThanLaterOnes() {
        XCTAssertLessThan(HintLevel.orient.wordLimit, HintLevel.principle.wordLimit)
        XCTAssertLessThan(HintLevel.principle.wordLimit, HintLevel.appliedNudge.wordLimit)
    }
}

final class TutorResponseValidatorTests: XCTestCase {

    private let validator = TutorResponseValidator()

    func testAWellFormedHintIsAccepted() {
        XCTAssertTrue(validator.accepts(response(), context: context()))
    }

    func testAnEmptyHintIsRejected() {
        let rejections = validator.rejections(for: response(text: "   "), context: context())
        XCTAssertTrue(rejections.contains(.empty))
    }

    // The model is not trusted to obey the ceiling. Asking it nicely in the
    // prompt is not the same as being unable to exceed it.
    func testALevelAboveWhatIsPermittedIsRejected() {
        let rejections = validator.rejections(
            for: response(level: .workedStep, text: "The top factors to 3(x^2 - 4)."),
            context: context(permitted: .principle, asked: true)
        )
        XCTAssertTrue(rejections.contains(.exceededPermittedLevel(
            got: .workedStep, permitted: .principle
        )))
    }

    // Skipping a rung robs the student of the chance to fix it from a lighter
    // touch, which is the entire mechanism the ladder exists to provide.
    func testSkippingARungIsRejected() {
        let rejections = validator.rejections(
            for: response(level: .workedStep, text: "The top factors to 3(x^2 - 4)."),
            context: context(current: .orient, permitted: .workedStep, asked: true)
        )
        XCTAssertTrue(rejections.contains(.skippedALevel(from: .orient, to: .workedStep)))
    }

    func testAdvancingOneRungIsFine() {
        XCTAssertTrue(validator.accepts(
            response(level: .principle, text: "You can only cancel factors, not terms."),
            context: context(current: .orient, permitted: .principle)
        ))
    }

    func testAWorkedStepWithoutAskingIsRejected() {
        let rejections = validator.rejections(
            for: response(level: .workedStep, text: "The top factors to 3(x^2 - 4)."),
            context: context(current: .appliedNudge, permitted: .workedStep, asked: false)
        )
        XCTAssertTrue(rejections.contains(.workedStepWithoutRequest))
    }

    func testAWorkedStepAfterAskingIsAllowed() {
        XCTAssertTrue(validator.accepts(
            response(level: .workedStep, text: "The top factors to 3(x^2 - 4). Take it from there."),
            context: context(current: .appliedNudge, permitted: .workedStep, asked: true)
        ))
    }

    func testAnOverlongHintIsRejected() {
        let rambling = String(repeating: "word ", count: 60)
        let rejections = validator.rejections(
            for: response(level: .orient, text: rambling),
            context: context()
        )
        XCTAssertTrue(rejections.contains { if case .tooLong = $0 { return true }; return false })
    }

    // Silence beats a wrong hint. A hint pointing at a step that was actually
    // correct destroys trust in every hint after it, and the student has no way
    // to tell the difference in the moment.
    func testLowConfidenceIsRejected() {
        let rejections = validator.rejections(
            for: response(confidence: 0.2),
            context: context()
        )
        XCTAssertTrue(rejections.contains { if case .confidenceBelowFloor = $0 { return true }; return false })
    }

    func testBlatantFinalAnswersAreCaught() {
        for text in ["The answer is x = 2.", "So x = -3, therefore done.", "This simplifies to 3(x+2)/(x+3)."] {
            let rejections = validator.rejections(for: response(text: text), context: context())
            XCTAssertTrue(
                rejections.contains { if case .looksLikeAFinalAnswer = $0 { return true }; return false },
                "should have caught: \(text)"
            )
        }
    }

    func testTheFinalAnswerCheckCanBeTurnedOffOnlyByConfig() {
        var permissive = TutorConfig.default
        permissive.enforceNoAnswer = false
        let lenient = TutorResponseValidator(config: permissive)

        let text = "The answer is x = 2."
        XCTAssertFalse(TutorResponseValidator().accepts(response(text: text), context: context()))
        XCTAssertTrue(lenient.accepts(response(text: text), context: context()))
    }

    // Refusing is the product working, not failing, so a refusal is exempt from
    // the ladder rules it exists to protect.
    func testARefusalIsNotHeldToTheLadderRules() {
        let refusal = TutorResponse(
            level: .orient,
            hintText: "I can't help during a test — that's on you. Afterwards, I'm all yours.",
            errorClass: nil,
            confidence: 1.0,
            refusal: .assessmentInProgress
        )
        XCTAssertTrue(TutorResponseValidator().accepts(refusal, context: context()))
    }

    func testAnEmptyRefusalIsStillRejected() {
        let empty = TutorResponse(
            level: .orient, hintText: "", errorClass: nil,
            confidence: 1.0, refusal: .answerRequested
        )
        XCTAssertFalse(TutorResponseValidator().accepts(empty, context: context()))
    }

    // Reported all at once rather than one at a time, because a regeneration
    // prompt that names one fault per round trip costs one round trip per
    // fault, on the student's own API budget.
    func testEveryFaultIsReportedAtOnce() {
        let bad = TutorResponse(
            level: .workedStep,
            hintText: "The answer is x = 2. " + String(repeating: "word ", count: 80),
            errorClass: nil,
            confidence: 0.1,
            refusal: nil
        )
        let rejections = validator.rejections(for: bad, context: context(permitted: .orient))
        XCTAssertGreaterThanOrEqual(rejections.count, 4)
    }

    func testResponseSurvivesARoundTrip() throws {
        let original = TutorResponse(
            level: .appliedNudge,
            hintText: "Factor the top and bottom completely before cancelling anything.",
            errorClass: "math.cancellation.termsNotFactors",
            confidence: 0.87,
            refusal: nil
        )
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(TutorResponse.self, from: data), original)
    }
}

final class EvaluationContextTests: XCTestCase {

    // Sending an evaluation with nothing to reason about spends the student's
    // own API budget to receive a guess.
    func testAContextWithNothingToLookAtIsNotSendable() {
        XCTAssertFalse(EvaluationContext().isSendable)
    }

    func testAPromptAloneIsEnoughToSend() {
        XCTAssertTrue(EvaluationContext(prompt: "simplify").isSendable)
    }

    func testTimingOfNoStrokesIsAllZero() {
        let timing = StrokeTiming.measuring([], asOf: t0)
        XCTAssertEqual(timing.strokeCount, 0)
        XCTAssertEqual(timing.totalDuration, 0)
        XCTAssertEqual(timing.secondsSinceLastStroke, 0)
    }

    func testTimingMeasuresTheGapSinceTheLastStroke() {
        let stroke = InkStroke(
            points: [
                InkPoint(position: .zero, timeOffset: 0, pressure: 0.5,
                         azimuth: 0, altitude: 1.5, width: 4),
                InkPoint(position: CanvasPoint(x: 10, y: 0), timeOffset: 0.5, pressure: 0.5,
                         azimuth: 0, altitude: 1.5, width: 4)
            ],
            style: .defaultPen, createdAt: t0,
            hasPressure: false, hasTilt: false, lastModified: t0
        )

        let timing = StrokeTiming.measuring([stroke], asOf: t0.addingTimeInterval(10))

        XCTAssertEqual(timing.strokeCount, 1)
        XCTAssertEqual(timing.secondsSinceLastStroke, 9.5, accuracy: 0.01)
    }

    // Hesitation is the signal an image cannot carry. A ninety-second pause
    // before a line says something the finished picture does not.
    func testTimingFindsTheLongestPauseBetweenStrokes() {
        func stroke(startingAt offset: TimeInterval) -> InkStroke {
            InkStroke(
                points: [InkPoint(position: .zero, timeOffset: 0, pressure: 0.5,
                                  azimuth: 0, altitude: 1.5, width: 4)],
                style: .defaultPen,
                createdAt: t0.addingTimeInterval(offset),
                hasPressure: false, hasTilt: false,
                lastModified: t0
            )
        }

        let timing = StrokeTiming.measuring(
            [stroke(startingAt: 0), stroke(startingAt: 2), stroke(startingAt: 92)],
            asOf: t0.addingTimeInterval(92)
        )

        XCTAssertEqual(timing.longestPause, 90, accuracy: 0.01)
    }
}
