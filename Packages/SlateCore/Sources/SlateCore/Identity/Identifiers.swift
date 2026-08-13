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
}

/// Identifies a document — one canvas, one file, one thing in the document list.
public struct DocumentID: UniqueIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

/// Identifies a single element on a canvas.
///
/// v1 elements are stroke groups, images, and hints. v1.5 adds text blocks,
/// source documents, and outline nodes. The identifier type does not change
/// when the set of element kinds grows.
public struct ElementID: UniqueIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

/// Identifies a bounded area of a canvas that work happens inside — in v1 a
/// math problem, later a reading passage, outline section, or draft section.
public struct WorkRegionID: UniqueIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
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

    /// The single owner used throughout v1, before accounts exist.
    ///
    /// Fixed rather than random so that data created across app launches on one
    /// device shares an owner, which is what makes this value useful at all.
    public static let localDefault = OwnerID(
        rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    )
}
