import XCTest
@testable import SlateCore

// MARK: - Doubles

/// Answers with whatever it was told to, and records what it was asked.
///
/// An actor because the provider is `Sendable` and calls this across a
/// concurrency boundary; a plain class with mutable state would not compile
/// under Swift 6's strict checking, and silencing that with `@unchecked` in a
/// test double is how a real data race later gets waved through.
actor StubHTTPTransport: HTTPTransport {

    enum Outcome {
        case respond(HTTPResponse)
        case fail(HTTPTransportError)
    }

    private var outcome: Outcome
    private(set) var received: [HTTPRequest] = []

    init(_ outcome: Outcome) {
        self.outcome = outcome
    }

    init(status: Int, json: String, headers: [String: String] = [:]) {
        self.outcome = .respond(HTTPResponse(
            statusCode: status,
            headers: headers,
            body: Data(json.utf8)
        ))
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        received.append(request)
        switch outcome {
        case .respond(let response): return response
        case .fail(let error): throw error
        }
    }

    var lastRequest: HTTPRequest? { received.last }
}

struct StubKeyStore: APIKeyStore {
    var stored: String?

    func key(for providerName: String) async throws -> String? { stored }
    func setKey(_ key: String?, for providerName: String) async throws {}
}

// MARK: - Helpers

/// JSON-escapes a string, so the tests do not depend on hand-escaping.
private func jsonString(_ value: String) -> String {
    let data = try! JSONEncoder().encode(value)
    return String(data: data, encoding: .utf8)!
}

/// Wraps a hint payload in a minimal but faithful Messages API reply.
private func replyEnvelope(_ payload: String, stopReason: String = "end_turn") -> String {
    """
    {"id":"msg_1","type":"message","role":"assistant","model":"m",
     "stop_reason":"\(stopReason)",
     "content":[{"type":"text","text":\(jsonString(payload))}]}
    """
}

private func makeProvider(
    transport: HTTPTransport,
    key: String? = "sk-test",
    config: TutorConfig = .default
) -> AnthropicProvider {
    AnthropicProvider(
        modelIdentifier: "claude-test",
        transport: transport,
        keyStore: StubKeyStore(stored: key),
        promptBuilder: TutorPromptBuilder(config: config),
        validator: TutorResponseValidator(config: config)
    )
}

private func sendableContext(
    permitted: HintLevel = .appliedNudge,
    current: HintLevel? = nil,
    asked: Bool = false
) -> EvaluationContext {
    EvaluationContext(
        prompt: "Simplify (x^2 - 4) / (x - 2)",
        currentLevel: current,
        permittedLevel: permitted,
        studentAskedExplicitly: asked
    )
}

// MARK: - Request construction

final class AnthropicRequestTests: XCTestCase {

    func testRequestCarriesTheHeadersTheAPIRequires() async throws {
        let transport = StubHTTPTransport(status: 200, json: replyEnvelope(
            #"{"level":1,"hint":"Look again at the numerator.","errorClass":null,"confidence":0.9,"refusal":null}"#
        ))
        _ = try await makeProvider(transport: transport).evaluate(sendableContext())

        let request = await transport.lastRequest
        let headers = try XCTUnwrap(request?.headers)

        XCTAssertEqual(headers["x-api-key"], "sk-test")
        XCTAssertEqual(headers["anthropic-version"], "2023-06-01")
        XCTAssertEqual(headers["content-type"], "application/json")
        XCTAssertEqual(request?.method, .post)
        XCTAssertEqual(request?.url, "https://api.anthropic.com/v1/messages")
    }

    // The body is snake_cased on the way out. This is the kind of thing that
    // works on the developer's machine because the API tolerates it and then
    // does not, so it is asserted rather than assumed.
    func testRequestBodyUsesSnakeCaseKeys() throws {
        let provider = makeProvider(transport: StubHTTPTransport(status: 200, json: "{}"))
        let request = try provider.makeRequest(for: sendableContext(), key: "sk-test")
        let json = String(data: try XCTUnwrap(request.body), encoding: .utf8) ?? ""

        XCTAssertTrue(json.contains("\"max_tokens\""))
        XCTAssertFalse(json.contains("\"maxTokens\""))
        XCTAssertTrue(json.contains("\"model\":\"claude-test\""))
    }

    func testAnImageIsSentAheadOfTheTextThatDescribesIt() throws {
        var context = sendableContext()
        context.image = RasterizedRegion(
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            mediaType: "image/png",
            sourceBounds: CanvasRect(x: 0, y: 0, width: 10, height: 10),
            pixelWidth: 10,
            pixelHeight: 10
        )

        let provider = makeProvider(transport: StubHTTPTransport(status: 200, json: "{}"))
        let request = try provider.makeRequest(for: context, key: "sk-test")
        let json = String(data: try XCTUnwrap(request.body), encoding: .utf8) ?? ""

        let imageRange = try XCTUnwrap(json.range(of: "\"image\""))
        let textRange = try XCTUnwrap(json.range(of: "\"text\""))
        XCTAssertLessThan(imageRange.lowerBound, textRange.lowerBound)

        // JSONEncoder escapes forward slashes on some platforms and not others,
        // so accept either spelling rather than pinning the test to one.
        XCTAssertTrue(
            json.contains("\"media_type\":\"image/png\"")
                || json.contains("\"media_type\":\"image\\/png\"")
        )
        XCTAssertTrue(json.contains(Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString()))
    }

    func testNothingIsSentWithoutAKey() async {
        let transport = StubHTTPTransport(status: 200, json: "{}")
        let provider = makeProvider(transport: transport, key: nil)

        await assertThrows(AIProviderError.self, when: {
            _ = try await provider.evaluate(sendableContext())
        }, satisfies: {
            guard case .notAuthorised = $0 else { return false }
            return true
        })

        let count = await transport.received.count
        XCTAssertEqual(count, 0, "a keyless request must not reach the network")
    }

    // An evaluation with neither picture nor problem has nothing to reason
    // about, and sending it spends the student's own API budget on a guess.
    func testAnEmptyContextIsNeverSent() async {
        let transport = StubHTTPTransport(status: 200, json: "{}")
        let provider = makeProvider(transport: transport)

        await assertThrows(AIProviderError.self, when: {
            _ = try await provider.evaluate(EvaluationContext())
        }, satisfies: { _ in true })

        let count = await transport.received.count
        XCTAssertEqual(count, 0)
    }
}

// MARK: - Response decoding

final class AnthropicDecodingTests: XCTestCase {

    func testDecodesAWellFormedReply() throws {
        let response = try AnthropicProvider.decode(Data(replyEnvelope(
            #"{"level":2,"hint":"Cancelling requires factors, not terms.","errorClass":"math.algebra.cancelledTermsNotFactors","confidence":0.82,"refusal":null}"#
        ).utf8))

        XCTAssertEqual(response.level, .principle)
        XCTAssertEqual(response.errorClass, "math.algebra.cancelledTermsNotFactors")
        XCTAssertEqual(response.confidence, 0.82, accuracy: 0.0001)
        XCTAssertNil(response.refusal)
    }

    // Models wrap JSON in a fence or a sentence often enough that refusing such
    // a reply would throw away good hints over formatting.
    func testDecodesJSONWrappedInACodeFenceAndPreamble() throws {
        let wrapped = """
        Here is the hint you asked for:
        ```json
        {"level":1,"hint":"Check the second line.","errorClass":null,"confidence":0.7,"refusal":null}
        ```
        """
        let response = try AnthropicProvider.decode(Data(replyEnvelope(wrapped).utf8))
        XCTAssertEqual(response.hintText, "Check the second line.")
    }

    // A brace inside the hint text must not end the scan early.
    func testABraceInsideTheHintDoesNotTruncateTheObject() throws {
        let payload = #"{"level":1,"hint":"Look at the set {1, 2}.","errorClass":null,"confidence":0.7,"refusal":null}"#
        let response = try AnthropicProvider.decode(Data(replyEnvelope(payload).utf8))
        XCTAssertEqual(response.hintText, "Look at the set {1, 2}.")
    }

    func testTrailingCommentaryAfterTheObjectIsIgnored() throws {
        let payload = #"{"level":1,"hint":"Try again.","errorClass":null,"confidence":0.7,"refusal":null} Hope that helps!"#
        let response = try AnthropicProvider.decode(Data(replyEnvelope(payload).utf8))
        XCTAssertEqual(response.hintText, "Try again.")
    }

    func testConfidenceIsClampedRatherThanRejected() throws {
        let response = try AnthropicProvider.decode(Data(replyEnvelope(
            #"{"level":1,"hint":"Look again.","errorClass":null,"confidence":1.4,"refusal":null}"#
        ).utf8))
        XCTAssertEqual(response.confidence, 1.0, accuracy: 0.0001)
    }

    func testARefusalIsParsedAsAnOutcomeRatherThanAnError() throws {
        let response = try AnthropicProvider.decode(Data(replyEnvelope(
            #"{"level":1,"hint":"I can't help while you're being assessed.","errorClass":null,"confidence":0.95,"refusal":"assessmentInProgress"}"#
        ).utf8))
        XCTAssertEqual(response.refusal, .assessmentInProgress)
    }

    // A reply cut off at the token ceiling leaves truncated JSON. Without this
    // check the symptom is an inscrutable decoding error.
    func testATruncatedReplyIsNamedAsSuch() {
        let body = Data(replyEnvelope("{\"level\":1,", stopReason: "max_tokens").utf8)
        XCTAssertThrowsError(try AnthropicProvider.decode(body)) { error in
            guard case AIProviderError.malformedResponse(let reason) = error else {
                return XCTFail("expected malformedResponse, got \(error)")
            }
            XCTAssertTrue(reason.contains("token ceiling"), reason)
        }
    }

    func testAnUnknownLevelIsRejected() {
        let body = Data(replyEnvelope(
            #"{"level":9,"hint":"x","errorClass":null,"confidence":0.9,"refusal":null}"#
        ).utf8)
        XCTAssertThrowsError(try AnthropicProvider.decode(body))
    }

    func testProseWithNoJSONIsRejected() {
        let body = Data(replyEnvelope("I think you should factor the numerator first.").utf8)
        XCTAssertThrowsError(try AnthropicProvider.decode(body))
    }
}

// MARK: - Error classification

final class AnthropicErrorTests: XCTestCase {

    private func classify(
        _ status: Int,
        _ json: String = "{}",
        headers: [String: String] = [:]
    ) -> AIProviderError {
        AnthropicProvider.classify(HTTPResponse(
            statusCode: status, headers: headers, body: Data(json.utf8)
        ))
    }

    func testAuthenticationFailuresAreNotTransient() {
        let error = classify(401, #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#)
        guard case .notAuthorised(let reason) = error else {
            return XCTFail("expected notAuthorised, got \(error)")
        }
        XCTAssertTrue(reason.contains("invalid x-api-key"), reason)
        XCTAssertFalse(error.isTransient)
    }

    func testRateLimitingCarriesTheRetryHint() {
        let error = classify(429, "{}", headers: ["Retry-After": "12"])
        guard case .rateLimited(let after) = error else {
            return XCTFail("expected rateLimited, got \(error)")
        }
        XCTAssertEqual(after, 12)
        XCTAssertTrue(error.isTransient)
    }

    // Header names are case-insensitive and servers disagree in practice. If
    // this regresses, the retry policy silently stops working.
    func testRetryAfterIsFoundWhateverItsCase() {
        guard case .rateLimited(let after) = classify(429, "{}", headers: ["retry-after": "5"]) else {
            return XCTFail("expected rateLimited")
        }
        XCTAssertEqual(after, 5)
    }

    func testOverloadedIsTreatedAsTransient() {
        XCTAssertTrue(classify(529).isTransient)
        XCTAssertTrue(classify(503).isTransient)
    }

    func testABadRequestIsNotRetried() {
        XCTAssertFalse(classify(400).isTransient)
    }

    // A proxy or captive portal will happily return HTML for a 429, so
    // classification must not depend on the body parsing at all.
    func testHTMLErrorBodiesDoNotBreakClassification() {
        guard case .rateLimited = classify(429, "<html><body>Too Many Requests</body></html>") else {
            return XCTFail("expected rateLimited")
        }
    }
}

// MARK: - The ladder is enforced here, not requested

final class AnthropicLadderEnforcementTests: XCTestCase {

    // R5. The model is prompted to stay within the permitted rung; this proves
    // that ignoring the prompt still cannot reach the student.
    func testAResponseAboveThePermittedRungIsRejected() async {
        let transport = StubHTTPTransport(status: 200, json: replyEnvelope(
            #"{"level":4,"hint":"Factor the numerator as (x-2)(x+2).","errorClass":null,"confidence":0.95,"refusal":null}"#
        ))

        await assertThrows(AIProviderError.self, when: {
            _ = try await makeProvider(transport: transport)
                .evaluate(sendableContext(permitted: .principle))
        }, satisfies: {
            guard case .rejected(let rejections) = $0 else { return false }
            return rejections.contains {
                if case .exceededPermittedLevel = $0 { return true } else { return false }
            }
        })
    }

    func testAResponseThatStatesTheAnswerIsRejected() async {
        let transport = StubHTTPTransport(status: 200, json: replyEnvelope(
            #"{"level":1,"hint":"The answer is x + 2.","errorClass":null,"confidence":0.99,"refusal":null}"#
        ))

        await assertThrows(AIProviderError.self, when: {
            _ = try await makeProvider(transport: transport).evaluate(sendableContext())
        }, satisfies: {
            guard case .rejected(let rejections) = $0 else { return false }
            return rejections.contains {
                if case .looksLikeAFinalAnswer = $0 { return true } else { return false }
            }
        })
    }

    func testTransportFailuresBecomeUnreachable() async {
        let transport = StubHTTPTransport(.fail(.unreachable(reason: "offline")))

        await assertThrows(AIProviderError.self, when: {
            _ = try await makeProvider(transport: transport).evaluate(sendableContext())
        }, satisfies: {
            guard case .unreachable = $0 else { return false }
            return $0.isTransient
        })
    }
}

// MARK: - Async throwing assertion

// XCTAssertThrowsError takes an autoclosure, and an autoclosure may not contain
// `await` on Apple platforms even though it compiles on Linux. This is the
// hoisted form that works on both.
func assertThrows<E: Error>(
    _ type: E.Type,
    when body: () async throws -> Void,
    satisfies predicate: (E) -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await body()
        XCTFail("expected \(type) to be thrown", file: file, line: line)
    } catch let error as E {
        XCTAssertTrue(predicate(error), "threw \(error), which did not satisfy the predicate", file: file, line: line)
    } catch {
        XCTFail("expected \(type), got \(error)", file: file, line: line)
    }
}
