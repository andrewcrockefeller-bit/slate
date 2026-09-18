import UIKit
import SwiftUI

/// Three papers, no more. Adding a fourth requires a decision from Andrew —
/// see the "Slate design rules" block in CLAUDE.md.
enum PaperStyle: Int, CaseIterable {
    case plain
    case faintGrid
    case dotGrid

    var label: String {
        switch self {
        case .plain: return "Plain"
        case .faintGrid: return "Grid"
        case .dotGrid: return "Dots"
        }
    }

    var symbolName: String {
        switch self {
        case .plain: return "square"
        case .faintGrid: return "grid"
        case .dotGrid: return "circle.grid.2x2"
        }
    }
}

/// The canvas ground: 3% grain plus an optional ruling, generated once per
/// (style, color scheme) pair and cached as a tiled `UIColor`. Tiling through
/// `UIColor(patternImage:)` rather than a screen-space overlay means the
/// texture scrolls with canvas content — set as `PKCanvasView.backgroundColor`,
/// it paints in the view's own bounds, which move with `contentOffset`.
///
/// All three papers share this same ground color and grain; only the ruling
/// differs. No lined/ruled paper — see docs/DS-CONFLICTS.md and INK-2: ruled
/// lines belong to note-taking apps, not a working surface.
@MainActor
enum PaperBackground {
    /// Large enough that the grain reads as texture rather than an obviously
    /// repeating tile, and that ruling spacing looks natural at typical zoom.
    private static let tileSize: CGFloat = 256
    private static let gridSpacing: CGFloat = 32
    private static let dotSpacing: CGFloat = 32

    private struct CacheKey: Hashable {
        let style: PaperStyle
        let isDark: Bool
    }

    /// Generated once per key, never per frame — this is the whole point of
    /// caching rather than drawing the texture live.
    private static var cache: [CacheKey: UIColor] = [:]

    static func color(for style: PaperStyle, traitCollection: UITraitCollection) -> UIColor {
        let isDark = traitCollection.userInterfaceStyle == .dark
        let key = CacheKey(style: style, isDark: isDark)

        if let cached = cache[key] {
            return cached
        }

        let resolved = UIColor(patternImage: tileImage(for: style, traitCollection: traitCollection))
        cache[key] = resolved
        return resolved
    }

    private static func tileImage(for style: PaperStyle, traitCollection: UITraitCollection) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: tileSize, height: tileSize))

        // `performAsCurrent` returns Void — it just makes `traitCollection`
        // the one dynamic colors resolve against for the duration of the
        // closure, so the drawn image is captured into a local instead.
        var tile = UIImage()
        traitCollection.performAsCurrent {
            tile = renderer.image { context in
                UIColor(Palette.paper).setFill()
                context.fill(CGRect(x: 0, y: 0, width: tileSize, height: tileSize))

                drawGrain(in: context.cgContext)

                switch style {
                case .plain:
                    break
                case .faintGrid:
                    drawGrid(in: context.cgContext)
                case .dotGrid:
                    drawDots(in: context.cgContext)
                }
            }
        }
        return tile
    }

    /// 3% opacity noise, INK-1's acceptance: imperceptible when you look for
    /// it, missed when it's gone.
    private static func drawGrain(in context: CGContext) {
        context.saveGState()
        context.setAlpha(0.03)
        context.setFillColor(UIColor.black.cgColor)

        let dotCount = Int((tileSize * tileSize) / 6)
        for _ in 0..<dotCount {
            let x = CGFloat.random(in: 0..<tileSize)
            let y = CGFloat.random(in: 0..<tileSize)
            context.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }
        context.restoreGState()
    }

    private static func drawGrid(in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(UIColor(Palette.hairline).cgColor)
        context.setLineWidth(1)

        var x: CGFloat = 0
        while x <= tileSize {
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: tileSize))
            x += gridSpacing
        }
        var y: CGFloat = 0
        while y <= tileSize {
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: tileSize, y: y))
            y += gridSpacing
        }
        context.strokePath()
        context.restoreGState()
    }

    private static func drawDots(in context: CGContext) {
        context.saveGState()
        context.setFillColor(UIColor(Palette.hairline).cgColor)

        var y: CGFloat = dotSpacing / 2
        while y < tileSize {
            var x: CGFloat = dotSpacing / 2
            while x < tileSize {
                context.fillEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
                x += dotSpacing
            }
            y += dotSpacing
        }
        context.restoreGState()
    }
}
