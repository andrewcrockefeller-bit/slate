import Foundation

/// What kind of work happens inside a region.
///
/// v1 ships one case. The set is closed and string-valued for the same reason
/// `InkKind` is: adding a case must be a compile error at every switch, and
/// must not reinterpret regions already written to disk.
public enum WorkRegionKind: String, Hashable, Sendable, Codable, CaseIterable {
    /// A math or science problem the student works by hand.
    case mathProblem

    /// v1.5 adds `.readingPassage`, `.outlineSection`, and `.draftSection`.
    /// They are named here only in this comment; adding them is a deliberate
    /// change, not a default.

    /// How this kind is referred to in the interface — "Problem 3".
    public var noun: String {
        switch self {
        case .mathProblem: return "Problem"
        }
    }
}

/// How far along a region is.
///
/// Two of these are observed and two are decided. `untouched` and `inProgress`
/// follow from whether there is work inside the region, and the app moves
/// between them on its own. `complete` and `setAside` are judgements — by the
/// student or by the tutor — and once set they stick, because having the app
/// silently un-complete a problem because a stroke was erased would be
/// infuriating and would also destroy the record of what was finished.
public enum WorkRegionState: String, Hashable, Sendable, Codable, CaseIterable {
    /// Nothing has been written inside it yet.
    case untouched

    /// There is work in it, and it has not been declared finished.
    case inProgress

    /// Finished. A judgement, not an observation.
    case complete

    /// Skipped for now, to come back to. Reached after the tutor has given all
    /// the help it is willing to give on one problem.
    case setAside

    /// Whether this state was decided rather than observed.
    public var isDeclared: Bool {
        switch self {
        case .untouched, .inProgress: return false
        case .complete, .setAside: return true
        }
    }
}

/// A bounded area of the canvas that work happens inside.
///
/// This is the thing the prototype did not have and most needed. Without it
/// there is no "problem 7" — no per-problem state, no record of which hints
/// have been given where, no way to crop the right part of the canvas to look
/// at, and no way to summarise a session afterwards. Ink alone is a picture;
/// ink plus regions is a worked problem set.
public struct WorkRegion: Hashable, Sendable, Codable, Identifiable {

    public let id: ElementID
    public var kind: WorkRegionKind
    public var bounds: CanvasRect
    public var state: WorkRegionState

    /// Position in the problem set, 1-based — the "3" in "Problem 3".
    ///
    /// Stored rather than derived from position on the canvas, because reading
    /// order is not something geometry can be trusted to answer. A student who
    /// works down the left column and then the right has an order that no
    /// sort by y-coordinate recovers.
    public var ordinal: Int

    /// The problem as text, when it is known — because the app generated it, or
    /// because it was read off an imported page.
    ///
    /// Optional because a region the student drew around their own work has no
    /// statement the app can know. The tutor behaves differently in that case:
    /// it can still see the work, but it cannot assume it knows the question.
    public var prompt: String?

    public var lastModified: Date
    public var owner: OwnerID

    public init(
        id: ElementID = ElementID(),
        kind: WorkRegionKind = .mathProblem,
        bounds: CanvasRect,
        state: WorkRegionState = .untouched,
        ordinal: Int,
        prompt: String? = nil,
        lastModified: Date,
        owner: OwnerID = .localDefault
    ) {
        self.id = id
        self.kind = kind
        self.bounds = bounds
        self.state = state
        self.ordinal = ordinal
        self.prompt = prompt
        self.lastModified = lastModified
        self.owner = owner
    }

    /// "Problem 3".
    public var label: String {
        "\(kind.noun) \(ordinal)"
    }

    // MARK: - What belongs to this region

    /// Whether the region claims a stroke as work done inside it.
    ///
    /// Assignment is by the centre of the stroke's path bounds, not by overlap.
    /// Handwriting routinely spills past whatever box was drawn around it — a
    /// descender, a long fraction bar, a bracket reaching down the margin — and
    /// an overlap rule would let one stroke belong to two problems at once.
    /// Every stroke belongs to at most one region, and a stroke that strays
    /// outside still counts for the problem it started in.
    public func claims(_ stroke: InkStroke) -> Bool {
        guard !stroke.points.isEmpty else { return false }
        let path = stroke.pathBounds
        let centre = CanvasPoint(
            x: path.minX + path.size.width / 2,
            y: path.minY + path.size.height / 2
        )
        return bounds.contains(centre)
    }

    /// Whether any part of a stroke paints inside the region. Used for
    /// hit-testing and cropping, not for assignment.
    public func intersects(_ stroke: InkStroke) -> Bool {
        bounds.intersects(stroke.renderBounds)
    }

    /// The area to send to a model when asking about this region.
    ///
    /// The region's own bounds grown to include everything it claims, then
    /// padded. Cropping to the drawn box alone would clip the parts of the
    /// student's working that spilled outside it, and a model reading a crop
    /// with the bottom of a fraction missing reads it confidently and wrongly.
    public func captureBounds(
        claiming strokes: [InkStroke],
        padding: Double
    ) -> CanvasRect {
        let covered = strokes
            .filter(claims)
            .reduce(bounds) { $0.union($1.renderBounds) }

        guard !covered.isEmpty else { return bounds }
        return covered.expanded(by: covered.size.width * padding)
    }

    // MARK: - State

    /// The state this region should be in, given whether it contains work.
    ///
    /// Only moves between the two observed states. A declared state —
    /// `complete` or `setAside` — is returned unchanged, because those are
    /// judgements and an erased stroke is not grounds for overruling one.
    public static func observedState(
        from current: WorkRegionState,
        hasWork: Bool
    ) -> WorkRegionState {
        guard !current.isDeclared else { return current }
        return hasWork ? .inProgress : .untouched
    }

    /// Returns a copy in the state its contents imply, or `nil` if it is
    /// already correct.
    ///
    /// Returning `nil` rather than an identical copy so callers can tell
    /// "nothing changed" from "changed to the same value" without comparing —
    /// which is what keeps a stroke inside an already-in-progress region from
    /// writing a pointless operation on every pen-up.
    public func updatingState(hasWork: Bool, at moment: Date) -> WorkRegion? {
        let next = Self.observedState(from: state, hasWork: hasWork)
        guard next != state else { return nil }

        var updated = self
        updated.state = next
        updated.lastModified = moment
        return updated
    }

    /// Returns a copy in a declared state.
    public func declaring(_ declared: WorkRegionState, at moment: Date) -> WorkRegion {
        var updated = self
        updated.state = declared
        updated.lastModified = moment
        return updated
    }
}
