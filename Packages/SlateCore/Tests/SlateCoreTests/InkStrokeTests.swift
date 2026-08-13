import XCTest
@testable import SlateCore

private let t0 = FixedTimeSource.reference.now

private func makeStroke(
    positions: [CanvasPoint],
    width: Double = 4,
    spacing: TimeInterval = 0.01
) -> InkStroke {
    let points = positions.enumerated().map { index, position in
        InkPoint(
            position: position,
            timeOffset: Double(index) * spacing,
            pressure: 0.5,
            azimuth: 0,
            altitude: .pi / 2,
            width: width
        )
    }
    return InkStroke(
        points: points,
        style: InkStyle(kind: .pen, color: .black, width: width),
        createdAt: t0,
        hasPressure: true,
        hasTilt: true,
        lastModified: t0
    )
}

final class InkStrokeTests: XCTestCase {

    func testPathBoundsCoverEverySample() {
        let stroke = makeStroke(positions: [
            CanvasPoint(x: 0, y: 0),
            CanvasPoint(x: 10, y: 4),
            CanvasPoint(x: -3, y: 9)
        ])
        let bounds = stroke.pathBounds

        XCTAssertEqual(bounds.minX, -3)
        XCTAssertEqual(bounds.minY, 0)
        XCTAssertEqual(bounds.maxX, 10)
        XCTAssertEqual(bounds.maxY, 9)
    }

    // A wide stroke paints outside its path. Cropping a region to a path
    // bounds clips the outer edge of the ink, and a model reading a crop with
    // the top of a digit shaved off reads it confidently and wrongly.
    func testRenderBoundsAreWiderThanPathBounds() {
        let stroke = makeStroke(positions: [
            CanvasPoint(x: 0, y: 0),
            CanvasPoint(x: 10, y: 0)
        ], width: 8)

        XCTAssertEqual(stroke.pathBounds.minY, 0)
        XCTAssertEqual(stroke.renderBounds.minY, -4)
        XCTAssertEqual(stroke.renderBounds.maxY, 4)
    }

    func testRenderBoundsOfAnEmptyStrokeIsZero() {
        let stroke = makeStroke(positions: [])
        XCTAssertEqual(stroke.renderBounds, .zero)
    }

    func testDurationIsLastMinusFirstOffset() {
        let stroke = makeStroke(
            positions: Array(repeating: CanvasPoint(x: 0, y: 0), count: 5),
            spacing: 0.25
        )
        XCTAssertEqual(stroke.duration, 1.0, accuracy: 1e-12)
    }

    func testEndedAtIsCreatedAtPlusDuration() {
        let stroke = makeStroke(
            positions: Array(repeating: CanvasPoint(x: 0, y: 0), count: 3),
            spacing: 0.5
        )
        XCTAssertEqual(stroke.endedAt.timeIntervalSince(t0), 1.0, accuracy: 1e-12)
    }

    func testArcLengthSumsConsecutiveDistances() {
        let stroke = makeStroke(positions: [
            CanvasPoint(x: 0, y: 0),
            CanvasPoint(x: 3, y: 4),   // 5
            CanvasPoint(x: 3, y: 14)   // 10
        ])
        XCTAssertEqual(stroke.arcLength, 15, accuracy: 1e-12)
    }

    func testArcLengthOfASinglePointIsZero() {
        XCTAssertEqual(makeStroke(positions: [CanvasPoint(x: 1, y: 1)]).arcLength, 0)
    }

    func testShortMarksAreDots() {
        let dot = makeStroke(positions: [
            CanvasPoint(x: 0, y: 0),
            CanvasPoint(x: 0.5, y: 0)
        ], width: 4)
        XCTAssertTrue(dot.isDot)
    }

    func testLongMarksAreNotDots() {
        let line = makeStroke(positions: [
            CanvasPoint(x: 0, y: 0),
            CanvasPoint(x: 50, y: 0)
        ], width: 4)
        XCTAssertFalse(line.isDot)
    }
}

final class InkStrokeTransformTests: XCTestCase {

    func testTransformMovesEveryPoint() {
        let stroke = makeStroke(positions: [
            CanvasPoint(x: 0, y: 0),
            CanvasPoint(x: 10, y: 10)
        ])
        let moved = stroke.transformed(by: .translation(x: 5, y: -5))

        XCTAssertEqual(moved.points.first?.position, CanvasPoint(x: 5, y: -5))
        XCTAssertEqual(moved.points.last?.position, CanvasPoint(x: 15, y: 5))
    }

    func testTransformPreservesIdentityAndOrder() {
        let stroke = makeStroke(positions: [
            CanvasPoint(x: 0, y: 0),
            CanvasPoint(x: 1, y: 1),
            CanvasPoint(x: 2, y: 2)
        ])
        let moved = stroke.transformed(by: .scale(x: 2, y: 2))

        XCTAssertEqual(moved.id, stroke.id)
        XCTAssertEqual(moved.points.count, 3)
        XCTAssertEqual(moved.points.map(\.timeOffset), stroke.points.map(\.timeOffset))
    }

    // Widths are scalars and cannot be transformed as points, so they scale by
    // the transform's uniform scale. Forgetting this leaves a scaled-up stroke
    // with hairline width, which looks like a rendering bug and is a data one.
    func testTransformScalesWidths() {
        let stroke = makeStroke(positions: [CanvasPoint(x: 0, y: 0)], width: 4)
        let scaled = stroke.transformed(by: .scale(x: 3, y: 3))

        XCTAssertEqual(scaled.style.width, 12, accuracy: 1e-12)
        XCTAssertEqual(scaled.points[0].width, 12, accuracy: 1e-12)
    }

    // Pressure, azimuth, and altitude describe the hand that drew the stroke.
    // Moving the stroke across the canvas afterwards does not change how hard
    // it was pressed.
    func testTransformLeavesStylusDataAlone() {
        let stroke = makeStroke(positions: [CanvasPoint(x: 0, y: 0)])
        let moved = stroke.transformed(by: .scale(x: 5, y: 5))

        XCTAssertEqual(moved.points[0].pressure, stroke.points[0].pressure)
        XCTAssertEqual(moved.points[0].azimuth, stroke.points[0].azimuth)
        XCTAssertEqual(moved.points[0].altitude, stroke.points[0].altitude)
    }

    func testIdentityTransformIsANoOp() {
        let stroke = makeStroke(positions: [CanvasPoint(x: 1, y: 2)])
        XCTAssertEqual(stroke.transformed(by: .identity), stroke)
    }
}

final class InkSerializationTests: XCTestCase {

    // Invariant 2: this is the canonical record. If it does not round-trip
    // losslessly, the document format is lossy and no amount of clean layering
    // fixes that.
    func testStrokeSurvivesACodableRoundTrip() throws {
        let original = makeStroke(positions: [
            CanvasPoint(x: 0, y: 0),
            CanvasPoint(x: 1.5, y: -2.25),
            CanvasPoint(x: 100, y: 3)
        ])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(InkStroke.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.points, original.points)
        XCTAssertEqual(decoded.style, original.style)
        XCTAssertEqual(decoded.hasPressure, original.hasPressure)
        XCTAssertEqual(decoded.hasTilt, original.hasTilt)
        XCTAssertEqual(decoded.owner, original.owner)
    }

    // Raw values are strings so that adding or reordering a case does not
    // silently reinterpret every stroke in every document already on disk.
    func testInkKindEncodesAsAStableString() throws {
        let data = try JSONEncoder().encode(InkKind.highlighter)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "\"highlighter\"")
    }

    func testEveryInkKindRoundTrips() throws {
        for kind in InkKind.allCases {
            let data = try JSONEncoder().encode(kind)
            XCTAssertEqual(try JSONDecoder().decode(InkKind.self, from: data), kind)
        }
    }

    func testExtendedRangeColorIsPreservedButClampable() {
        let wide = InkColor(red: 1.2, green: -0.1, blue: 0.5, alpha: 1)
        XCTAssertEqual(wide.red, 1.2)
        XCTAssertEqual(wide.clamped.red, 1.0)
        XCTAssertEqual(wide.clamped.green, 0.0)
        XCTAssertEqual(wide.clamped.blue, 0.5)
    }
}

final class InkPointTests: XCTestCase {

    // Invariant 5: a mouse and a finger are sources of the same normalized
    // stroke events as a Pencil, with the optional channels absent rather than
    // invented.
    func testPositionOnlyPointsHaveNeutralStylusData() {
        let point = InkPoint.positionOnly(
            CanvasPoint(x: 1, y: 2),
            timeOffset: 0.5,
            width: 3
        )
        XCTAssertEqual(point.pressure, 1)
        XCTAssertEqual(point.altitude, .pi / 2, accuracy: 1e-12)
        XCTAssertEqual(point.width, 3)
    }
}

final class InkCapabilityInferenceTests: XCTestCase {

    private func points(pressures: [Double], altitudes: [Double]? = nil) -> [InkPoint] {
        let alts = altitudes ?? Array(repeating: Double.pi / 2, count: pressures.count)
        return zip(pressures, alts).enumerated().map { index, pair in
            InkPoint(
                position: CanvasPoint(x: Double(index), y: 0),
                timeOffset: Double(index) * 0.01,
                pressure: pair.0,
                azimuth: 0,
                altitude: pair.1,
                width: 4
            )
        }
    }

    func testVaryingPressureIsDetected() {
        let caps = InkStroke.inferredCapabilities(from: points(pressures: [0.2, 0.5, 0.9]))
        XCTAssertTrue(caps.hasPressure)
    }

    // A mouse reports the same value at every sample. Recording that as real
    // pressure makes the renderer draw a taper the user never produced.
    func testConstantPressureIsNotDetected() {
        let caps = InkStroke.inferredCapabilities(from: points(pressures: [1, 1, 1, 1]))
        XCTAssertFalse(caps.hasPressure)
    }

    func testVaryingAltitudeCountsAsTilt() {
        let caps = InkStroke.inferredCapabilities(
            from: points(pressures: [1, 1, 1], altitudes: [1.0, 1.2, 0.9])
        )
        XCTAssertTrue(caps.hasTilt)
        XCTAssertFalse(caps.hasPressure)
    }

    // The documented false negative: too few samples to see variance. Failing
    // this way loses a subtlety; failing the other way invents data.
    func testTooFewSamplesReportsNoCapabilities() {
        let caps = InkStroke.inferredCapabilities(from: points(pressures: [0.7]))
        XCTAssertFalse(caps.hasPressure)
        XCTAssertFalse(caps.hasTilt)
    }

    func testNoSamplesReportsNoCapabilities() {
        let caps = InkStroke.inferredCapabilities(from: [])
        XCTAssertFalse(caps.hasPressure)
        XCTAssertFalse(caps.hasTilt)
    }

    func testVarianceBelowToleranceIsIgnored() {
        let caps = InkStroke.inferredCapabilities(
            from: points(pressures: [0.5, 0.5 + 1e-9, 0.5])
        )
        XCTAssertFalse(caps.hasPressure)
    }
}
