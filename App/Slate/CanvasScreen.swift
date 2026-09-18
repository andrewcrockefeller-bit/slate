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
    @State private var isShowingAPIKeySettings = false
    @State private var isShowingDebugResult = false
    @State private var paperStyle: PaperStyle = .plain
    @State private var toolKind: ToolKind = .fountainPen
    @State private var inkIndex = 0
    @State private var markerIndex = 0
    @State private var isChromeDimmed = false
    @State private var chromeReturnTask: Task<Void, Never>?
    @State private var isScaleHUDVisible = false
    @State private var scaleHUDFadeTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(environment: AppEnvironment) {
        self.environment = environment
        _controller = StateObject(
            wrappedValue: CanvasController(
                repository: environment.documents,
                timeSource: environment.timeSource,
                rasterizer: environment.rasterizer,
                aiProvider: environment.aiProvider,
                config: environment.config
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
            InkCanvasView(
                controller: controller,
                paperStyle: paperStyle,
                toolKind: toolKind,
                inkIndex: inkIndex,
                markerIndex: markerIndex
            )
            .ignoresSafeArea()

            statusLine
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .overlay(alignment: .topTrailing) {
            editingControls
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .opacity(isChromeDimmed ? 0.25 : 1.0)
        }
        .overlay(alignment: .bottom) {
            toolTray
                .padding(.bottom, 20)
                .opacity(isChromeDimmed ? 0.25 : 1.0)
        }
        .overlay {
            if isScaleHUDVisible {
                Text("\(Int((controller.zoomScale * 100).rounded()))%")
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Palette.graphite)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Palette.surface, in: Capsule())
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .task {
            await controller.start()
        }
        // INK-7: the scale HUD appears the moment a pinch begins and stays
        // up through the gesture; once it ends, it waits Motion.scaleHUD
        // before fading — the delay is the named constant, not the fade
        // itself.
        .onChange(of: controller.isZooming) { _, isZooming in
            scaleHUDFadeTask?.cancel()

            if isZooming {
                isScaleHUDVisible = true
            } else {
                scaleHUDFadeTask = Task {
                    try? await Task.sleep(for: .seconds(Motion.scaleHUD))
                    guard !Task.isCancelled else { return }
                    withAnimation(Motion.adaptive(Motion.standard)) {
                        isScaleHUDVisible = false
                    }
                }
            }
        }
        // UI-3: chrome yields to the pencil. Drops the moment a stroke
        // begins; the return is debounced by Motion.chromeFade so rapid
        // successive strokes (writing normally) don't flicker the chrome in
        // and out between each one — only a real pause triggers it.
        .onChange(of: controller.isPencilDown) { _, isPencilDown in
            chromeReturnTask?.cancel()

            if isPencilDown {
                withAnimation(Motion.adaptive(Motion.standard)) {
                    isChromeDimmed = true
                }
            } else {
                chromeReturnTask = Task {
                    try? await Task.sleep(for: .seconds(Motion.chromeFade))
                    guard !Task.isCancelled else { return }
                    withAnimation(Motion.adaptive(Motion.standard)) {
                        isChromeDimmed = false
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingAPIKeySettings) {
            APIKeySettingsView(apiKeyStore: environment.apiKeyStore, providerName: environment.aiProvider.providerName)
        }
        .sheet(isPresented: $isShowingDebugResult) {
            DebugEvaluationResultView(state: controller.debugState)
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

            Divider().frame(height: 20)

            paperPicker

            Divider().frame(height: 20)

            Button {
                isShowingAPIKeySettings = true
            } label: {
                Label("API Key", systemImage: "key")
            }

            // M4's acceptance test: write something messy, tap this, watch the
            // model read it back correctly. No region model yet, so this reads
            // the whole canvas — see CanvasController.runDebugEvaluation.
            Button {
                controller.runDebugEvaluation()
                isShowingDebugResult = true
            } label: {
                Label("Ask tutor", systemImage: "wand.and.stars")
            }
            .disabled(controller.debugState == .running)
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

    /// INK-2: plain, faint grid, dot grid — exactly three, no ruled paper.
    /// Adding a fourth requires a decision from Andrew, per CLAUDE.md.
    private var paperPicker: some View {
        Menu {
            ForEach(PaperStyle.allCases, id: \.rawValue) { style in
                Button {
                    Haptics.toolSelect()
                    paperStyle = style
                } label: {
                    Label(style.label, systemImage: style.symbolName)
                    if style == paperStyle {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            Label("Paper", systemImage: paperStyle.symbolName)
        }
    }

    /// INK-4: exactly four tools, six inks, three markers. No color wheel,
    /// eyedropper, or hex field — swatches only. Opaque (Palette.surface),
    /// not glass — editingControls is the app's one Liquid Glass surface,
    /// see docs/DS-CONFLICTS.md, C-1.
    private var toolTray: some View {
        VStack(spacing: 10) {
            if toolKind.usesInkPalette {
                swatchRow(colors: Palette.inks, selectedIndex: $inkIndex)
            } else if toolKind.usesMarkerPalette {
                swatchRow(colors: Palette.markers, selectedIndex: $markerIndex)
            }

            HStack(alignment: .bottom, spacing: 12) {
                ForEach(ToolKind.allCases, id: \.rawValue) { kind in
                    let isSelected = kind == toolKind

                    Button {
                        Haptics.toolSelect()
                        toolKind = kind
                    } label: {
                        ToolSampleView(kind: kind, color: sampleColor(for: kind))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 10)
                            .background(
                                isSelected ? Palette.hairline : Color.clear,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            // The selected tool physically rises — UI-2.
                            .scaleEffect(isSelected ? 1.12 : 1.0)
                            .offset(y: isSelected ? -4 : 0)
                            .shadow(
                                color: Palette.graphite.opacity(isSelected ? 0.18 : 0),
                                radius: 4, y: 2
                            )
                    }
                    .animation(Motion.adaptive(Motion.standard), value: toolKind)
                    .accessibilityLabel(kind.label)
                }
            }
        }
        .padding(12)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// UI-2's "changing ink color changes the picker samples": fountain pen
    /// and pencil both draw in whichever ink is currently selected, so
    /// changing that selection updates both samples, not just the active
    /// tool's. Highlighter always shows the selected marker; eraser ignores
    /// color entirely.
    private func sampleColor(for kind: ToolKind) -> Color {
        switch kind {
        case .fountainPen, .pencil:
            return Palette.inks[inkIndex]
        case .highlighter:
            return Palette.markers[markerIndex]
        case .eraser:
            return Palette.inkFaint
        }
    }

    private func swatchRow(colors: [Color], selectedIndex: Binding<Int>) -> some View {
        HStack(spacing: 10) {
            ForEach(colors.indices, id: \.self) { index in
                Button {
                    Haptics.toolSelect()
                    selectedIndex.wrappedValue = index
                } label: {
                    Circle()
                        .fill(colors[index])
                        .frame(width: 26, height: 26)
                        .overlay {
                            if index == selectedIndex.wrappedValue {
                                Circle().stroke(Palette.graphite, lineWidth: 2)
                            }
                        }
                }
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
