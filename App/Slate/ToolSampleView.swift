import SwiftUI

/// A live rendered stroke, not an icon of a pen — UI-2. Each of the four
/// tool buttons draws an actual sample of what that tool currently makes:
/// fountain pen and pencil in the selected ink, highlighter in the selected
/// marker. Redraws whenever `color` changes, which is how INK-4's palette
/// selection is reflected here without this view knowing about `ToolKind`
/// beyond picking a drawing style.
struct ToolSampleView: View {
    let kind: ToolKind
    let color: Color

    var body: some View {
        Canvas { context, size in
            switch kind {
            case .fountainPen:
                drawFountainPen(in: &context, size: size)
            case .pencil:
                drawPencil(in: &context, size: size)
            case .highlighter:
                drawHighlighter(in: &context, size: size)
            case .eraser:
                drawEraser(in: &context, size: size)
            }
        }
        .frame(width: 34, height: 22)
    }

    /// A smooth, continuous curve that tapers at both ends — approximated by
    /// stroking the same path three times at decreasing width, since Canvas
    /// has no single-stroke variable-width primitive.
    private func drawFountainPen(in context: inout GraphicsContext, size: CGSize) {
        let path = wave(in: size)
        for (widthFraction, opacity) in [(1.0, 0.35), (0.6, 0.6), (0.3, 1.0)] {
            context.stroke(
                path,
                with: .color(color.opacity(opacity)),
                style: StrokeStyle(lineWidth: 3.4 * widthFraction, lineCap: .round, lineJoin: .round)
            )
        }
    }

    /// Constant width, dashed rather than solid, and slightly translucent —
    /// reads as matte graphite rather than wet ink at this size.
    private func drawPencil(in context: inout GraphicsContext, size: CGSize) {
        let path = wave(in: size)
        context.stroke(
            path,
            with: .color(color.opacity(0.8)),
            style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round, dash: [0.5, 1.4])
        )
    }

    /// A flat translucent swipe — the shape a highlighter actually makes,
    /// not a line.
    private func drawHighlighter(in context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(x: 2, y: size.height * 0.32, width: size.width - 4, height: size.height * 0.42)
        context.fill(RoundedRectangle(cornerRadius: 3).path(in: rect), with: .color(color.opacity(0.55)))
    }

    /// No ink color applies to erasing, so the sample is a faded stroke
    /// fragment being lifted — composition, not a glyph, per UI-2's "no
    /// glyph-only tool buttons."
    private func drawEraser(in context: inout GraphicsContext, size: CGSize) {
        var fadingPath = wave(in: size)
        fadingPath = fadingPath.trimmedPath(from: 0, to: 0.62)
        context.stroke(
            fadingPath,
            with: .color(Palette.inkFaint.opacity(0.5)),
            style: StrokeStyle(lineWidth: 2.6, lineCap: .round)
        )

        let eraserRect = CGRect(x: size.width * 0.58, y: size.height * 0.32, width: size.width * 0.34, height: size.height * 0.36)
        context.fill(RoundedRectangle(cornerRadius: 2.5).path(in: eraserRect), with: .color(Palette.hairline))
    }

    private func wave(in size: CGSize) -> Path {
        Path { path in
            let midY = size.height * 0.55
            path.move(to: CGPoint(x: 2, y: midY + 4))
            path.addCurve(
                to: CGPoint(x: size.width - 2, y: midY - 4),
                control1: CGPoint(x: size.width * 0.3, y: midY - 8),
                control2: CGPoint(x: size.width * 0.7, y: midY + 8)
            )
        }
    }
}
