import XCTest
@testable import SlateCore

final class CanvasGeometryTests: XCTestCase {

    func testDistanceIsEuclidean() {
        let a = CanvasPoint(x: 0, y: 0)
        let b = CanvasPoint(x: 3, y: 4)
        XCTAssertEqual(a.distance(to: b), 5, accuracy: 1e-12)
    }

    func testBoundingOfNoPointsIsZero() {
        XCTAssertEqual(CanvasRect.bounding([CanvasPoint]()), .zero)
    }

    func testBoundingOfOnePointIsDegenerate() {
        let rect = CanvasRect.bounding([CanvasPoint(x: 5, y: -2)])
        XCTAssertEqual(rect.origin, CanvasPoint(x: 5, y: -2))
        XCTAssertEqual(rect.size, .zero)
    }

    // Canvas coordinates are unbounded in both directions. A bounds
    // computation that assumes non-negative coordinates works fine until
    // someone scrolls up and left of where they started, which on an infinite
    // canvas is immediately.
    func testBoundingHandlesNegativeCoordinates() {
        let rect = CanvasRect.bounding([
            CanvasPoint(x: -10, y: -20),
            CanvasPoint(x: -2, y: -5)
        ])
        XCTAssertEqual(rect.minX, -10)
        XCTAssertEqual(rect.minY, -20)
        XCTAssertEqual(rect.maxX, -2)
        XCTAssertEqual(rect.maxY, -5)
    }

    func testUnionTreatsEmptyAsAbsentRatherThanAsARectAtTheOrigin() {
        let far = CanvasRect(x: 100, y: 100, width: 10, height: 10)
        XCTAssertEqual(CanvasRect.zero.union(far), far)
        XCTAssertEqual(far.union(.zero), far)
    }

    func testUnionCoversBoth() {
        let a = CanvasRect(x: 0, y: 0, width: 10, height: 10)
        let b = CanvasRect(x: 20, y: -5, width: 5, height: 5)
        let u = a.union(b)
        XCTAssertEqual(u.minX, 0)
        XCTAssertEqual(u.minY, -5)
        XCTAssertEqual(u.maxX, 25)
        XCTAssertEqual(u.maxY, 10)
    }

    func testExpandedGrowsOnAllSides() {
        let rect = CanvasRect(x: 10, y: 10, width: 10, height: 10).expanded(by: 2)
        XCTAssertEqual(rect.minX, 8)
        XCTAssertEqual(rect.minY, 8)
        XCTAssertEqual(rect.maxX, 22)
        XCTAssertEqual(rect.maxY, 22)
    }

    func testContainsIncludesTheBoundary() {
        let rect = CanvasRect(x: 0, y: 0, width: 10, height: 10)
        XCTAssertTrue(rect.contains(CanvasPoint(x: 0, y: 0)))
        XCTAssertTrue(rect.contains(CanvasPoint(x: 10, y: 10)))
        XCTAssertFalse(rect.contains(CanvasPoint(x: 10.001, y: 5)))
    }

    func testIntersectsIsSymmetricAndExcludesSeparated() {
        let a = CanvasRect(x: 0, y: 0, width: 10, height: 10)
        let b = CanvasRect(x: 5, y: 5, width: 10, height: 10)
        let far = CanvasRect(x: 100, y: 100, width: 1, height: 1)

        XCTAssertTrue(a.intersects(b))
        XCTAssertTrue(b.intersects(a))
        XCTAssertFalse(a.intersects(far))
        XCTAssertFalse(far.intersects(a))
    }
}

final class CanvasTransformTests: XCTestCase {

    func testIdentityLeavesPointsAlone() {
        let point = CanvasPoint(x: 3, y: 7)
        XCTAssertEqual(CanvasTransform.identity.apply(to: point), point)
        XCTAssertTrue(CanvasTransform.identity.isIdentity)
    }

    func testTranslation() {
        let moved = CanvasTransform.translation(x: 10, y: -5)
            .apply(to: CanvasPoint(x: 1, y: 1))
        XCTAssertEqual(moved, CanvasPoint(x: 11, y: -4))
    }

    func testScale() {
        let scaled = CanvasTransform.scale(x: 2, y: 3)
            .apply(to: CanvasPoint(x: 4, y: 5))
        XCTAssertEqual(scaled, CanvasPoint(x: 8, y: 15))
    }

    // Component order matches CGAffineTransform so Layer 2's conversion is
    // field-for-field. Getting b and c the wrong way round produces a
    // transposed transform that is correct for pure scales and translations
    // and wrong for everything else — which is to say, it looks fine until it
    // suddenly doesn't.
    func testRotationMatchesTheStandardComponentOrder() {
        // 90° counter-clockwise: a=0, b=1, c=-1, d=0
        let rotate = CanvasTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0)
        let rotated = rotate.apply(to: CanvasPoint(x: 1, y: 0))

        XCTAssertEqual(rotated.x, 0, accuracy: 1e-12)
        XCTAssertEqual(rotated.y, 1, accuracy: 1e-12)
    }

    func testUniformScaleOfIdentityIsOne() {
        XCTAssertEqual(CanvasTransform.identity.uniformScale, 1, accuracy: 1e-12)
    }

    func testUniformScaleOfAUniformScale() {
        XCTAssertEqual(CanvasTransform.scale(x: 3, y: 3).uniformScale, 3, accuracy: 1e-12)
    }

    func testUniformScaleIgnoresTranslation() {
        XCTAssertEqual(CanvasTransform.translation(x: 100, y: 100).uniformScale, 1, accuracy: 1e-12)
    }

    // A mirroring transform has a negative determinant. Taking the square root
    // without the absolute value produces NaN, which then propagates silently
    // into every stroke width in the document.
    func testUniformScaleOfAMirrorIsPositive() {
        let mirrored = CanvasTransform(a: -2, b: 0, c: 0, d: 2, tx: 0, ty: 0)
        XCTAssertEqual(mirrored.uniformScale, 2, accuracy: 1e-12)
        XCTAssertFalse(mirrored.uniformScale.isNaN)
    }
}
