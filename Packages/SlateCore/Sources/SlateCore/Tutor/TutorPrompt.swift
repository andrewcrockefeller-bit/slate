import Foundation

/// A request to a model, in provider-neutral terms.
///
/// Three parts, because every model worth using accepts roughly these three:
/// standing instructions, a turn of user text, and optionally an image. An
/// adapter's job is to express this in one vendor's wire format — not to decide
/// what it says. Keeping the words here means the tutor's behaviour is one file
/// that can be read, diffed, and tested, rather than something smeared across
/// however many provider adapters exist.
public struct TutorPrompt: Hashable, Sendable {
    public let system: String
    public let userText: String
    public let image: RasterizedRegion?

    public init(system: String, userText: String, image: RasterizedRegion? = nil) {
        self.system = system
        self.userText = userText
        self.image = image
    }
}

/// Turns an evaluation context into words.
///
/// Pure and deterministic: the same context produces the same prompt, byte for
/// byte. That is what makes it possible to assert on the prompt in a test
/// instead of hoping it still says what it used to.
public struct TutorPromptBuilder: Sendable {

    public var config: TutorConfig

    public init(config: TutorConfig = .default) {
        self.config = config
    }

    /// The output contract the model is held to.
    ///
    /// Named here because two things have to agree on it: this prompt and
    /// `TutorWirePayload`'s decoder. When they drift, the symptom is a parse
    /// failure on every response, which is loud — deliberately preferable to a
    /// silent fallback that shows the student a hint we never validated.
    public static let responseSchema = """
    {
      "level": <integer 1-4>,
      "hint": "<the hint, addressed to the student>",
      "errorClass": "<dotted identifier, or null>",
      "confidence": <number 0.0-1.0>,
      "refusal": "<assessmentInProgress | answerRequested | workIllegible, or null>"
    }
    """

    public func prompt(for context: EvaluationContext) -> TutorPrompt {
        TutorPrompt(
            system: systemPrompt(for: context),
            userText: userPrompt(for: context),
            image: context.image
        )
    }

    // MARK: - System

    /// The standing instructions. Stable across a session.
    ///
    /// Written as rules rather than as a persona. A persona ("you are a patient
    /// tutor") produces warmth and no constraint; the ladder needs constraint.
    /// Warmth is a property of the hint text, and the length limits do more for
    /// it than an adjective would.
    public func systemPrompt(for context: EvaluationContext) -> String {
        var lines: [String] = []

        lines.append("""
        You are a tutor watching a student work a problem by hand. You never give \
        the answer. Your entire job is to say the smallest true thing that lets \
        the student take the next step themselves.
        """)

        lines.append("""
        HINT LADDER. Every hint sits on exactly one rung. Start at the lowest rung \
        that could help and never skip one.
          1 ORIENT (max \(HintLevel.orient.wordLimit) words) — point at where the \
        trouble is. Name no mathematics. Do not say what is wrong, only where.
          2 PRINCIPLE (max \(HintLevel.principle.wordLimit) words) — state the \
        general rule that was broken. Do not touch the student's numbers.
          3 APPLIED NUDGE (max \(HintLevel.appliedNudge.wordLimit) words) — apply \
        the rule to the student's own expression and pose the next sub-question. \
        Stop before answering it.
          4 WORKED STEP (max \(HintLevel.workedStep.wordLimit) words) — perform \
        exactly one step and hand control back. Never the last step, and never \
        the step that reveals the result.
        """)

        lines.append("""
        HARD RULES.
        - Never state a final answer, a simplified result, or a value the student \
        is working towards, on any rung.
        - Never write "the answer is", "the solution is", "therefore x =", or \
        anything that means the same.
        - You may go no higher than rung \(context.permittedLevel.rawValue) on this turn.
        - If you cannot see the work well enough to be specific, refuse with \
        "workIllegible" rather than guessing. A wrong hint about correct work \
        costs more than silence.
        - If the student is being assessed, refuse with "assessmentInProgress".
        - If the student asked you for the answer, refuse with "answerRequested" \
        and say nothing that answers it.
        - Confidence is your own estimate that the fault you identified is real. \
        Below \(String(format: "%.2f", config.confidenceFloor)) nothing will be \
        shown, so an honest low number is better than a padded one.
        """)

        lines.append("""
        ERROR CLASS. When you can name the mistake, use a dotted identifier \
        scoped by subject — for example math.algebra.cancelledTermsNotFactors or \
        math.calculus.chainRuleOmitted. Use null when no single mistake explains \
        what you see.
        """)

        lines.append("""
        OUTPUT. Reply with one JSON object and nothing else. No prose before it, \
        no code fence around it.
        \(Self.responseSchema)
        """)

        return lines.joined(separator: "\n\n")
    }

    // MARK: - User turn

    /// The turn-specific text: the problem, the history, and what the student's
    /// pen has been doing.
    public func userPrompt(for context: EvaluationContext) -> String {
        var lines: [String] = []

        if let prompt = context.prompt, !prompt.isEmpty {
            lines.append("PROBLEM AS GIVEN:\n\(prompt)")
        } else {
            lines.append("""
            PROBLEM: not known. The student drew a region around their own work, \
            so you can see the working but not the question. Do not assume what \
            was asked.
            """)
        }

        if context.image != nil {
            lines.append("The image is the student's handwritten work in that region.")
        }

        if let timing = context.timing, timing.strokeCount > 0 {
            lines.append("""
            PEN ACTIVITY: \(timing.strokeCount) strokes over \
            \(Self.seconds(timing.totalDuration)); longest pause mid-work \
            \(Self.seconds(timing.longestPause)); idle for \
            \(Self.seconds(timing.secondsSinceLastStroke)) now.
            """)
        }

        if context.hintsAlreadyGiven.isEmpty {
            lines.append("No hints have been given on this problem yet. Begin at rung 1.")
        } else {
            let history = context.hintsAlreadyGiven
                .enumerated()
                .map { "  \($0.offset + 1). \($0.element)" }
                .joined(separator: "\n")
            lines.append("""
            HINTS ALREADY GIVEN, oldest first. Do not repeat them; the student \
            has read them and is still stuck.
            \(history)
            """)
        }

        if let current = context.currentLevel {
            lines.append("Current rung: \(current.rawValue). You may use rung \(current.rawValue) again, or rung \(min(current.rawValue + 1, context.permittedLevel.rawValue)) at most.")
        }

        if !context.recentErrorClasses.isEmpty {
            lines.append("""
            RECENT ERRORS THIS SESSION, most recent first: \
            \(context.recentErrorClasses.joined(separator: ", ")). A repeat of one \
            of these is worth naming as such.
            """)
        }

        lines.append(context.studentAskedExplicitly
            ? "The student asked for help outright."
            : "The student did not ask. You are stepping in because they appear stuck, so be lighter than you would be if asked.")

        return lines.joined(separator: "\n\n")
    }

    /// Whole seconds, so that an irrelevant fraction does not become something
    /// the model reasons about.
    private static func seconds(_ interval: TimeInterval) -> String {
        "\(Int(interval.rounded()))s"
    }
}
