import XCTest
@testable import SlateCore

private let t0 = FixedTimeSource.reference.now

private func strokeSpanning(from a: CanvasPoint, to b: CanvasPoint, width: Double = 4) -> InkStroke {
    InkStroke(
        points: [
            InkPoint(position: a, timeOffset: 0, pressure: 0.5,
                     azimuth: 0, altitude: .pi / 2, width: width),
            InkPoint(position: b, timeOffset: 0.05, pressure: 0.6,
                     azimuth: 0, altitude: .pi / 2, width: width)
        ],
        style: InkStyle(kind: .pen, color: .black, width: width),
        createdAt: t0,
        hasPressure: true,
        hasTilt: false,
        lastModified: t0
    )
}

private func region(
    x: Double = 0, y: Double = 0, width: Double = 100, height: Double = 100,
    state: WorkRegionState = .untouched,
    ordinal: Int = 1
) -> WorkRegion {
    WorkRegion(
        bounds: CanvasRect(x: x, y: y, width: width, height: height),
        state: state,
        ordinal: ordinal,
        lastModified: t0
    )
}

final class WorkRegionTests: XCTestCase {

    func testLabelReadsLikeTheInterface() {
        XCTAssertEqual(region(ordinal: 3).label, "Problem 3")
    }

    // MARK: - Claiming

    func testClaimsAStrokeDrawnInside() {
        let r = region()
        let s = strokeSpanning(from: CanvasPoint(x: 20, y: 20), to: CanvasPoint(x: 60, y: 60))
        XCTAssertTrue(r.claims(s))
    }

    func testDoesNotClaimAStrokeDrawnElsewhere() {
        let r = region()
        let s = strokeSpanning(from: CanvasPoint(x: 300, y: 300), to: CanvasPoint(x: 340, y: 340))
        XCTAssertFalse(r.claims(s))
    }

    // Handwriting spills. A descender, a long fraction bar, a bracket reaching
    // into the margin — all routinely cross whatever box was drawn around the
    // work, and all still belong to the problem they were written for.
    func testClaimsAStrokeThatStartsInsideAndSpillsOut() {
        let r = region()
        let s = strokeSpanning(from: CanvasPoint(x: 40, y: 40), to: CanvasPoint(x: 130, y: 60))
        XCTAssertTrue(r.claims(s))
    }

    // Assignment is by centre, not overlap, so a stroke cannot belong to two
    // problems at once. A stroke that merely grazes a region is not its work.
    func testDoesNotClaimAStrokeThatOnlyGrazesIt() {
        let r = region()
        let s = strokeSpanning(from: CanvasPoint(x: 90, y: 50), to: CanvasPoint(x: 300, y: 50))
        XCTAssertFalse(r.claims(s))
        XCTAssertTrue(r.intersects(s), "it does overlap — it just isn't this region's work")
    }

    func testClaimsNothingFromAnEmptyStroke() {
        let empty = InkStroke(
            points: [], style: .defaultPen, createdAt: t0,
            hasPressure: false, hasTilt: false, lastModified: t0
        )
        XCTAssertFalse(region().claims(empty))
    }

    func testIntersectsIsFalseForDistantStrokes() {
        let s = strokeSpanning(from: CanvasPoint(x: 500, y: 500), to: CanvasPoint(x: 520, y: 520))
        XCTAssertFalse(region().intersects(s))
    }

    // MARK: - Capture bounds

    // Cropping to the drawn box would clip working that spilled outside it, and
    // a model reading a crop with the bottom of a fraction missing reads it
    // confidently and wrongly.
    func testCaptureBoundsGrowToCoverSpilledWork() {
        let r = region()
        let spilling = strokeSpanning(from: CanvasPoint(x: 40, y: 40), to: CanvasPoint(x: 130, y: 40))

        let capture = r.captureBounds(claiming: [spilling], padding: 0)

        XCTAssertGreaterThan(capture.maxX, 130)
        XCTAssertEqual(capture.minX, 0, accuracy: 1e-9)
    }

    func testCaptureBoundsIgnoreStrokesBelongingElsewhere() {
        let r = region()
        let elsewhere = strokeSpanning(from: CanvasPoint(x: 400, y: 400), to: CanvasPoint(x: 440, y: 440))

        XCTAssertEqual(r.captureBounds(claiming: [elsewhere], padding: 0), r.bounds)
    }

    func testCaptureBoundsOfAnEmptyRegionAreItsBounds() {
        let r = region()
        XCTAssertEqual(r.captureBounds(claiming: [], padding: 0), r.bounds)
    }

    // Padding always applies, with or without spilled work. The point of it is
    // that a crop handed to a model should not end exactly where the ink does —
    // a stroke flush against the edge of the image reads as clipped, and a
    // model reading a clipped crop reads it confidently and wrongly.
    func testCaptureBoundsApplyPadding() {
        let r = region()   // 100 x 100 at the origin
        let padded = r.captureBounds(claiming: [], padding: 0.1)

        XCTAssertEqual(padded.minX, -10, accuracy: 1e-9)
        XCTAssertEqual(padded.minY, -10, accuracy: 1e-9)
        XCTAssertEqual(padded.maxX, 110, accuracy: 1e-9)
        XCTAssertEqual(padded.maxY, 110, accuracy: 1e-9)
    }

    func testZeroPaddingLeavesTheCaptureExact() {
        let r = region()
        XCTAssertEqual(r.captureBounds(claiming: [], padding: 0), r.bounds)
    }

    // MARK: - State

    func testWorkMovesAnUntouchedRegionToInProgress() {
        XCTAssertEqual(WorkRegion.observedState(from: .untouched, hasWork: true), .inProgress)
    }

    func testErasingEverythingReturnsARegionToUntouched() {
        XCTAssertEqual(WorkRegion.observedState(from: .inProgress, hasWork: false), .untouched)
    }

    // Declared states are judgements. Having the app silently un-complete a
    // problem because a stroke was erased would be infuriating and would
    // destroy the record of what was finished.
    func testDeclaredStatesSurviveTheContentsChanging() {
        XCTAssertEqual(WorkRegion.observedState(from: .complete, hasWork: false), .complete)
        XCTAssertEqual(WorkRegion.observedState(from: .setAside, hasWork: true), .setAside)
    }

    func testUpdatingStateReturnsNilWhenNothingChanges() {
        let r = region(state: .inProgress)
        XCTAssertNil(r.updatingState(hasWork: true, at: t0))
    }

    func testUpdatingStateReturnsTheNewRegionWhenItChanges() throws {
        let r = region(state: .untouched)
        let updated = try XCTUnwrap(r.updatingState(hasWork: true, at: t0.addingTimeInterval(5)))

        XCTAssertEqual(updated.state, .inProgress)
        XCTAssertEqual(updated.id, r.id)
        XCTAssertEqual(updated.lastModified, t0.addingTimeInterval(5))
    }

    func testDeclaringSetsTheStateAndStamps() {
        let declared = region().declaring(.complete, at: t0.addingTimeInterval(9))
        XCTAssertEqual(declared.state, .complete)
        XCTAssertEqual(declared.lastModified, t0.addingTimeInterval(9))
    }

    func testOnlyDeclaredStatesReportAsDeclared() {
        XCTAssertFalse(WorkRegionState.untouched.isDeclared)
        XCTAssertFalse(WorkRegionState.inProgress.isDeclared)
        XCTAssertTrue(WorkRegionState.complete.isDeclared)
        XCTAssertTrue(WorkRegionState.setAside.isDeclared)
    }

    // MARK: - Wire format

    func testRegionSurvivesARoundTrip() throws {
        var original = region(state: .complete, ordinal: 7)
        original.prompt = "simplify (3x^2 - 12)/(x^2 + x - 6)"

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkRegion.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testRegionEncodesInsideACanvasElementWithAStableDiscriminator() throws {
        let data = try JSONEncoder().encode(CanvasElement.workRegion(region()))
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(json.contains("\"kind\":\"workRegion\""), json)
    }

    func testEveryStateAndKindRoundTrips() throws {
        for state in WorkRegionState.allCases {
            let data = try JSONEncoder().encode(state)
            XCTAssertEqual(try JSONDecoder().decode(WorkRegionState.self, from: data), state)
        }
        for kind in WorkRegionKind.allCases {
            let data = try JSONEncoder().encode(kind)
            XCTAssertEqual(try JSONDecoder().decode(WorkRegionKind.self, from: data), kind)
        }
    }
}

final class DocumentRegionTests: XCTestCase {

    private func documentWith(_ elements: [CanvasElement]) throws -> Document {
        var document = Document(title: "Untitled", createdAt: t0)
        for element in elements {
            try document.apply(document.operation(.insert(element), at: t0))
        }
        return document
    }

    func testRegionsAndStrokesAreSeparableFromTheSameElementList() throws {
        let r = region()
        let s = strokeSpanning(from: CanvasPoint(x: 10, y: 10), to: CanvasPoint(x: 30, y: 30))
        let document = try documentWith([.workRegion(r), .ink(s)])

        XCTAssertEqual(document.elements.count, 2)
        XCTAssertEqual(document.workRegions.map(\.id), [r.id])
        XCTAssertEqual(document.inkStrokes.map(\.id), [s.id])
    }

    func testStrokesAreAssignedToTheRegionTheyWereDrawnIn() throws {
        let first = region(x: 0, y: 0, ordinal: 1)
        let second = region(x: 200, y: 0, ordinal: 2)
        let inFirst = strokeSpanning(from: CanvasPoint(x: 20, y: 20), to: CanvasPoint(x: 40, y: 40))
        let inSecond = strokeSpanning(from: CanvasPoint(x: 220, y: 20), to: CanvasPoint(x: 240, y: 40))

        let document = try documentWith([
            .workRegion(first), .workRegion(second), .ink(inFirst), .ink(inSecond)
        ])

        XCTAssertEqual(document.region(claiming: inFirst)?.id, first.id)
        XCTAssertEqual(document.region(claiming: inSecond)?.id, second.id)
        XCTAssertEqual(document.strokes(in: first).map(\.id), [inFirst.id])
        XCTAssertEqual(document.strokes(in: second).map(\.id), [inSecond.id])
    }

    func testAStrokeDrawnOutsideEveryRegionBelongsToNone() throws {
        let r = region()
        let stray = strokeSpanning(from: CanvasPoint(x: 500, y: 500), to: CanvasPoint(x: 520, y: 520))
        let document = try documentWith([.workRegion(r), .ink(stray)])

        XCTAssertNil(document.region(claiming: stray))
        XCTAssertFalse(document.hasWork(in: r))
    }

    func testHasWorkFollowsTheContents() throws {
        let r = region()
        let inside = strokeSpanning(from: CanvasPoint(x: 20, y: 20), to: CanvasPoint(x: 40, y: 40))

        XCTAssertFalse(try documentWith([.workRegion(r)]).hasWork(in: r))
        XCTAssertTrue(try documentWith([.workRegion(r), .ink(inside)]).hasWork(in: r))
    }

    // One past the highest in use rather than the count, so deleting Problem 2
    // of three does not produce a second Problem 3.
    func testNextOrdinalDoesNotReuseNumbersAfterADeletion() throws {
        let one = region(ordinal: 1)
        let two = region(x: 200, ordinal: 2)
        let three = region(x: 400, ordinal: 3)

        var document = try documentWith([.workRegion(one), .workRegion(two), .workRegion(three)])
        try document.apply(document.operation(.remove(two.id), at: t0))

        XCTAssertEqual(document.workRegions.count, 2)
        XCTAssertEqual(document.nextRegionOrdinal, 4)
    }

    func testNextOrdinalStartsAtOne() throws {
        XCTAssertEqual(try documentWith([]).nextRegionOrdinal, 1)
    }

    func testRegionsNeedingUpdateIsEmptyWhenEverythingAgrees() throws {
        let r = region(state: .inProgress)
        let inside = strokeSpanning(from: CanvasPoint(x: 20, y: 20), to: CanvasPoint(x: 40, y: 40))
        let document = try documentWith([.workRegion(r), .ink(inside)])

        XCTAssertTrue(document.regionsNeedingStateUpdate(at: t0).isEmpty)
    }

    func testRegionsNeedingUpdateReportsAFreshlyUsedRegion() throws {
        let r = region(state: .untouched)
        let inside = strokeSpanning(from: CanvasPoint(x: 20, y: 20), to: CanvasPoint(x: 40, y: 40))
        let document = try documentWith([.workRegion(r), .ink(inside)])

        let pending = document.regionsNeedingStateUpdate(at: t0)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.state, .inProgress)
    }

    func testRegionsGoThroughTheSameOperationMachineryAsInk() throws {
        let r = region(state: .untouched)
        var document = try documentWith([.workRegion(r)])

        let advanced = try XCTUnwrap(r.updatingState(hasWork: true, at: t0))
        try document.apply(document.operation(.replace(.workRegion(advanced)), at: t0))

        XCTAssertEqual(document.workRegions.first?.state, .inProgress)
        XCTAssertEqual(document.lastSequence, 2)
    }

    func testRegionsSurviveReplay() throws {
        let r = region(ordinal: 2)
        let s = strokeSpanning(from: CanvasPoint(x: 20, y: 20), to: CanvasPoint(x: 40, y: 40))

        var source = Document(title: "Untitled", createdAt: t0)
        var log: [DocumentOperation] = []
        for element in [CanvasElement.workRegion(r), .ink(s)] {
            let op = source.operation(.insert(element), at: t0)
            log.append(op)
            try source.apply(op)
        }

        let replayed = try Document.replaying(log, onto: Document(title: "Untitled", createdAt: t0))

        XCTAssertEqual(replayed.workRegions.first?.ordinal, 2)
        XCTAssertEqual(replayed.workRegions.first?.id, r.id)
        XCTAssertEqual(replayed.inkStrokes.count, 1)
    }
}
