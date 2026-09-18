import Foundation
import PencilKit
import SlateCore
import SlatePlatform

/// Holds the canonical document for the canvas on screen, keeps it in step with
/// what PencilKit has rendered, and persists every change.
///
/// The document is the record; `PKDrawing` is the renderer's cache. This class
/// is the seam between them, and the only place in the app where both are in
/// scope.
@MainActor
final class CanvasController: ObservableObject {

    enum SaveState: Equatable {
        case loading
        case ready
        case saving
        case saved
        case failed(String)
    }

    /// Outcome of the M4 debug evaluation — "send whatever is on the canvas to
    /// the tutor and show what came back," with no region model or trigger
    /// logic yet. That is M5's job; this exists to prove the seam end to end.
    enum DebugEvaluationState: Equatable {
        case idle
        case running
        case succeeded(TutorResponse)
        case failed(String)
    }

    @Published private(set) var document: Document?
    @Published private(set) var saveState: SaveState = .loading
    @Published private(set) var lastCapture: String = "nothing captured yet"
    @Published private(set) var debugState: DebugEvaluationState = .idle

    /// Bumped when the canvas should be repainted from the document.
    ///
    /// A counter rather than a flag because the view has to be able to tell
    /// "restore again" from "same restore it already did", and SwiftUI gives no
    /// guarantee about how many times `updateUIView` runs for one change.
    @Published private(set) var restoreGeneration: Int = 0

    /// Set by the representable once the view exists, for undo and redo.
    weak var canvasView: PKCanvasView?

    private let repository: any DocumentRepository
    private let converter: PencilKitInkConverter
    private let timeSource: any TimeSource
    private let rasterizer: any StrokeRasterizing
    private let aiProvider: any AIProvider
    private let config: TutorConfig

    /// Suppresses capture while the canvas is being repainted from the
    /// document. Without it, restoring a drawing looks exactly like the user
    /// drawing forty strokes at once, and the document would record its own
    /// contents a second time.
    private var isRestoring = false

    /// Persistence runs off the main actor, so two quick strokes could
    /// otherwise race and write their operations out of order. Chaining each
    /// save onto the previous one keeps the log in the order the user drew.
    private var saveChain: Task<Void, Never>?

    init(
        repository: any DocumentRepository,
        converter: PencilKitInkConverter = PencilKitInkConverter(),
        timeSource: any TimeSource,
        rasterizer: any StrokeRasterizing,
        aiProvider: any AIProvider,
        config: TutorConfig
    ) {
        self.repository = repository
        self.converter = converter
        self.timeSource = timeSource
        self.rasterizer = rasterizer
        self.aiProvider = aiProvider
        self.config = config
    }

    // MARK: - Opening

    /// Opens the most recently modified document, creating one if the store is
    /// empty.
    ///
    /// v1 has a single implicit canvas rather than a document browser. The
    /// repository already supports many, so the browser is a UI feature rather
    /// than a storage change.
    func start() async {
        do {
            let existing = try await repository.summaries()

            let opened: Document
            if let newest = existing.first {
                opened = try await repository.document(newest.id)
            } else {
                opened = try await repository.createDocument(title: "Untitled")
            }

            document = opened
            describe(opened)
            saveState = .ready

            if !opened.isEmpty {
                restoreGeneration += 1
            }
        } catch {
            saveState = .failed(short(error))
        }
    }

    /// The drawing the canvas should show for the current document.
    func drawingForRestore() -> PKDrawing {
        guard let document else { return PKDrawing() }
        return converter.pkDrawing(from: document.inkStrokes)
    }

    func beginRestore() { isRestoring = true }
    func endRestore() { isRestoring = false }

    // MARK: - Capture

    /// Brings the document in line with a drawing and persists the difference.
    ///
    /// The common case — one stroke appended — converts and stores only that
    /// stroke. Converting the whole drawing on every change would be O(every
    /// point ever drawn) on the hot path of writing, which is exactly the kind
    /// of work that turns into visible lag halfway down a page of algebra.
    func ingest(_ drawing: PKDrawing) {
        guard !isRestoring, let current = document else { return }

        let incoming = drawing.strokes
        let now = timeSource.now

        if incoming.count > current.elements.count {
            let appended = incoming[current.elements.count...].map {
                converter.inkStroke(from: $0, lastModified: now)
            }
            commit(current.operationsInserting(appended, at: now))

        } else if incoming.count != current.elements.count {
            commit(rebuildOperations(from: drawing, current: current, at: now))
        }
        // Equal counts with changed content is an in-place edit, which cannot
        // happen from drawing alone and does not exist until selection lands.
        // Detecting it would mean a deep comparison on every stroke.
    }

    /// Operations that replace the document's contents wholesale.
    ///
    /// Used for erase, undo, and clear. PencilKit reports *that* the drawing
    /// changed and never *how* — `PKCanvasViewDelegate` has no erase callback
    /// at all — and the strokes that come back carry no identity tying them to
    /// what was there before. So the only correct move is to remove everything
    /// and re-insert what remains.
    ///
    /// The cost is real: erasing one stroke on a 200-stroke canvas writes 400
    /// operations. Acceptable for now because it is off the writing path and
    /// compaction folds it away. The fix, if it starts to hurt, is stable
    /// stroke identity — `PKStroke.id` exists and would let this become a true
    /// diff, but whether it survives an erase has not been verified.
    private func rebuildOperations(
        from drawing: PKDrawing,
        current: Document,
        at moment: Date
    ) -> [DocumentOperation] {
        var sequence = current.lastSequence
        var operations: [DocumentOperation] = []

        for element in current.elements {
            sequence += 1
            operations.append(DocumentOperation(
                sequence: sequence, timestamp: moment, change: .remove(element.id)
            ))
        }

        for stroke in converter.inkStrokes(from: drawing, lastModified: moment) {
            sequence += 1
            operations.append(DocumentOperation(
                sequence: sequence, timestamp: moment, change: .insert(.ink(stroke))
            ))
        }

        return operations
    }

    /// Applies operations optimistically, then persists them.
    ///
    /// Optimistic because the canvas has already drawn the stroke — making the
    /// user wait on a disk write to see their own ink would be the worst
    /// possible trade in this product. If the write fails the status line says
    /// so; the ink stays on screen either way.
    private func commit(_ operations: [DocumentOperation]) {
        guard var current = document, !operations.isEmpty else { return }

        do {
            try current.apply(operations)
        } catch {
            saveState = .failed(short(error))
            return
        }

        document = current
        describe(current)
        saveState = .saving

        let repository = self.repository
        let id = current.id
        let previous = saveChain

        saveChain = Task { [weak self] in
            _ = await previous?.value

            do {
                _ = try await repository.append(operations, to: id)
                await MainActor.run { self?.saveState = .saved }
            } catch {
                await MainActor.run { self?.saveState = .failed(Self.shortDescription(error)) }
            }
        }
    }

    // MARK: - Editing

    var canUndo: Bool { canvasView?.undoManager?.canUndo ?? false }
    var canRedo: Bool { canvasView?.undoManager?.canRedo ?? false }

    func undo() { canvasView?.undoManager?.undo() }
    func redo() { canvasView?.undoManager?.redo() }

    func clear() {
        canvasView?.drawing = PKDrawing()
    }

    // MARK: - Debug evaluation (M4)

    /// Sends every stroke currently on the canvas to the configured provider
    /// and reports what came back.
    ///
    /// Whole-canvas rather than a region, because `WorkRegion` creation has no
    /// UI yet (M3). This is deliberately the smallest thing that can answer the
    /// founding brief's M4 acceptance test — "write something messy, tap debug,
    /// watch the model read it back correctly" — without waiting on M3 or M5.
    func runDebugEvaluation() {
        guard let document else { return }
        let strokes = document.inkStrokes

        guard !strokes.isEmpty else {
            debugState = .failed("nothing drawn yet")
            return
        }

        let now = timeSource.now
        let unpadded = strokes.reduce(CanvasRect.zero) { $0.union($1.renderBounds) }
        let bounds = unpadded.expanded(by: unpadded.longEdge * config.regionPaddingFraction)
        let timing = StrokeTiming.measuring(strokes, asOf: now)

        debugState = .running

        Task { [weak self, rasterizer, aiProvider, config] in
            guard let self else { return }
            do {
                let region = try await rasterizer.rasterize(
                    strokes,
                    bounds: bounds,
                    scale: config.regionRenderScale,
                    maximumLongEdge: config.regionRenderMaxEdge
                )

                let context = EvaluationContext(
                    image: region,
                    prompt: nil,
                    permittedLevel: .orient,
                    timing: timing
                )

                let response = try await aiProvider.evaluate(context)
                await MainActor.run { self.debugState = .succeeded(response) }
            } catch {
                await MainActor.run { self.debugState = .failed(Self.shortDescription(error)) }
            }
        }
    }

    // MARK: - Reporting

    private func describe(_ document: Document) {
        guard let last = document.inkStrokes.last else {
            lastCapture = "\(document.elements.count) strokes"
            return
        }

        let pressure = last.hasPressure ? "pressure" : "no pressure"
        let tilt = last.hasTilt ? "tilt" : "no tilt"

        lastCapture = "\(document.elements.count) strokes · last: \(last.points.count) pts, "
            + String(format: "%.2fs", last.duration)
            + ", \(pressure), \(tilt)"
    }

    private func short(_ error: Error) -> String { Self.shortDescription(error) }

    private nonisolated static func shortDescription(_ error: Error) -> String {
        if let repositoryError = error as? DocumentRepositoryError {
            return repositoryError.description
        }
        return "\(error)"
    }
}
