import Foundation

/// Every value in the tutor loop that anyone might want to tune.
///
/// The rule this type exists to enforce: no timing threshold, no cooldown, no
/// cap, no render dimension, and no confidence floor appears as a literal at a
/// call site anywhere in the codebase. They live here, with a documented
/// default and a note on what moving it does, because all of them will be
/// adjusted repeatedly against real use and hunting them down individually is
/// how tuning stops happening.
///
/// v1.5 adds a parallel set for text-based work. When it does, it goes in a
/// sibling type composed into this one rather than doubling this struct's
/// length.
public struct TutorConfig: Hashable, Sendable, Codable {

    // MARK: - Trigger timing

    /// Stroke silence before the stall trigger arms, in seconds.
    ///
    /// The primary trigger and the main personality dial. Lower means a pushier
    /// tutor. Below roughly 2.5s it starts interrupting people who are thinking
    /// rather than stuck, which reads as nagging and is worse than being late.
    public var stallThreshold: TimeInterval

    /// Minimum spacing between two placed hints, in seconds.
    ///
    /// Does not apply to an explicit request from the student, which is never
    /// suppressed.
    public var hintCooldown: TimeInterval

    /// Window after a hint lands during which the stall trigger cannot fire at
    /// all, in seconds.
    ///
    /// Distinct from `hintCooldown` on purpose: the student is reading the hint
    /// and is not writing, which looks exactly like a stall and is the opposite
    /// of one.
    public var postHintQuietPeriod: TimeInterval

    /// Time on a single region with continuing strokes but no structural
    /// progress before the dwell trigger arms, in seconds.
    ///
    /// Catches the student who is busily going nowhere. The stall trigger never
    /// fires for them because they never stop writing.
    public var dwellThreshold: TimeInterval

    // MARK: - Erase burst

    /// Fraction of recently written strokes that must be erased to trigger an
    /// evaluation, from 0 to 1.
    ///
    /// An erase burst means the student has detected an error but not diagnosed
    /// it, which is the most receptive moment in a session. Lowering this makes
    /// the tutor more eager to jump on ordinary corrections.
    public var eraseBurstFraction: Double

    /// Window over which `eraseBurstFraction` is measured, in seconds.
    public var eraseBurstWindow: TimeInterval

    // MARK: - Caps

    /// Hints placed on one region before the tutor goes quiet until the student
    /// explicitly asks.
    public var maxHintsPerProblem: Int

    /// Worked-step hints permitted on one region.
    ///
    /// After the last one the tutor offers to set the problem aside rather than
    /// continuing to walk the student through it, because at that point walking
    /// them through it is just doing it for them slowly.
    public var maxLevel4PerProblem: Int

    // MARK: - Response handling

    /// Model confidence below which nothing is placed, from 0 to 1.
    ///
    /// Silence beats a wrong hint by a wide margin. A hint pointing at a step
    /// that was actually correct destroys trust in every subsequent hint, and
    /// the student has no way to tell the difference in the moment.
    public var confidenceFloor: Double

    // MARK: - Region rendering

    /// Scale factor applied when rasterizing a work region for the model.
    public var regionRenderScale: Double

    /// Cap on the long edge of a rasterized region, in pixels.
    ///
    /// The single biggest lever on both cost per hint and reading accuracy.
    /// Set it from measured numbers once the provider seam is live, not from
    /// intuition.
    public var regionRenderMaxEdge: Int

    /// Padding around a region when cropping, as a fraction of its long edge.
    ///
    /// Handwriting routinely spills outside the region a student marked, and a
    /// crop that clips the last line of work produces confidently wrong hints.
    public var regionPaddingFraction: Double

    // MARK: - Input

    /// Debounce applied before treating a stroke as complete, in seconds.
    ///
    /// Ink capture emits partial strokes mid-gesture on at least one platform,
    /// so acting on the first event delivered would treat one pen stroke as
    /// several. Belongs to the domain rather than the adapter because the tutor
    /// loop's notion of "a stroke happened" is what it protects.
    public var strokeDebounce: TimeInterval

    // MARK: - Feature flags

    /// Whether hint levels require an intervening student attempt to advance.
    ///
    /// Testing only. Off means the ladder escalates on repeated stalls alone,
    /// which is useful for exercising level 3 and 4 quickly and is not a
    /// shippable tutoring behavior.
    public var ladderRequiresAttempt: Bool

    /// Whether parsed responses are validated against the no-answer rules and
    /// regenerated on violation.
    ///
    /// Never ship this false. Prompting alone holds most of the time, and the
    /// rest of the time is the screenshot that ends up on a teacher's desk.
    public var enforceNoAnswer: Bool

    // MARK: - Provider

    /// Which Anthropic model `AnthropicProvider` asks.
    ///
    /// The single biggest lever on cost per hint after `regionRenderMaxEdge`.
    /// Swapping this for a cheaper or faster model is meant to be a one-line
    /// change here, never a search-and-replace across call sites.
    public var anthropicModelIdentifier: String

    public init(
        stallThreshold: TimeInterval = 4.0,
        hintCooldown: TimeInterval = 20.0,
        postHintQuietPeriod: TimeInterval = 8.0,
        dwellThreshold: TimeInterval = 90.0,
        eraseBurstFraction: Double = 0.40,
        eraseBurstWindow: TimeInterval = 10.0,
        maxHintsPerProblem: Int = 6,
        maxLevel4PerProblem: Int = 2,
        confidenceFloor: Double = 0.60,
        regionRenderScale: Double = 2.0,
        regionRenderMaxEdge: Int = 1536,
        regionPaddingFraction: Double = 0.08,
        strokeDebounce: TimeInterval = 0.4,
        ladderRequiresAttempt: Bool = true,
        enforceNoAnswer: Bool = true,
        anthropicModelIdentifier: String = "claude-sonnet-5"
    ) {
        self.stallThreshold = stallThreshold
        self.hintCooldown = hintCooldown
        self.postHintQuietPeriod = postHintQuietPeriod
        self.dwellThreshold = dwellThreshold
        self.eraseBurstFraction = eraseBurstFraction
        self.eraseBurstWindow = eraseBurstWindow
        self.maxHintsPerProblem = maxHintsPerProblem
        self.maxLevel4PerProblem = maxLevel4PerProblem
        self.confidenceFloor = confidenceFloor
        self.regionRenderScale = regionRenderScale
        self.regionRenderMaxEdge = regionRenderMaxEdge
        self.regionPaddingFraction = regionPaddingFraction
        self.strokeDebounce = strokeDebounce
        self.ladderRequiresAttempt = ladderRequiresAttempt
        self.enforceNoAnswer = enforceNoAnswer
        self.anthropicModelIdentifier = anthropicModelIdentifier
    }

    /// The shipping defaults.
    public static let `default` = TutorConfig()
}

// MARK: - Validation

extension TutorConfig {

    /// A configuration value that is outside its usable range.
    public struct ValidationIssue: Hashable, Sendable, CustomStringConvertible {
        public let field: String
        public let reason: String

        public init(field: String, reason: String) {
            self.field = field
            self.reason = reason
        }

        public var description: String { "\(field): \(reason)" }
    }

    /// Values that are outside their usable range, in no particular order.
    ///
    /// The tuning screen is developer-facing and takes free-form numbers, so
    /// this exists to catch a typo before it becomes a tutor that fires every
    /// 0.04 seconds. It reports rather than clamps: silently correcting a value
    /// someone deliberately typed is how tuning sessions produce results nobody
    /// can reproduce.
    public func validationIssues() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        func requirePositive(_ value: Double, _ name: String) {
            if !(value > 0) {
                issues.append(ValidationIssue(field: name, reason: "must be greater than zero"))
            }
        }

        func requireFraction(_ value: Double, _ name: String) {
            if !(value >= 0 && value <= 1) {
                issues.append(ValidationIssue(field: name, reason: "must be between 0 and 1"))
            }
        }

        func requirePositiveCount(_ value: Int, _ name: String) {
            if value <= 0 {
                issues.append(ValidationIssue(field: name, reason: "must be at least 1"))
            }
        }

        requirePositive(stallThreshold, "stallThreshold")
        requirePositive(hintCooldown, "hintCooldown")
        requirePositive(postHintQuietPeriod, "postHintQuietPeriod")
        requirePositive(dwellThreshold, "dwellThreshold")
        requirePositive(eraseBurstWindow, "eraseBurstWindow")
        requirePositive(regionRenderScale, "regionRenderScale")
        requirePositive(strokeDebounce, "strokeDebounce")

        requireFraction(eraseBurstFraction, "eraseBurstFraction")
        requireFraction(confidenceFloor, "confidenceFloor")
        requireFraction(regionPaddingFraction, "regionPaddingFraction")

        requirePositiveCount(maxHintsPerProblem, "maxHintsPerProblem")
        requirePositiveCount(maxLevel4PerProblem, "maxLevel4PerProblem")
        requirePositiveCount(regionRenderMaxEdge, "regionRenderMaxEdge")

        if maxLevel4PerProblem > maxHintsPerProblem {
            issues.append(ValidationIssue(
                field: "maxLevel4PerProblem",
                reason: "cannot exceed maxHintsPerProblem"
            ))
        }

        if dwellThreshold <= stallThreshold {
            issues.append(ValidationIssue(
                field: "dwellThreshold",
                reason: "must be greater than stallThreshold, or the stall trigger preempts it entirely"
            ))
        }

        return issues
    }

    /// Whether every value is inside its usable range.
    public var isValid: Bool {
        validationIssues().isEmpty
    }
}
