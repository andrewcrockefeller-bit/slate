import Foundation
import Security
import SlateCore

/// Keeps the student's API key in the system keychain.
///
/// Not `UserDefaults`, which is a plist in the app container that anything with
/// filesystem access can read, and not a file we encrypt ourselves, which means
/// inventing key management. The keychain is the one place on Apple platforms
/// where a secret belongs.
///
/// The item is accessible after first unlock and marked device-only, so the key
/// never leaves this device through iCloud Keychain. That is a deliberate
/// trade: the student re-enters the key on a second device, and a stolen
/// backup does not carry a working key to someone else's billing account.
public struct KeychainAPIKeyStore: APIKeyStore {

    /// The keychain service string every item is filed under.
    ///
    /// Explicit rather than derived from the bundle identifier, so that renaming
    /// the app does not orphan a key the student already entered.
    public static let defaultService = "com.andrewrock.slate.api-keys"

    private let service: String

    public init(service: String = KeychainAPIKeyStore.defaultService) {
        self.service = service
    }

    public enum KeychainError: Error, CustomStringConvertible {
        case unexpectedStatus(OSStatus, operation: String)
        case unreadableValue

        public var description: String {
            switch self {
            case .unexpectedStatus(let status, let operation):
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
                return "keychain \(operation) failed: \(message)"
            case .unreadableValue:
                return "the stored key was not readable text"
            }
        }
    }

    // MARK: - APIKeyStore

    public func key(for providerName: String) async throws -> String? {
        var query = baseQuery(for: providerName)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let text = String(data: data, encoding: .utf8) else {
                throw KeychainError.unreadableValue
            }
            return text

        case errSecItemNotFound:
            // Absence is an answer, not a failure. A student who has not entered
            // a key yet is the normal first-run state.
            return nil

        default:
            throw KeychainError.unexpectedStatus(status, operation: "read")
        }
    }

    public func setKey(_ key: String?, for providerName: String) async throws {
        guard let key, !key.isEmpty else {
            try delete(providerName)
            return
        }

        let data = Data(key.utf8)
        let query = baseQuery(for: providerName)

        // Update first, then add. The reverse order means every re-entry of a
        // key returns errSecDuplicateItem, and handling that by deleting and
        // re-adding leaves a window where the student has no key at all.
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        switch updateStatus {
        case errSecSuccess:
            return

        case errSecItemNotFound:
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus, operation: "add")
            }

        default:
            throw KeychainError.unexpectedStatus(updateStatus, operation: "update")
        }
    }

    // MARK: - Internals

    private func delete(_ providerName: String) throws {
        let status = SecItemDelete(baseQuery(for: providerName) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status, operation: "delete")
        }
    }

    /// The attributes that identify one provider's key. Everything else — the
    /// value, the accessibility class — is layered on by the caller, so that a
    /// lookup and a write cannot disagree about what "the same item" means.
    private func baseQuery(for providerName: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerName
        ]
    }
}
