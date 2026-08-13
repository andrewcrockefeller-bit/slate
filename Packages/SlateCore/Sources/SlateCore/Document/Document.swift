import Foundation

/// One canvas.
///
/// The element list is derived state: it is whatever you get by replaying this
/// document's operations in order. Nothing mutates it directly, which is what
/// keeps the operation log authoritative rather than decorative.
public struct Document: Entity, Hashable, Sendable, Codable {

    public let id: DocumentID
    public var title: String
    public let createdAt: Date
    public private(set) var lastModified: Date
    public let owner: OwnerID

    /// Elements in draw order — earlier entries paint first, so later strokes
    /// sit on top. This is document order, not sorted order, and it is
    /// meaningful: reordering it changes what the user sees.
    public private(set) var elements: [CanvasElement]

    /// The sequence number of the last operation applied.
    public private(set) var lastSequence: Int

    public init(
        id: DocumentID = DocumentID(),
        title: String,
        createdAt: Date,
        owner: OwnerID = .localDefault
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.lastModified = createdAt
        self.owner = owner
        self.elements = []
        self.lastSequence = 0
    }

    // MARK: - Lookup

    public func element(_ id: ElementID) -> CanvasElement? {
        elements.first { $0.id == id }
    }

    public func contains(_ id: ElementID) -> Bool {
        elements.contains { $0.id == id }
    }

    /// Every stroke, in draw order.
    public var inkStrokes: [InkStroke] {
        elements.compactMap(\.inkStroke)
    }

    /// Every work region, in the order they were created.
    public var workRegions: [WorkRegion] {
        elements.compactMap(\.workRegion)
    }

    /// The region a stroke belongs to, or `nil` if it was drawn outside them
    /// all.
    ///
    /// First match wins when regions overlap. Overlapping regions are a user
    /// mistake rather than a supported arrangement, and picking deterministically
    /// beats picking cleverly: the same stroke lands in the same problem every
    /// time, which is what makes the session record trustworthy.
    public func region(claiming stroke: InkStroke) -> WorkRegion? {
        workRegions.first { $0.claims(stroke) }
    }

    /// Every stroke a region claims, in draw order.
    public func strokes(in region: WorkRegion) -> [InkStroke] {
        inkStrokes.filter(region.claims)
    }

    /// Whether a region has any work in it.
    public func hasWork(in region: WorkRegion) -> Bool {
        inkStrokes.contains(where: region.claims)
    }

    /// The number the next region created should carry.
    ///
    /// One past the highest in use rather than the count, so that deleting
    /// Problem 2 of three does not produce a second Problem 3.
    public var nextRegionOrdinal: Int {
        (workRegions.map(\.ordinal).max() ?? 0) + 1
    }

    /// Regions whose stored state disagrees with their contents, paired with
    /// the state they should be in.
    ///
    /// Returned rather than applied, because changing a region is an operation
    /// like any other and this type does not get to mutate itself behind the
    /// caller's back. Empty in the common case, which is what keeps a stroke
    /// inside an already-in-progress region from writing an operation on every
    /// pen-up.
    public func regionsNeedingStateUpdate(at moment: Date) -> [WorkRegion] {
        workRegions.compactMap { region in
            region.updatingState(hasWork: hasWork(in: region), at: moment)
        }
    }

    /// The area covered by everything on the canvas, or `.zero` when empty.
    public var contentBounds: CanvasRect {
        elements.reduce(CanvasRect.zero) { $0.union($1.renderBounds) }
    }

    public var isEmpty: Bool { elements.isEmpty }

    // MARK: - Applying operations

    public enum OperationError: Error, Hashable, Sendable, CustomStringConvertible {
        case outOfOrder(expected: Int, got: Int)
        case duplicateElement(ElementID)
        case unknownElement(ElementID)

        public var description: String {
            switch self {
            case .outOfOrder(let expected, let got):
                return "operation sequence \(got) arrived when \(expected) was expected"
            case .duplicateElement(let id):
                return "element \(id) is already in the document"
            case .unknownElement(let id):
                return "element \(id) is not in the document"
            }
        }
    }

    /// Applies one operation, or throws without changing anything.
    ///
    /// Strict about ordering on purpose. A gap in the sequence means an
    /// operation was lost, and replaying the rest anyway produces a document
    /// that looks fine and is quietly wrong — a stroke missing from the middle
    /// of a worked problem, with nothing to indicate it. Failing loudly at the
    /// gap is recoverable; carrying on is not.
    public mutating func apply(_ operation: DocumentOperation) throws {
        let expected = lastSequence + 1
        guard operation.sequence == expected else {
            throw OperationError.outOfOrder(expected: expected, got: operation.sequence)
        }

        switch operation.change {
        case .insert(let element):
            guard !contains(element.id) else {
                throw OperationError.duplicateElement(element.id)
            }
            elements.append(element)

        case .replace(let element):
            guard let index = elements.firstIndex(where: { $0.id == element.id }) else {
                throw OperationError.unknownElement(element.id)
            }
            // Replaced in place rather than removed and appended, so an edit
            // does not silently bring a stroke to the front of the z-order.
            elements[index] = element

        case .remove(let id):
            guard let index = elements.firstIndex(where: { $0.id == id }) else {
                throw OperationError.unknownElement(id)
            }
            elements.remove(at: index)
        }

        lastSequence = operation.sequence
        lastModified = operation.timestamp
    }

    /// Applies operations in order, stopping at the first failure.
    public mutating func apply(_ operations: [DocumentOperation]) throws {
        for operation in operations {
            try apply(operation)
        }
    }

    /// Rebuilds a document from a starting point and a run of operations.
    ///
    /// The starting point is a snapshot: an empty document when replaying from
    /// the beginning, or a compacted one when replaying only the tail. Both
    /// paths go through the same code, so a compacted document cannot drift
    /// from a fully-replayed one.
    public static func replaying(
        _ operations: [DocumentOperation],
        onto snapshot: Document
    ) throws -> Document {
        var document = snapshot
        try document.apply(operations)
        return document
    }

    // MARK: - Building operations

    /// The next operation to append, without applying it.
    ///
    /// Numbering lives here rather than at call sites so that a caller cannot
    /// invent a sequence number and quietly create a gap.
    public func operation(
        _ change: DocumentOperation.Change,
        at moment: Date,
        owner: OwnerID = .localDefault
    ) -> DocumentOperation {
        DocumentOperation(
            sequence: lastSequence + 1,
            timestamp: moment,
            owner: owner,
            change: change
        )
    }

    /// A run of operations that appends the given strokes, numbered
    /// consecutively from this document's current position.
    public func operationsInserting(
        _ strokes: [InkStroke],
        at moment: Date,
        owner: OwnerID = .localDefault
    ) -> [DocumentOperation] {
        strokes.enumerated().map { offset, stroke in
            DocumentOperation(
                sequence: lastSequence + 1 + offset,
                timestamp: moment,
                owner: owner,
                change: .insert(.ink(stroke))
            )
        }
    }

    /// Renames the document.
    public mutating func rename(to newTitle: String, at moment: Date) {
        title = newTitle
        lastModified = moment
    }
}

/// Enough of a document to list it without loading its contents.
///
/// The document browser reads these; opening a canvas is what reads the
/// operations. Loading every stroke of every document to draw a list of names
/// is the kind of thing that is fine with three documents and unusable with
/// three hundred.
public struct DocumentSummary: Hashable, Sendable, Codable, Identifiable {
    public let id: DocumentID
    public let title: String
    public let createdAt: Date
    public let lastModified: Date
    public let owner: OwnerID
    public let elementCount: Int

    public init(
        id: DocumentID,
        title: String,
        createdAt: Date,
        lastModified: Date,
        owner: OwnerID,
        elementCount: Int
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.lastModified = lastModified
        self.owner = owner
        self.elementCount = elementCount
    }

    public init(_ document: Document) {
        self.init(
            id: document.id,
            title: document.title,
            createdAt: document.createdAt,
            lastModified: document.lastModified,
            owner: document.owner,
            elementCount: document.elements.count
        )
    }
}
