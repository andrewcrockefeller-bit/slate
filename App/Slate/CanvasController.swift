import Foundation
import PencilKit
import SlateCore
import SlatePlatform

/// Holds the canonical stroke record for the canvas on screen and keeps it in
/// step with what PencilKit has rendered.
///
/// The domain model is the record; `PKDrawing` is the renderer's cache. This
/// class is the seam between them, and the only place in the app where the two
/// are both in scope.
@MainActor
final class CanvasController: ObservableObject {

    /// The canonical strokes, in the order they were drawn.
    @Published private(set) var strokes: [InkStroke] = []

    /// A short description of the most recent capture, for the status line.
    @Published private(set) var lastCapture: String = "nothing captured yet"

    /// Set by the representable once the view exists, for undo and redo.
    weak var canvasView: PKCanvasView?

    private let converter: PencilKitInkConverter
    private let timeSource: any TimeSource

    init(converter: PencilKitInkConverter = PencilKitInkConverter(), timeSource: any TimeSource) {
        self.converter = converter
        self.timeSource = timeSource
    }

    // MARK: - Ingestion

    /// Brings the canonical record in line with a drawing.
    ///
    /// Converting the entire drawing on every change would be O(every point
    /// ever drawn) on each stroke, which is exactly the kind of work that turns
    /// into visible lag halfway through a page of algebra. Ink feel outranks
    /// everything, so the common case — one new stroke appended — converts only
    /// that stroke.
    ///
    /// Anything other than a pure append (an erase, an undo, a selection move)
    /// changes strokes in place or removes them, and there is no cheap way to
    /// tell which from a `PKDrawing` alone: PencilKit reports that the drawing
    /// changed, never how. Those fall back to a full rebuild, which is correct
    /// and is not on the hot path of writing.
    func ingest(_ drawing: PKDrawing) {
        let incoming = drawing.strokes
        let now = timeSource.now

        if incoming.count > strokes.count {
            let appended = incoming[strokes.count...].map {
                converter.inkStroke(from: $0, lastModified: now)
            }
            strokes.append(contentsOf: appended)
            describe(appended.last, total: strokes.count)
        } else if incoming.count != strokes.count {
            strokes = converter.inkStrokes(from: drawing, lastModified: now)
            describe(strokes.last, total: strokes.count)
        }
        // Equal counts with changed content — an in-place edit — is not
        // detected here. It cannot happen from drawing alone, and the cases
        // that produce it (selection drags) do not exist until a later
        // milestone. Revisit when they do rather than paying for a deep
        // comparison on every stroke now.
    }

    private func describe(_ stroke: InkStroke?, total: Int) {
        guard let stroke else {
            lastCapture = "\(total) strokes"
            return
        }

        let pressure = stroke.hasPressure ? "pressure" : "no pressure"
        let tilt = stroke.hasTilt ? "tilt" : "no tilt"
        lastCapture = "\(total) strokes · last: \(stroke.points.count) pts, "
            + String(format: "%.2fs", stroke.duration)
            + ", \(pressure), \(tilt)"
    }

    // MARK: - Editing

    var canUndo: Bool { canvasView?.undoManager?.canUndo ?? false }
    var canRedo: Bool { canvasView?.undoManager?.canRedo ?? false }

    func undo() {
        canvasView?.undoManager?.undo()
    }

    func redo() {
        canvasView?.undoManager?.redo()
    }

    func clear() {
        canvasView?.drawing = PKDrawing()
        strokes.removeAll()
        lastCapture = "cleared"
    }
}
