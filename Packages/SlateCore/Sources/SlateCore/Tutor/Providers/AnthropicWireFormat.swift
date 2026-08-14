import Foundation

// The exact JSON Slate sends to, and expects back from, the Anthropic Messages
// API — kept apart from the adapter's logic so that a wire-format change is a
// diff in one small file rather than noise inside the code that classifies
// errors and enforces the ladder.


/// The shape the model is asked to reply in.
///
/// Separate from `TutorResponse` on purpose. `TutorResponse` is ours and may be
/// refactored freely; this is a contract with something outside the process, and
/// letting synthesised `Codable` keys on a domain type double as a public wire
/// contract is how a rename becomes an outage.
struct TutorWirePayload: Decodable {
    let level: Int
    let hint: String
    let errorClass: String?
    let confidence: Double
    let refusal: String?

    func tutorResponse() throws -> TutorResponse {
        guard let level = HintLevel(rawValue: level) else {
            throw AIProviderError.malformedResponse(reason: "'\(level)' is not a hint level")
        }

        var parsedRefusal: TutorResponse.Refusal?
        if let refusal, !refusal.isEmpty, refusal.lowercased() != "null" {
            guard let known = TutorResponse.Refusal(rawValue: refusal) else {
                throw AIProviderError.malformedResponse(reason: "'\(refusal)' is not a refusal reason")
            }
            parsedRefusal = known
        }

        let cleanedErrorClass = errorClass.flatMap {
            $0.isEmpty || $0.lowercased() == "null" ? nil : $0
        }

        return TutorResponse(
            level: level,
            hintText: hint.trimmingCharacters(in: .whitespacesAndNewlines),
            errorClass: cleanedErrorClass,
            // Clamped rather than rejected: a model reporting 1.2 is being
            // enthusiastic, not malformed, and the confidence floor only cares
            // about the bottom of the range.
            confidence: Swift.min(1, Swift.max(0, confidence)),
            refusal: parsedRefusal
        )
    }
}

struct AnthropicWireRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [AnthropicWireMessage]
}

struct AnthropicWireMessage: Encodable {
    let role: String
    let content: [AnthropicWireContentBlock]
}

struct AnthropicWireContentBlock: Encodable {
    let type: String
    let text: String?
    let source: AnthropicWireImageSource?
}

struct AnthropicWireImageSource: Encodable {
    let type: String
    let mediaType: String
    let data: String
}

struct AnthropicWireResponse: Decodable {
    struct Block: Decodable {
        let type: String
        let text: String?
    }
    let content: [Block]
    let stopReason: String?
}
