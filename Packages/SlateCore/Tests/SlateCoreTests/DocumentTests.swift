import XCTest
@testable import SlateCore

private let t0 = FixedTimeSource.reference.now

private func stroke(at x: Double = 0, width: Double = 4) -> InkStroke {
    InkStroke(
        points: [
            InkPoint(position: CanvasPoint(x: x, y: 0), timeOffset: 0,
                     pressure: 0.5, azimuth: 0, altitude: .pi / 2, width: width),
            InkPoint(position: CanvasPoint(x: x + 10, y: 0), timeOffset: 0.05,
                     pressure: 0.6, azimuth: 0, altitude: .pi / 2, width: width)
        ],
        style: InkStyle(kind: .pen, color: .black, width: width),
        createdAt: t0,
        hasPressure: true,
        hasTilt: false,
        lastModified: t0
    )
}

private func newDocument() -> Document {
    Document(title: "Untitled", createdAt: t0)
}

final class DocumentOperationTests: XCTestCase {

    func testInsertAddsAnElement() throws {
        var document = newDocument()
        let s = stroke()

        try document.apply(document.operation(.insert(.ink(s)), at: t0))

        XCTAssertEqual(document.elements.count, 1)
        XCTAssertEqual(document.element(s.id)?.id, s.id)
        XCTAssertEqual(document.lastSequence, 1)
    }

    func testSequenceStartsAtOne() {
        let document = newDocument()
        XCTAssertEqual(document.lastSequence, 0)
        XCTAssertEqual(document.operation(.insert(.ink(stroke())), at: t0).sequence, 1)
    }

    // A gap means an operation was lost. Replaying the rest anyway produces a
    // document that looks fine and is quietly missing a stroke from the middle
    // of a worked problem, with nothing to indicate it.
    func testOutOfOrderOperationIsRejected() {
        var document = newDocument()
        let skipped = DocumentOperation(
            sequence: 2, timestamp: t0, change: .insert(.ink(stroke()))
        )

        XCTAssertThrowsError(try document.apply(skipped)) { error in
            XCTAssertEqual(
                error as? Document.OperationError,
                .outOfOrder(expected: 1, got: 2)
            )
        }
    }

    func testARejectedOperationChangesNothing() {
        var document = newDocument()
        let before = document

        try? document.apply(DocumentOperation(
            sequence: 99, timestamp: t0, change: .insert(.ink(stroke()))
        ))

        XCTAssertEqual(document, before)
    }

    func testInsertingTheSameElementTwiceIsRejected() throws {
        var document = newDocument()
        let s = stroke()
        try document.apply(document.operation(.insert(.ink(s)), at: t0))

        XCTAssertThrowsError(
            try document.apply(document.operation(.insert(.ink(s)), at: t0))
        ) { error in
            XCTAssertEqual(error as? Document.OperationError, .duplicateElement(s.id))
        }
    }

    func testRemovingAnAbsentElementIsRejected() {
        var document = newDocument()
        let id = ElementID()

        XCTAssertThrowsError(
            try document.apply(document.operation(.remove(id), at: t0))
        ) { error in
            XCTAssertEqual(error as? Document.OperationError, .unknownElement(id))
        }
    }

    func testRemoveDeletesTheElement() throws {
        var document = newDocument()
        let s = stroke()
        try document.apply(document.operation(.insert(.ink(s)), at: t0))
        try document.apply(document.operation(.remove(s.id), at: t0))

        XCTAssertTrue(document.isEmpty)
        XCTAssertEqual(document.lastSequence, 2)
    }

    // Replacing must not reorder. If an edit moved a stroke to the end of the
    // list it would jump to the front of the z-order, which reads as a
    // rendering bug and is a data one.
    func testReplacePreservesDrawOrder() throws {
        var document = newDocument()
        let first = stroke(at: 0)
        let second = stroke(at: 100)

        try document.apply(document.operation(.insert(.ink(first)), at: t0))
        try document.apply(document.operation(.insert(.ink(second)), at: t0))

        var edited = first
        edited.replacePoints(first.points, modifiedAt: t0.addingTimeInterval(5))
        try document.apply(document.operation(.replace(.ink(edited)), at: t0))

        XCTAssertEqual(document.elements.map(\.id), [first.id, second.id])
    }

    func testReplacingAnAbsentElementIsRejected() {
        var document = newDocument()

        XCTAssertThrowsError(
            try document.apply(document.operation(.replace(.ink(stroke())), at: t0))
        )
    }

    func testApplyingARunAdvancesTheSequence() throws {
        var document = newDocument()
        let strokes = (0..<5).map { stroke(at: Double($0) * 20) }

        try document.apply(document.operationsInserting(strokes, at: t0))

        XCTAssertEqual(document.elements.count, 5)
        XCTAssertEqual(document.lastSequence, 5)
    }

    func testOperationsInsertingNumbersConsecutivelyFromCurrentPosition() throws {
        var document = newDocument()
        try document.apply(document.operationsInserting([stroke()], at: t0))

        let next = document.operationsInserting([stroke(at: 50), stroke(at: 80)], at: t0)
        XCTAssertEqual(next.map(\.sequence), [2, 3])
    }

    func testLastModifiedFollowsTheOperationTimestamp() throws {
        var document = newDocument()
        let later = t0.addingTimeInterval(600)

        try document.apply(document.operation(.insert(.ink(stroke())), at: later))

        XCTAssertEqual(document.lastModified, later)
    }
}

final class DocumentReplayTests: XCTestCase {

    // The property the whole design rests on: state is a function of the
    // operation log. If replay could diverge from incremental application,
    // then reopening a document could show something different from what the
    // user just drew.
    func testReplayReproducesIncrementalApplicationExactly() throws {
        var incremental = newDocument()
        let strokes = (0..<10).map { stroke(at: Double($0) * 15) }
        var log: [DocumentOperation] = []

        for s in strokes {
            let op = incremental.operation(.insert(.ink(s)), at: t0)
            log.append(op)
            try incremental.apply(op)
        }

        let removal = incremental.operation(.remove(strokes[3].id), at: t0)
        log.append(removal)
        try incremental.apply(removal)

        let replayed = try Document.replaying(log, onto: newDocument())

        XCTAssertEqual(replayed.elements.map(\.id), incremental.elements.map(\.id))
        XCTAssertEqual(replayed.lastSequence, incremental.lastSequence)
        XCTAssertEqual(replayed.lastModified, incremental.lastModified)
    }

    // Compaction replays a tail onto a snapshot rather than the whole log onto
    // an empty document. Both paths go through the same code so that a
    // compacted document cannot drift from a fully-replayed one.
    func testReplayingATailOntoASnapshotMatchesFullReplay() throws {
        var document = newDocument()
        var log: [DocumentOperation] = []

        for index in 0..<6 {
            let op = document.operation(.insert(.ink(stroke(at: Double(index) * 12))), at: t0)
            log.append(op)
            try document.apply(op)
        }

        let snapshot = try Document.replaying(Array(log.prefix(4)), onto: newDocument())
        let fromTail = try Document.replaying(Array(log.suffix(2)), onto: snapshot)
        let fromScratch = try Document.replaying(log, onto: newDocument())

        XCTAssertEqual(fromTail.elements.map(\.id), fromScratch.elements.map(\.id))
        XCTAssertEqual(fromTail.lastSequence, fromScratch.lastSequence)
    }

    func testReplayOfAnEmptyLogIsTheSnapshot() throws {
        let snapshot = newDocument()
        XCTAssertEqual(try Document.replaying([], onto: snapshot), snapshot)
    }

    func testContentBoundsCoverEveryElement() throws {
        var document = newDocument()
        try document.apply(document.operationsInserting(
            [stroke(at: 0), stroke(at: 100)], at: t0
        ))

        XCTAssertEqual(document.contentBounds.minX, -2, accuracy: 1e-9)
        XCTAssertEqual(document.contentBounds.maxX, 112, accuracy: 1e-9)
    }

    func testContentBoundsOfAnEmptyDocumentIsZero() {
        XCTAssertEqual(newDocument().contentBounds, .zero)
    }
}

final class DocumentSerializationTests: XCTestCase {

    func testDocumentSurvivesARoundTrip() throws {
        var document = newDocument()
        try document.apply(document.operationsInserting(
            [stroke(at: 0), stroke(at: 30)], at: t0
        ))

        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(Document.self, from: data)

        XCTAssertEqual(decoded.id, document.id)
        XCTAssertEqual(decoded.elements.map(\.id), document.elements.map(\.id))
        XCTAssertEqual(decoded.lastSequence, document.lastSequence)
    }

    func testOperationSurvivesARoundTrip() throws {
        let document = newDocument()
        let original = document.operation(.insert(.ink(stroke())), at: t0)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DocumentOperation.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testEveryChangeKindSurvivesARoundTrip() throws {
        let changes: [DocumentOperation.Change] = [
            .insert(.ink(stroke())),
            .replace(.ink(stroke(at: 20))),
            .remove(ElementID())
        ]

        for change in changes {
            let data = try JSONEncoder().encode(change)
            let decoded = try JSONDecoder().decode(DocumentOperation.Change.self, from: data)
            XCTAssertEqual(decoded, change)
        }
    }

    // Identifiers encode as bare strings. Settled at M2 because M2 is the
    // milestone that first writes a document to disk; after that it is a
    // migration against files on a real device.
    func testIdentifiersEncodeAsBareStrings() throws {
        let id = DocumentID()
        let data = try JSONEncoder().encode(id)

        XCTAssertEqual(String(decoding: data, as: UTF8.self), "\"\(id.rawValue.uuidString)\"")
    }

    func testIdentifiersStillRoundTrip() throws {
        let id = ElementID()
        let data = try JSONEncoder().encode(id)
        XCTAssertEqual(try JSONDecoder().decode(ElementID.self, from: data), id)
    }

    func testMalformedIdentifierIsRejected() {
        let data = Data("\"not-a-uuid\"".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(DocumentID.self, from: data))
    }

    // The discriminator is a string so that adding an element kind, or
    // reordering the enum, cannot reinterpret elements already on disk.
    func testElementKindIsWrittenAsAStableString() throws {
        let data = try JSONEncoder().encode(CanvasElement.ink(stroke()))
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(json.contains("\"kind\":\"ink\""), json)
    }
}

final class InMemoryDocumentRepositoryTests: XCTestCase {

    private func repository() -> InMemoryDocumentRepository {
        InMemoryDocumentRepository(timeSource: FixedTimeSource.reference)
    }

    func testCreatedDocumentCanBeLoaded() async throws {
        let repo = repository()
        let created = try await repo.createDocument(title: "Calc homework")

        let loaded = try await repo.document(created.id)
        XCTAssertEqual(loaded.id, created.id)
        XCTAssertEqual(loaded.title, "Calc homework")
    }

    func testLoadingAnUnknownDocumentThrowsNotFound() async {
        let repo = repository()
        let id = DocumentID()

        do {
            _ = try await repo.document(id)
            XCTFail("expected notFound")
        } catch {
            XCTAssertEqual(error as? DocumentRepositoryError, .notFound(id))
        }
    }

    func testAppendPersistsStateAndLog() async throws {
        let repo = repository()
        let document = try await repo.createDocument(title: "Untitled")
        let operations = document.operationsInserting([stroke(), stroke(at: 40)], at: t0)

        let updated = try await repo.append(operations, to: document.id)
        XCTAssertEqual(updated.elements.count, 2)

        let reloaded = try await repo.document(document.id)
        XCTAssertEqual(reloaded.elements.count, 2)

        let log = await repo.operationLog(for: document.id)
        XCTAssertEqual(log.count, 2)
    }

    func testAppendingAGapIsRejectedAndNothingIsStored() async throws {
        let repo = repository()
        let document = try await repo.createDocument(title: "Untitled")
        let bad = DocumentOperation(sequence: 5, timestamp: t0, change: .insert(.ink(stroke())))

        do {
            _ = try await repo.append([bad], to: document.id)
            XCTFail("expected rejection")
        } catch {
            guard case DocumentRepositoryError.rejected = error else {
                return XCTFail("expected .rejected, got \(error)")
            }
        }

        let reloaded = try await repo.document(document.id)
        XCTAssertTrue(reloaded.isEmpty)
    }

    func testSummariesAreMostRecentlyModifiedFirst() async throws {
        let repo = repository()
        let older = try await repo.createDocument(title: "Older")
        let newer = try await repo.createDocument(title: "Newer")

        _ = try await repo.append(
            newer.operationsInserting([stroke()], at: t0.addingTimeInterval(1_000)),
            to: newer.id
        )

        let summaries = try await repo.summaries()
        XCTAssertEqual(summaries.first?.id, newer.id)
        XCTAssertEqual(summaries.count, 2)
        XCTAssertTrue(summaries.contains { $0.id == older.id })
    }

    func testSummaryCarriesElementCount() async throws {
        let repo = repository()
        let document = try await repo.createDocument(title: "Untitled")
        _ = try await repo.append(
            document.operationsInserting([stroke(), stroke(at: 20), stroke(at: 40)], at: t0),
            to: document.id
        )

        let summaries = try await repo.summaries()
        XCTAssertEqual(summaries.first?.elementCount, 3)
    }

    func testDeleteRemovesTheDocument() async throws {
        let repo = repository()
        let document = try await repo.createDocument(title: "Untitled")

        try await repo.deleteDocument(document.id)

        let summaries = try await repo.summaries()
        XCTAssertTrue(summaries.isEmpty)
    }

    func testRenameChangesTheTitle() async throws {
        let repo = repository()
        let document = try await repo.createDocument(title: "Untitled")

        try await repo.rename(document.id, to: "Section 3.2")

        XCTAssertEqual(try await repo.document(document.id).title, "Section 3.2")
    }
}
