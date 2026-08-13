import Foundation

/// One discrete, ordered, serializable change to a document.
///
/// This type is Invariant 4 made concrete. A document is never mutated as a
/// blob and re-saved; it is changed by appending operations, and its current
/// state is what you get by replaying them. That distinction costs almost
/// nothing today and is the difference between adding real-time sync later and
/// rewriting the persistence layer to get it.
///
/// What it buys, concretely:
///   - Undo is replay to an earlier point rather than a snapshot stack.
///   - Two devices editing the same document produce two operation streams that
///     can be merged, instead of two whole files where one has to win.
///   - "What did the student do, in what order" is already recorded, which the
///     tutor loop wants anyway.
public struct DocumentOperation: Hashable, Sendable, Codable {

    /// What the operation does.
    public enum Change: Hashable, Sendable {
        /// Add an element that is not already present.
        case insert(CanvasElement)

        /// Replace an existing element, keeping its identity.
        case replace(CanvasElement)

        /// Remove an element.
        case remove(ElementID)

        /// The element this change concerns.
        public var elementID: ElementID {
            switch self {
            case .insert(let element), .replace(let element): return element.id
            case .remove(let id): return id
            }
        }
    }

    /// Identity of the operation itself, distinct from its position.
    public let id: OperationID

    /// Position in this document's order, starting at 1.
    ///
    /// Monotonic and gapless within a single document. A remote-backed
    /// repository will eventually need to reconcile two devices that both
    /// claimed the same number; that is exactly the conflict this design keeps
    /// tractable, and where a real CRDT would go. Noted as deferred rather than
    /// pretended away.
    public let sequence: Int

    /// When the change happened, from an injected time source.
    public let timestamp: Date

    /// Who made it. Always `OwnerID.localDefault` in v1.
    public let owner: OwnerID

    public let change: Change

    public init(
        id: OperationID = OperationID(),
        sequence: Int,
        timestamp: Date,
        owner: OwnerID = .localDefault,
        change: Change
    ) {
        self.id = id
        self.sequence = sequence
        self.timestamp = timestamp
        self.owner = owner
        self.change = change
    }

    /// The element this operation concerns.
    public var elementID: ElementID { change.elementID }
}

// MARK: - Wire format

extension DocumentOperation.Change: Codable {

    private enum Kind: String, Codable {
        case insert
        case replace
        case remove
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case element
        case elementID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        switch try container.decode(Kind.self, forKey: .kind) {
        case .insert:
            self = .insert(try container.decode(CanvasElement.self, forKey: .element))
        case .replace:
            self = .replace(try container.decode(CanvasElement.self, forKey: .element))
        case .remove:
            self = .remove(try container.decode(ElementID.self, forKey: .elementID))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .insert(let element):
            try container.encode(Kind.insert, forKey: .kind)
            try container.encode(element, forKey: .element)
        case .replace(let element):
            try container.encode(Kind.replace, forKey: .kind)
            try container.encode(element, forKey: .element)
        case .remove(let id):
            try container.encode(Kind.remove, forKey: .kind)
            try container.encode(id, forKey: .elementID)
        }
    }
}
