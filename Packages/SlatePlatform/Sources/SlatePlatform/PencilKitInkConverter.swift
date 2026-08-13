import Foundation
import PencilKit
import SlateCore

#if canImport(UIKit)
import UIKit
/// The host platform's colour type.
///
/// PencilKit's model types — `PKStroke`, `PKInk`, `PKDrawing`, `PKStrokePath` —
/// exist on macOS as well as iOS, but `PKInk.color` is `UIColor` on iOS and
/// `NSColor` on macOS. Aliasing lets one converter serve both, which matters
/// for a reason beyond the eventual Mac port: `swift test` on a Mac builds this
/// package **for macOS**, so a UIKit-only adapter cannot be tested without
/// going through xcodebuild and an iOS destination. Keeping the fast test loop
/// is worth two conditional branches.
public typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
public typealias PlatformColor = NSColor
#endif

/// Translates between PencilKit's stroke representation and the domain's.
///
/// This is the entire Apple-specific surface of ink capture. Everything above
/// it works in `InkStroke`; everything below it is PencilKit's business. When
/// the Android port arrives, this file has a sibling and nothing else changes.
///
/// Both directions are implemented deliberately. Capture alone would be enough
/// to draw on screen, because `PKCanvasView` renders from its own `PKDrawing`.
/// But if the domain model cannot rebuild a drawing, then the domain model is
/// lossy and `PKDrawing` is secretly the source of truth — a direct violation
/// of Invariant 2 that would stay invisible until persistence landed and
/// reopened documents looked wrong. Round-tripping now is how we find out
/// while it is still cheap to fix.
public struct PencilKitInkConverter: Sendable {

    /// Values that map PencilKit's units onto the domain's.
    ///
    /// Separated out because at least one of them is a guess that needs
    /// checking against a real Pencil on real hardware.
    public struct Calibration: Hashable, Sendable {

        /// The force value corresponding to full pressure.
        ///
        /// PencilKit does not document the range of `PKStrokePoint.force`, and
        /// the domain contract for `InkPoint.pressure` is 0...1. If pressure
        /// response looks wrong on device — taper too aggressive, or absent —
        /// this is the dial, and the fix is to measure a hard press and set
        /// this to what it actually reports.
        public var maximumForce: Double

        /// Canvas units per PencilKit point.
        ///
        /// 1.0 while the canvas is not zoomable in its own right. Kept explicit
        /// so that the day canvas coordinates stop being screen points, there
        /// is one place to change rather than a hunt.
        public var canvasScale: Double

        public init(maximumForce: Double = 1.0, canvasScale: Double = 1.0) {
            self.maximumForce = maximumForce
            self.canvasScale = canvasScale
        }

        public static let `default` = Calibration()
    }

    public var calibration: Calibration

    public init(calibration: Calibration = .default) {
        self.calibration = calibration
    }

    // MARK: - PencilKit to domain

    /// Converts a PencilKit stroke into the canonical representation.
    ///
    /// The stroke's affine transform is baked into the point coordinates rather
    /// than carried alongside them. A stroke whose positions are only correct
    /// once some other field is applied is an implicit coupling that will not
    /// survive being read by a different renderer on a different platform.
    public func inkStroke(
        from stroke: PKStroke,
        lastModified: Date,
        owner: OwnerID = .localDefault
    ) -> InkStroke {
        // Iterating a PKStrokePath yields its B-spline control points. Those
        // are what PencilKit itself stores, which makes them the closest thing
        // to a raw capture available; the on-curve points from
        // interpolatedPoints(in:by:) are derived from them and can be
        // recomputed at any time.
        let rawPoints: [InkPoint] = stroke.path.map { point in
            InkPoint(
                position: CanvasPoint(
                    x: Double(point.location.x) * calibration.canvasScale,
                    y: Double(point.location.y) * calibration.canvasScale
                ),
                timeOffset: point.timeOffset,
                pressure: normalizedPressure(Double(point.force)),
                azimuth: Double(point.azimuth),
                altitude: Double(point.altitude),
                width: Double(point.size.width) * calibration.canvasScale
            )
        }

        let capabilities = InkStroke.inferredCapabilities(from: rawPoints)

        let untransformed = InkStroke(
            points: rawPoints,
            style: inkStyle(from: stroke.ink, points: rawPoints),
            createdAt: stroke.path.creationDate,
            hasPressure: capabilities.hasPressure,
            hasTilt: capabilities.hasTilt,
            lastModified: lastModified,
            owner: owner
        )

        return untransformed.transformed(by: canvasTransform(from: stroke.transform))
    }

    /// Converts every stroke in a drawing.
    public func inkStrokes(
        from drawing: PKDrawing,
        lastModified: Date,
        owner: OwnerID = .localDefault
    ) -> [InkStroke] {
        drawing.strokes.map { inkStroke(from: $0, lastModified: lastModified, owner: owner) }
    }

    // MARK: - Domain to PencilKit

    /// Rebuilds a PencilKit stroke from the canonical representation.
    ///
    /// Known lossy field: `PKStrokePoint.opacity` is written as 1 because the
    /// domain does not carry per-point opacity — stroke-level translucency
    /// lives in the ink colour's alpha instead. If a round-tripped highlighter
    /// ever looks visibly different from the original, this is why, and the fix
    /// is to add the channel to `InkPoint` rather than to special-case it here.
    public func pkStroke(from stroke: InkStroke) -> PKStroke {
        let controlPoints = stroke.points.map { point in
            PKStrokePoint(
                location: CGPoint(
                    x: point.position.x / calibration.canvasScale,
                    y: point.position.y / calibration.canvasScale
                ),
                timeOffset: point.timeOffset,
                size: CGSize(
                    width: point.width / calibration.canvasScale,
                    height: point.width / calibration.canvasScale
                ),
                opacity: 1,
                force: CGFloat(point.pressure * calibration.maximumForce),
                azimuth: CGFloat(point.azimuth),
                altitude: CGFloat(point.altitude)
            )
        }

        let path = PKStrokePath(
            controlPoints: controlPoints,
            creationDate: stroke.createdAt
        )

        // Identity transform: the domain already baked any transform into the
        // point coordinates on the way in.
        return PKStroke(
            ink: pkInk(from: stroke.style),
            path: path,
            transform: .identity,
            mask: nil
        )
    }

    /// Rebuilds a drawing from canonical strokes.
    public func pkDrawing(from strokes: [InkStroke]) -> PKDrawing {
        PKDrawing(strokes: strokes.map(pkStroke(from:)))
    }

    // MARK: - Style

    private func inkStyle(from ink: PKInk, points: [InkPoint]) -> InkStyle {
        // PKInk carries no nominal width — width lives per point, modulated by
        // pressure. The average is the most representative single number, and
        // it is only ever used as a fallback for renderers that cannot vary
        // width along a stroke.
        let nominalWidth: Double
        if points.isEmpty {
            nominalWidth = InkStyle.defaultPen.width
        } else {
            nominalWidth = points.reduce(0) { $0 + $1.width } / Double(points.count)
        }

        return InkStyle(
            kind: inkKind(from: ink.inkType),
            color: inkColor(from: ink.color),
            width: nominalWidth
        )
    }

    /// Maps PencilKit's ink type onto the domain's closed set.
    ///
    /// Written as equality comparisons with a fallback rather than an
    /// exhaustive switch on purpose. `PKInk.InkType` is a type alias for
    /// `PKInkingTool.InkType`, whose members have grown across releases
    /// (monoline, fountain pen, watercolor, crayon). An exhaustive switch would
    /// stop compiling on a future SDK, and pinning the domain's vocabulary to
    /// Apple's would break Invariant 5 the moment a platform without a
    /// "watercolor" had to open the document.
    ///
    /// Anything unrecognised becomes a pen: an unfamiliar mark still renders as
    /// a mark, which is the correct failure.
    private func inkKind(from inkType: PKInk.InkType) -> InkKind {
        if inkType == .pencil { return .pencil }
        if inkType == .marker { return .marker }
        if inkType == .pen { return .pen }
        return .pen
    }

    private func pkInk(from style: InkStyle) -> PKInk {
        let type: PKInk.InkType
        switch style.kind {
        case .pen:
            type = .pen
        case .pencil:
            type = .pencil
        case .marker, .highlighter:
            // The domain distinguishes a broad translucent marker from a
            // highlighter wash; PencilKit renders both with .marker. The
            // distinction survives in the document and is honoured by
            // renderers that can express it.
            type = .marker
        }

        return PKInk(type, color: platformColor(from: style.color))
    }

    // MARK: - Primitives

    private func normalizedPressure(_ force: Double) -> Double {
        guard calibration.maximumForce > 0 else { return 1 }
        return min(1, max(0, force / calibration.maximumForce))
    }

    private func canvasTransform(from transform: CGAffineTransform) -> CanvasTransform {
        CanvasTransform(
            a: Double(transform.a),
            b: Double(transform.b),
            c: Double(transform.c),
            d: Double(transform.d),
            tx: Double(transform.tx),
            ty: Double(transform.ty)
        )
    }

    private func inkColor(from color: PlatformColor) -> InkColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0

        #if canImport(UIKit)
        // Returns false for colours not expressible in RGBA — pattern colours,
        // and some system colours before resolution against a trait collection.
        // Opaque black is a visible, obviously-wrong fallback rather than a
        // silent one.
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return .black
        }
        #elseif canImport(AppKit)
        // NSColor's getRed does not report failure — it traps if the receiver
        // is not in an RGB colour space. Converting first is mandatory, not
        // defensive.
        guard let rgb = color.usingColorSpace(.sRGB) else { return .black }
        rgb.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #endif

        return InkColor(
            red: Double(red),
            green: Double(green),
            blue: Double(blue),
            alpha: Double(alpha)
        )
    }

    private func platformColor(from color: InkColor) -> PlatformColor {
        #if canImport(UIKit)
        return UIColor(
            red: CGFloat(color.red),
            green: CGFloat(color.green),
            blue: CGFloat(color.blue),
            alpha: CGFloat(color.alpha)
        )
        #elseif canImport(AppKit)
        // srgbRed rather than the deviceRGB initializer, so that a colour
        // round-trips through the same colour space it was read in.
        return NSColor(
            srgbRed: CGFloat(color.red),
            green: CGFloat(color.green),
            blue: CGFloat(color.blue),
            alpha: CGFloat(color.alpha)
        )
        #endif
    }
}
