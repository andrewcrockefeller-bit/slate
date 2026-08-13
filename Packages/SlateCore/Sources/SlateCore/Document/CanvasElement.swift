import Foundation

/// Anything that can sit on a canvas.
///
/// Work regions are elements rather than a separate collection with their own
/// operations. They have identity, bounds, and a lifetime on the canvas, so
/// modelling them as elements means every piece of already-tested operation
/// machinery — insert, replace, remove, ordering, replay, persistence — applies
/// to them for free, and the operation log has one address space instead of two.
///
/// v1.5 adds text blocks, source documents, and outline nodes. Adding a case is
/// a compile error at every switch, which is the loud kind of change.
/// Retrofitting polymorphism onto a stored array of strokes would be a
/// migration against files on someone's iPad, which is the expensive kind.
public enum CanvasElement: Hashable, Sendable {
    case ink(InkStroke)
    case workRegion(WorkRegion)

    /// Identity, stable across edits and devices.
    public var id: ElementID {
        switch self {
        case .ink(let stroke): return stroke.id
        case .workRegion(let region): return region.id
        }
    }

    public var lastModified: Date {
        switch self {
        case .ink(let stroke): return stroke.lastModified
        case .workRegion(let region): return region.lastModified
        }
    }

    public var owner: OwnerID {
        switch self {
        case .ink(let stroke): return stroke.owner
        case .workRegion(let region): return region.owner
        }
    }

    /// The area this element occupies, for culling and for cropping a region to
    /// send to a model.
    public var renderBounds: CanvasRect {
        switch self {
        case .ink(let stroke): return stroke.renderBounds
        case .workRegion(let region): return region.bounds
        }
    }

    /// The stroke, if this is one.
    public var inkStroke: InkStroke? {
        switch self {
        case .ink(let stroke): return stroke
        case .workRegion: return nil
        }
    }

    /// The region, if this is one.
    public var workRegion: WorkRegion? {
        switch self {
        case .ink: return nil
        case .workRegion(let region): return region
        }
    }

    /// Whether this element is ink the student drew, as opposed to structure
    /// laid over it.
    public var isInk: Bool { inkStroke != nil }
}

// MARK: - Wire format

extension CanvasElement: Codable {

    /// The discriminator written into every encoded element.
    ///
    /// String-valued and explicit so that adding a kind, or reordering the
    /// enum, cannot silently reinterpret elements already on disk.
    private enum Kind: String, Codable {
        case ink
        case workRegion
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        switch try container.decode(Kind.self, forKey: .kind) {
        case .ink:
            self = .ink(try container.decode(InkStroke.self, forKey: .value))
        case .workRegion:
            self = .workRegion(try container.decode(WorkRegion.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .ink(let stroke):
            try container.encode(Kind.ink, forKey: .kind)
            try container.encode(stroke, forKey: .value)
        case .workRegion(let region):
            try container.encode(Kind.workRegion, forKey: .kind)
            try container.encode(region, forKey: .value)
        }
    }
}
