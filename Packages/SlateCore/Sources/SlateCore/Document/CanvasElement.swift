import Foundation

/// Anything that can sit on a canvas.
///
/// v1 carries one case. It exists as a closed set anyway because the document
/// format has to survive the arrival of the others: text blocks and outline
/// nodes in v1.5, imported source documents, tutor hints. Adding a case to an
/// enum is a compile error at every switch, which is the loud kind of change.
/// Retrofitting polymorphism onto a stored array of strokes is a migration
/// against files on someone's iPad, which is the expensive kind.
public enum CanvasElement: Hashable, Sendable {
    case ink(InkStroke)

    /// Identity, stable across edits and devices.
    public var id: ElementID {
        switch self {
        case .ink(let stroke): return stroke.id
        }
    }

    public var lastModified: Date {
        switch self {
        case .ink(let stroke): return stroke.lastModified
        }
    }

    public var owner: OwnerID {
        switch self {
        case .ink(let stroke): return stroke.owner
        }
    }

    /// The area this element paints, for culling and for cropping a region to
    /// send to a model.
    public var renderBounds: CanvasRect {
        switch self {
        case .ink(let stroke): return stroke.renderBounds
        }
    }

    /// The stroke, if this is one.
    public var inkStroke: InkStroke? {
        switch self {
        case .ink(let stroke): return stroke
        }
    }
}

// MARK: - Wire format

extension CanvasElement: Codable {

    /// The discriminator written into every encoded element.
    ///
    /// String-valued and explicit so that adding a kind, or reordering the
    /// enum, cannot silently reinterpret elements already on disk.
    private enum Kind: String, Codable {
        case ink
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)

        switch kind {
        case .ink:
            self = .ink(try container.decode(InkStroke.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .ink(let stroke):
            try container.encode(Kind.ink, forKey: .kind)
            try container.encode(stroke, forKey: .value)
        }
    }
}
