import Foundation
import SlateCore
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Draws normalized ink into a PNG the model can look at.
///
/// CoreGraphics and ImageIO rather than UIKit, because both exist on iOS and
/// macOS and neither pulls in a view hierarchy. `UIGraphicsImageRenderer` would
/// be shorter and would not compile on the Mac, which is where SlatePlatform's
/// tests run.
///
/// It renders from `InkStroke` — the normalized record — and never from
/// `PKDrawing`. Invariant 2 is not only about what is on disk: if the picture
/// the tutor reasons about comes out of an Apple type, then the Android port
/// inherits a tutor that sees something different from what this one sees.
public struct CoreGraphicsStrokeRasterizer: StrokeRasterizing {

    public enum RasterizerError: Error, CustomStringConvertible {
        case nothingToRender
        case contextUnavailable
        case encodingFailed

        public var description: String {
            switch self {
            case .nothingToRender: return "there is no ink in that region"
            case .contextUnavailable: return "could not create a bitmap context"
            case .encodingFailed: return "could not encode the region as PNG"
            }
        }
    }

    /// The background the work is drawn onto.
    ///
    /// Opaque white, always. A transparent PNG composites against whatever the
    /// receiving service happens to use, and black ink on a black background is
    /// a blank image that costs a request to discover.
    public var backgroundIsOpaqueWhite: Bool

    public init(backgroundIsOpaqueWhite: Bool = true) {
        self.backgroundIsOpaqueWhite = backgroundIsOpaqueWhite
    }

    public func rasterize(
        _ strokes: [InkStroke],
        bounds: CanvasRect,
        scale: Double,
        maximumLongEdge: Int
    ) async throws -> RasterizedRegion {

        guard !strokes.isEmpty, !bounds.isEmpty else {
            throw RasterizerError.nothingToRender
        }

        // Requested scale, then reduced uniformly if it would exceed the long
        // edge cap. Uniformly, so the aspect ratio the student sees is the
        // aspect ratio the model sees — a squashed image changes what a
        // fraction bar looks like.
        let longestSide = max(bounds.size.width, bounds.size.height)
        let cappedScale = longestSide > 0
            ? min(scale, Double(maximumLongEdge) / longestSide)
            : scale
        let effectiveScale = max(0.01, cappedScale)

        let pixelWidth = max(1, Int((bounds.size.width * effectiveScale).rounded()))
        let pixelHeight = max(1, Int((bounds.size.height * effectiveScale).rounded()))

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw RasterizerError.contextUnavailable
        }

        if backgroundIsOpaqueWhite {
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        }

        // Canvas coordinates run y-down, as every pen-input API on every
        // platform reports them. A bitmap context runs y-up. Flipping once here
        // is cheaper and far less error-prone than negating a y somewhere in the
        // geometry code, which would then be wrong for everything else.
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: CGFloat(effectiveScale), y: CGFloat(-effectiveScale))
        context.translateBy(x: CGFloat(-bounds.minX), y: CGFloat(-bounds.minY))

        context.setLineCap(.round)
        context.setLineJoin(.round)

        for stroke in strokes {
            draw(stroke, into: context)
        }

        guard let image = context.makeImage() else {
            throw RasterizerError.encodingFailed
        }

        return RasterizedRegion(
            data: try Self.png(from: image),
            mediaType: "image/png",
            sourceBounds: bounds,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )
    }

    // MARK: - Drawing

    private func draw(_ stroke: InkStroke, into context: CGContext) {
        guard let first = stroke.points.first else { return }

        let colour = stroke.style.color.clamped
        context.setStrokeColor(CGColor(
            srgbRed: CGFloat(colour.red),
            green: CGFloat(colour.green),
            blue: CGFloat(colour.blue),
            alpha: CGFloat(colour.alpha)
        ))

        // Highlighter marks composite so that overlapping passes do not darken
        // without limit, which is what a real highlighter does and what the
        // student will expect the picture to show.
        context.setBlendMode(stroke.style.kind == .highlighter ? .multiply : .normal)

        // One width for the whole stroke, taken as the mean of its points.
        // Stroking each segment at its own width would be more faithful and
        // leaves visible seams at the joins; at the resolution a model reads,
        // the seams are more misleading than the constant width is.
        let widths = stroke.points.map(\.width).filter { $0 > 0 }
        let width = widths.isEmpty
            ? stroke.style.width
            : widths.reduce(0, +) / Double(widths.count)
        context.setLineWidth(CGFloat(max(0.1, width)))

        // A single-point stroke is a dot. Stroking a zero-length path draws
        // nothing at all, so the decimal point in "3.14" would silently vanish.
        if stroke.points.count == 1 || stroke.isDot {
            context.setFillColor(CGColor(
                srgbRed: CGFloat(colour.red),
                green: CGFloat(colour.green),
                blue: CGFloat(colour.blue),
                alpha: CGFloat(colour.alpha)
            ))
            let radius = CGFloat(max(0.1, width) / 2)
            context.fillEllipse(in: CGRect(
                x: CGFloat(first.position.x) - radius,
                y: CGFloat(first.position.y) - radius,
                width: radius * 2,
                height: radius * 2
            ))
            return
        }

        context.beginPath()
        context.move(to: CGPoint(x: first.position.x, y: first.position.y))
        for point in stroke.points.dropFirst() {
            context.addLine(to: CGPoint(x: point.position.x, y: point.position.y))
        }
        context.strokePath()
    }

    // MARK: - Encoding

    private static func png(from image: CGImage) throws -> Data {
        let data = NSMutableData()

        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw RasterizerError.encodingFailed
        }

        CGImageDestinationAddImage(destination, image, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw RasterizerError.encodingFailed
        }

        return data as Data
    }
}
