import Foundation

/// A stable, globally unique identifier for a domain object.
///
/// Every persisted object in Slate carries one from the moment it is created,
/// including in v1 where there is no server and no sync. Retrofitting identity
/// onto user data that already exists on devices is a migration nobody wants to
/// write, so identity is free here and expensive later.
///
/// Distinct concrete types (rather than raw `UUID` everywhere) make it a
/// compile error to hand a document's identifier to something expecting an
/// element's.
public protocol UniqueIdentifier: Hashable, Sendable, Codable, CustomStringConvertible {
    var rawValue: UUID { get }
    init(rawValue: UUID)
}

extension UniqueIdentifier {
    /// Mints a fresh identifier.
    public init() {
        self.init(rawValue: UUID())
    }

    public var description: String {
        rawValue.uuidString
    }

    // MARK: - Wire format

    // Identifiers encode as a bare string — "8B1F…" — rather than as the
    // object `{"rawValue": "8B1F…"}` that Codable would synthesise.
    //
    // Settled at M2, deliberately, because M2 is the milestone that first
    // writes a document to disk. Before that this is a free choice; afterwards
    // it is a migration against files sitting on someone's iPad. A document
    // holds an identifier for every element and every operation, so the
    // wrapper costs about fifteen bytes per occurrence for nothing, and a
    // format people have to read while debugging is worth keeping legible.
    //
    // These are helpers rather than the `Codable` witnesses themselves.
    // Providing `init(from:)` directly in a protocol extension competes with
    // the compiler's own synthesis for conforming types, which is a subtle
    // way to end up with a format nobody chose. Each concrete type wires
    // these up explicitly in two lines.

    public static func decodeRawValue(from decoder: Decoder) throws -> UUID {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)

        guard let uuid = UUID(uuidString: string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "'\(string)' is not a valid UUID"
            )
        }

        return uuid
    }

    public func encodeRawValue(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue.uuidString)
    }
}

/// Identifies a document — one canvas, one file, one thing in the document list.
public struct DocumentID: UniqueIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try Self.decodeRawValue(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        try encodeRawValue(to: encoder)
    }
}

/// Identifies a single element on a canvas.
///
/// v1 elements are stroke groups, images, and hints. v1.5 adds text blocks,
/// source documents, and outline nodes. The identifier type does not change
/// when the set of element kinds grows.
public struct ElementID: UniqueIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try Self.decodeRawValue(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        try encodeRawValue(to: encoder)
    }
}

/// Identifies a single mutation of a document.
///
/// Distinct from the sequence number: the sequence gives an operation its place
/// in one document's order, while this identifies the operation itself. Once
/// two devices can both append, sequence numbers collide and identity is what
/// tells a genuine duplicate from two different edits that happened to land in
/// the same slot.
public struct OperationID: UniqueIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try Self.decodeRawValue(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        try encodeRawValue(to: encoder)
    }
}

/// Identifies a bounded area of a canvas that work happens inside — in v1 a
/// math problem, later a reading passage, outline section, or draft section.
public struct WorkRegionID: UniqueIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try Self.decodeRawValue(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        try encodeRawValue(to: encoder)
    }
}

/// Identifies the owner of a piece of data.
///
/// v1 has no accounts and every object in the app carries the same value, from
/// `OwnerID.localDefault`. It is threaded through anyway: the alternative is a
/// schema migration on the day accounts arrive, against data sitting on real
/// devices. Nothing may assume a single implicit local user forever.
public struct OwnerID: UniqueIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try Self.decodeRawValue(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        try encodeRawValue(to: encoder)
    }

    /// The single owner used throughout v1, before accounts exist.
    ///
    /// Fixed rather than random so that data created across app launches on one
    /// device shares an owner, which is what makes this value useful at all.
    public static let localDefault = OwnerID(
        rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    )
}
