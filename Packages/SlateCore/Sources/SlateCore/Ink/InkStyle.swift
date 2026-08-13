import Foundation

/// A colour, stored as extended-range sRGB components.
///
/// Not `UIColor`, not `Color`, not `CGColor`. Those are Apple types, and a
/// colour is part of the stroke record — if the only copy of what colour the
/// user drew in lives in a `UIColor`, the document is not portable.
///
/// Components are allowed outside 0...1 because wide-gamut displays produce
/// them and clamping at capture time would silently discard colour the user
/// actually picked.
public struct InkColor: Hashable, Sendable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let black = InkColor(red: 0, green: 0, blue: 0)
    public static let white = InkColor(red: 1, green: 1, blue: 1)

    /// Components clamped to 0...1, for renderers that cannot express
    /// extended range.
    public var clamped: InkColor {
        func clamp(_ value: Double) -> Double { Swift.min(1, Swift.max(0, value)) }
        return InkColor(red: clamp(red), green: clamp(green), blue: clamp(blue), alpha: clamp(alpha))
    }
}

/// The kind of mark a stroke makes.
///
/// A closed set on purpose. Every platform this app will ever run on has some
/// notion of a pen and a highlighter, and the renderer on each platform maps
/// these to whatever it has. Storing the platform's own tool identifier instead
/// would make a document drawn on iPad unopenable on Android.
///
/// `String` raw values rather than integers so that a persisted document
/// remains readable when a case is added or reordered.
public enum InkKind: String, Hashable, Sendable, Codable, CaseIterable {
    /// A firm, opaque, pressure-sensitive line. The default for working
    /// problems.
    case pen

    /// A softer line that responds to tilt as well as pressure.
    case pencil

    /// A broad, translucent line that composites so overlapping marks do not
    /// darken indefinitely.
    case marker

    /// Translucent wash for emphasis, drawn behind or blended with other ink.
    case highlighter

    /// Whether marks of this kind are translucent by nature. Affects both
    /// rendering and, later, whether the tutor treats the mark as work or as
    /// annotation.
    public var isTranslucent: Bool {
        switch self {
        case .pen, .pencil: return false
        case .marker, .highlighter: return true
        }
    }
}

/// Everything about how a stroke should look, independent of its geometry.
public struct InkStyle: Hashable, Sendable, Codable {
    public var kind: InkKind
    public var color: InkColor

    /// The nominal width of the stroke in canvas units, before per-point
    /// pressure modulation.
    public var width: Double

    public init(kind: InkKind, color: InkColor, width: Double) {
        self.kind = kind
        self.color = color
        self.width = width
    }

    /// The default writing tool.
    public static let defaultPen = InkStyle(kind: .pen, color: .black, width: 3)

    /// Returns a copy with the width scaled, for applying a stroke transform.
    public func scaled(by factor: Double) -> InkStyle {
        InkStyle(kind: kind, color: color, width: width * factor)
    }
}
