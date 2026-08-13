import Foundation
import SlateCore

/// Documents on disk.
///
/// Layout, one directory per document:
///
///     <root>/<document-id>/snapshot.json      a Document at some sequence
///     <root>/<document-id>/operations.jsonl   operations after that snapshot
///
/// Snapshot plus tail rather than one file, because the operation log is the
/// record and rewriting the whole document on every stroke would be both slow
/// and a lie about what changed. Appending a line is O(1) and is exactly the
/// payload a sync engine would later forward to another device.
///
/// The log is JSON Lines rather than a JSON array on purpose: an array has to
/// be rewritten to add an element, while a line can be appended to a file
/// opened at its end. It also degrades well — a truncated final line loses one
/// operation instead of making the whole file unparseable.
public actor FileDocumentRepository: DocumentRepository {

    /// Knobs that affect how the store behaves on disk.
    public struct Options: Hashable, Sendable {

        /// Operations in the tail log before it is folded into a new snapshot.
        ///
        /// Lower means smaller logs and slower writes; higher means faster
        /// writes and a longer replay on open. 500 strokes is a dense page of
        /// working, so a document opens after replaying at most about one page
        /// of history.
        public var compactAfterOperations: Int

        /// Whether written JSON is indented.
        ///
        /// On by default. This is a user's homework, in a format nobody else
        /// will ever read; being able to open the file and see what went wrong
        /// is worth more than the bytes. Turn it off if documents get large.
        public var prettyPrinted: Bool

        public init(compactAfterOperations: Int = 500, prettyPrinted: Bool = true) {
            self.compactAfterOperations = compactAfterOperations
            self.prettyPrinted = prettyPrinted
        }

        public static let `default` = Options()
    }

    private let root: URL
    private let options: Options
    private let timeSource: any TimeSource
    private let fileManager = FileManager.default

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Documents already read this session, so repeated opens do not replay.
    private var cache: [DocumentID: Document] = [:]

    public init(
        root: URL,
        timeSource: any TimeSource,
        options: Options = .default
    ) {
        self.root = root
        self.timeSource = timeSource
        self.options = options

        let encoder = JSONEncoder()
        // ISO 8601 rather than the default seconds-since-2001 double. A
        // timestamp another platform has to read should not require knowing
        // that Apple's epoch is not the Unix one.
        encoder.dateEncodingStrategy = .iso8601
        if options.prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        } else {
            encoder.outputFormatting = [.sortedKeys]
        }
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    // MARK: - Paths

    private func directory(for id: DocumentID) -> URL {
        root.appendingPathComponent(id.rawValue.uuidString, isDirectory: true)
    }

    private func snapshotURL(for id: DocumentID) -> URL {
        directory(for: id).appendingPathComponent("snapshot.json")
    }

    private func logURL(for id: DocumentID) -> URL {
        directory(for: id).appendingPathComponent("operations.jsonl")
    }

    // MARK: - DocumentRepository

    public func summaries() throws -> [DocumentSummary] {
        try ensureRoot()

        let entries = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        )) ?? []

        var result: [DocumentSummary] = []

        for entry in entries {
            guard let uuid = UUID(uuidString: entry.lastPathComponent) else { continue }
            let id = DocumentID(rawValue: uuid)

            // A directory that fails to load is skipped rather than failing the
            // whole listing. One corrupt document should not make the browser
            // unopenable — the user still needs to reach everything else.
            guard let document = try? document(id) else { continue }
            result.append(DocumentSummary(document))
        }

        return result.sorted { $0.lastModified > $1.lastModified }
    }

    public func document(_ id: DocumentID) throws -> Document {
        if let cached = cache[id] { return cached }

        let snapshotPath = snapshotURL(for: id)
        guard fileManager.fileExists(atPath: snapshotPath.path) else {
            throw DocumentRepositoryError.notFound(id)
        }

        let snapshot: Document
        do {
            snapshot = try decoder.decode(Document.self, from: Data(contentsOf: snapshotPath))
        } catch {
            throw DocumentRepositoryError.unreadable(id, reason: "snapshot: \(error)")
        }

        let operations = try readLog(for: id)

        do {
            let document = try Document.replaying(operations, onto: snapshot)
            cache[id] = document
            return document
        } catch {
            throw DocumentRepositoryError.unreadable(id, reason: "replay: \(error)")
        }
    }

    public func createDocument(title: String) throws -> Document {
        try ensureRoot()

        let document = Document(title: title, createdAt: timeSource.now)
        let directory = directory(for: document.id)

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw DocumentRepositoryError.notWritable(reason: "\(error)")
        }

        try writeSnapshot(document)
        try writeLog([], for: document.id)

        cache[document.id] = document
        return document
    }

    @discardableResult
    public func append(
        _ operations: [DocumentOperation],
        to id: DocumentID
    ) throws -> Document {
        guard !operations.isEmpty else { return try document(id) }

        var current = try document(id)

        // Validated against the in-memory document before anything touches the
        // disk. A rejected run must leave the stored log exactly as it was;
        // half-writing an invalid run is how a document becomes unopenable.
        do {
            try current.apply(operations)
        } catch {
            throw DocumentRepositoryError.rejected(id, reason: "\(error)")
        }

        let existing = try readLog(for: id)

        if existing.count + operations.count >= options.compactAfterOperations {
            // Fold everything into a new snapshot and start the log again.
            try writeSnapshot(current)
            try writeLog([], for: id)
        } else {
            try appendToLog(operations, for: id)
        }

        cache[id] = current
        return current
    }

    public func rename(_ id: DocumentID, to title: String) throws {
        var document = try document(id)
        document.rename(to: title, at: timeSource.now)

        // A title is document metadata rather than canvas content, so it lives
        // in the snapshot and is not an operation. When multi-device editing
        // arrives this becomes a rename operation like any other; it is called
        // out here so that gap is deliberate rather than forgotten.
        try writeSnapshot(document)
        cache[id] = document
    }

    public func deleteDocument(_ id: DocumentID) throws {
        let directory = directory(for: id)
        guard fileManager.fileExists(atPath: directory.path) else {
            throw DocumentRepositoryError.notFound(id)
        }

        do {
            try fileManager.removeItem(at: directory)
        } catch {
            throw DocumentRepositoryError.notWritable(reason: "\(error)")
        }

        cache[id] = nil
    }

    // MARK: - Storage

    private func ensureRoot() throws {
        guard !fileManager.fileExists(atPath: root.path) else { return }
        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            throw DocumentRepositoryError.notWritable(reason: "\(error)")
        }
    }

    private func writeSnapshot(_ document: Document) throws {
        do {
            let data = try encoder.encode(document)
            // .atomic writes to a temporary file and renames. Without it, a
            // crash mid-write leaves a half-written snapshot, which is the one
            // file that cannot be recovered from the log.
            try data.write(to: snapshotURL(for: document.id), options: .atomic)
        } catch {
            throw DocumentRepositoryError.notWritable(reason: "snapshot: \(error)")
        }
    }

    private func readLog(for id: DocumentID) throws -> [DocumentOperation] {
        let url = logURL(for: id)
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [] }

        var operations: [DocumentOperation] = []

        for line in data.split(separator: UInt8(ascii: "\n")) where !line.isEmpty {
            do {
                operations.append(try decoder.decode(DocumentOperation.self, from: Data(line)))
            } catch {
                // A trailing partial line means the process died mid-append.
                // Everything before it is intact and replays cleanly, so the
                // document opens missing the very last stroke rather than not
                // opening at all. Anything else is real corruption.
                if line == data.split(separator: UInt8(ascii: "\n")).last {
                    break
                }
                throw DocumentRepositoryError.unreadable(id, reason: "log: \(error)")
            }
        }

        return operations
    }

    private func writeLog(_ operations: [DocumentOperation], for id: DocumentID) throws {
        do {
            let data = try encodeLines(operations)
            try data.write(to: logURL(for: id), options: .atomic)
        } catch let error as DocumentRepositoryError {
            throw error
        } catch {
            throw DocumentRepositoryError.notWritable(reason: "log: \(error)")
        }
    }

    private func appendToLog(_ operations: [DocumentOperation], for id: DocumentID) throws {
        let url = logURL(for: id)
        let data = try encodeLines(operations)

        guard let handle = try? FileHandle(forWritingTo: url) else {
            // No log file yet — writing it whole is equivalent and correct.
            try writeLog(operations, for: id)
            return
        }

        defer { try? handle.close() }

        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            throw DocumentRepositoryError.notWritable(reason: "log append: \(error)")
        }
    }

    private func encodeLines(_ operations: [DocumentOperation]) throws -> Data {
        var data = Data()

        // One operation per line, so the encoder must not pretty-print here
        // even when snapshots are indented — an embedded newline would split
        // one operation across several lines and break the format.
        let lineEncoder = JSONEncoder()
        lineEncoder.dateEncodingStrategy = .iso8601
        lineEncoder.outputFormatting = [.sortedKeys]

        for operation in operations {
            do {
                data.append(try lineEncoder.encode(operation))
                data.append(UInt8(ascii: "\n"))
            } catch {
                throw DocumentRepositoryError.notWritable(reason: "encode: \(error)")
            }
        }

        return data
    }
}
