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
    var toolKind: ToolKind
    var inkIndex: Int
    var markerIndex: Int

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

    /// INK-7's "nearest sensible scale step." Spans minimumZoom...maximumZoom.
    static let zoomSteps: [CGFloat] = [0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0]

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

        // INK-4: exactly four tools, driven by our own tray rather than
        // PKToolPicker — see docs/DS-CONFLICTS.md, C-2. No system tool
        // picker is attached at all, so there is no system color wheel,
        // eyedropper, or extra tool to reach for. `.fountainPen`/`.pencil`
        // are PencilKit's own ink types, so pressure/tilt rendering is
        // unchanged from what M1 verified on device.
        let initialTool = AppliedTool(kind: toolKind, inkIndex: inkIndex, markerIndex: markerIndex)
        canvas.tool = ToolSelection.pencilKitTool(for: initialTool)
        context.coordinator.appliedTool = initialTool

        canvas.becomeFirstResponder()
        controller.canvasView = canvas

        // INK-7: two-finger double-tap returns to exactly 100%.
        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTapToReset)
        )
        doubleTap.numberOfTapsRequired = 2
        doubleTap.numberOfTouchesRequired = 2
        canvas.addGestureRecognizer(doubleTap)

        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        // Cheap regardless of whether it changed — PaperBackground caches
        // the tiled UIColor, so this is a dictionary lookup, not a redraw.
        (canvas as? PaperCanvasView)?.paperStyle = paperStyle

        // Only reassign `canvas.tool` when the selection actually changed.
        // This view updates on every controller publish (e.g. lastCapture
        // while drawing); reassigning the tool on each of those would be
        // visible mid-stroke.
        let desiredTool = AppliedTool(kind: toolKind, inkIndex: inkIndex, markerIndex: markerIndex)
        if context.coordinator.appliedTool != desiredTool {
            context.coordinator.appliedTool = desiredTool
            canvas.tool = ToolSelection.pencilKitTool(for: desiredTool)
        }

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

        /// The restore the canvas has already painted. Starts at zero, which
        /// is also the controller's value before anything is loaded, so a fresh
        /// empty canvas does no work.
        var appliedRestoreGeneration = 0

        /// The tool selection already pushed onto `canvas.tool`. See
        /// `updateUIView` — compared so an unrelated SwiftUI update never
        /// reassigns the tool mid-stroke.
        var appliedTool: AppliedTool?

        init(controller: CanvasController) {
            self.controller = controller
        }

        /// Pen down — UI-3's chrome-yields signal. Fires on touch-down, not
        /// touch-up, per the "respond on touch-down" rule.
        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            controller.pencilDidTouchDown()
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
            controller.pencilDidLift()
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

        // MARK: - Zoom (INK-7)
        //
        // `PKCanvasViewDelegate` extends `UIScrollViewDelegate`, so these
        // live on the same coordinator as the drawing callbacks above.

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            controller.zoomGestureDidBegin()
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            controller.zoomDidChange(to: scrollView.zoomScale)
        }

        /// Pinch released. Settles to the nearest step in `InkCanvasView.
        /// zoomSteps`, projected slightly ahead by the pinch's release
        /// velocity so a fast release visibly lands a step further in the
        /// direction of motion — not a hard snap to whatever step happens to
        /// be nearest the raw release point.
        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            controller.zoomGestureDidEnd()

            let velocity = scrollView.pinchGestureRecognizer?.velocity ?? 0
            let projected = scale + velocity * Self.velocityLookahead
            let clamped = min(max(projected, InkCanvasView.minimumZoom), InkCanvasView.maximumZoom)
            let target = InkCanvasView.zoomSteps.min(by: { abs($0 - clamped) < abs($1 - clamped) }) ?? scale

            settle(scrollView, to: target, from: scale, velocity: velocity)
        }

        @objc func handleDoubleTapToReset(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            Haptics.toolSelect()
            settle(scrollView, to: 1.0, from: scrollView.zoomScale, velocity: 0)
        }

        /// How far ahead (in scale units, per unit of gesture velocity) to
        /// project before picking the nearest step. Not a Motion value —
        /// this shapes step *selection*, not an animation's timing.
        private static let velocityLookahead: CGFloat = 0.15

        /// Drives `zoomScale` with a `UIViewPropertyAnimator` rather than
        /// `withAnimation`/`Motion.adaptive(_:)` — SwiftUI's animation
        /// modifiers only affect SwiftUI-owned state, not a UIKit property
        /// like `UIScrollView.zoomScale`, so Reduce Motion is checked
        /// directly here instead.
        private func settle(_ scrollView: UIScrollView, to target: CGFloat, from current: CGFloat, velocity: CGFloat) {
            let distance = target - current
            let initialVelocity = distance == 0 ? .zero : CGVector(dx: velocity / distance, dy: 0)

            let animator = UIViewPropertyAnimator(
                duration: UIAccessibility.isReduceMotionEnabled ? 0.15 : Motion.settleResponse,
                timingParameters: UIAccessibility.isReduceMotionEnabled
                    ? UICubicTimingParameters(animationCurve: .easeInOut)
                    : Motion.settleSpringTiming(initialVelocity: initialVelocity)
            )
            animator.addAnimations {
                scrollView.zoomScale = target
            }
            animator.startAnimation()
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
