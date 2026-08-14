import Foundation

/// Speaks the Anthropic Messages API.
///
/// Lives in Layer 1 and imports nothing but Foundation, which is deliberate and
/// slightly unusual: the *transport* is an Apple thing, but building a request
/// body, parsing a reply, and deciding what an HTTP status means are pure data
/// transformations, and they are where the bugs are. Behind `HTTPTransport` this
/// whole file is testable on Linux with no network, no key, and no cost.
///
/// Wire format, for whoever reads this next: POST to /v1/messages with
/// `x-api-key` and `anthropic-version` headers; the reply carries an array of
/// content blocks of which we want the text ones. If Anthropic changes that, the
/// failure lands in `classify` or `decode` below and nowhere else.
public struct AnthropicProvider: AIProvider {

    public struct Configuration: Hashable, Sendable {

        /// Where requests go. Overridable so a test can point at a stub and a
        /// future backend proxy can be dropped in without touching this file.
        public var endpoint: String

        /// The API version header. Anthropic pins behaviour to this string, so
        /// changing it is a deliberate act rather than a drift.
        public var apiVersion: String

        /// Ceiling on the reply. A hint is at most seventy words plus a small
        /// JSON envelope; this is generous by an order of magnitude and exists
        /// only so a runaway reply cannot bill the student for a novel.
        public var maxOutputTokens: Int

        /// How long to wait. Past this the student has moved on, and a hint
        /// about work they finished two minutes ago is worse than no hint.
        public var requestTimeout: TimeInterval

        public init(
            endpoint: String = "https://api.anthropic.com/v1/messages",
            apiVersion: String = "2023-06-01",
            maxOutputTokens: Int = 512,
            requestTimeout: TimeInterval = 30
        ) {
            self.endpoint = endpoint
            self.apiVersion = apiVersion
            self.maxOutputTokens = maxOutputTokens
            self.requestTimeout = requestTimeout
        }

        public static let `default` = Configuration()
    }

    public let providerName = "Anthropic"
    public let modelIdentifier: String

    private let transport: HTTPTransport
    private let keyStore: APIKeyStore
    private let promptBuilder: TutorPromptBuilder
    private let validator: TutorResponseValidator
    private let configuration: Configuration

    public init(
        modelIdentifier: String,
        transport: HTTPTransport,
        keyStore: APIKeyStore,
        promptBuilder: TutorPromptBuilder = TutorPromptBuilder(),
        validator: TutorResponseValidator = TutorResponseValidator(),
        configuration: Configuration = .default
    ) {
        self.modelIdentifier = modelIdentifier
        self.transport = transport
        self.keyStore = keyStore
        self.promptBuilder = promptBuilder
        self.validator = validator
        self.configuration = configuration
    }

    // MARK: - AIProvider

    public func evaluate(_ context: EvaluationContext) async throws -> TutorResponse {
        guard context.isSendable else {
            throw AIProviderError.other(reason: "nothing to evaluate: no image and no problem statement")
        }

        guard let key = try await keyStore.key(for: providerName), !key.isEmpty else {
            throw AIProviderError.notAuthorised(reason: "no API key is configured")
        }

        let request = try makeRequest(for: context, key: key)

        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch let error as HTTPTransportError {
            throw AIProviderError.unreachable(reason: error.description)
        } catch {
            throw AIProviderError.unreachable(reason: String(describing: error))
        }

        guard response.isSuccess else {
            throw Self.classify(response)
        }

        let tutorResponse = try Self.decode(response.body)

        // R5: the ladder is enforced here, not merely requested in the prompt.
        // A model that ignores the instruction must still be unable to exceed it.
        let rejections = validator.rejections(for: tutorResponse, context: context)
        guard rejections.isEmpty else {
            throw AIProviderError.rejected(rejections)
        }

        return tutorResponse
    }

    // MARK: - Request

    /// Builds the request. Internal rather than private so tests can assert on
    /// the exact bytes without a transport.
    func makeRequest(for context: EvaluationContext, key: String) throws -> HTTPRequest {
        let prompt = promptBuilder.prompt(for: context)

        var content: [AnthropicWireContentBlock] = []

        // Image first: Anthropic's guidance is that an image ahead of the text
        // that refers to it improves accuracy, and the text here is entirely
        // about the image.
        if let image = prompt.image {
            content.append(AnthropicWireContentBlock(
                type: "image",
                text: nil,
                source: AnthropicWireImageSource(
                    type: "base64",
                    mediaType: image.mediaType,
                    data: image.data.base64EncodedString()
                )
            ))
        }

        content.append(AnthropicWireContentBlock(type: "text", text: prompt.userText, source: nil))

        let body = AnthropicWireRequest(
            model: modelIdentifier,
            maxTokens: configuration.maxOutputTokens,
            system: prompt.system,
            messages: [AnthropicWireMessage(role: "user", content: content)]
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        let data: Data
        do {
            data = try encoder.encode(body)
        } catch {
            throw AIProviderError.other(reason: "could not encode the request: \(error)")
        }

        return HTTPRequest(
            method: .post,
            url: configuration.endpoint,
            headers: [
                "content-type": "application/json",
                "x-api-key": key,
                "anthropic-version": configuration.apiVersion
            ],
            body: data,
            timeout: configuration.requestTimeout
        )
    }

    // MARK: - Response

    /// Turns a successful body into a `TutorResponse`, or throws.
    static func decode(_ body: Data) throws -> TutorResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let message: AnthropicWireResponse
        do {
            message = try decoder.decode(AnthropicWireResponse.self, from: body)
        } catch {
            throw AIProviderError.malformedResponse(reason: "not a Messages API reply: \(error)")
        }

        // A reply cut off at the token ceiling leaves truncated JSON, which
        // would otherwise surface as an inscrutable decode error. Name it.
        if message.stopReason == "max_tokens" {
            throw AIProviderError.malformedResponse(
                reason: "the reply hit the output token ceiling and is incomplete"
            )
        }

        let text = message.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()

        guard let json = extractJSONObject(from: text) else {
            throw AIProviderError.malformedResponse(
                reason: "no JSON object in the reply: \(Self.excerpt(text))"
            )
        }

        let payload: TutorWirePayload
        do {
            payload = try JSONDecoder().decode(TutorWirePayload.self, from: Data(json.utf8))
        } catch {
            throw AIProviderError.malformedResponse(
                reason: "the reply's JSON does not match the agreed shape: \(error)"
            )
        }

        return try payload.tutorResponse()
    }

    /// Pulls the first balanced JSON object out of a reply.
    ///
    /// Models wrap JSON in a code fence or a sentence of preamble often enough
    /// that refusing such a reply would throw away good hints over formatting.
    /// Brace-counting rather than first-brace-to-last-brace, so that trailing
    /// commentary after the object does not drag in unbalanced text — and
    /// string-aware, so a brace inside the hint itself cannot end the scan
    /// early.
    static func extractJSONObject(from text: String) -> String? {
        var depth = 0
        var start: String.Index?
        var inString = false
        var escaped = false

        for index in text.indices {
            let character = text[index]

            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }

            switch character {
            case "\"":
                inString = true
            case "{":
                if depth == 0 { start = index }
                depth += 1
            case "}":
                guard depth > 0 else { break }
                depth -= 1
                if depth == 0, let start {
                    return String(text[start...index])
                }
            default:
                break
            }
        }

        return nil
    }

    /// Maps an unsuccessful HTTP reply onto the domain's error vocabulary.
    ///
    /// Status first, body second. Anthropic's error bodies are informative but
    /// the status is what determines whether retrying is sane, and that
    /// decision must not depend on parsing text that may not be JSON at all —
    /// a proxy or a captive portal will happily return HTML for a 429.
    static func classify(_ response: HTTPResponse) -> AIProviderError {
        let detail = decodeErrorMessage(response.body) ?? Self.excerpt(response.bodyText)

        switch response.statusCode {
        case 401, 403:
            return .notAuthorised(reason: detail)

        case 429:
            return .rateLimited(retryAfter: response.headerValue("retry-after").flatMap(TimeInterval.init))

        case 400, 404, 413, 422:
            return .malformedResponse(reason: "the request was rejected: \(detail)")

        // 529 is Anthropic's "overloaded". Transient by definition, so it is
        // grouped with the retryable cases rather than with server faults.
        case 500...504, 529:
            return .unreachable(reason: "the service is unavailable (\(response.statusCode)): \(detail)")

        default:
            return .other(reason: "HTTP \(response.statusCode): \(detail)")
        }
    }

    private static func decodeErrorMessage(_ body: Data) -> String? {
        struct Envelope: Decodable {
            struct Detail: Decodable {
                let type: String?
                let message: String?
            }
            let error: Detail?
        }

        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: body),
              let error = envelope.error else { return nil }

        return [error.type, error.message].compactMap { $0 }.joined(separator: ": ")
    }

    /// Error messages carry a bounded excerpt rather than the whole body: a
    /// failure that pastes a megabyte of HTML into a log is a failure nobody
    /// reads.
    private static func excerpt(_ text: String, limit: Int = 240) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count <= limit ? trimmed : String(trimmed.prefix(limit)) + "…"
    }
}
