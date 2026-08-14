import Foundation

/// A rendered picture of part of the canvas, ready to send to a model.
///
/// Bytes plus the geometry they came from. The domain does not know or care
/// what encoding it is — that is the rasterizer's business — but it does need
/// to know which region of canvas the pixels correspond to, because a hint has
/// to be placed back onto the canvas afterwards.
public struct RasterizedRegion: Hashable, Sendable {
    public let data: Data
    public let mediaType: String
    public let sourceBounds: CanvasRect
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(
        data: Data,
        mediaType: String,
        sourceBounds: CanvasRect,
        pixelWidth: Int,
        pixelHeight: Int
    ) {
        self.data = data
        self.mediaType = mediaType
        self.sourceBounds = sourceBounds
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// What a stroke reveals about how it was made, expressed as text a model can
/// read.
///
/// Timing, order, and hesitation are the signal an image cannot carry. A pause
/// of ninety seconds before a line, or a stroke retraced three times, says
/// something about confidence that the finished picture does not.
public struct StrokeTiming: Hashable, Sendable {
    public let strokeCount: Int
    public let totalDuration: TimeInterval
    public let longestPause: TimeInterval
    public let secondsSinceLastStroke: TimeInterval

    public init(
        strokeCount: Int,
        totalDuration: TimeInterval,
        longestPause: TimeInterval,
        secondsSinceLastStroke: TimeInterval
    ) {
        self.strokeCount = strokeCount
        self.totalDuration = totalDuration
        self.longestPause = longestPause
        self.secondsSinceLastStroke = secondsSinceLastStroke
    }

    /// Derives timing from a run of strokes, as of a given moment.
    ///
    /// Pure, so the tutor loop's notion of "how long have they been stuck" is
    /// testable without a clock or a canvas.
    public static func measuring(
        _ strokes: [InkStroke],
        asOf moment: Date
    ) -> StrokeTiming {
        let ordered = strokes.sorted { $0.createdAt < $1.createdAt }

        guard let first = ordered.first, let last = ordered.last else {
            return StrokeTiming(
                strokeCount: 0,
                totalDuration: 0,
                longestPause: 0,
                secondsSinceLastStroke: 0
            )
        }

        var longestPause: TimeInterval = 0
        for (previous, current) in zip(ordered, ordered.dropFirst()) {
            longestPause = max(longestPause, current.createdAt.timeIntervalSince(previous.endedAt))
        }

        return StrokeTiming(
            strokeCount: ordered.count,
            totalDuration: max(0, last.endedAt.timeIntervalSince(first.createdAt)),
            longestPause: max(0, longestPause),
            secondsSinceLastStroke: max(0, moment.timeIntervalSince(last.endedAt))
        )
    }
}

/// Everything the tutor knows when it decides what to say.
///
/// Composable rather than a fixed shape, per the founding brief's section 10:
/// v1 carries a rasterized region and stroke timing, and v1.5 adds text spans,
/// document chunks, and an outline graph. Adding a field must not change the
/// shape of the evaluation pipeline.
public struct EvaluationContext: Sendable {

    /// The picture of the student's work.
    public var image: RasterizedRegion?

    /// The problem statement, when the app knows it.
    ///
    /// Absent when the student drew a region around their own work. The tutor
    /// behaves differently then: it can still see the working, but it must not
    /// assume it knows the question.
    public var prompt: String?

    /// What has already been said about this region, oldest first.
    ///
    /// Sent so the model does not repeat itself, and so it can tell how much
    /// help has already been given.
    public var hintsAlreadyGiven: [String]

    /// The rung the ladder is currently on for this region.
    public var currentLevel: HintLevel?

    /// The highest rung this evaluation is permitted to reach.
    ///
    /// Enforced by our code after the response comes back, not merely requested
    /// in the prompt. A model that ignores the instruction must still be
    /// unable to exceed it.
    public var permittedLevel: HintLevel

    public var timing: StrokeTiming?

    /// Error classes this student has already shown this session, most recent
    /// first.
    public var recentErrorClasses: [String]

    /// Whether the student asked for help outright, as opposed to the tutor
    /// noticing a stall.
    public var studentAskedExplicitly: Bool

    public init(
        image: RasterizedRegion? = nil,
        prompt: String? = nil,
        hintsAlreadyGiven: [String] = [],
        currentLevel: HintLevel? = nil,
        permittedLevel: HintLevel = .orient,
        timing: StrokeTiming? = nil,
        recentErrorClasses: [String] = [],
        studentAskedExplicitly: Bool = false
    ) {
        self.image = image
        self.prompt = prompt
        self.hintsAlreadyGiven = hintsAlreadyGiven
        self.currentLevel = currentLevel
        self.permittedLevel = permittedLevel
        self.timing = timing
        self.recentErrorClasses = recentErrorClasses
        self.studentAskedExplicitly = studentAskedExplicitly
    }

    /// Whether there is anything worth sending.
    ///
    /// An evaluation with no picture and no problem statement has nothing to
    /// reason about, and sending it would spend the student's own API budget to
    /// receive a guess.
    public var isSendable: Bool {
        image != nil || prompt != nil
    }
}
