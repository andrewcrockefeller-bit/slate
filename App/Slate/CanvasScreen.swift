import SwiftUI
import SlateCore

/// The canvas.
///
/// Empty at M0 by design — this milestone proves the three-layer wiring and the
/// Linux CI, nothing else. Ink capture arrives in M1, and when it does it comes
/// in as a `UIViewRepresentable` living in Layer 2 that this screen presents.
/// No drawing logic will ever live in this file.
///
/// The status line exists so that "it launched" and "it launched with Layer 1
/// actually linked and readable" are distinguishable by looking at the screen.
struct CanvasScreen: View {
    let environment: AppEnvironment

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(white: 0.99)
                .ignoresSafeArea()

            statusLine
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
    }

    private var statusLine: some View {
        HStack(spacing: 10) {
            Text("SLATE")
                .font(.system(.caption, design: .monospaced).weight(.semibold))

            Text("M0")
                .font(.system(.caption2, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15), in: Capsule())

            // Read straight from the domain package. If these render, SlateCore
            // is linked and reachable from Layer 3 — which is the entire
            // acceptance criterion for this milestone on-device.
            Text(verbatim: "stall \(format(environment.config.stallThreshold))s")
                .font(.system(.caption2, design: .monospaced))

            Text(verbatim: "cooldown \(format(environment.config.hintCooldown))s")
                .font(.system(.caption2, design: .monospaced))

            Text(verbatim: environment.config.isValid ? "config ok" : "config INVALID")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(environment.config.isValid ? Color.secondary : Color.red)
        }
        .foregroundStyle(.secondary)
    }

    private func format(_ value: TimeInterval) -> String {
        String(format: "%.1f", value)
    }
}

#Preview("Empty canvas") {
    CanvasScreen(environment: .preview())
}
