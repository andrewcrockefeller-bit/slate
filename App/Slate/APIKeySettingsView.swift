import SwiftUI
import SlateCore

/// Lets the student enter, replace, or remove the API key for one provider.
///
/// Talks only to the `APIKeyStore` protocol, never to Keychain directly — the
/// same seam that lets `AppEnvironment.preview()` swap in an in-memory store
/// with no code here changing.
struct APIKeySettingsView: View {
    let apiKeyStore: any APIKeyStore
    let providerName: String

    @Environment(\.dismiss) private var dismiss
    @State private var keyText = ""
    @State private var hasStoredKey = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("API key", text: $keyText)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                } header: {
                    Text(providerName)
                } footer: {
                    // Says where it lives so "why can't I see it on my other
                    // iPad" has an answer before it becomes a support question.
                    Text(hasStoredKey
                        ? "A key is saved for \(providerName) on this device. Enter a new one to replace it."
                        : "No key saved yet. The key is stored in this device's Keychain only — it does not sync via iCloud.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                if hasStoredKey {
                    Section {
                        Button("Remove saved key", role: .destructive) {
                            save(nil)
                        }
                    }
                }
            }
            .disabled(isLoading)
            .navigationTitle("API Key")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(keyText) }
                        .disabled(keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            hasStoredKey = try await apiKeyStore.key(for: providerName)?.isEmpty == false
        } catch {
            errorMessage = "\(error)"
        }
        isLoading = false
    }

    private func save(_ newKey: String?) {
        Task {
            do {
                try await apiKeyStore.setKey(newKey, for: providerName)
                dismiss()
            } catch {
                errorMessage = "\(error)"
            }
        }
    }
}

#Preview("API Key") {
    APIKeySettingsView(apiKeyStore: InMemoryAPIKeyStore(), providerName: "Anthropic")
}
