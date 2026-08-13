import Foundation

/// One continuous mark, from pen-down to pen-up.
///
/// The canonical record of ink. A `PKDrawing` may be cached beside a collection
/// of these as a rendering optimisation, and may be discarded and rebuilt at
/// any time; this is what gets persisted, synced, diffed, and eventually shown
/// to a tutor.
public struct InkStroke: Entity, Hashable, Sendable, Codable {

    public let id: ElementID

    /// Ordered samples, first to last. Order is the stroke — reversing it
    /// reverses the direction the user drew, which the tutor loop can read.
    public private(set) var points: [InkPoint]

    public var style: InkStyle

    /// Wall-clock time of the stroke's first point. Per-point `timeOffset` is
    /// relative to this.
    public var createdAt: Date

    /// Whether the input device reported real pressure.
    ///
    /// Distinguishes "drawn with a Pencil at constant pressure" from "drawn
    /// with a mouse, which has no pressure", which look identical in the point
    /// data and mean entirely different things to a renderer and to the tutor.
    public var hasPressure: Bool

    /// Whether the input device reported real tilt and azimuth.
    public var hasTilt: Bool

    public var lastModified: Date
    public var owner: OwnerID

    public init(
        id: ElementID = ElementID(),
        points: [InkPoint],
        style: InkStyle,
        createdAt: Date,
        hasPressure: Bool,
        hasTilt: Bool,
        lastModified: Date,
        owner: OwnerID = .localDefault
    ) {
        self.id = id
        self.points = points
        self.style = style
        self.createdAt = createdAt
        self.hasPressure = hasPressure
        self.hasTilt = hasTilt
        self.lastModified = lastModified
        self.owner = owner
    }

    /// Convenience initializer stamping provenance from a time source.
    public init(
        id: ElementID = ElementID(),
        points: [InkPoint],
        style: InkStyle,
        createdAt: Date,
        hasPressure: Bool,
        hasTilt: Bool,
        now timeSource: some TimeSource,
        owner: OwnerID = .localDefault
    ) {
        self.init(
            id: id,
            points: points,
            style: style,
            createdAt: createdAt,
            hasPressure: hasPressure,
            hasTilt: hasTilt,
            lastModified: timeSource.now,
            owner: owner
        )
    }

    // MARK: - Derived geometry

    /// The tightest rectangle containing every sample position.
    ///
    /// Note this is the *path* bounds, not the rendered bounds: a wide stroke
    /// paints outside it by roughly half its width. Use `renderBounds` when the
    /// question is what pixels are affected — for instance when cropping a
    /// region to send to a model, where clipping the edge of the last character
    /// produces confidently wrong readings.
    public var pathBounds: CanvasRect {
        CanvasRect.bounding(points.map(\.position))
    }

    /// Path bounds grown by the widest half-width in the stroke.
    public var renderBounds: CanvasRect {
        guard !points.isEmpty else { return .zero }
        let widest = points.map(\.width).max() ?? style.width
        return pathBounds.expanded(by: Swift.max(widest, style.width) / 2)
    }

    /// Elapsed seconds from the first sample to the last.
    public var duration: TimeInterval {
        guard let first = points.first, let last = points.last else { return 0 }
        return Swift.max(0, last.timeOffset - first.timeOffset)
    }

    /// Wall-clock time of the final sample.
    ///
    /// The stall detector's notion of "when did the user last write something".
    public var endedAt: Date {
        createdAt.addingTimeInterval(duration)
    }

    /// Total distance travelled along the sampled path.
    ///
    /// Straight-line between consecutive samples rather than along the fitted
    /// curve, which understates a tightly curved stroke slightly. Good enough
    /// for its purpose: telling a deliberate mark from an accidental dot.
    public var arcLength: Double {
        guard points.count > 1 else { return 0 }
        var total = 0.0
        for index in 1..<points.count {
            total += points[index - 1].position.distance(to: points[index].position)
        }
        return total
    }

    /// Whether this is a dot rather than a line — a tap, or a stray contact.
    public var isDot: Bool {
        points.count <= 1 || arcLength < style.width
    }

    // MARK: - Transformation

    /// Returns a copy with every point moved and scaled.
    ///
    /// Applied at capture time to bake a platform's stroke transform into the
    /// canonical coordinates, so that stored geometry never depends on a
    /// transform stored elsewhere. A stroke whose points are only correct once
    /// some other field is applied is exactly the kind of implicit coupling
    /// that does not survive a port.
    public func transformed(by transform: CanvasTransform) -> InkStroke {
        guard !transform.isIdentity else { return self }
        var copy = self
        copy.points = points.map { $0.transformed(by: transform) }
        copy.style = style.scaled(by: transform.uniformScale)
        return copy
    }

    /// Replaces the samples, preserving identity and style.
    public mutating func replacePoints(_ newPoints: [InkPoint], modifiedAt: Date) {
        points = newPoints
        lastModified = modifiedAt
    }
}

/// Which optional input channels a stroke's samples actually carry.
public struct InkCapabilities: Hashable, Sendable {
    public var hasPressure: Bool
    public var hasTilt: Bool

    public init(hasPressure: Bool, hasTilt: Bool) {
        self.hasPressure = hasPressure
        self.hasTilt = hasTilt
    }
}

extension InkStroke {

    /// Infers whether a stroke's samples carry real pressure and tilt.
    ///
    /// Capture frameworks generally do not report which input device produced a
    /// stroke — the samples arrive with pressure and tilt fields populated
    /// whether or not the hardware can measure them, filled with a constant
    /// when it cannot. So the signal is variance: a Pencil pressed across a
    /// stroke produces varying force, while a mouse produces the identical
    /// value at every sample.
    ///
    /// This is a heuristic and it has a known false negative: a very short
    /// stroke, or one drawn with unusually even pressure, reads as having none.
    /// That is the right way to be wrong. Treating absent data as present makes
    /// a renderer draw a mouse line with fake pressure taper; treating present
    /// data as absent only loses a subtlety.
    ///
    /// Lives here rather than in a platform adapter so it is one implementation
    /// shared by every platform's capture path, and testable without a device.
    public static func inferredCapabilities(
        from points: [InkPoint],
        tolerance: Double = 1e-6
    ) -> InkCapabilities {
        guard points.count >= 2 else {
            return InkCapabilities(hasPressure: false, hasTilt: false)
        }

        func varies(_ values: [Double]) -> Bool {
            guard let first = values.first else { return false }
            return values.contains { abs($0 - first) > tolerance }
        }

        return InkCapabilities(
            hasPressure: varies(points.map(\.pressure)),
            hasTilt: varies(points.map(\.altitude)) || varies(points.map(\.azimuth))
        )
    }
}
