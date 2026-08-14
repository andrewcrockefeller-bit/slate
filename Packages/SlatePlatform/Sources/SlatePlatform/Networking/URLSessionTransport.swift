import Foundation
import SlateCore

#if canImport(FoundationNetworking)
// On Linux, URLSession lives in a separate module. SlatePlatform is not expected
// to build on Linux, but importing conditionally costs nothing and means this
// file is not the reason if that ever changes.
import FoundationNetworking
#endif

/// The only place in Slate that knows what a `URLSession` is.
///
/// Everything above this — building the request, reading the reply, deciding
/// what a 429 means — happens in SlateCore against `HTTPRequest`/`HTTPResponse`,
/// which is why the provider adapters are testable without a network. This file
/// is the translation layer and contains no decisions.
public struct URLSessionTransport: HTTPTransport {

    private let session: URLSession

    /// A session configured for short, independent API calls.
    ///
    /// `waitsForConnectivity` is deliberately off: the tutor's whole value is
    /// timeliness, and a request that queues silently until the train leaves the
    /// tunnel arrives as a hint about work the student finished ten minutes ago.
    /// Failing fast lets the domain decide, which is where that decision belongs.
    public static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        configuration.httpAdditionalHeaders = nil
        return URLSession(configuration: configuration)
    }

    public init(session: URLSession? = nil) {
        self.session = session ?? Self.makeDefaultSession()
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard let url = URL(string: request.url) else {
            throw HTTPTransportError.invalidURL(request.url)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = request.timeout

        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError where error.code == .cancelled {
            throw HTTPTransportError.cancelled
        } catch {
            throw HTTPTransportError.unreachable(reason: error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw HTTPTransportError.unreachable(reason: "the reply was not an HTTP response")
        }

        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let name = key as? String, let text = value as? String {
                headers[name] = text
            }
        }

        return HTTPResponse(statusCode: http.statusCode, headers: headers, body: data)
    }
}
