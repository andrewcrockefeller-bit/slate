import Foundation

/// The three things every persisted domain object carries, from v1 onward.
///
/// - `id`          stable across edits, devices, and future sync
/// - `lastModified` the basis of any future conflict resolution
/// - `owner`       always `OwnerID.localDefault` in v1, not always
///
/// This exists at M0, before there is anything to persist, because the cost of
/// conforming a new type is one line and the cost of adding these fields to
/// types that already have user data on disk is a migration.
/// Deliberately does NOT refine `Identifiable`.
///
/// `Identifiable` exists for SwiftUI's benefit — it is how a `List` tells rows
/// apart — and on Apple platforms it carries an availability annotation, which
/// would leak a deployment-target constraint into the domain core for a
/// protocol the domain has no use for. Any concrete type conforming to `Entity`
/// already satisfies `Identifiable`'s only requirement, so Layer 3 can add
/// `extension Document: Identifiable {}` for free where it actually needs it.
public protocol Entity: Sendable {
    associatedtype ID: UniqueIdentifier

    var id: ID { get }
    var lastModified: Date { get }
    var owner: OwnerID { get }
}

/// A stamp recording who last changed something and when.
///
/// Bundled as one value so that "touch this object" is a single assignment and
/// cannot half-happen — updating `lastModified` while forgetting `owner` is
/// exactly the kind of bug that only shows up once sync exists.
public struct Provenance: Hashable, Sendable, Codable {
    public var lastModified: Date
    public var owner: OwnerID

    public init(lastModified: Date, owner: OwnerID = .localDefault) {
        self.lastModified = lastModified
        self.owner = owner
    }

    /// Stamps the current moment from an injected time source.
    ///
    /// Takes a `TimeSource` rather than calling `Date()` so that domain logic
    /// stays deterministic under test. Layer 1 never reads the wall clock
    /// directly.
    public init(now timeSource: some TimeSource, owner: OwnerID = .localDefault) {
        self.lastModified = timeSource.now
        self.owner = owner
    }

    /// Returns a copy stamped at the given moment, preserving the owner.
    public func touched(at moment: Date) -> Provenance {
        Provenance(lastModified: moment, owner: owner)
    }

    /// Returns a copy stamped from the given time source, preserving the owner.
    public func touched(by timeSource: some TimeSource) -> Provenance {
        touched(at: timeSource.now)
    }
}
