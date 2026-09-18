import Foundation

/// A model the tutor can ask.
///
/// Invariant 3's most important instance. Adding Gemini, swapping to a local
/// model, or routing through a future backend must mean writing one adapter
/// file and changing one line of wiring — never touching a call site.
///
/// Deliberately narrow: one method. Everything about *what* to ask lives in
/// `EvaluationContext` and everything about *what came back* lives in
/// `TutorResponse`, so an adapter's whole job is transport and translation. An
/// adapter that starts making decisions has taken on work that belongs in
/// Layer 1, where it can be tested without a network.
public protocol AIProvider: Sendable {

    /// A name for the interface — "Anthropic", "Gemini", "On-device".
    var providerName: String { get }

    /// The specific model in use, for display and for the session record.
    var modelIdentifier: String { get }

    /// Asks for a hint.
    func evaluate(_ context: EvaluationContext) async throws -> TutorResponse
}

/// What can go wrong, in terms the domain understands.
///
/// Transport-specific failures — an HTTP status, a URLSession error, a JSON
/// decoding fault — are translated into these by the adapter. Layer 1 must not
/// know what a status code is, and the tutor loop deciding whether to retry
/// should not be switching on someone else's error taxonomy.
public enum AIProviderError: Error, Hashable, Sendable, CustomStringConvertible {

    /// No key configured, or the key was rejected.
    case notAuthorised(reason: String)

    /// Rate limited or out of quota. Carries a retry hint when the service
    /// gave one.
    case rateLimited(retryAfter: TimeInterval?)

    /// The network failed.
    case unreachable(reason: String)

    /// The service answered, but not with something we could parse.
    case malformedResponse(reason: String)

    /// The response parsed but broke the ladder rules and could not be
    /// salvaged by regenerating.
    case rejected([TutorResponseRejection])

    /// The service refused the request itself.
    case refusedByProvider(reason: String)

    /// Anything else, kept rather than swallowed.
    case other(reason: String)

    public var description: String {
        switch self {
        case .notAuthorised(let reason): return "not authorised: \(reason)"
        case .rateLimited(let after):
            return after.map { "rate limited, retry in \(Int($0))s" } ?? "rate limited"
        case .unreachable(let reason): return "unreachable: \(reason)"
        case .malformedResponse(let reason): return "malformed response: \(reason)"
        case .rejected(let rejections):
            return "rejected: " + rejections.map(\.description).joined(separator: "; ")
        case .refusedByProvider(let reason): return "provider refused: \(reason)"
        case .other(let reason): return reason
        }
    }

    /// Whether trying the same request again could plausibly succeed.
    ///
    /// Drives whether the tutor retries silently or tells the student something
    /// is wrong. Getting this wrong in the permissive direction means hammering
    /// a service that has already said no, on the student's own API budget.
    public var isTransient: Bool {
        switch self {
        case .rateLimited, .unreachable: return true
        case .notAuthorised, .malformedResponse, .rejected, .refusedByProvider, .other: return false
        }
    }
}

/// Turns part of a canvas into an image.
///
/// Declared here and implemented in Layer 2, because rasterizing needs
/// CoreGraphics on Apple platforms and something else everywhere else — and
/// Layer 1 may not import either. Layer 1 decides *what* to render and at what
/// scale; Layer 2 renders it.
public protocol StrokeRasterizing: Sendable {
    func rasterize(
        _ strokes: [InkStroke],
        bounds: CanvasRect,
        scale: Double,
        maximumLongEdge: Int
    ) async throws -> RasterizedRegion
}

/// Where the student's API key lives.
///
/// A protocol so the domain can express "there is a key" without knowing about
/// Keychain, which is an Apple framework and would not survive the port.
public protocol APIKeyStore: Sendable {
    func key(for providerName: String) async throws -> String?
    func setKey(_ key: String?, for providerName: String) async throws
}

/// An `APIKeyStore` that never touches the Keychain.
///
/// For previews and manual testing, same reasoning as
/// `InMemoryDocumentRepository`: a preview that read or wrote the real
/// Keychain would leak state between Xcode rebuilds and could collide with a
/// key the student actually entered.
public actor InMemoryAPIKeyStore: APIKeyStore {
    private var keys: [String: String]

    public init(seed: [String: String] = [:]) {
        self.keys = seed
    }

    public func key(for providerName: String) async throws -> String? {
        keys[providerName]
    }

    public func setKey(_ key: String?, for providerName: String) async throws {
        keys[providerName] = key
    }
}
