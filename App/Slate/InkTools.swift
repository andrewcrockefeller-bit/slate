import PencilKit
import SwiftUI
import UIKit

/// Exactly four tools. Adding a fifth requires a decision from Andrew — see
/// the "Slate design rules" block in CLAUDE.md.
enum ToolKind: Int, CaseIterable {
    case fountainPen
    case pencil
    case highlighter
    case eraser

    var label: String {
        switch self {
        case .fountainPen: return "Fountain Pen"
        case .pencil: return "Pencil"
        case .highlighter: return "Highlighter"
        case .eraser: return "Eraser"
        }
    }

    var symbolName: String {
        switch self {
        case .fountainPen: return "pencil.tip"
        case .pencil: return "pencil"
        case .highlighter: return "highlighter"
        case .eraser: return "eraser"
        }
    }

    /// Fixed per tool — INK-4 allows no width slider beyond what the four
    /// tools themselves define.
    var width: CGFloat {
        switch self {
        case .fountainPen: return 3
        case .pencil: return 4
        case .highlighter: return 14
        case .eraser: return 0 // unused — PKEraserTool has no width.
        }
    }

    var usesInkPalette: Bool { self == .fountainPen || self == .pencil }
    var usesMarkerPalette: Bool { self == .highlighter }

    fileprivate var inkType: PKInkingTool.InkType? {
        switch self {
        case .fountainPen: return .fountainPen
        case .pencil: return .pencil
        case .highlighter: return .marker
        case .eraser: return nil
        }
    }
}

/// What's currently applied to the canvas: the tool plus, for the two
/// palette-driven tools, which swatch. Compared on every SwiftUI update so
/// `canvas.tool` is only reassigned when the selection actually changed —
/// reassigning it mid-stroke on an unrelated view update would be visible.
struct AppliedTool: Equatable {
    var kind: ToolKind
    var inkIndex: Int
    var markerIndex: Int
}

enum ToolSelection {
    /// Six inks (`Palette.inks`), three markers (`Palette.markers`), no color
    /// wheel, no eyedropper, no hex field — INK-4. Fountain pen and pencil
    /// map onto PencilKit's own `.fountainPen`/`.pencil` ink types, so
    /// pressure/tilt rendering stays exactly what M1 verified on device; only
    /// the picker chrome around them is new.
    static func pencilKitTool(for applied: AppliedTool) -> PKTool {
        guard let inkType = applied.kind.inkType else {
            return PKEraserTool(.vector)
        }

        let color: Color = applied.kind.usesMarkerPalette
            ? Palette.markers[applied.markerIndex]
            : Palette.inks[applied.inkIndex]

        return PKInkingTool(inkType, color: UIColor(color), width: applied.kind.width)
    }
}
