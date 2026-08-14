import Foundation

/// One HTTP request, described in terms Foundation alone can express.
///
/// Deliberately not `URLRequest`. `URLRequest` is Foundation on Apple platforms
/// and FoundationNetworking on Linux, which is a different module that must be
/// imported separately — so using it here would break the Linux build of Layer 1
/// and, worse, would tie the domain to whatever URL loading system happens to
/// exist on each platform. A string URL and a dictionary of headers say
/// everything a request needs to say and cost nothing to port.
public struct HTTPRequest: Hashable, Sendable {

    public enum Method: String, Hashable, Sendable {
        case get = "GET"
        case post = "POST"
    }

    public var method: Method
    public var url: String
    public var headers: [String: String]
    public var body: Data?

    /// How long the transport should wait before giving up.
    ///
    /// Carried on the request rather than configured once on the transport,
    /// because a tutor evaluation and a key-validation ping have very different
    /// tolerances and they share one transport.
    public var timeout: TimeInterval

    public init(
        method: Method = .post,
        url: String,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval = 30
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}

/// What came back.
public struct HTTPResponse: Hashable, Sendable {

    public var statusCode: Int
    public var headers: [String: String]
    public var body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    public var isSuccess: Bool { (200..<300).contains(statusCode) }

    /// Header lookup that does not care about case.
    ///
    /// HTTP header names are case-insensitive and servers disagree in practice
    /// — `Retry-After`, `retry-after`, `RETRY-AFTER` are all seen in the wild.
    /// A plain dictionary subscript would miss two of the three, and the symptom
    /// would be a retry policy that silently stops working against one vendor.
    public func headerValue(_ name: String) -> String? {
        let wanted = name.lowercased()
        return headers.first { $0.key.lowercased() == wanted }?.value
    }

    /// The body as UTF-8 text, for error messages and for logging.
    public var bodyText: String {
        String(data: body, encoding: .utf8) ?? ""
    }
}

/// Something that can perform an HTTP request.
///
/// The single seam between the domain's provider adapters and the network.
/// Because it is a protocol declared here, an adapter that speaks the Anthropic
/// Messages API can be written, tested, and run on Linux with no network at all
/// — which is what keeps the most failure-prone code in the app testable.
public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// Transport-level failures, before there is any status code to reason about.
public enum HTTPTransportError: Error, Hashable, Sendable, CustomStringConvertible {
    case invalidURL(String)
    case unreachable(reason: String)
    case cancelled

    public var description: String {
        switch self {
        case .invalidURL(let url): return "'\(url)' is not a valid URL"
        case .unreachable(let reason): return "unreachable: \(reason)"
        case .cancelled: return "cancelled"
        }
    }
}
