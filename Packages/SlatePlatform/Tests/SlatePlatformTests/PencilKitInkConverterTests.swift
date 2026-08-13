import XCTest
import PencilKit
import UIKit
import SlateCore
@testable import SlatePlatform

final class PencilKitInkConverterTests: XCTestCase {

    private let converter = PencilKitInkConverter()
    private let t0 = FixedTimeSource.reference.now

    private func makePKStroke(
        locations: [CGPoint],
        forces: [CGFloat]? = nil,
        transform: CGAffineTransform = .identity,
        inkType: PKInk.InkType = .pen,
        color: UIColor = .black
    ) -> PKStroke {
        let f = forces ?? Array(repeating: CGFloat(1), count: locations.count)
        let controlPoints = zip(locations, f).enumerated().map { index, pair in
            PKStrokePoint(
                location: pair.0,
                timeOffset: Double(index) * 0.01,
                size: CGSize(width: 4, height: 4),
                opacity: 1,
                force: pair.1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        let path = PKStrokePath(controlPoints: controlPoints, creationDate: t0)
        return PKStroke(ink: PKInk(inkType, color: color), path: path, transform: transform, mask: nil)
    }

    // MARK: - Capture

    func testCapturePreservesPointCountAndOrder() {
        let stroke = converter.inkStroke(
            from: makePKStroke(locations: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 10, y: 5),
                CGPoint(x: 20, y: 0)
            ]),
            lastModified: t0
        )

        XCTAssertEqual(stroke.points.count, 3)
        XCTAssertEqual(stroke.points[0].position, CanvasPoint(x: 0, y: 0))
        XCTAssertEqual(stroke.points[1].position, CanvasPoint(x: 10, y: 5))
        XCTAssertEqual(stroke.points[2].position, CanvasPoint(x: 20, y: 0))
    }

    func testCapturePreservesCreationDate() {
        let stroke = converter.inkStroke(from: makePKStroke(locations: [.zero]), lastModified: t0)
        XCTAssertEqual(stroke.createdAt.timeIntervalSince1970, t0.timeIntervalSince1970, accuracy: 0.001)
    }

    // The stroke transform must be baked into the coordinates. If it is not,
    // stored geometry is only correct when read alongside a field the domain
    // does not carry — which is a lossy format wearing a clean-looking model.
    func testCaptureBakesTheStrokeTransformIntoCoordinates() {
        let stroke = converter.inkStroke(
            from: makePKStroke(
                locations: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)],
                transform: CGAffineTransform(translationX: 100, y: 50)
            ),
            lastModified: t0
        )

        XCTAssertEqual(stroke.points[0].position, CanvasPoint(x: 100, y: 50))
        XCTAssertEqual(stroke.points[1].position, CanvasPoint(x: 110, y: 50))
    }

    func testCaptureScalesWidthByTheStrokeTransform() {
        let stroke = converter.inkStroke(
            from: makePKStroke(
                locations: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)],
                transform: CGAffineTransform(scaleX: 2, y: 2)
            ),
            lastModified: t0
        )

        XCTAssertEqual(stroke.points[0].width, 8, accuracy: 1e-9)
    }

    func testCaptureDetectsVaryingPressure() {
        let stroke = converter.inkStroke(
            from: makePKStroke(
                locations: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 2, y: 0)],
                forces: [0.2, 0.6, 0.9]
            ),
            lastModified: t0
        )

        XCTAssertTrue(stroke.hasPressure)
        XCTAssertEqual(stroke.points[0].pressure, 0.2, accuracy: 1e-9)
    }

    func testCaptureTreatsConstantForceAsNoPressure() {
        let stroke = converter.inkStroke(
            from: makePKStroke(
                locations: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0)],
                forces: [1, 1]
            ),
            lastModified: t0
        )

        XCTAssertFalse(stroke.hasPressure)
    }

    func testCaptureClampsPressureIntoTheDomainRange() {
        let stroke = converter.inkStroke(
            from: makePKStroke(
                locations: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0)],
                forces: [-0.5, 4.0]
            ),
            lastModified: t0
        )

        XCTAssertTrue(stroke.points.allSatisfy { $0.pressure >= 0 && $0.pressure <= 1 })
    }

    func testCaptureMapsColor() {
        let stroke = converter.inkStroke(
            from: makePKStroke(locations: [.zero], color: .red),
            lastModified: t0
        )

        XCTAssertEqual(stroke.style.color.red, 1, accuracy: 0.01)
        XCTAssertEqual(stroke.style.color.green, 0, accuracy: 0.01)
    }

    func testCaptureMapsKnownInkTypes() {
        let pencil = converter.inkStroke(
            from: makePKStroke(locations: [.zero], inkType: .pencil),
            lastModified: t0
        )
        let marker = converter.inkStroke(
            from: makePKStroke(locations: [.zero], inkType: .marker),
            lastModified: t0
        )

        XCTAssertEqual(pencil.style.kind, .pencil)
        XCTAssertEqual(marker.style.kind, .marker)
    }

    // MARK: - Round trip

    // Invariant 2's real test. If a drawing cannot be rebuilt from the domain
    // model, then PKDrawing is quietly the source of truth no matter what the
    // layering diagram says.
    func testRoundTripPreservesGeometry() {
        let original = converter.inkStroke(
            from: makePKStroke(locations: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 10, y: 5),
                CGPoint(x: 20, y: -3)
            ], forces: [0.2, 0.5, 0.8]),
            lastModified: t0
        )

        let rebuilt = converter.inkStroke(
            from: converter.pkStroke(from: original),
            lastModified: t0
        )

        XCTAssertEqual(rebuilt.points.count, original.points.count)
        for (a, b) in zip(rebuilt.points, original.points) {
            XCTAssertEqual(a.position.x, b.position.x, accuracy: 1e-6)
            XCTAssertEqual(a.position.y, b.position.y, accuracy: 1e-6)
            XCTAssertEqual(a.pressure, b.pressure, accuracy: 1e-6)
            XCTAssertEqual(a.timeOffset, b.timeOffset, accuracy: 1e-6)
            XCTAssertEqual(a.width, b.width, accuracy: 1e-6)
        }
    }

    func testRoundTripPreservesStyle() {
        let original = converter.inkStroke(
            from: makePKStroke(locations: [.zero, CGPoint(x: 5, y: 5)], inkType: .pencil, color: .blue),
            lastModified: t0
        )

        let rebuilt = converter.inkStroke(from: converter.pkStroke(from: original), lastModified: t0)

        XCTAssertEqual(rebuilt.style.kind, original.style.kind)
        XCTAssertEqual(rebuilt.style.color.blue, original.style.color.blue, accuracy: 0.01)
    }

    func testDrawingRoundTripPreservesStrokeCount() {
        let strokes = (0..<5).map { index in
            converter.inkStroke(
                from: makePKStroke(locations: [
                    CGPoint(x: Double(index) * 10, y: 0),
                    CGPoint(x: Double(index) * 10 + 5, y: 5)
                ]),
                lastModified: t0
            )
        }

        let rebuilt = converter.inkStrokes(
            from: converter.pkDrawing(from: strokes),
            lastModified: t0
        )

        XCTAssertEqual(rebuilt.count, strokes.count)
    }
}
