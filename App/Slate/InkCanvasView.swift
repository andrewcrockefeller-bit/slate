import SwiftUI
import PencilKit
import SlateCore

/// Hosts a `PKCanvasView` in SwiftUI.
///
/// Contains no business logic: it wires PencilKit's callbacks to the
/// controller and configures the view. Conversion between PencilKit's stroke
/// representation and the domain's lives in Layer 2, and the canonical record
/// lives in the controller.
struct InkCanvasView: UIViewRepresentable {

    @ObservedObject var controller: CanvasController

    /// The drawable extent, in points.
    ///
    /// `PKCanvasView` is a scroll view, so a content size larger than the frame
    /// gives pan and zoom for free. This is a very large finite canvas rather
    /// than a genuinely infinite one — true infinity needs the content to be
    /// recentred as the user approaches an edge, which is a real piece of work
    /// and is not what M1 is for. At this size a student would have to scroll
    /// for a long while to notice, and the seam is one place to change.
    static let canvasExtent = CGSize(width: 20_000, height: 20_000)

    static let minimumZoom: CGFloat = 0.25
    static let maximumZoom: CGFloat = 4.0

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()

        canvas.delegate = context.coordinator
        canvas.drawing = PKDrawing()

        // Pencil draws, finger scrolls. This is what makes resting a hand on
        // the screen while writing work, and it is the single setting most
        // responsible for the canvas feeling like paper rather than like a
        // touchscreen. Becomes a user preference later; it is not a default
        // worth surfacing at M1.
        canvas.drawingPolicy = .pencilOnly

        canvas.alwaysBounceVertical = true
        canvas.alwaysBounceHorizontal = true
        canvas.contentSize = Self.canvasExtent
        canvas.minimumZoomScale = Self.minimumZoom
        canvas.maximumZoomScale = Self.maximumZoom
        canvas.backgroundColor = .systemBackground
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
        // Nothing to push down. The canvas owns its own drawing; the controller
        // observes it. Writing `canvas.drawing = ...` here would fight the
        // user's own input on every SwiftUI update.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {

        private let controller: CanvasController
        private let toolPicker = PKToolPicker()

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
        /// deliberate. That callback fires repeatedly *during* a stroke, and
        /// converting a partially-drawn stroke means doing the work several
        /// times over and producing intermediate records that were never real.
        /// Pen-up is the moment a stroke exists.
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
