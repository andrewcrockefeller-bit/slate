import Foundation

/// How the app reads and writes documents.
///
/// Invariant 4's central seam. No feature ever touches a file, a database, or a
/// network call directly; everything goes through here. The local
/// implementation in v1 writes to disk. A later one talks to a server. Adding
/// it means writing one adapter and changing one line of wiring, and no call
/// site moves.
///
/// Deliberately `async` even though the v1 implementation could be synchronous.
/// Retrofitting `async` onto a synchronous protocol means touching every caller
/// — which is exactly the "restructuring" a cloud-ready design is supposed to
/// avoid. The cost of an await against a local file is nothing.
public protocol DocumentRepository: Sendable {

    /// Every document, most recently modified first.
    func summaries() async throws -> [DocumentSummary]

    /// The full document, with all operations replayed.
    func document(_ id: DocumentID) async throws -> Document

    /// Creates and persists an empty document.
    func createDocument(title: String) async throws -> Document

    /// Appends operations to a document's log and returns the resulting state.
    ///
    /// Append rather than save-the-whole-thing. A remote implementation can
    /// forward exactly these operations to other devices; a "save this blob"
    /// interface would have nothing useful to send.
    @discardableResult
    func append(
        _ operations: [DocumentOperation],
        to id: DocumentID
    ) async throws -> Document

    func rename(_ id: DocumentID, to title: String) async throws

    func deleteDocument(_ id: DocumentID) async throws
}

/// What can go wrong, in terms the domain understands.
///
/// Storage-specific failures — a permissions error, a corrupt file, an HTTP
/// status — are translated into these by the adapter. Layer 1 must not know
/// what a file path or a status code is, and a feature deciding what to show
/// the user should not be switching on someone else's error taxonomy.
public enum DocumentRepositoryError: Error, Hashable, Sendable, CustomStringConvertible {
    case notFound(DocumentID)
    case unreadable(DocumentID, reason: String)
    case notWritable(reason: String)
    case rejected(DocumentID, reason: String)

    public var description: String {
        switch self {
        case .notFound(let id):
            return "no document with id \(id)"
        case .unreadable(let id, let reason):
            return "document \(id) could not be read: \(reason)"
        case .notWritable(let reason):
            return "storage is not writable: \(reason)"
        case .rejected(let id, let reason):
            return "change to document \(id) was rejected: \(reason)"
        }
    }
}

/// An in-memory repository, for tests and previews.
///
/// Lives in Layer 1 because it depends on nothing outside it, which means the
/// domain's own tests can exercise anything built on the protocol without a
/// filesystem. It is also the reference implementation: if behaviour here and
/// in the file-backed adapter ever disagree, one of them is wrong, and this one
/// is easier to read.
public actor InMemoryDocumentRepository: DocumentRepository {

    private var documents: [DocumentID: Document] = [:]
    private var operations: [DocumentID: [DocumentOperation]] = [:]
    private let timeSource: any TimeSource

    public init(timeSource: any TimeSource) {
        self.timeSource = timeSource
    }

    public func summaries() async throws -> [DocumentSummary] {
        documents.values
            .map(DocumentSummary.init)
            .sorted { $0.lastModified > $1.lastModified }
    }

    public func document(_ id: DocumentID) async throws -> Document {
        guard let document = documents[id] else {
            throw DocumentRepositoryError.notFound(id)
        }
        return document
    }

    public func createDocument(title: String) async throws -> Document {
        let document = Document(title: title, createdAt: timeSource.now)
        documents[document.id] = document
        operations[document.id] = []
        return document
    }

    @discardableResult
    public func append(
        _ newOperations: [DocumentOperation],
        to id: DocumentID
    ) async throws -> Document {
        guard var document = documents[id] else {
            throw DocumentRepositoryError.notFound(id)
        }

        do {
            try document.apply(newOperations)
        } catch {
            throw DocumentRepositoryError.rejected(id, reason: "\(error)")
        }

        documents[id] = document
        operations[id, default: []].append(contentsOf: newOperations)
        return document
    }

    public func rename(_ id: DocumentID, to title: String) async throws {
        guard var document = documents[id] else {
            throw DocumentRepositoryError.notFound(id)
        }
        document.rename(to: title, at: timeSource.now)
        documents[id] = document
    }

    public func deleteDocument(_ id: DocumentID) async throws {
        guard documents.removeValue(forKey: id) != nil else {
            throw DocumentRepositoryError.notFound(id)
        }
        operations[id] = nil
    }

    /// The recorded operation log, for tests that care that operations were
    /// stored rather than just that state ended up right.
    public func operationLog(for id: DocumentID) -> [DocumentOperation] {
        operations[id] ?? []
    }
}
