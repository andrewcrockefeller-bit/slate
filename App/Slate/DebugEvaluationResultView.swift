import SwiftUI
import SlateCore

/// Shows what came back from `CanvasController.runDebugEvaluation()`.
///
/// This is the M4 acceptance test made visible: whether the hint reflects
/// what is actually on the canvas is a judgement call for whoever is looking
/// at the iPad, not something this view can decide — it only has to get out
/// of the way and show the raw response.
struct DebugEvaluationResultView: View {
    let state: CanvasController.DebugEvaluationState

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .idle:
                    ContentUnavailableView("Nothing asked yet", systemImage: "wand.and.stars")

                case .running:
                    ProgressView("Asking the tutor…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .succeeded(let response):
                    succeeded(response)

                case .failed(let reason):
                    failed(reason)
                }
            }
            .padding()
            .navigationTitle("Tutor response")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func succeeded(_ response: TutorResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let refusal = response.refusal {
                    Label(refusalText(refusal), systemImage: "hand.raised")
                        .foregroundStyle(.orange)
                } else {
                    HStack {
                        Text("Rung \(response.level.rawValue)")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())

                        Text(String(format: "confidence %.2f", response.confidence))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(response.hintText)
                    .font(.body)

                if let errorClass = response.errorClass {
                    Text("Error class: \(errorClass)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func failed(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Could not get a response", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(.red)

            Text(reason)
                .font(.body.monospaced())

            if reason.contains("no API key") {
                Text("Enter a key with the key button before asking the tutor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refusalText(_ refusal: TutorResponse.Refusal) -> String {
        switch refusal {
        case .assessmentInProgress: return "The tutor is holding back — assessment mode."
        case .answerRequested: return "The tutor declined to give the answer outright."
        case .workIllegible: return "The tutor could not read the work well enough to help."
        }
    }
}

#Preview("Succeeded") {
    DebugEvaluationResultView(state: .succeeded(TutorResponse(
        level: .orient,
        hintText: "Look again at the second line — something changes sign there.",
        confidence: 0.82
    )))
}

#Preview("Failed") {
    DebugEvaluationResultView(state: .failed("not authorised: no API key is configured"))
}
