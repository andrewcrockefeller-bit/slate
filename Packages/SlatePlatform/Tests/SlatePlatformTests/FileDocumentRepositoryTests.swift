import XCTest
import SlateCore
@testable import SlatePlatform

final class FileDocumentRepositoryTests: XCTestCase {

    private var root: URL!
    private let t0 = FixedTimeSource.reference.now

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("slate-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// A repository pointed at the same directory but sharing no memory.
    ///
    /// Every persistence test reloads through a fresh instance on purpose: the
    /// in-process cache would happily answer from memory and prove nothing
    /// about what actually reached the disk.
    private func makeRepository(compactAfter: Int = 500) -> FileDocumentRepository {
        FileDocumentRepository(
            root: root,
            timeSource: FixedTimeSource.reference,
            options: .init(compactAfterOperations: compactAfter)
        )
    }

    private func stroke(at x: Double) -> InkStroke {
        InkStroke(
            points: [
                InkPoint(position: CanvasPoint(x: x, y: 0), timeOffset: 0,
                         pressure: 0.4, azimuth: 0, altitude: .pi / 2, width: 4),
                InkPoint(position: CanvasPoint(x: x + 8, y: 3), timeOffset: 0.04,
                         pressure: 0.7, azimuth: 0.2, altitude: 1.1, width: 5)
            ],
            style: InkStyle(kind: .pen, color: .black, width: 4),
            createdAt: t0,
            hasPressure: true,
            hasTilt: true,
            lastModified: t0
        )
    }

    // MARK: - The acceptance test, in miniature

    func testDocumentSurvivesAFreshRepository() async throws {
        let created = try await makeRepository().createDocument(title: "Calc")
        _ = try await makeRepository().append(
            created.operationsInserting([stroke(at: 0), stroke(at: 40)], at: t0),
            to: created.id
        )

        let reloaded = try await makeRepository().document(created.id)

        XCTAssertEqual(reloaded.id, created.id)
        XCTAssertEqual(reloaded.title, "Calc")
        XCTAssertEqual(reloaded.elements.count, 2)
        XCTAssertEqual(reloaded.lastSequence, 2)
    }

    func testStrokeGeometrySurvivesTheRoundTripToDisk() async throws {
        let repo = makeRepository()
        let document = try await repo.createDocument(title: "Untitled")
        let original = stroke(at: 12.5)
        _ = try await repo.append(
            document.operationsInserting([original], at: t0),
            to: document.id
        )

        let reloaded = try await makeRepository().document(document.id)
        let restored = try XCTUnwrap(reloaded.inkStrokes.first)

        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.points.count, original.points.count)
        for (a, b) in zip(restored.points, original.points) {
            XCTAssertEqual(a.position.x, b.position.x, accuracy: 1e-9)
            XCTAssertEqual(a.pressure, b.pressure, accuracy: 1e-9)
            XCTAssertEqual(a.altitude, b.altitude, accuracy: 1e-9)
            XCTAssertEqual(a.timeOffset, b.timeOffset, accuracy: 1e-9)
        }
        XCTAssertEqual(restored.hasPressure, original.hasPressure)
        XCTAssertEqual(restored.hasTilt, original.hasTilt)
    }

    func testAppendsAccumulateAcrossSessions() async throws {
        let created = try await makeRepository().createDocument(title: "Untitled")

        for index in 0..<5 {
            let repo = makeRepository()
            let current = try await repo.document(created.id)
            _ = try await repo.append(
                current.operationsInserting([stroke(at: Double(index) * 20)], at: t0),
                to: created.id
            )
        }

        let reloaded = try await makeRepository().document(created.id)
        XCTAssertEqual(reloaded.elements.count, 5)
        XCTAssertEqual(reloaded.lastSequence, 5)
    }

    // MARK: - Storage shape

    func testOperationsAreWrittenAsOneLineEach() async throws {
        let repo = makeRepository()
        let document = try await repo.createDocument(title: "Untitled")
        _ = try await repo.append(
            document.operationsInserting([stroke(at: 0), stroke(at: 10), stroke(at: 20)], at: t0),
            to: document.id
        )

        let log = root
            .appendingPathComponent(document.id.rawValue.uuidString)
            .appendingPathComponent("operations.jsonl")
        let text = try String(contentsOf: log, encoding: .utf8)
        let lines = text.split(separator: "\n").filter { !$0.isEmpty }

        XCTAssertEqual(lines.count, 3)
    }

    // Compaction folds the log into the snapshot. The state afterwards must be
    // identical — if it is not, opening a long document shows something other
    // than what the user drew.
    func testCompactionPreservesStateExactly() async throws {
        let repo = makeRepository(compactAfter: 4)
        let document = try await repo.createDocument(title: "Untitled")

        var current = document
        for index in 0..<9 {
            current = try await repo.append(
                current.operationsInserting([stroke(at: Double(index) * 11)], at: t0),
                to: document.id
            )
        }

        let reloaded = try await makeRepository().document(document.id)

        XCTAssertEqual(reloaded.elements.map(\.id), current.elements.map(\.id))
        XCTAssertEqual(reloaded.lastSequence, current.lastSequence)
        XCTAssertEqual(reloaded.elements.count, 9)
    }

    func testCompactionShrinksTheLog() async throws {
        let repo = makeRepository(compactAfter: 3)
        let document = try await repo.createDocument(title: "Untitled")

        var current = document
        for index in 0..<6 {
            current = try await repo.append(
                current.operationsInserting([stroke(at: Double(index))], at: t0),
                to: document.id
            )
        }

        let log = root
            .appendingPathComponent(document.id.rawValue.uuidString)
            .appendingPathComponent("operations.jsonl")
        let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        let lines = text.split(separator: "\n").filter { !$0.isEmpty }

        XCTAssertLessThan(lines.count, 6)
    }

    // MARK: - Failure behaviour

    func testUnknownDocumentThrowsNotFound() async {
        let id = DocumentID()
        do {
            _ = try await makeRepository().document(id)
            XCTFail("expected notFound")
        } catch {
            XCTAssertEqual(error as? DocumentRepositoryError, .notFound(id))
        }
    }

    // A rejected run must leave the stored log exactly as it was. Half-writing
    // an invalid run is how a document becomes unopenable.
    func testRejectedOperationsDoNotReachDisk() async throws {
        let repo = makeRepository()
        let document = try await repo.createDocument(title: "Untitled")
        _ = try await repo.append(
            document.operationsInserting([stroke(at: 0)], at: t0),
            to: document.id
        )

        let gap = DocumentOperation(sequence: 99, timestamp: t0, change: .insert(.ink(stroke(at: 5))))

        do {
            _ = try await repo.append([gap], to: document.id)
            XCTFail("expected rejection")
        } catch {
            guard case DocumentRepositoryError.rejected = error else {
                return XCTFail("expected .rejected, got \(error)")
            }
        }

        let reloaded = try await makeRepository().document(document.id)
        XCTAssertEqual(reloaded.elements.count, 1)
        XCTAssertEqual(reloaded.lastSequence, 1)
    }

    // A process killed mid-append leaves a partial final line. Everything
    // before it is intact, so the document should open missing the last stroke
    // rather than not opening at all.
    func testTruncatedFinalLogLineIsTolerated() async throws {
        let repo = makeRepository()
        let document = try await repo.createDocument(title: "Untitled")
        _ = try await repo.append(
            document.operationsInserting([stroke(at: 0), stroke(at: 30)], at: t0),
            to: document.id
        )

        let log = root
            .appendingPathComponent(document.id.rawValue.uuidString)
            .appendingPathComponent("operations.jsonl")
        var text = try String(contentsOf: log, encoding: .utf8)
        text += "{\"sequence\":3,\"timesta"
        try text.write(to: log, atomically: true, encoding: .utf8)

        let reloaded = try await makeRepository().document(document.id)
        XCTAssertEqual(reloaded.elements.count, 2)
    }

    // MARK: - Listing and lifecycle

    func testSummariesListEveryDocument() async throws {
        let repo = makeRepository()
        _ = try await repo.createDocument(title: "One")
        _ = try await repo.createDocument(title: "Two")

        let summaries = try await makeRepository().summaries()
        XCTAssertEqual(summaries.count, 2)
        XCTAssertEqual(Set(summaries.map(\.title)), ["One", "Two"])
    }

    func testSummariesCarryElementCounts() async throws {
        let repo = makeRepository()
        let document = try await repo.createDocument(title: "Untitled")
        _ = try await repo.append(
            document.operationsInserting([stroke(at: 0), stroke(at: 9)], at: t0),
            to: document.id
        )

        let summaries = try await makeRepository().summaries()
        let summary = try XCTUnwrap(summaries.first)
        XCTAssertEqual(summary.elementCount, 2)
    }

    func testRenamePersists() async throws {
        let repo = makeRepository()
        let document = try await repo.createDocument(title: "Untitled")

        try await repo.rename(document.id, to: "Section 3.2")

        let reloaded = try await makeRepository().document(document.id)
        XCTAssertEqual(reloaded.title, "Section 3.2")
    }

    func testDeleteRemovesTheDirectory() async throws {
        let repo = makeRepository()
        let document = try await repo.createDocument(title: "Untitled")

        try await repo.deleteDocument(document.id)

        let directory = root.appendingPathComponent(document.id.rawValue.uuidString)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))

        let remaining = try await makeRepository().summaries()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testSummariesOnAnEmptyStoreIsEmpty() async throws {
        let summaries = try await makeRepository().summaries()
        XCTAssertTrue(summaries.isEmpty)
    }
}
