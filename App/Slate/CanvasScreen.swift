import SwiftUI
import SlateCore

/// The canvas.
///
/// M1: ink capture. You draw with a Pencil, PencilKit renders it, and every
/// finished stroke is converted into the canonical `InkStroke` record that the
/// rest of the product is built on. Problem regions, persistence, and the tutor
/// loop arrive in later milestones; this screen deliberately contains no logic
/// beyond presenting what the controller reports.
struct CanvasScreen: View {
    let environment: AppEnvironment

    @StateObject private var controller: CanvasController

    init(environment: AppEnvironment) {
        self.environment = environment
        _controller = StateObject(
            wrappedValue: CanvasController(timeSource: environment.timeSource)
        )
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
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
        .background(.thinMaterial, in: Capsule())
    }

    /// Reports what the domain model actually captured, not what PencilKit
    /// drew. The two agreeing is the whole point of the milestone, and the
    /// cheapest way to see that they do is to print the domain's version.
    private var statusLine: some View {
        HStack(spacing: 10) {
            Text("SLATE")
                .font(.system(.caption, design: .monospaced).weight(.semibold))

            Text("M1")
                .font(.system(.caption2, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15), in: Capsule())

            Text(controller.lastCapture)
                .font(.system(.caption2, design: .monospaced))
                .lineLimit(1)

            Text(verbatim: environment.config.isValid ? "config ok" : "config INVALID")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(environment.config.isValid ? Color.secondary : Color.red)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
    }
}

#Preview("Canvas") {
    CanvasScreen(environment: .preview())
}
