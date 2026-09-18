import XCTest
import SlateCore
@testable import SlatePlatform

/// These assert on the bytes, not on how the picture looks. A rasterizer test
/// that only checks "it did not throw" passes just as happily when the image is
/// entirely blank — which is the failure that actually happens, and the one that
/// costs an API request to discover.
final class CoreGraphicsStrokeRasterizerTests: XCTestCase {

    private let rasterizer = CoreGraphicsStrokeRasterizer()

    private func stroke(
        from start: CanvasPoint,
        to end: CanvasPoint,
        width: Double = 4,
        color: InkColor = .black
    ) -> InkStroke {
        InkStroke(
            points: [
                InkPoint.positionOnly(start, timeOffset: 0, width: width),
                InkPoint.positionOnly(end, timeOffset: 0.2, width: width)
            ],
            style: InkStyle(kind: .pen, color: color, width: width),
            createdAt: FixedTimeSource.reference.now,
            hasPressure: false,
            hasTilt: false,
            lastModified: FixedTimeSource.reference.now
        )
    }

    func testProducesAPNGOfTheExpectedSize() async throws {
        let region = try await rasterizer.rasterize(
            [stroke(from: CanvasPoint(x: 10, y: 10), to: CanvasPoint(x: 90, y: 90))],
            bounds: CanvasRect(x: 0, y: 0, width: 100, height: 50),
            scale: 2,
            maximumLongEdge: 1000
        )

        XCTAssertEqual(region.mediaType, "image/png")
        XCTAssertEqual(region.pixelWidth, 200)
        XCTAssertEqual(region.pixelHeight, 100)
        XCTAssertEqual(region.sourceBounds, CanvasRect(x: 0, y: 0, width: 100, height: 50))

        // The eight-byte PNG signature. Cheap proof that this is really a PNG
        // and not, say, an empty Data that everything downstream would accept.
        XCTAssertEqual(
            Array(region.data.prefix(8)),
            [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        )
    }

    // Uniformly, so a fraction bar keeps its proportions. A squashed image
    // changes what the work means.
    func testTheLongEdgeCapPreservesAspectRatio() async throws {
        let region = try await rasterizer.rasterize(
            [stroke(from: CanvasPoint(x: 0, y: 0), to: CanvasPoint(x: 400, y: 100))],
            bounds: CanvasRect(x: 0, y: 0, width: 400, height: 100),
            scale: 4,
            maximumLongEdge: 800
        )

        XCTAssertEqual(region.pixelWidth, 800)
        XCTAssertEqual(region.pixelHeight, 200)
    }

    func testEmptyInputIsRefusedRatherThanRenderedBlank() async {
        do {
            _ = try await rasterizer.rasterize(
                [],
                bounds: CanvasRect(x: 0, y: 0, width: 10, height: 10),
                scale: 1,
                maximumLongEdge: 100
            )
            XCTFail("expected an error for an empty stroke list")
        } catch {
            // Expected.
        }
    }

    func testAnEmptyRegionIsRefused() async {
        do {
            _ = try await rasterizer.rasterize(
                [stroke(from: .zero, to: CanvasPoint(x: 1, y: 1))],
                bounds: .zero,
                scale: 1,
                maximumLongEdge: 100
            )
            XCTFail("expected an error for empty bounds")
        } catch {
            // Expected.
        }
    }

    // The real failure mode. Everything above this passes on a blank white
    // image; only this test notices that no ink was drawn.
    func testInkActuallyReachesThePixels() async throws {
        let inked = try await rasterizer.rasterize(
            [stroke(from: CanvasPoint(x: 5, y: 25), to: CanvasPoint(x: 95, y: 25), width: 8)],
            bounds: CanvasRect(x: 0, y: 0, width: 100, height: 50),
            scale: 1,
            maximumLongEdge: 500
        )

        let blank = try await rasterizer.rasterize(
            [stroke(from: CanvasPoint(x: 5, y: 25), to: CanvasPoint(x: 95, y: 25), width: 8, color: .white)],
            bounds: CanvasRect(x: 0, y: 0, width: 100, height: 50),
            scale: 1,
            maximumLongEdge: 500
        )

        XCTAssertNotEqual(inked.data, blank.data, "black ink on white produced the same bytes as white ink on white")
    }

    // Stroking a zero-length path draws nothing, so without the dot case the
    // decimal point in "3.14" silently disappears.
    func testASinglePointStrokeStillMarksThePage() async throws {
        let dot = InkStroke(
            points: [InkPoint.positionOnly(CanvasPoint(x: 25, y: 25), timeOffset: 0, width: 6)],
            style: .defaultPen,
            createdAt: FixedTimeSource.reference.now,
            hasPressure: false,
            hasTilt: false,
            lastModified: FixedTimeSource.reference.now
        )

        let drawn = try await rasterizer.rasterize(
            [dot],
            bounds: CanvasRect(x: 0, y: 0, width: 50, height: 50),
            scale: 1,
            maximumLongEdge: 500
        )

        let empty = try await rasterizer.rasterize(
            [InkStroke(
                points: [InkPoint.positionOnly(CanvasPoint(x: 25, y: 25), timeOffset: 0, width: 6)],
                style: InkStyle(kind: .pen, color: .white, width: 6),
                createdAt: FixedTimeSource.reference.now,
                hasPressure: false,
                hasTilt: false,
                lastModified: FixedTimeSource.reference.now
            )],
            bounds: CanvasRect(x: 0, y: 0, width: 50, height: 50),
            scale: 1,
            maximumLongEdge: 500
        )

        XCTAssertNotEqual(drawn.data, empty.data, "a single-point stroke rendered as nothing")
    }
}
