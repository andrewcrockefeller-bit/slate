import SwiftUI
import PencilKit
import SlateCore

/// Hosts a `PKCanvasView` in SwiftUI.
///
/// Contains no business logic: it wires PencilKit's callbacks to the controller
/// and configures the view. Conversion between PencilKit's stroke
/// representation and the domain's lives in Layer 2, and the canonical document
/// lives in the controller.
struct InkCanvasView: UIViewRepresentable {

    @ObservedObject var controller: CanvasController
    var paperStyle: PaperStyle

    /// The drawable extent, in points.
    ///
    /// `PKCanvasView` is a scroll view, so a content size larger than the frame
    /// gives pan and zoom for free. This is a very large finite canvas rather
    /// than a genuinely infinite one — true infinity needs the content to be
    /// recentred as the user approaches an edge, which is real work and is not
    /// what this milestone is for. At this size a student would have to scroll
    /// for a long while to notice, and the seam is one place to change.
    static let canvasExtent = CGSize(width: 20_000, height: 20_000)

    static let minimumZoom: CGFloat = 0.25
    static let maximumZoom: CGFloat = 4.0

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PaperCanvasView()

        canvas.delegate = context.coordinator
        canvas.drawing = PKDrawing()

        // Pencil draws, finger scrolls. This is what makes resting a hand on
        // the screen while writing work, and it is the single setting most
        // responsible for the canvas feeling like paper rather than like a
        // touchscreen.
        canvas.drawingPolicy = .pencilOnly

        canvas.alwaysBounceVertical = true
        canvas.alwaysBounceHorizontal = true
        canvas.contentSize = Self.canvasExtent
        canvas.minimumZoomScale = Self.minimumZoom
        canvas.maximumZoomScale = Self.maximumZoom
        canvas.paperStyle = paperStyle
        canvas.isOpaque = true

        // Start in the middle, so there is room in every direction rather than
        // a wall up and to the left.
        canvas.contentOffset = CGPoint(
            x: (Self.canvasExtent.width - canvas.bounds.width) / 2,
            y: (Self.canvasExtent.height - canvas.bounds.height) / 2
        )

        canvas.tool = PKInkingTool(.pen, color: .label, width: 3)

        controller.canvasView = canvas
        context.coordinator.attachToolPicker(to: canvas)

        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        // Cheap regardless of whether it changed — PaperBackground caches
        // the tiled UIColor, so this is a dictionary lookup, not a redraw.
        (canvas as? PaperCanvasView)?.paperStyle = paperStyle

        // The only thing ever pushed down: repainting the canvas from a
        // document that was just loaded from disk. Assigning `canvas.drawing`
        // unconditionally here would fight the user's own input on every
        // SwiftUI update, so it happens once per restore generation.
        guard context.coordinator.appliedRestoreGeneration != controller.restoreGeneration else {
            return
        }
        context.coordinator.appliedRestoreGeneration = controller.restoreGeneration

        // Capture is suppressed across the assignment. Restoring a drawing
        // produces the same delegate callbacks as the user drawing every
        // stroke at once, and without this the document would record its own
        // contents a second time.
        controller.beginRestore()
        canvas.drawing = controller.drawingForRestore()
        controller.endRestore()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {

        private let controller: CanvasController
        private let toolPicker = PKToolPicker()

        /// The restore the canvas has already painted. Starts at zero, which
        /// is also the controller's value before anything is loaded, so a fresh
        /// empty canvas does no work.
        var appliedRestoreGeneration = 0

        init(controller: CanvasController) {
            self.controller = controller
        }

        func attachToolPicker(to canvas: PKCanvasView) {
            toolPicker.addObserver(canvas)
            toolPicker.setVisible(true, forFirstResponder: canvas)
            canvas.becomeFirstResponder()
        }

        /// Called when a drawing sequence finishes — pen up.
        ///
        /// Ingesting here rather than in `canvasViewDrawingDidChange` is
        /// deliberate. That callback fires repeatedly *during* a stroke, so
        /// acting on it means doing the work several times over and recording
        /// intermediate strokes that were never real. Pen-up is the moment a
        /// stroke exists.
        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            controller.ingest(canvasView.drawing)
        }

        /// Catches changes that are not the user drawing: undo, redo, erase,
        /// clear.
        ///
        /// PencilKit reports only that the drawing changed, never what changed
        /// — there is no erase event in `PKCanvasViewDelegate`. So this fires
        /// for every mutation including mid-stroke ones, and the controller's
        /// count comparison is what keeps mid-stroke noise from producing
        /// spurious records.
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            controller.ingest(canvasView.drawing)
        }
    }
}

/// `PKCanvasView` with one addition: `backgroundColor` is the cached paper
/// texture rather than a flat color, and it's regenerated when the color
/// scheme changes, not left stale under the previous appearance's tile.
private final class PaperCanvasView: PKCanvasView {
    var paperStyle: PaperStyle = .plain {
        didSet { applyPaperBackground() }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyPaperBackground()
        }
    }

    private func applyPaperBackground() {
        backgroundColor = PaperBackground.color(for: paperStyle, traitCollection: traitCollection)
    }
}
