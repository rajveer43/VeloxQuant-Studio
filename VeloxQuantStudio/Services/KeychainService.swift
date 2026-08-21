import Foundation
import Security

/// Thin wrapper around the macOS Keychain for storing the Supabase session
/// (access + refresh token). Never stores plaintext credentials to disk —
/// SwiftData/UserDefaults are not used for anything session-related.
enum KeychainService {
    private static let service = "com.veloxquant.studio.auth"
    private static let sessionAccount = "supabase-session"

    static func saveSession(_ session: AuthSession) throws {
        let data = try JSONEncoder().encode(session)
        try save(data, account: sessionAccount)
    }

    static func loadSession() -> AuthSession? {
        guard let data = load(account: sessionAccount) else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    static func clearSession() {
        delete(account: sessionAccount)
    }

    // MARK: - Generic keychain primitives

    private static func save(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    private static func load(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            "Could not save to Keychain (status \(status))."
        }
    }
}
