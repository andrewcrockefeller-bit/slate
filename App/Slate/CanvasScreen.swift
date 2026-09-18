import SwiftUI
import SlateCore

/// The canvas.
///
/// M2: ink capture and persistence. Strokes are converted into the canonical
/// document, every change is written as an ordered operation, and the document
/// is reloaded on launch. Problem regions and the tutor loop arrive later; this
/// screen deliberately contains no logic beyond presenting what the controller
/// reports.
struct CanvasScreen: View {
    let environment: AppEnvironment

    @StateObject private var controller: CanvasController
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(environment: AppEnvironment) {
        self.environment = environment
        _controller = StateObject(
            wrappedValue: CanvasController(
                repository: environment.documents,
                timeSource: environment.timeSource
            )
        )
    }

    var body: some View {
        // Status line top-left, not bottom-left.
        //
        // PKToolPicker docks along the bottom edge on iPad and sits above the
        // app's own content, so anything placed bottom-leading is hidden behind
        // the palette exactly when the canvas is in use. Found by running it,
        // not by reading it.
        ZStack(alignment: .topLeading) {
            InkCanvasView(controller: controller)
                .ignoresSafeArea()

            statusLine
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .overlay(alignment: .topTrailing) {
            editingControls
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .task {
            await controller.start()
        }
    }

    private var editingControls: some View {
        HStack(spacing: 16) {
            Button {
                controller.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }

            Button {
                controller.redo()
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }

            Button(role: .destructive) {
                controller.clear()
            } label: {
                Label("Clear", systemImage: "trash")
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        // The app's one Liquid Glass surface — see docs/DS-CONFLICTS.md, C-1.
        // Regular variant only, never Clear, and nothing else in the app may
        // be translucent. Falls back to an opaque Palette.surface capsule
        // both under Reduce Transparency and on OS versions before Liquid
        // Glass existed.
        .modifier(GlassToolbarSurface(reduceTransparency: reduceTransparency))
    }

    /// The one allowed translucent surface in the app. Everywhere else is
    /// opaque — see the "Slate design rules" block in CLAUDE.md.
    private struct GlassToolbarSurface: ViewModifier {
        let reduceTransparency: Bool

        func body(content: Content) -> some View {
            if #available(iOS 26.0, *), !reduceTransparency {
                content.glassEffect(.regular, in: Capsule())
            } else {
                content.background(Palette.surface, in: Capsule())
            }
        }
    }

    /// Reports what the domain model captured and whether it reached disk —
    /// not what PencilKit drew. The two agreeing is the point of the milestone,
    /// and the cheapest way to see that they do is to print the domain's view.
    private var statusLine: some View {
        HStack(spacing: 10) {
            Text("SLATE")
                .font(.system(.caption, design: .monospaced).weight(.semibold))

            Text("M2")
                .font(.system(.caption2, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Palette.hairline, in: Capsule())

            Text(controller.lastCapture)
                .font(.system(.caption2, design: .monospaced))
                .lineLimit(1)

            saveIndicator
        }
        .foregroundStyle(Palette.inkSoft)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        // Opaque — only the floating canvas toolbar (editingControls) is
        // translucent. See docs/DS-CONFLICTS.md, C-1.
        .background(Palette.surface, in: Capsule())
    }

    @ViewBuilder
    private var saveIndicator: some View {
        switch controller.saveState {
        case .loading:
            Text("opening…")
                .font(.system(.caption2, design: .monospaced))
        case .ready:
            Text("ready")
                .font(.system(.caption2, design: .monospaced))
        case .saving:
            Text("saving…")
                .font(.system(.caption2, design: .monospaced))
        case .saved:
            Text("saved")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Palette.inkSoft)
        case .failed(let reason):
            // Loud on purpose. A failed write with a calm status line is how a
            // student loses an hour of work without noticing.
            Text("SAVE FAILED: \(reason)")
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .foregroundStyle(Palette.alert)
                .lineLimit(1)
        }
    }
}

#Preview("Canvas") {
    CanvasScreen(environment: .preview())
}
