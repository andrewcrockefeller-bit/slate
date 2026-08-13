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
public protocol Entity: Identifiable, Sendable {
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
