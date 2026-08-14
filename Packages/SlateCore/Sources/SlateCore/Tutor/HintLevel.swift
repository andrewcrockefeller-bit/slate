import Foundation

/// A rung on the hint ladder.
///
/// The ladder is a hard product constraint, not a setting. Each level says more
/// than the last, and the tutor never starts above the bottom. See the founding
/// brief, section 4.
public enum HintLevel: Int, Hashable, Sendable, Codable, CaseIterable, Comparable {

    /// Points at where the trouble is. Names no mathematics.
    case orient = 1

    /// States the general rule that was broken, without touching the student's
    /// numbers.
    case principle = 2

    /// Applies the rule to the student's actual expression and poses the next
    /// sub-question. Stops before answering it.
    case appliedNudge = 3

    /// Performs exactly one step, then hands control back. Never the last step.
    case workedStep = 4

    public static func < (lhs: HintLevel, rhs: HintLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The next rung, or `nil` at the top.
    public var next: HintLevel? {
        HintLevel(rawValue: rawValue + 1)
    }

    /// Whether reaching this level requires the student to have asked outright.
    ///
    /// Only level 4. A worked step is the closest the tutor ever comes to doing
    /// the problem, so it is never volunteered — a stall alone must not produce
    /// one.
    public var requiresExplicitRequest: Bool {
        self == .workedStep
    }

    /// The most words this level may use.
    ///
    /// Length is a proxy for restraint. A level-1 hint that runs to sixty words
    /// has stopped orienting and started explaining, which is level 2 wearing
    /// level 1's label — and the ladder only means anything if the rungs stay
    /// distinct.
    public var wordLimit: Int {
        switch self {
        case .orient: return 25
        case .principle: return 45
        case .appliedNudge: return 70
        case .workedStep: return 60
        }
    }
}
