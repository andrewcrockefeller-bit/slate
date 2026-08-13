import Foundation

// Geometry primitives for the domain core.
//
// These exist because CGPoint, CGRect, and CGAffineTransform do not: they come
// from CoreGraphics, which is Apple-only, and using them here would put the
// canonical shape of every stroke a user has ever drawn behind a framework that
// does not exist on Android or Windows. Layer 2 converts at the boundary.
//
// Everything is Double rather than CGFloat for the same reason — CGFloat is a
// CoreGraphics typealias whose width varies by architecture.

/// A point in canvas coordinates.
///
/// Canvas coordinates are device-independent and unbounded in both directions.
/// They are not pixels, not points-at-2x, and not screen-relative; a stroke has
/// the same coordinates whether it was drawn on a 11" iPad or a 27" monitor.
public struct CanvasPoint: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = CanvasPoint(x: 0, y: 0)

    /// Straight-line distance to another point.
    public func distance(to other: CanvasPoint) -> Double {
        let dx = other.x - x
        let dy = other.y - y
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// A width and height in canvas units. May be zero; may not be negative in
/// practice, though nothing enforces that at the type level.
public struct CanvasSize: Hashable, Sendable, Codable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public static let zero = CanvasSize(width: 0, height: 0)
}

/// An axis-aligned rectangle in canvas coordinates.
public struct CanvasRect: Hashable, Sendable, Codable {
    public var origin: CanvasPoint
    public var size: CanvasSize

    public init(origin: CanvasPoint, size: CanvasSize) {
        self.origin = origin
        self.size = size
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(origin: CanvasPoint(x: x, y: y),
                  size: CanvasSize(width: width, height: height))
    }

    public static let zero = CanvasRect(origin: .zero, size: .zero)

    public var minX: Double { origin.x }
    public var minY: Double { origin.y }
    public var maxX: Double { origin.x + size.width }
    public var maxY: Double { origin.y + size.height }

    public var isEmpty: Bool { size.width <= 0 || size.height <= 0 }

    public func contains(_ point: CanvasPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }

    public func intersects(_ other: CanvasRect) -> Bool {
        !(other.minX > maxX || other.maxX < minX || other.minY > maxY || other.maxY < minY)
    }

    /// The smallest rectangle containing both. An empty rectangle is treated as
    /// absent rather than as a degenerate rectangle at the origin, so that
    /// folding over a sequence starting from `.zero` does not drag every bounds
    /// computation back to include the origin.
    public func union(_ other: CanvasRect) -> CanvasRect {
        if isEmpty { return other }
        if other.isEmpty { return self }
        let x0 = Swift.min(minX, other.minX)
        let y0 = Swift.min(minY, other.minY)
        let x1 = Swift.max(maxX, other.maxX)
        let y1 = Swift.max(maxY, other.maxY)
        return CanvasRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// Grows the rectangle by `amount` on every side.
    public func expanded(by amount: Double) -> CanvasRect {
        CanvasRect(x: minX - amount,
                   y: minY - amount,
                   width: size.width + amount * 2,
                   height: size.height + amount * 2)
    }

    /// The tightest rectangle containing every given point, or `.zero` if there
    /// are none.
    public static func bounding(_ points: some Sequence<CanvasPoint>) -> CanvasRect {
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        var seen = false

        for point in points {
            seen = true
            minX = Swift.min(minX, point.x)
            minY = Swift.min(minY, point.y)
            maxX = Swift.max(maxX, point.x)
            maxY = Swift.max(maxY, point.y)
        }

        guard seen else { return .zero }
        return CanvasRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// A 2D affine transform, in the same component order as every other affine
/// transform in graphics:
///
///     | a  b  0 |
///     | c  d  0 |
///     | tx ty 1 |
///
/// Layer 2 maps this to and from `CGAffineTransform`, whose fields have the
/// same names and the same meaning, so the conversion is field-for-field.
public struct CanvasTransform: Hashable, Sendable, Codable {
    public var a: Double
    public var b: Double
    public var c: Double
    public var d: Double
    public var tx: Double
    public var ty: Double

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    public static let identity = CanvasTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    public static func translation(x: Double, y: Double) -> CanvasTransform {
        CanvasTransform(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y)
    }

    public static func scale(x: Double, y: Double) -> CanvasTransform {
        CanvasTransform(a: x, b: 0, c: 0, d: y, tx: 0, ty: 0)
    }

    public var isIdentity: Bool { self == .identity }

    /// Applies the transform to a point.
    public func apply(to point: CanvasPoint) -> CanvasPoint {
        CanvasPoint(
            x: a * point.x + c * point.y + tx,
            y: b * point.x + d * point.y + ty
        )
    }

    /// The uniform scale factor this transform applies, taken as the square
    /// root of the absolute determinant.
    ///
    /// Used to scale stroke widths, which are scalars and cannot be transformed
    /// as points. For a non-uniform or skewed transform this is an
    /// approximation — an acceptable one, because PencilKit stroke transforms
    /// in practice are translations and uniform scales, and a visibly wrong
    /// width under extreme shear is a cosmetic problem rather than a data one.
    public var uniformScale: Double {
        let determinant = a * d - b * c
        return abs(determinant).squareRoot()
    }
}
