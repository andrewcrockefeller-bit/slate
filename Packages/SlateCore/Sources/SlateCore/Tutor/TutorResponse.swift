import Foundation

/// What the tutor decided to say.
///
/// Structured rather than free text, because every field is something our own
/// code has to check before a word of it reaches the student.
public struct TutorResponse: Hashable, Sendable, Codable {

    /// The rung this hint sits on.
    public let level: HintLevel

    /// The hint itself, as the student will read it.
    public let hintText: String

    /// What the student got wrong, from a fixed vocabulary.
    ///
    /// Namespaced by domain — `math.cancellation.termsNotFactors` — so that the
    /// taxonomy survives v1.5 adding reading and writing. A flat vocabulary does
    /// not survive a second domain.
    public let errorClass: String?

    /// How sure the model is, 0...1. Below the configured floor, nothing is
    /// placed: silence beats a hint pointing at a step that was correct.
    public let confidence: Double

    /// Set when the tutor declined to help — during an exam, or because the
    /// student asked for the answer outright.
    ///
    /// A first-class outcome rather than an error. Refusing is the product
    /// working, not failing.
    public let refusal: Refusal?

    public enum Refusal: String, Hashable, Sendable, Codable {
        /// The app is in exam mode, or the student said they are being
        /// assessed.
        case assessmentInProgress

        /// The student asked for the answer rather than for help.
        case answerRequested

        /// The model could not read the work well enough to say anything
        /// useful.
        case workIllegible
    }

    public init(
        level: HintLevel,
        hintText: String,
        errorClass: String? = nil,
        confidence: Double,
        refusal: Refusal? = nil
    ) {
        self.level = level
        self.hintText = hintText
        self.errorClass = errorClass
        self.confidence = confidence
        self.refusal = refusal
    }

    public var wordCount: Int {
        hintText.split(whereSeparator: \.isWhitespace).count
    }
}

/// Why a response was rejected.
public enum TutorResponseRejection: Hashable, Sendable, CustomStringConvertible {
    case exceededPermittedLevel(got: HintLevel, permitted: HintLevel)
    case skippedALevel(from: HintLevel, to: HintLevel)
    case workedStepWithoutRequest
    case tooLong(level: HintLevel, words: Int, limit: Int)
    case empty
    case confidenceBelowFloor(Double, floor: Double)
    case looksLikeAFinalAnswer(matched: String)

    public var description: String {
        switch self {
        case .exceededPermittedLevel(let got, let permitted):
            return "level \(got.rawValue) exceeds the permitted \(permitted.rawValue)"
        case .skippedALevel(let from, let to):
            return "jumped from level \(from.rawValue) to \(to.rawValue)"
        case .workedStepWithoutRequest:
            return "a worked step was offered without the student asking"
        case .tooLong(let level, let words, let limit):
            return "level \(level.rawValue) hint is \(words) words, over the \(limit)-word limit"
        case .empty:
            return "the hint is empty"
        case .confidenceBelowFloor(let value, let floor):
            return "confidence \(value) is below the floor of \(floor)"
        case .looksLikeAFinalAnswer(let matched):
            return "the hint reads like a final answer (matched '\(matched)')"
        }
    }
}

/// Checks a response before any of it reaches the student.
///
/// This is rule R5 from the founding brief: the model is not trusted to obey
/// the ladder; the ladder is enforced by our code on the way out. Prompting
/// alone holds most of the time, and the rest of the time is the screenshot
/// that ends up on a teacher's desk.
///
/// Honest about its limits. The structural checks — level, length, ordering,
/// confidence — are exact and enforceable. The final-answer check is a
/// heuristic backstop and is not, and cannot be, a guarantee: deciding whether
/// a sentence gives away the answer is the same problem as understanding the
/// sentence. It is here to catch the blatant cases cheaply, and the structural
/// rules are what actually hold the line.
public struct TutorResponseValidator: Sendable {

    /// Phrases that almost always mean the answer is about to be stated
    /// outright. Deliberately short and blunt.
    public static let finalityMarkers: [String] = [
        "the answer is",
        "the solution is",
        "so x =",
        "therefore x =",
        "which gives x =",
        "the final answer",
        "simplifies to",
        "in conclusion"
    ]

    public var config: TutorConfig

    public init(config: TutorConfig = .default) {
        self.config = config
    }

    /// Every reason this response should not be shown, or an empty array.
    ///
    /// Returns all of them rather than the first, because a regeneration prompt
    /// that names one fault at a time takes as many round trips as there are
    /// faults, and each one costs the student's own API budget.
    public func rejections(
        for response: TutorResponse,
        context: EvaluationContext
    ) -> [TutorResponseRejection] {

        // A refusal is the product working. It is exempt from the ladder rules
        // it exists to protect.
        if response.refusal != nil {
            return response.hintText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? [.empty]
                : []
        }

        var rejections: [TutorResponseRejection] = []

        if response.hintText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rejections.append(.empty)
        }

        if response.level > context.permittedLevel {
            rejections.append(.exceededPermittedLevel(
                got: response.level, permitted: context.permittedLevel
            ))
        }

        // Never skip a rung. Going straight to an applied nudge robs the
        // student of the chance to fix it from a lighter touch, which is the
        // entire mechanism the ladder exists to provide.
        if let current = context.currentLevel,
           response.level.rawValue > current.rawValue + 1 {
            rejections.append(.skippedALevel(from: current, to: response.level))
        }

        if config.ladderRequiresAttempt,
           response.level.requiresExplicitRequest,
           !context.studentAskedExplicitly {
            rejections.append(.workedStepWithoutRequest)
        }

        let words = response.wordCount
        if words > response.level.wordLimit {
            rejections.append(.tooLong(
                level: response.level, words: words, limit: response.level.wordLimit
            ))
        }

        if response.confidence < config.confidenceFloor {
            rejections.append(.confidenceBelowFloor(
                response.confidence, floor: config.confidenceFloor
            ))
        }

        if config.enforceNoAnswer, let matched = Self.finalityMarker(in: response.hintText) {
            rejections.append(.looksLikeAFinalAnswer(matched: matched))
        }

        return rejections
    }

    /// Whether the response may be shown as it stands.
    public func accepts(_ response: TutorResponse, context: EvaluationContext) -> Bool {
        rejections(for: response, context: context).isEmpty
    }

    /// The first finality marker found, if any.
    public static func finalityMarker(in text: String) -> String? {
        let lowered = text.lowercased()
        return finalityMarkers.first { lowered.contains($0) }
    }
}
